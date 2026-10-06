import XCTest
@testable import QwenRuntime

final class QwenRuntimeTests: XCTestCase {
    func testExactNonThinkingNoBOSFraming() throws {
        XCTAssertEqual(try QwenGeneration.template(system: "System", user: "café 안녕"),
            "<|im_start|>system\nSystem<|im_end|>\n<|im_start|>user\ncafé 안녕<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
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
        XCTAssertEqual(QwenGeneration.modelBytes, 396705472)
        XCTAssertEqual(QwenGeneration.modelSHA256, "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a")
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
