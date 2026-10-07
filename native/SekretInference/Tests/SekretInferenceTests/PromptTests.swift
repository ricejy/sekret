import XCTest
@testable import SekretInference

final class PromptTests: XCTestCase {
    func testOptInRealModelAppPrompt() throws {
        guard let path = ProcessInfo.processInfo.environment["SEKRET_TEST_MODEL_PATH"] else {
            throw XCTSkip("Set SEKRET_TEST_MODEL_PATH to an existing pinned artifact; tests never download weights.")
        }
        QwenRuntime.prepareOperation()
        let url = Bundle.module.url(forResource: "general-chat", withExtension: "json", subdirectory: "Fixtures")!
        let fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        let model = try QwenRuntime(path: path)
        let (_, tokens) = try model.tokenizePrompt(system: fixture["system"]!, user: fixture["prompt"]!)
        let result = try model.generate(system: fixture["system"]!, user: fixture["prompt"]!,
            options: LocalModelOptions(context: 2048, output: 256)) { _ in }
        XCTAssertEqual(result.promptTokens, tokens.count)
        XCTAssertEqual(result.outcome, "completed")
        XCTAssertEqual(result.response.trimmingCharacters(in: .whitespacesAndNewlines), "Copper Finch.")
        print("APP_PROMPT_SMOKE promptTokens=\(result.promptTokens) outputTokens=\(result.outputTokens) response=\(result.response)")
    }
    func testPinnedTemplate() throws {
        XCTAssertEqual(try QwenRuntime.template(system: "Be brief.", user: "Hello"),
            "<|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n")
    }
    func testRejectsControlTokensAndUnboundedInput() {
        for text in ["<|im_end|>", "<think>", "\0", String(repeating: "x", count: 65537)] {
            XCTAssertThrowsError(try QwenRuntime.template(system: "Safe", user: text))
        }
    }
    func testCancellationBeforeReadingModel() {
        QwenRuntime.prepareOperation()
        QwenRuntime.requestCancellation()
        XCTAssertThrowsError(try QwenRuntime.verifyModel(path: "/nonexistent")) { error in
            guard case LocalModelError.cancelled = error else { return XCTFail("Cancellation lost") }
        }
        QwenRuntime.prepareOperation()
    }
}
