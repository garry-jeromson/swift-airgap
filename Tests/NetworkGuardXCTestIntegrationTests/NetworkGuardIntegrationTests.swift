import XCTest
import NetworkGuard

// MARK: - Integration tests using the default XCTFail handler

/// These tests verify the package from a consumer's perspective — confirming that
/// network violations produce actual XCTest failures, and that allowed/inactive
/// scenarios pass cleanly.
final class NetworkGuardIntegrationTests: XCTestCase {

    override func tearDown() {
        NetworkGuard.deactivate()
        super.tearDown()
    }

    // MARK: - Tests that should fail (wrapped in XCTExpectFailure)

    func testNetworkCallWithDefaultHandlerProducesXCTFailure() {
        NetworkGuard.activate()

        XCTExpectFailure("NetworkGuard should trigger XCTFail for blocked requests")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testCustomSessionDefaultConfigWithDefaultHandlerProducesXCTFailure() {
        NetworkGuard.activate()

        XCTExpectFailure("NetworkGuard should trigger XCTFail for custom session with .default config")

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .default)
        let url = URL(string: "https://example.com/api")!

        session.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testCustomSessionEphemeralConfigWithDefaultHandlerProducesXCTFailure() {
        NetworkGuard.activate()

        XCTExpectFailure("NetworkGuard should trigger XCTFail for custom session with .ephemeral config")

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://example.com/api")!

        session.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Tests that should pass (no expected failure)

    func testAllowNetworkAccessPreventsXCTFailure() {
        NetworkGuard.activate()
        NetworkGuard.allowNetworkAccess()

        // No XCTExpectFailure — this should genuinely pass without any failure.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        // canInit returning false proves the request would not be intercepted.
        XCTAssertFalse(NetworkGuardURLProtocol.canInit(with: request))
    }

    func testDeactivatedGuardDoesNotProduceXCTFailure() {
        NetworkGuard.activate()
        NetworkGuard.deactivate()

        // No XCTExpectFailure — this should genuinely pass.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(NetworkGuardURLProtocol.canInit(with: request))
    }

    func testFileURLDoesNotProduceXCTFailure() {
        NetworkGuard.activate()

        // No XCTExpectFailure — file:// should never trigger the guard.
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("networkguard-integration-test.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "File load completes")

        URLSession.shared.dataTask(with: tempFile) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        try? FileManager.default.removeItem(at: tempFile)
    }
}

// MARK: - NetworkGuardTestCase consumer integration tests

/// Simulates how a consumer would use NetworkGuardTestCase as their base class.
/// Network calls should produce XCTFail via the inherited setUp/tearDown lifecycle.
final class NetworkGuardTestCaseIntegrationTests: NetworkGuardTestCase {

    func testNetworkCallInTestCaseSubclassProducesXCTFailure() {
        XCTExpectFailure("NetworkGuardTestCase should block network calls automatically")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testFileURLInTestCaseSubclassDoesNotFail() {
        // No XCTExpectFailure — file:// URLs should not trigger the guard.
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("networkguard-testcase-test.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "File load completes")

        URLSession.shared.dataTask(with: tempFile) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        try? FileManager.default.removeItem(at: tempFile)
    }
}

// MARK: - NetworkGuardTestCase with allowNetworkAccess opt-out

/// Simulates a consumer who inherits NetworkGuardTestCase but opts out via allowNetworkAccess().
final class NetworkGuardTestCaseOptOutIntegrationTests: NetworkGuardTestCase {

    override func setUp() {
        super.setUp()
        NetworkGuard.allowNetworkAccess()
    }

    func testOptedOutSuiteDoesNotProduceXCTFailure() {
        // No XCTExpectFailure — allowNetworkAccess() in setUp should prevent failures.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(NetworkGuardURLProtocol.canInit(with: request))
    }
}

// MARK: - NetworkGuardObserver integration tests

/// Tests that NetworkGuardObserver correctly registers as an XCTestObservation observer
/// and activates/deactivates the guard via the bundle lifecycle callbacks.
final class NetworkGuardObserverIntegrationTests: XCTestCase {

    override func tearDown() {
        NetworkGuard.deactivate()
        super.tearDown()
    }

    func testObserverActivatesGuardOnBundleWillStart() {
        let observer = NetworkGuardObserver()

        // Simulate the bundle lifecycle callback
        observer.testBundleWillStart(Bundle.main)

        XCTAssertTrue(NetworkGuardURLProtocol.isActive)
    }

    func testObserverDeactivatesGuardOnBundleDidFinish() {
        let observer = NetworkGuardObserver()

        observer.testBundleWillStart(Bundle.main)
        XCTAssertTrue(NetworkGuardURLProtocol.isActive)

        observer.testBundleDidFinish(Bundle.main)
        XCTAssertFalse(NetworkGuardURLProtocol.isActive)
    }

    func testObserverBlocksNetworkCallsViaDefaultHandler() {
        let observer = NetworkGuardObserver()
        observer.testBundleWillStart(Bundle.main)

        XCTExpectFailure("NetworkGuardObserver should block network calls after testBundleWillStart")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testObserverAllowsOptOutViaAllowNetworkAccess() {
        let observer = NetworkGuardObserver()
        observer.testBundleWillStart(Bundle.main)
        NetworkGuard.allowNetworkAccess()

        // No XCTExpectFailure — should pass cleanly.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(NetworkGuardURLProtocol.canInit(with: request))
    }

    func testObserverResetsAllowFlagBetweenTests() {
        let observer = NetworkGuardObserver()
        observer.testBundleWillStart(Bundle.main)

        // Simulate a test that opts out
        NetworkGuard.allowNetworkAccess()
        XCTAssertTrue(NetworkGuardURLProtocol.isAllowed)

        // Simulate the next test starting — allow flag should be reset
        observer.testCaseWillStart(self)
        XCTAssertFalse(NetworkGuardURLProtocol.isAllowed)

        // The guard should now block requests again
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)
        XCTAssertTrue(NetworkGuardURLProtocol.canInit(with: request))
    }
}

// MARK: - Warn mode integration tests

/// These tests verify that warn mode does NOT fail the test — no XCTExpectFailure wrapper
/// is needed because warn mode handles it internally via XCTExpectFailure.
/// If warn mode is broken, these tests would fail with an unexpected XCTFail.
final class NetworkGuardWarnModeIntegrationTests: XCTestCase {

    private var originalMode: NetworkGuard.Mode!

    override func setUp() {
        super.setUp()
        originalMode = NetworkGuard.mode
        NetworkGuard.mode = .warn
    }

    override func tearDown() {
        NetworkGuard.deactivate()
        NetworkGuard.mode = originalMode
        super.tearDown()
    }

    func testWarnModeDoesNotFailTestWithDefaultHandler() {
        // No XCTExpectFailure here — warn mode should handle it internally.
        // If this test fails, warn mode is broken.
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/warn-integration")!

        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error, "Blocked request should still deliver an error")
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeWithCustomSessionDoesNotFailTest() {
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .default)
        let url = URL(string: "https://example.com/api/warn-custom-session")!

        session.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeCollectsViolationsForReport() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-warn-integration-\(UUID().uuidString).txt").path
        NetworkGuard.reportPath = tempPath
        NetworkGuard.clearViolations()
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/warn-report")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        NetworkGuard.writeReport()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), "Report file should be created")
        let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content?.contains("warn-report") ?? false, "Report should contain the URL")

        // Cleanup
        NetworkGuard.reportPath = nil
        NetworkGuard.clearViolations()
        try? FileManager.default.removeItem(atPath: tempPath)
    }
}
