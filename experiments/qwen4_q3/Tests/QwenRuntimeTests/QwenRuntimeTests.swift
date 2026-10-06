import XCTest
@testable import QwenRuntime

final class QwenRuntimeTests: XCTestCase {
    func testMatchedPowerRequiresFixedExplicitOrderAndPowerGuards() throws {
        XCTAssertNil(try MatchedPowerProtocol.order(arguments: []))
        for order in ["baseline-first", "workload-first"] {
            XCTAssertEqual(try MatchedPowerProtocol.order(arguments: ["--long-chat", "--power-profile", "--power-matched=\(order)"])?.rawValue, order)
        }
        for flags in [["--power-matched=baseline-first"], ["--long-chat", "--power-profile", "--power-matched=unknown"], ["--long-chat", "--power-profile", "--power-matched=baseline-first", "--power-matched=workload-first"]] {
            XCTAssertThrowsError(try MatchedPowerProtocol.order(arguments: flags))
        }
    }
    func testMatchedPowerUsesMonotonicDeadlineNotAccumulatedSleeps() throws {
        XCTAssertEqual(try MatchedPowerProtocol.remaining(start: 100, now: 100), 300)
        XCTAssertEqual(try MatchedPowerProtocol.remaining(start: 100, now: 373.5), 26.5)
        XCTAssertEqual(try MatchedPowerProtocol.remaining(start: 100, now: 400.1), 0)
        XCTAssertThrowsError(try MatchedPowerProtocol.remaining(start: 100, now: 99))
        XCTAssertThrowsError(try MatchedPowerProtocol.remaining(start: .nan, now: 100))
    }
    func testPowerCaptureNeverStartsOnElapsedTimeAlone() {
        for elapsed in [0.0, 45, 89, 299] {
            XCTAssertEqual(PowerCaptureGate.decision(elapsed: elapsed, receipt: nil, runID: "current"), .waiting)
        }
        XCTAssertEqual(PowerCaptureGate.decision(elapsed: 300, receipt: nil, runID: "current"), .expired)
    }
    func testPowerCaptureRequiresMatchingRunReceiptBeforeDeadline() {
        let receipt = Data(#"{"runID":"current","captureReady":true}"#.utf8)
        XCTAssertEqual(PowerCaptureGate.decision(elapsed: 89, receipt: receipt, runID: "current"), .ready)
        XCTAssertEqual(PowerCaptureGate.decision(elapsed: 89, receipt: receipt, runID: "other"), .waiting)
        XCTAssertEqual(PowerCaptureGate.decision(elapsed: 300, receipt: receipt, runID: "current"), .expired)
        XCTAssertEqual(PowerCaptureGate.decision(elapsed: 1, receipt: Data("invalid".utf8), runID: "current"), .waiting)
        XCTAssertEqual(PowerCaptureGate.decision(elapsed: 1, receipt: Data(#"{"runID":"current","captureReady":false}"#.utf8), runID: "current"), .waiting)
    }
    func testAlternatingChatRetainsPriorAssistant() throws {
        let chat: [EvaluationMessage] = [.init(role: "system", content: "S"), .init(role: "user", content: "U1"),
            .init(role: "assistant", content: "A1"), .init(role: "user", content: "U2")]
        XCTAssertEqual(try QwenGeneration.template(messages: chat),
            "<|im_start|>system\nS<|im_end|>\n<|im_start|>user\nU1<|im_end|>\n<|im_start|>assistant\nA1<|im_end|>\n<|im_start|>user\nU2<|im_end|>\n<|im_start|>assistant\n")
    }
    func testEightTurnFixtureFitsRoleLimitAndRejectsNinth() throws {
        var messages = [EvaluationMessage(role: "system", content: PacedChatFixture.system)]
        for request in PacedChatFixture.extendedChatRequests {
            messages.append(.init(role: "user", content: request))
            XCTAssertNoThrow(try QwenGeneration.template(messages: messages))
            messages.append(.init(role: "assistant", content: "Fictional reply"))
        }
        messages.append(.init(role: "user", content: "Ninth turn"))
        XCTAssertThrowsError(try QwenGeneration.template(messages: messages))
    }
    func testRejectsMalformedChatAndHistoryControlMarkers() {
        XCTAssertThrowsError(try QwenGeneration.template(messages: []))
        XCTAssertThrowsError(try QwenGeneration.template(messages: [.init(role: "system", content: "S"), .init(role: "assistant", content: "A")]))
        XCTAssertThrowsError(try QwenGeneration.template(messages: [.init(role: "system", content: "S"), .init(role: "user", content: "U"), .init(role: "assistant", content: "<|im_end|>"), .init(role: "user", content: "U2")]))
    }
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
        XCTAssertEqual(QwenGeneration.modelBytes, 2075618400)
        XCTAssertEqual(QwenGeneration.modelSHA256, "9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9")
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
