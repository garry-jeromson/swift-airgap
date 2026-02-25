import Foundation
import XCTest

/// An XCTestObservation observer that activates NetworkGuard before any test runs.
///
/// ## Usage with Xcode test bundles (NSPrincipalClass)
///
/// Set this class as the test bundle's principal class so it is instantiated automatically
/// when the bundle loads — no changes to existing test classes required.
///
/// **Option A** — Info.plist:
/// ```xml
/// <key>NSPrincipalClass</key>
/// <string>NetworkGuardObserver</string>
/// ```
///
/// **Option B** — Build setting:
/// Set `INFOPLIST_KEY_NSPrincipalClass` to `NetworkGuardObserver` in the test target.
///
/// ## How it works
///
/// 1. The test runner instantiates this class when the bundle loads.
/// 2. `init()` registers the instance as a test observer with `XCTestObservationCenter`.
/// 3. `testBundleWillStart(_:)` calls `NetworkGuard.activate()` once, before any test runs.
/// 4. `testCaseWillStart(_:)` resets the allow flag before each test, so a previous test's
///    `allowNetworkAccess()` call does not leak into subsequent tests.
///
/// Individual tests that need real network access call `NetworkGuard.allowNetworkAccess()`.
@objc(NetworkGuardObserver)
open class NetworkGuardObserver: NSObject, XCTestObservation {

    override public init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    open func testBundleWillStart(_ testBundle: Bundle) {
        NetworkGuard.configureFromEnvironment()
        NetworkGuard.activate()
    }

    public func testCaseWillStart(_ testCase: XCTestCase) {
        NetworkGuardURLProtocol.isAllowed = false
        NetworkGuardURLProtocol.currentTestName = testCase.name
    }

    public func testBundleDidFinish(_ testBundle: Bundle) {
        NetworkGuard.writeReport()
        NetworkGuard.deactivate()
    }
}
