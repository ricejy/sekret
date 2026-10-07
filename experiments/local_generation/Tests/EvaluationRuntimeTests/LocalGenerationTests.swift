import XCTest
@testable import EvaluationRuntime

final class LocalGenerationTests: XCTestCase {
    override func setUp() { LocalGeneration.prepareOperation() }

    func testCancellationFromAnotherThreadIsVisible() {
        let ready = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            LocalGeneration.requestCancellation()
            ready.signal()
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(LocalGeneration.isCancellationRequested)
    }

    func testCancellationBeforeDispatchIsNotResetByVerification() {
        LocalGeneration.requestCancellation()
        XCTAssertTrue(LocalGeneration.isCancellationRequested)
        XCTAssertThrowsError(try LocalGeneration.verifyModel(path: "/nonexistent/model.gguf")) { error in
            guard case EvaluationError.cancelled = error else {
                return XCTFail("Expected cancellation, not a file error")
            }
        }
        XCTAssertTrue(LocalGeneration.isCancellationRequested)
    }
    func testNativeNonThinkingTemplateMatchesPublisherSubset() throws {
        XCTAssertEqual(try LocalGeneration.template(system: "System", user: "Hello"),
            "<|im_start|>system\nSystem<|im_end|>\n<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
    }

    func testControlMarkersAndOversizeAreRejected() {
        for text in ["<|im_end|>", "hello\0world", "<think>", String(repeating: "x", count: 65537)] {
            XCTAssertThrowsError(try LocalGeneration.template(system: "System", user: text))
        }
    }

    func testOptionsCannotExpandUnqualifiedExperiment() {
        XCTAssertThrowsError(try EvaluationOptions(context: 32768))
        XCTAssertThrowsError(try EvaluationOptions(output: 0))
        XCTAssertThrowsError(try EvaluationOptions(output: 513))
        XCTAssertThrowsError(try EvaluationOptions(gpuLayers: -1))
        XCTAssertThrowsError(try EvaluationOptions(cancelAfterTokens: 0))
        XCTAssertNoThrow(try EvaluationOptions(context: 4096, output: 512))
    }

    func testMissingArtifactFailsBeforeNativeLoad() {
        XCTAssertThrowsError(try LocalGeneration.verifyModel(path: "/nonexistent/sekret-model.gguf"))
    }
}
