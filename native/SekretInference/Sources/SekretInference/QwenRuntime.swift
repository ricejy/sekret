import Foundation
import CryptoKit
import RuntimeSupport
import llama

public enum LocalModelError: Error, CustomStringConvertible {
    case invalid(String)
    case cancelled
    public var description: String {
        switch self {
        case .invalid(let message): return message
        case .cancelled: return "Local model cancelled."
        }
    }
}
public struct LocalModelOptions {
    public let context: Int
    public let output: Int
    public let gpuLayers: Int32
    public let cancelAfterTokens: Int?
    public init(context: Int = 2048, output: Int = 512, gpuLayers: Int32 = 99,
                cancelAfterTokens: Int? = nil) throws {
        guard [2048, 4096].contains(context), (1...512).contains(output),
              gpuLayers == 0 || gpuLayers == 99,
              cancelAfterTokens.map({ $0 > 0 }) ?? true else {
            throw LocalModelError.invalid("Use context 2048/4096, output 1...512, GPU layers 0/99, and positive cancellation count.")
        }
        self.context = context; self.output = output; self.gpuLayers = gpuLayers
        self.cancelAfterTokens = cancelAfterTokens
    }
}

public struct LocalModelResult: Codable {
    public var outcome: String
    public let promptTokens: Int
    public let outputTokens: Int
    public let configuredContext: Int
    public let actualContext: Int
    public let outputCap: Int
    public let promptSHA256: String
    public let tokenIDsSHA256: String
    public let response: String
    public let elapsedSeconds: Double
    public let firstTokenSeconds: Double?
    public let cancellationObservationSeconds: Double?
    public let peakObservedFootprintBytes: UInt64
    public let processPeakRSSBytes: UInt64
    public let thermalState: Int
}

public struct LocalModelMessage: Codable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public final class QwenRuntime {
    public static var availableMemoryBytes: UInt64 { sekret_available_memory_bytes() }
    // One active operation per local model process. Prepare on the controlling
    // thread before dispatch; never reset after Stop/backgrounding can arrive.
    public static func prepareOperation() { sekret_reset_cancel() }
    public static func requestCancellation() { sekret_request_cancel() }
    public static var isCancellationRequested: Bool { sekret_cancelled(nil) }
    public static let modelSHA256 = "9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9"
    public static let modelBytes: UInt64 = 2075618400
    public static let templateVersion = "qwen3-4b-instruct-2507-single-turn-no-tools-no-thinking-v1"
    public static let chatTemplateVersion = "qwen3-4b-instruct-2507-alternating-chat-no-tools-v1"
    public let loadSeconds: Double
    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let gpuLayers: Int32

    /// Reject a different artifact before native parsing. Reads in bounded chunks.
    public static func verifyModel(path: String) throws {
        if isCancellationRequested { throw LocalModelError.cancelled }
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, UInt64(values.fileSize ?? 0) == modelBytes else {
            throw LocalModelError.invalid("Model size/type differs from pinned local model artifact.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        // Drain Foundation's temporary NSData buffers per chunk, not per model.
        while try autoreleasepool(invoking: { () throws -> Bool in
            if isCancellationRequested { throw LocalModelError.cancelled }
            guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { return false }
            hash.update(data: chunk)
            return true
        }) {}
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == modelSHA256 else {
            throw LocalModelError.invalid("Model SHA-256 mismatch.")
        }
    }

    public init(path: String, gpuLayers: Int32 = 99) throws {
        try Self.verifyModel(path: path)
        let start = ProcessInfo.processInfo.systemUptime
        llama_backend_init()
        var params = llama_model_default_params()
        params.n_gpu_layers = gpuLayers
        params.progress_callback = { _, _ in !sekret_cancelled(nil) }
        guard let loaded = llama_model_load_from_file(path, params) else {
            llama_backend_free()
            if Self.isCancellationRequested { throw LocalModelError.cancelled }
            throw LocalModelError.invalid("Native model loading failed.")
        }
        model = loaded
        vocab = llama_model_get_vocab(loaded)
        self.gpuLayers = gpuLayers
        guard llama_vocab_eos(vocab) == 151645, llama_vocab_is_eog(vocab, 151645), llama_vocab_is_eog(vocab, 151643) else {
            llama_model_free(loaded); llama_backend_free()
            throw LocalModelError.invalid("Native end-of-generation IDs differ from pinned publisher configuration.")
        }
        loadSeconds = ProcessInfo.processInfo.systemUptime - start
    }

    deinit { llama_model_free(model); llama_backend_free() }

    /// The publisher's no-tools, single-system/single-user template subset.
    /// Not a general Jinja implementation; compare to the native chatml formatter.
    public static func template(system: String, user: String) throws -> String {
        try template(messages: [.init(role: "system", content: system), .init(role: "user", content: user)])
    }

    /// Pinned publisher subset: one system, alternating user/assistant, ending in user.
    public static func template(messages: [LocalModelMessage]) throws -> String {
        guard messages.count >= 2, messages.count <= 16, messages.count % 2 == 0,
              messages.first?.role == "system",
              messages.reduce(0, { $0 + $1.content.utf8.count }) <= 64 * 1024 else {
            throw LocalModelError.invalid("Invalid bounded local model chat.")
        }
        for (index, message) in messages.enumerated() {
            guard message.role == (index == 0 ? "system" : index % 2 == 1 ? "user" : "assistant") else {
                throw LocalModelError.invalid("Local model chat roles must alternate and end in user.")
            }
            let content = message.content
            guard !content.contains("\0"), !content.contains("<|"), !content.contains("<think>"),
                  !content.contains("</think>"), content.utf8.count <= 64 * 1024 else {
                throw LocalModelError.invalid("Local model text contains control markers or exceeds 64 KiB.")
            }
        }
        let roles = messages.map { strdup($0.role)! }
        let contents = messages.map { strdup($0.content)! }
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        let nativeMessages = messages.indices.map {
            llama_chat_message(role: UnsafePointer(roles[$0]), content: UnsafePointer(contents[$0]))
        }
        var buffer = [CChar](repeating: 0, count: messages.reduce(0, { $0 + $1.content.utf8.count }) + messages.count * 64 + 64)
        let count = llama_chat_apply_template("chatml", nativeMessages, nativeMessages.count, true, &buffer, Int32(buffer.count))
        guard count > 0, count <= buffer.count else { throw LocalModelError.invalid("Native chat template failed.") }
        let native = String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let expected = messages.map { "<|im_start|>\($0.role)\n\($0.content)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"
        guard native == expected else { throw LocalModelError.invalid("Native template differs from pinned subset.") }
        return native
    }

    public func tokenizePrompt(system: String, user: String) throws -> (String, [llama_token]) {
        try tokenizePrompt(messages: [.init(role: "system", content: system), .init(role: "user", content: user)])
    }

    public func tokenizePrompt(messages: [LocalModelMessage]) throws -> (String, [llama_token]) {
        let prompt = try Self.template(messages: messages)
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), false, true)
        guard count > 0, count <= tokens.count else { throw LocalModelError.invalid("Native tokenization failed.") }
        tokens = Array(tokens.prefix(Int(count)))
        guard tokens.first == 151644, !tokens.contains(151643), tokens.contains(151645) else {
            throw LocalModelError.invalid("Unexpected Qwen special-token framing.")
        }
        return (prompt, tokens)
    }

    public func generate(system: String, user: String, options: LocalModelOptions,
                         snapshot: (String) -> Void) throws -> LocalModelResult {
        try generate(messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
                     options: options, snapshot: snapshot)
    }

    public func generate(messages: [LocalModelMessage], options: LocalModelOptions,
                         snapshot: (String) -> Void) throws -> LocalModelResult {
        if Self.isCancellationRequested { throw LocalModelError.cancelled }
        guard options.gpuLayers == gpuLayers else { throw LocalModelError.invalid("GPU configuration changed after loading.") }
        let (prompt, tokens) = try tokenizePrompt(messages: messages)
        guard tokens.count + options.output <= options.context else {
            throw LocalModelError.invalid("Exact templated input plus output reservation exceeds context; no truncation.")
        }
        let started = ProcessInfo.processInfo.systemUptime
        var params = llama_context_default_params()
        params.n_ctx = UInt32(options.context)
        params.n_batch = 128
        params.n_ubatch = 128
        params.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))
        params.n_threads_batch = params.n_threads
        params.abort_callback = sekret_cancelled
        params.no_perf = false
        guard let context = llama_init_from_model(model, params) else { throw LocalModelError.invalid("Native context creation failed.") }
        defer { llama_free(context) }
        let actual = Int(llama_n_ctx(context))
        guard tokens.count + options.output <= actual else { throw LocalModelError.invalid("Allocated context is smaller than reservation.") }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw LocalModelError.invalid("Sampler creation failed.")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.8, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(42))
        var batch = llama_batch_init(128, 0, 1)
        defer { llama_batch_free(batch) }
        var footprint = sekret_footprint_bytes()
        func decode(_ ids: [llama_token], offset: Int) throws {
            batch.n_tokens = Int32(ids.count)
            for index in ids.indices {
                batch.token[index] = ids[index]
                batch.pos[index] = Int32(offset + index)
                batch.n_seq_id[index] = 1
                batch.seq_id[index]![0] = 0
                batch.logits[index] = index == ids.count - 1 ? 1 : 0
            }
            let status = llama_decode(context, batch)
            footprint = max(footprint, sekret_footprint_bytes())
            if status != 0 && !sekret_cancelled(nil) { throw LocalModelError.invalid("Native decode failed (\(status)).") }
        }
        for offset in stride(from: 0, to: tokens.count, by: 128) {
            if sekret_cancelled(nil) { break }
            try decode(Array(tokens[offset..<min(offset + 128, tokens.count)]), offset: offset)
        }
        var bytes = Data()
        var outputCount = 0
        var firstToken: Double?
        var cancelStarted: Double?
        var outcome = "output-limit"
        while outputCount < options.output && !sekret_cancelled(nil) {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { outcome = "completed"; break }
            var piece = [CChar](repeating: 0, count: 128)
            var length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length < 0 {
                piece = [CChar](repeating: 0, count: Int(-length))
                length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard length >= 0, length <= piece.count else { throw LocalModelError.invalid("Token decoding failed.") }
            bytes.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            outputCount += 1
            if firstToken == nil { firstToken = ProcessInfo.processInfo.systemUptime - started }
            if let text = String(data: bytes, encoding: .utf8) { snapshot(text) }
            if outputCount == options.cancelAfterTokens {
                cancelStarted = ProcessInfo.processInfo.systemUptime
                sekret_request_cancel()
                break
            }
            if outputCount < options.output { try decode([token], offset: tokens.count + outputCount - 1) }
        }
        if sekret_cancelled(nil) { outcome = "cancelled" }
        guard let response = String(data: bytes, encoding: .utf8) else {
            throw LocalModelError.invalid("Output ended with incomplete UTF-8; no repaired bytes reported as a valid response.")
        }
        let ended = ProcessInfo.processInfo.systemUptime
        let tokenString = tokens.map(String.init).joined(separator: ",")
        func hash(_ string: String) -> String { SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined() }
        return LocalModelResult(outcome: outcome, promptTokens: tokens.count, outputTokens: outputCount,
            configuredContext: options.context, actualContext: actual, outputCap: options.output,
            promptSHA256: hash(prompt), tokenIDsSHA256: hash(tokenString), response: response,
            elapsedSeconds: ended - started, firstTokenSeconds: firstToken,
            cancellationObservationSeconds: cancelStarted.map { ended - $0 },
            peakObservedFootprintBytes: footprint, processPeakRSSBytes: sekret_peak_rss_bytes(),
            thermalState: ProcessInfo.processInfo.thermalState.rawValue)
    }
}
