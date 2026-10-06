import XCTest
@testable import QwenRuntime

final class QwenRuntimeTests: XCTestCase {
    func testExactNonThinkingNoBOSFraming() throws {
        XCTAssertEqual(try QwenGeneration.template(system: "System", user: "café 안녕"),
            "<|im_start|>system\nSystem<|im_end|>\n<|im_start|>user\ncafé 안녕<|im_end|>\n<|im_start|>assistant\n")
    }
    func testRejectsControlMarkers() {
        for text in ["<|startoftext|>", "<think>", "\0"] {
            XCTAssertThrowsError(try QwenGeneration.template(system: "System", user: text))
        }
    }
    func testRejectsOversizedPrompt() {
        XCTAssertThrowsError(try QwenGeneration.template(system: "System", user: String(repeating: "x", count: 65537)))
    }
    func testDifferentPinAndBoundedOptions() {
        XCTAssertEqual(QwenGeneration.modelBytes, 2497281120)
        XCTAssertEqual(QwenGeneration.modelSHA256, "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597")
        XCTAssertThrowsError(try EvaluationOptions(context: 32768))
        XCTAssertThrowsError(try EvaluationOptions(output: 513))
    }
    func testCancellationSurvivesDispatch() {
        QwenGeneration.prepareOperation()
        QwenGeneration.requestCancellation()
        XCTAssertTrue(QwenGeneration.isCancellationRequested)
        QwenGeneration.prepareOperation()
    }
}
