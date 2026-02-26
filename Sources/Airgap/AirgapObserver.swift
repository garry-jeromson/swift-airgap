import Foundation
import XCTest

/// An XCTestObservation observer that activates Airgap before any test runs.
///
/// ## Usage with Xcode test bundles (NSPrincipalClass)
///
/// Set this class as the test bundle's principal class so it is instantiated automatically
/// when the bundle loads — no changes to existing test classes required.
///
/// **Option A** — Info.plist:
/// ```xml
/// <key>NSPrincipalClass</key>
/// <string>AirgapObserver</string>
/// ```
///
/// **Option B** — Build setting:
/// Set `INFOPLIST_KEY_NSPrincipalClass` to `AirgapObserver` in the test target.
///
/// ## How it works
///
/// 1. The test runner instantiates this class when the bundle loads.
/// 2. `init()` registers the instance as a test observer with `XCTestObservationCenter`.
/// 3. `testBundleWillStart(_:)` calls `Airgap.activate()` once, before any test runs.
/// 4. `testCaseWillStart(_:)` resets the allow flag before each test, so a previous test's
///    `allowNetworkAccess()` call does not leak into subsequent tests.
///
/// Individual tests that need real network access call `Airgap.allowNetworkAccess()`.
@objc(AirgapObserver)
open class AirgapObserver: NSObject, XCTestObservation, @unchecked Sendable {

    override public init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    /// Called before any test in the bundle runs.
    ///
    /// Sets `inXCTestContext`, reads environment variables via `configureFromEnvironment()`,
    /// and activates the guard. Subclasses should call `super` — set custom configuration
    /// (e.g., `Airgap.mode`, `Airgap.reportPath`) either before or after `super` depending
    /// on whether the environment should take precedence.
    open func testBundleWillStart(_ testBundle: Bundle) {
        Airgap.inXCTestContext = true
        Airgap.configureFromEnvironment()
        Airgap.activate()
    }

    /// Called before each test method runs.
    ///
    /// Resets the allow flag so a previous test's `allowNetworkAccess()` does not leak,
    /// and sets `currentTestName` for violation attribution.
    public func testCaseWillStart(_ testCase: XCTestCase) {
        AirgapURLProtocol.isAllowed = false
        AirgapURLProtocol.currentTestName = testCase.name
    }

    /// Called after all tests in the bundle have finished.
    ///
    /// Prints the violation summary (if any), writes the report file, and deactivates the guard.
    public func testBundleDidFinish(_ testBundle: Bundle) {
        if let summary = Airgap.violationSummary() {
            print(summary)
        }
        Airgap.writeReport()
        Airgap.deactivate()
    }
}
