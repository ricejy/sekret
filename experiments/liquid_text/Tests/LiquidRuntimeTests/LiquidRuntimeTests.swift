import XCTest
@testable import LiquidRuntime

final class LiquidRuntimeTests: XCTestCase {
    func testExactBOSAndNonThinkingFraming() throws {
        XCTAssertEqual(try LiquidGeneration.template(system: "System", user: "café 안녕"),
            "<|startoftext|><|im_start|>system\nSystem<|im_end|>\n<|im_start|>user\ncafé 안녕<|im_end|>\n<|im_start|>assistant\n")
    }
    func testRejectsControlMarkers() {
        for text in ["<|startoftext|>", "<think>", "\0"] {
            XCTAssertThrowsError(try LiquidGeneration.template(system: "System", user: text))
        }
    }
    func testRejectsOversizedPrompt() {
        XCTAssertThrowsError(try LiquidGeneration.template(system: "System", user: String(repeating: "x", count: 65537)))
    }
    func testDifferentPinAndBoundedOptions() {
        XCTAssertEqual(LiquidGeneration.modelBytes, 730895168)
        XCTAssertThrowsError(try EvaluationOptions(context: 32768))
        XCTAssertThrowsError(try EvaluationOptions(output: 513))
    }
    func testCancellationSurvivesDispatch() {
        LiquidGeneration.prepareOperation()
        LiquidGeneration.requestCancellation()
        XCTAssertTrue(LiquidGeneration.isCancellationRequested)
        LiquidGeneration.prepareOperation()
    }
}
