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


/// One loaded reviewed GGUF, run exactly as its `ModelProfile` pins.
public final class LocalRuntime {
    public static var availableMemoryBytes: UInt64 { sekret_available_memory_bytes() }
    // One active operation per local model process. Prepare on the controlling
    // thread before dispatch; never reset after Stop/backgrounding can arrive.
    public static func prepareOperation() { sekret_reset_cancel() }
    public static func requestCancellation() { sekret_request_cancel() }
    public static var isCancellationRequested: Bool { sekret_cancelled(nil) }
    public let profile: ModelProfile
    public let loadSeconds: Double
    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let gpuLayers: Int32
    private let turnStart: llama_token
    private let turnEnd: llama_token
    private let stops: Set<llama_token>
    private let bos: llama_token?
    /// `<think>`/`</think>` ids, for profiles that turn thinking off.
    private let thinkingMarkers: Set<llama_token>

    /// Reject a different artifact before native parsing. Reads in bounded chunks.
    public static func verifyModel(path: String, profile: ModelProfile) throws {
        if isCancellationRequested { throw LocalModelError.cancelled }
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, UInt64(values.fileSize ?? 0) == profile.bytes else {
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
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == profile.sha256 else {
            throw LocalModelError.invalid("Model SHA-256 mismatch.")
        }
    }

    public init(path: String, profile: ModelProfile, gpuLayers: Int32 = 99) throws {
        try Self.verifyModel(path: path, profile: profile)
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
        let vocab = llama_model_get_vocab(loaded)!
        do {
            let framing = try Self.checkVocabulary(vocab, model: loaded, profile: profile)
            turnStart = framing.start; turnEnd = framing.end; stops = framing.stops; bos = framing.bos
            thinkingMarkers = profile.thinking == .prefillEmpty
                ? Set(["<think>", "</think>"].compactMap { Self.singleToken($0, vocab: vocab) }) : []
        } catch {
            llama_model_free(loaded); llama_backend_free()
            throw error
        }
        model = loaded
        self.vocab = vocab
        self.profile = profile
        self.gpuLayers = gpuLayers
        loadSeconds = ProcessInfo.processInfo.systemUptime - start
    }

    deinit { llama_model_free(model); llama_backend_free() }

    /// The id of [text] when it is exactly one (special) token.
    private static func singleToken(_ text: String, vocab: OpaquePointer) -> llama_token? {
        var ids = [llama_token](repeating: 0, count: 8)
        let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &ids, Int32(ids.count), false, true)
        return count == 1 ? ids[0] : nil
    }

    /// End-of-answer and framing tokens must be what the profile pins.
    private static func checkVocabulary(_ vocab: OpaquePointer, model: OpaquePointer, profile: ModelProfile) throws
        -> (start: llama_token, end: llama_token, stops: Set<llama_token>, bos: llama_token?) {
        func fail() -> LocalModelError {
            .invalid("Native end-of-generation IDs differ from pinned publisher configuration.")
        }
        if let pinned = profile.pinnedIDs {
            guard llama_vocab_eos(vocab) == pinned.eos,
                  pinned.endOfGeneration.allSatisfy({ llama_vocab_is_eog(vocab, $0) }) else { throw fail() }
        }
        guard let start = singleToken(profile.family.turnStart, vocab: vocab),
              let end = singleToken(profile.family.turnEnd, vocab: vocab),
              let eos = singleToken(profile.eosText, vocab: vocab),
              llama_vocab_eos(vocab) == eos else { throw fail() }
        var endOfGeneration: [llama_token] = []
        for text in profile.endOfGenerationTexts {
            guard let id = singleToken(text, vocab: vocab), llama_vocab_is_eog(vocab, id) else { throw fail() }
            endOfGeneration.append(id)
        }
        var stops = Set([end])
        for text in profile.stopTexts {
            guard let id = singleToken(text, vocab: vocab) else { throw fail() }
            stops.insert(id)
        }
        if let pinned = profile.pinnedIDs {
            guard pinned.turnStart == start, pinned.turnEnd == end, pinned.eos == eos,
                  pinned.endOfGeneration == endOfGeneration else { throw fail() }
        }
        if profile.checksEmbeddedTemplate {
            guard let embedded = llama_model_chat_template(model, nil),
                  try render(probe, template: String(cString: embedded)) == profile.family.render(probe) else {
                throw LocalModelError.invalid("Embedded chat template differs from the pinned family.")
            }
        }
        var bos: llama_token?
        if profile.bos == .fromVocabulary && llama_vocab_get_add_bos(vocab) {
            let id = llama_vocab_bos(vocab)
            guard id >= 0 else { throw fail() }
            bos = id
        }
        return (start, end, stops, bos)
    }

    /// A conversation that exercises every role of the pinned subset.
    static let probe: [LocalModelMessage] = [
        .init(role: "system", content: "S"), .init(role: "user", content: "U1"),
        .init(role: "assistant", content: "A1"), .init(role: "user", content: "U2"),
    ]

    /// llama.cpp's built-in formatter: [template] is a family name or a Jinja
    /// template that llama.cpp recognises by its markers.
    static func render(_ messages: [LocalModelMessage], template: String) throws -> String {
        let roles = messages.map { strdup($0.role)! }
        let contents = messages.map { strdup($0.content)! }
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        let nativeMessages = messages.indices.map {
            llama_chat_message(role: UnsafePointer(roles[$0]), content: UnsafePointer(contents[$0]))
        }
        var buffer = [CChar](repeating: 0, count: messages.reduce(0, { $0 + $1.content.utf8.count }) + messages.count * 64 + 64)
        let count = llama_chat_apply_template(template, nativeMessages, nativeMessages.count, true, &buffer, Int32(buffer.count))
        guard count > 0, count <= buffer.count else { throw LocalModelError.invalid("Native chat template failed.") }
        return String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The publisher's no-tools, single-system/single-user template subset.
    public static func template(system: String, user: String, profile: ModelProfile) throws -> String {
        try template(messages: [.init(role: "system", content: system), .init(role: "user", content: user)], profile: profile)
    }

    /// Pinned publisher subset: one system, alternating user/assistant, ending in
    /// user, then the profile's thinking-off prefill. Not a general Jinja
    /// implementation; compared to llama.cpp's native formatter for the family.
    public static func template(messages: [LocalModelMessage], profile: ModelProfile) throws -> String {
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
            guard !profile.forbiddenContent.contains(where: { content.contains($0) }),
                  content.utf8.count <= 64 * 1024 else {
                throw LocalModelError.invalid("Local model text contains control markers or exceeds 64 KiB.")
            }
        }
        let native = try render(messages, template: profile.family.nativeName)
        guard native == profile.family.render(messages) else {
            throw LocalModelError.invalid("Native template differs from pinned subset.")
        }
        return native + profile.assistantPrefill
    }

    public func tokenizePrompt(system: String, user: String) throws -> (String, [llama_token]) {
        try tokenizePrompt(messages: [.init(role: "system", content: system), .init(role: "user", content: user)])
    }

    public func tokenizePrompt(messages: [LocalModelMessage]) throws -> (String, [llama_token]) {
        let prompt = try Self.template(messages: messages, profile: profile)
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), false, true)
        guard count > 0, count <= tokens.count else { throw LocalModelError.invalid("Native tokenization failed.") }
        tokens = Array(tokens.prefix(Int(count)))
        // Only the turn-end marker may end anything inside the prompt.
        guard tokens.first == turnStart, tokens.contains(turnEnd),
              !tokens.contains(where: { $0 != turnEnd && (llama_vocab_is_eog(vocab, $0) || stops.contains($0)) }) else {
            throw LocalModelError.invalid("Unexpected special-token framing.")
        }
        if let bos { tokens.insert(bos, at: 0) }
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
        let settings = profile.sampler
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(settings.topK))
        if settings.presencePenalty != 0 {
            // After top-k, as llama.h advises; penalises generated tokens only.
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
                llama_vocab_n_tokens(vocab), Int32(options.output), 1, 0, settings.presencePenalty))
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(settings.topP, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(settings.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(settings.seed))
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
            if llama_vocab_is_eog(vocab, token) || stops.contains(token) { outcome = "completed"; break }
            // Thinking is off; a reasoning marker means the profile is wrong.
            if thinkingMarkers.contains(token) { outcome = "thinking-leak"; break }
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
            if let text = String(data: bytes, encoding: .utf8) {
                if profile.thinking == .prefillEmpty && Self.leaksThinking(text) { outcome = "thinking-leak"; break }
                snapshot(text)
            }
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

    /// Whether streamed answer text carries a reasoning block marker.
    public static func leaksThinking(_ text: String) -> Bool {
        text.contains("<think>") || text.contains("</think>")
    }
}
