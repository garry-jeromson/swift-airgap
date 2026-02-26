import XCTest

/// An XCTestCase subclass that automatically activates and deactivates the network guard.
///
/// Inherit from this class instead of `XCTestCase` to block network access for all tests in the suite.
///
/// To opt out a specific test or subclass that needs network access, override `setUp` and call
/// `Airgap.allowNetworkAccess()` after `super.setUp()`.
open class AirgapTestCase: XCTestCase {

    override open func setUp() {
        super.setUp()
        Airgap.inXCTestContext = true
        Airgap.configureFromEnvironment()
        configure()
        Airgap.clearViolations()
        AirgapURLProtocol.currentTestName = name
        Airgap.activate()
    }

    /// Override to configure Airgap after environment variables are applied.
    /// Called after `configureFromEnvironment()` and before `activate()`.
    open func configure() {}

    override open func tearDown() {
        if let summary = Airgap.violationSummary() {
            print(summary)
        }
        Airgap.writeReport()
        Airgap.deactivate()
        super.tearDown()
    }
}
