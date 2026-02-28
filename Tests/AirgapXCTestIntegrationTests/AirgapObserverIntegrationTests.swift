import Airgap
import XCTest

// MARK: - AirgapObserver integration tests

/// Tests that AirgapObserver correctly registers as an XCTestObservation observer
/// and activates/deactivates the guard via the bundle lifecycle callbacks.
final class AirgapObserverIntegrationTests: XCTestCase {
    override func tearDown() {
        Airgap.deactivate()
        super.tearDown()
    }

    func testObserverActivatesGuardOnBundleWillStart() {
        let observer = AirgapObserver()

        // Simulate the bundle lifecycle callback
        observer.testBundleWillStart(Bundle.main)

        XCTAssertTrue(AirgapURLProtocol.isActive)
    }

    func testObserverDeactivatesGuardOnBundleDidFinish() {
        let observer = AirgapObserver()

        observer.testBundleWillStart(Bundle.main)
        XCTAssertTrue(AirgapURLProtocol.isActive)

        observer.testBundleDidFinish(Bundle.main)
        XCTAssertFalse(AirgapURLProtocol.isActive)
    }

    func testObserverBlocksNetworkCallsViaDefaultHandler() throws {
        let observer = AirgapObserver()
        observer.testBundleWillStart(Bundle.main)

        XCTExpectFailure("AirgapObserver should block network calls after testBundleWillStart")

        let expectation = expectation(description: "Data task completes")
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testObserverAllowsOptOutViaAllowNetworkAccess() throws {
        let observer = AirgapObserver()
        observer.testBundleWillStart(Bundle.main)
        Airgap.allowNetworkAccess()

        // No XCTExpectFailure — should pass cleanly.
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testObserverResetsAllowFlagBetweenTests() throws {
        let observer = AirgapObserver()
        observer.testBundleWillStart(Bundle.main)

        // Simulate a test that opts out
        Airgap.allowNetworkAccess()
        XCTAssertTrue(AirgapURLProtocol.isAllowed)

        // Simulate the next test starting — allow flag should be reset
        observer.testCaseWillStart(self)
        XCTAssertFalse(AirgapURLProtocol.isAllowed)

        // The guard should now block requests again
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))
        let request = URLRequest(url: url)
        XCTAssertTrue(AirgapURLProtocol.canInit(with: request))
    }
}
