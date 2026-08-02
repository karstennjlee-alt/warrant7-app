import XCTest

/// Signs in for real, against whatever `API_BASE_URL` is configured, and checks the queue
/// arrives.
///
/// Credentials come from the environment, never from this file. The repository is public, and
/// a working password in a test fixture is a password in everyone's clone forever. Run with:
///
///   WARRANT_TEST_EMAIL=… WARRANT_TEST_PASSWORD=… xcodebuild test …
///
/// Skips itself when they are absent, so CI and a fresh clone stay green.
@MainActor
final class SignInFlowTests: XCTestCase {

    private func signOutIfNeeded(_ app: XCUIApplication) {
        guard app.staticTexts["Approvals"].waitForExistence(timeout: 8) else { return }

        app.buttons["More"].tap()
        app.buttons["Settings"].tap()

        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 8), "Settings should offer a way out")
        signOut.tap()
    }

    func testPasswordSignInReachesTheQueue() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["WARRANT_TEST_EMAIL"],
              let password = environment["WARRANT_TEST_PASSWORD"] else {
            throw XCTSkip("set WARRANT_TEST_EMAIL and WARRANT_TEST_PASSWORD to run this")
        }

        let app = XCUIApplication()
        app.launch()

        // A session survives app reinstall, because the Keychain belongs to the simulator
        // rather than to the app. That is correct behaviour and worth keeping — so the test
        // signs out through the real UI rather than the app growing a test-only back door.
        signOutIfNeeded(app)

        let emailField = app.textFields["you@company.com"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15), "the sign-in screen should be showing")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.exists, "password is the default path, not the fallback")
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["Sign in"].tap()

        // Signing in has to clear the sign-in screen and land on the queue. The queue may be
        // empty — that is a legitimate state and not a failure — so the assertion is on the
        // header, not on there being an approval waiting.
        let header = app.staticTexts["Approvals"]
        XCTAssertTrue(header.waitForExistence(timeout: 25), "sign-in did not reach the queue")
        XCTAssertFalse(app.buttons["Sign in"].exists, "still on the sign-in screen")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "signed-in-queue"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
