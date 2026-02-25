import XCTest

/// An XCTestCase subclass that automatically activates and deactivates the network guard.
///
/// Inherit from this class instead of `XCTestCase` to block network access for all tests in the suite.
///
/// To opt out a specific test or subclass that needs network access, override `setUp` and call
/// `NetworkGuard.allowNetworkAccess()` after `super.setUp()`.
open class NetworkGuardTestCase: XCTestCase {

    override open func setUp() {
        super.setUp()
        NetworkGuard.configureFromEnvironment()
        NetworkGuardURLProtocol.currentTestName = name
        NetworkGuard.activate()
    }

    override open func tearDown() {
        NetworkGuard.writeReport()
        NetworkGuard.deactivate()
        super.tearDown()
    }
}
