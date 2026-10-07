import XCTest

final class LifecycleTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func wait(_ predicate: String, on object: Any, timeout: TimeInterval = 25) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: object)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func startLongProbe() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--manual-long-probe"]
        app.launch()
        let run = app.buttons["run-evaluation"]
        XCTAssertTrue(run.waitForExistence(timeout: 15))
        XCTAssertTrue(run.isEnabled, "Pinned model must already exist in the isolated app.")
        run.tap()
        wait("label BEGINSWITH 'Generating locally'", on: app.staticTexts["evaluation-status"])
        XCTAssertFalse(run.isEnabled, "Overlapping generation must remain disabled.")
        return app
    }

    private func verifyCancellationAndRecovery(_ app: XCUIApplication) {
        let status = app.staticTexts["evaluation-status"]
        wait("label BEGINSWITH 'cancelled:'", on: status)
        let run = app.buttons["run-evaluation"]
        wait("enabled == true", on: run)
        XCTAssertFalse(app.buttons["stop-evaluation"].isEnabled)
        run.tap()
        wait("label BEGINSWITH 'Generating locally'", on: status)
        wait("enabled == true", on: run)
        XCTAssertTrue(status.label.hasPrefix("completed:") || status.label.hasPrefix("output-limit:"), status.label)
    }

    func testActualStopTapAndNextRun() {
        let app = startLongProbe()
        app.buttons["stop-evaluation"].tap()
        verifyCancellationAndRecovery(app)
    }

    func testHomeButtonBackgroundAndForegroundRecovery() {
        let app = startLongProbe()
        XCUIDevice.shared.press(.home)
        XCTAssertNotEqual(app.state, .runningForeground)
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        verifyCancellationAndRecovery(app)
    }
}
