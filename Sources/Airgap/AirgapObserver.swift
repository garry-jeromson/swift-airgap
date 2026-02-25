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
open class AirgapObserver: NSObject, XCTestObservation {

    override public init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    open func testBundleWillStart(_ testBundle: Bundle) {
        Airgap.configureFromEnvironment()
        Airgap.activate()
    }

    public func testCaseWillStart(_ testCase: XCTestCase) {
        AirgapURLProtocol.isAllowed = false
        AirgapURLProtocol.currentTestName = testCase.name
    }

    public func testBundleDidFinish(_ testBundle: Bundle) {
        Airgap.writeReport()
        Airgap.deactivate()
    }
}
