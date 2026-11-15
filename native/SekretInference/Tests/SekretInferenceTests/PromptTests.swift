import XCTest
@testable import SekretInference

final class PromptTests: XCTestCase {
    /// Opt-in phone/Mac smoke run against an already present pinned GGUF.
    /// SEKRET_TEST_MODEL_PROFILE picks the profile (default Qwen3-4B).
    func testOptInRealModelAppPrompt() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SEKRET_TEST_MODEL_PATH"] else {
            throw XCTSkip("Set SEKRET_TEST_MODEL_PATH to an existing pinned artifact; tests never download weights.")
        }
        let profile = try XCTUnwrap(ModelProfile.byID(environment["SEKRET_TEST_MODEL_PROFILE"] ?? ModelProfile.qwen3_4b.id))
        LocalRuntime.prepareOperation()
        let url = Bundle.module.url(forResource: "general-chat", withExtension: "json", subdirectory: "Fixtures")!
        let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        let model = try LocalRuntime(path: path, profile: profile)
        let (_, tokens) = try model.tokenizePrompt(system: fixture["system"]!, user: fixture["prompt"]!)
        let result = try model.generate(system: fixture["system"]!, user: fixture["prompt"]!,
            options: LocalModelOptions(context: profile.context, output: profile.output)) { _ in }
        XCTAssertEqual(result.promptTokens, tokens.count)
        XCTAssertEqual(result.outcome, "completed")
        XCTAssertFalse(LocalRuntime.leaksThinking(result.response))
        XCTAssertEqual(result.response.trimmingCharacters(in: .whitespacesAndNewlines), "Copper Finch.")
        print("APP_PROMPT_SMOKE profile=\(profile.id) promptTokens=\(result.promptTokens) outputTokens=\(result.outputTokens) response=\(result.response)")
    }

    func testPinnedTemplate() throws {
        XCTAssertEqual(try LocalRuntime.template(system: "Be brief.", user: "Hello", profile: .qwen3_4b),
            "<|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n")
    }

    /// Regression: the shipped Qwen3-4B profile must not drift.
    func testQwen3ProfileIsUnchanged() {
        let profile = ModelProfile.qwen3_4b
        XCTAssertEqual(profile.sha256, "9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9")
        XCTAssertEqual(profile.bytes, 2075618400)
        XCTAssertEqual(profile.admissionBytes, 2_684_354_560)
        XCTAssertEqual(profile.family, .chatml)
        XCTAssertEqual(profile.thinking, .notSupported)
        XCTAssertEqual(profile.bos, .never)
        XCTAssertEqual(profile.assistantPrefill, "")
        XCTAssertEqual(profile.sampler, SamplerSettings(topK: 20, topP: 0.8, temperature: 0.7, presencePenalty: 0, seed: 42))
        XCTAssertEqual(profile.context, 2048)
        XCTAssertEqual(profile.output, 256)
        XCTAssertEqual(profile.templateVersion, "qwen3-4b-instruct-2507-alternating-chat-no-tools-v1")
        XCTAssertEqual(profile.pinnedIDs, PinnedTokenIDs(turnStart: 151644, turnEnd: 151645, eos: 151645,
                                                         endOfGeneration: [151645, 151643]))
        XCTAssertEqual(profile.forbiddenContent, ["\0", "<|", "<think>", "</think>"])
        XCTAssertFalse(profile.checksEmbeddedTemplate)
    }

    func testRejectsControlTokensAndUnboundedInput() {
        for profile in ModelProfile.all {
            for text in ["<|im_end|>", "<|end_of_text|>", "<think>", "</think>", "\0", String(repeating: "x", count: 65537)] {
                XCTAssertThrowsError(try LocalRuntime.template(system: "Safe", user: text, profile: profile), profile.id)
                XCTAssertThrowsError(try LocalRuntime.template(system: text, user: "Safe", profile: profile), profile.id)
            }
        }
        for profile in [ModelProfile.minicpm5_2b, .minicpm5_1b] {
            for text in ["</s>", "<s>"] {
                XCTAssertThrowsError(try LocalRuntime.template(system: "Safe", user: text, profile: profile))
            }
        }
    }

    func testCancellationBeforeReadingModel() {
        LocalRuntime.prepareOperation()
        LocalRuntime.requestCancellation()
        XCTAssertThrowsError(try LocalRuntime.verifyModel(path: "/nonexistent", profile: .qwen3_4b)) { error in
            guard case LocalModelError.cancelled = error else { return XCTFail("Cancellation lost") }
        }
        LocalRuntime.prepareOperation()
    }
}
