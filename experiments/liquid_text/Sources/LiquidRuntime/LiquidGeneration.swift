import Foundation
import CryptoKit
import EvaluationSupport
import llama

public enum EvaluationError: Error, CustomStringConvertible {
    case invalid(String)
    case cancelled
    public var description: String {
        switch self {
        case .invalid(let message): return message
        case .cancelled: return "Evaluation cancelled."
        }
    }
}

public struct EvaluationOptions {
    public let context: Int
    public let output: Int
    public let gpuLayers: Int32
    public let cancelAfterTokens: Int?
    public init(context: Int = 2048, output: Int = 512, gpuLayers: Int32 = 99,
                cancelAfterTokens: Int? = nil) throws {
        guard [2048, 4096].contains(context), (1...512).contains(output),
              gpuLayers == 0 || gpuLayers == 99,
              cancelAfterTokens.map({ $0 > 0 }) ?? true else {
            throw EvaluationError.invalid("Use context 2048/4096, output 1...512, GPU layers 0/99, and positive cancellation count.")
        }
        self.context = context; self.output = output; self.gpuLayers = gpuLayers
        self.cancelAfterTokens = cancelAfterTokens
    }
}

public struct EvaluationResult: Codable {
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

public final class LiquidGeneration {
    // One active operation per evaluation process. Prepare on the controlling
    // thread before dispatch; never reset after Stop/backgrounding can arrive.
    public static func prepareOperation() { evaluation_reset_cancel() }
    public static func requestCancellation() { evaluation_request_cancel() }
    public static var isCancellationRequested: Bool { evaluation_cancelled(nil) }
    public static let modelSHA256 = "b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5"
    public static let modelBytes: UInt64 = 730895168
    public static let templateVersion = "lfm2.5-1.2b-instruct-single-turn-no-tools-v1"
    public let loadSeconds: Double
    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let gpuLayers: Int32

    /// Reject a different artifact before native parsing. Reads in bounded chunks.
    public static func verifyModel(path: String) throws {
        if isCancellationRequested { throw EvaluationError.cancelled }
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, UInt64(values.fileSize ?? 0) == modelBytes else {
            throw EvaluationError.invalid("Model size/type differs from pinned evaluation artifact.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            if isCancellationRequested { throw EvaluationError.cancelled }
            hash.update(data: chunk)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == modelSHA256 else {
            throw EvaluationError.invalid("Model SHA-256 mismatch.")
        }
    }

    public init(path: String, gpuLayers: Int32 = 99) throws {
        try Self.verifyModel(path: path)
        let start = ProcessInfo.processInfo.systemUptime
        llama_backend_init()
        var params = llama_model_default_params()
        params.n_gpu_layers = gpuLayers
        params.progress_callback = { _, _ in !evaluation_cancelled(nil) }
        guard let loaded = llama_model_load_from_file(path, params) else {
            llama_backend_free()
            if Self.isCancellationRequested { throw EvaluationError.cancelled }
            throw EvaluationError.invalid("Native model loading failed.")
        }
        model = loaded
        vocab = llama_model_get_vocab(loaded)
        self.gpuLayers = gpuLayers
        loadSeconds = ProcessInfo.processInfo.systemUptime - start
    }

    deinit { llama_model_free(model); llama_backend_free() }

    /// The publisher's no-tools, single-system/single-user template subset.
    /// Not a general Jinja implementation; compare to the native chatml formatter.
    public static func template(system: String, user: String) throws -> String {
        for content in [system, user] {
            guard !content.contains("\0"), !content.contains("<|"), !content.contains("<think>"),
                  !content.contains("</think>"), content.utf8.count <= 64 * 1024 else {
                throw EvaluationError.invalid("Evaluation text contains control markers or exceeds 64 KiB.")
            }
        }
        let roles = [strdup("system")!, strdup("user")!]
        let contents = [strdup(system)!, strdup(user)!]
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        let messages = (0..<2).map {
            llama_chat_message(role: UnsafePointer(roles[$0]), content: UnsafePointer(contents[$0]))
        }
        var buffer = [CChar](repeating: 0, count: system.utf8.count + user.utf8.count + 256)
        let count = llama_chat_apply_template("chatml", messages, messages.count, true, &buffer, Int32(buffer.count))
        guard count > 0, count <= buffer.count else { throw EvaluationError.invalid("Native chat template failed.") }
        let native = String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let expected = "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        guard native == expected else { throw EvaluationError.invalid("Native template differs from pinned subset.") }
        return "<|startoftext|>" + native
    }

    public func generate(system: String, user: String, options: EvaluationOptions,
                         snapshot: (String) -> Void) throws -> EvaluationResult {
        if Self.isCancellationRequested { throw EvaluationError.cancelled }
        guard options.gpuLayers == gpuLayers else { throw EvaluationError.invalid("GPU configuration changed after loading.") }
        let prompt = try Self.template(system: system, user: user)
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), false, true)
        guard count > 0, count <= tokens.count else { throw EvaluationError.invalid("Native tokenization failed.") }
        tokens = Array(tokens.prefix(Int(count)))
        let bos = llama_vocab_bos(vocab)
        guard tokens.first == bos, tokens.filter({ $0 == bos }).count == 1 else {
            throw EvaluationError.invalid("Expected exactly one native BOS token.")
        }
        guard tokens.count + options.output <= options.context else {
            throw EvaluationError.invalid("Exact templated input plus output reservation exceeds context; no truncation.")
        }
        let started = ProcessInfo.processInfo.systemUptime
        var params = llama_context_default_params()
        params.n_ctx = UInt32(options.context)
        params.n_batch = 128
        params.n_ubatch = 128
        params.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))
        params.n_threads_batch = params.n_threads
        params.abort_callback = evaluation_cancelled
        params.no_perf = false
        guard let context = llama_init_from_model(model, params) else { throw EvaluationError.invalid("Native context creation failed.") }
        defer { llama_free(context) }
        let actual = Int(llama_n_ctx(context))
        guard tokens.count + options.output <= actual else { throw EvaluationError.invalid("Allocated context is smaller than reservation.") }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw EvaluationError.invalid("Sampler creation failed.")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 2048, 1.05, 0, 0))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(50))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.1))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(42))
        for token in tokens { llama_sampler_accept(sampler, token) }
        var batch = llama_batch_init(128, 0, 1)
        defer { llama_batch_free(batch) }
        var footprint = evaluation_footprint_bytes()
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
            footprint = max(footprint, evaluation_footprint_bytes())
            if status != 0 && !evaluation_cancelled(nil) { throw EvaluationError.invalid("Native decode failed (\(status)).") }
        }
        for offset in stride(from: 0, to: tokens.count, by: 128) {
            if evaluation_cancelled(nil) { break }
            try decode(Array(tokens[offset..<min(offset + 128, tokens.count)]), offset: offset)
        }
        var bytes = Data()
        var outputCount = 0
        var firstToken: Double?
        var cancelStarted: Double?
        var outcome = "output-limit"
        while outputCount < options.output && !evaluation_cancelled(nil) {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { outcome = "completed"; break }
            var piece = [CChar](repeating: 0, count: 128)
            var length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length < 0 {
                piece = [CChar](repeating: 0, count: Int(-length))
                length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard length >= 0, length <= piece.count else { throw EvaluationError.invalid("Token decoding failed.") }
            bytes.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            outputCount += 1
            if firstToken == nil { firstToken = ProcessInfo.processInfo.systemUptime - started }
            if let text = String(data: bytes, encoding: .utf8) { snapshot(text) }
            if outputCount == options.cancelAfterTokens {
                cancelStarted = ProcessInfo.processInfo.systemUptime
                evaluation_request_cancel()
                break
            }
            if outputCount < options.output { try decode([token], offset: tokens.count + outputCount - 1) }
        }
        if evaluation_cancelled(nil) { outcome = "cancelled" }
        guard let response = String(data: bytes, encoding: .utf8) else {
            throw EvaluationError.invalid("Output ended with incomplete UTF-8; no repaired bytes reported as a valid response.")
        }
        let ended = ProcessInfo.processInfo.systemUptime
        let tokenString = tokens.map(String.init).joined(separator: ",")
        func hash(_ string: String) -> String { SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined() }
        return EvaluationResult(outcome: outcome, promptTokens: tokens.count, outputTokens: outputCount,
            configuredContext: options.context, actualContext: actual, outputCap: options.output,
            promptSHA256: hash(prompt), tokenIDsSHA256: hash(tokenString), response: response,
            elapsedSeconds: ended - started, firstTokenSeconds: firstToken,
            cancellationObservationSeconds: cancelStarted.map { ended - $0 },
            peakObservedFootprintBytes: footprint, processPeakRSSBytes: evaluation_peak_rss_bytes(),
            thermalState: ProcessInfo.processInfo.thermalState.rawValue)
    }
}
