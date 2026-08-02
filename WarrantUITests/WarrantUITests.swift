import XCTest

/// The two flows from §10, run against demo mode so they need no gateway and no network.
// XCUITest's whole API is main-actor isolated under Swift 6, and a UI test that hops
// isolation to tap a button is a UI test with a race in it.
@MainActor
final class WarrantUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Keeps a picture of each step in the result bundle, so a run is reviewable afterwards
    /// rather than only pass/fail.
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WarrantDemoMode", "1"]
        app.launch()
        return app
    }

    /// Flow one: get to the pending $2,400 refund and deny it.
    ///
    /// Denying is the flow worth automating: it is the outcome that must never require a
    /// biometric prompt, which means it is the one a test can actually drive end to end.
    func testDenyTheInjectedRefund() throws {
        let app = launch()

        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] '2,400'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the pending approval should be in the inbox")
        capture("01-inbox")
        row.tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("02-approval-card")

        let deny = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Deny'")).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        deny.tap()

        // Pocket-tap guard may intervene if we got here in under three seconds.
        let confirm = app.alerts.buttons["Deny"]
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }

        let reason = app.buttons["Prompt injection in the request"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5), "a denial needs a reason on the receipt")
        capture("03-deny-reasons")
        reason.tap()

        app.buttons["Deny and sign"].tap()
        Thread.sleep(forTimeInterval: 2)
        capture("04-denied-stamp")

        // The sealed receipt states the outcome plainly, and shows the signature.
        let outcome = app.staticTexts["The refund did not happen"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Signed · Ed25519"].waitForExistence(timeout: 5))
    }

    /// Flow two: verification runs on device and names the record that was altered.
    func testVerifyTheLedgerOnDevice() throws {
        let app = launch()

        app.buttons["Receipts"].tap()

        let verify = app.buttons["Verify with public key"]
        XCTAssertTrue(verify.waitForExistence(timeout: 10))
        verify.tap()

        // Records are stamped 80ms apart, so allow for the walk down the chain.
        let verified = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'verified'")).firstMatch
        XCTAssertTrue(verified.waitForExistence(timeout: 20), "an untouched demo ledger must verify")
        Thread.sleep(forTimeInterval: 1.5)
        capture("05-ledger-verified")
    }

    /// The Verify tab is reachable and states its offline claim.
    func testVerifyTabWorksAndSaysItIsOffline() throws {
        let app = launch()

        app.buttons["Verify"].tap()

        let offline = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'airplane mode'")).firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10))
        let scan = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Scan a bundle'")).firstMatch
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        capture("06-verify-tab")
    }
}
