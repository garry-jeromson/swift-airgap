import XCTest
import Airgap

// MARK: - Integration tests using the default XCTFail handler

/// These tests verify the package from a consumer's perspective — confirming that
/// network violations produce actual XCTest failures, and that allowed/inactive
/// scenarios pass cleanly.
final class AirgapIntegrationTests: XCTestCase {

    override func tearDown() {
        Airgap.deactivate()
        super.tearDown()
    }

    // MARK: - Tests that should fail (wrapped in XCTExpectFailure)

    func testNetworkCallWithDefaultHandlerProducesXCTFailure() {
        Airgap.activate()

        XCTExpectFailure("Airgap should trigger XCTFail for blocked requests")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testCustomSessionDefaultConfigWithDefaultHandlerProducesXCTFailure() {
        Airgap.activate()

        XCTExpectFailure("Airgap should trigger XCTFail for custom session with .default config")

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .default)
        let url = URL(string: "https://example.com/api")!

        session.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testCustomSessionEphemeralConfigWithDefaultHandlerProducesXCTFailure() {
        Airgap.activate()

        XCTExpectFailure("Airgap should trigger XCTFail for custom session with .ephemeral config")

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
        Airgap.activate()
        Airgap.allowNetworkAccess()

        // No XCTExpectFailure — this should genuinely pass without any failure.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        // canInit returning false proves the request would not be intercepted.
        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testDeactivatedGuardDoesNotProduceXCTFailure() {
        Airgap.activate()
        Airgap.deactivate()

        // No XCTExpectFailure — this should genuinely pass.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testFileURLDoesNotProduceXCTFailure() {
        Airgap.activate()

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

// MARK: - AirgapTestCase consumer integration tests

/// Simulates how a consumer would use AirgapTestCase as their base class.
/// Network calls should produce XCTFail via the inherited setUp/tearDown lifecycle.
final class AirgapTestCaseIntegrationTests: AirgapTestCase {

    func testNetworkCallInTestCaseSubclassProducesXCTFailure() {
        XCTExpectFailure("AirgapTestCase should block network calls automatically")

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

// MARK: - AirgapTestCase with allowNetworkAccess opt-out

/// Simulates a consumer who inherits AirgapTestCase but opts out via allowNetworkAccess().
final class AirgapTestCaseOptOutIntegrationTests: AirgapTestCase {

    override func setUp() {
        super.setUp()
        Airgap.allowNetworkAccess()
    }

    func testOptedOutSuiteDoesNotProduceXCTFailure() {
        // No XCTExpectFailure — allowNetworkAccess() in setUp should prevent failures.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }
}

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

    func testObserverBlocksNetworkCallsViaDefaultHandler() {
        let observer = AirgapObserver()
        observer.testBundleWillStart(Bundle.main)

        XCTExpectFailure("AirgapObserver should block network calls after testBundleWillStart")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testObserverAllowsOptOutViaAllowNetworkAccess() {
        let observer = AirgapObserver()
        observer.testBundleWillStart(Bundle.main)
        Airgap.allowNetworkAccess()

        // No XCTExpectFailure — should pass cleanly.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testObserverResetsAllowFlagBetweenTests() {
        let observer = AirgapObserver()
        observer.testBundleWillStart(Bundle.main)

        // Simulate a test that opts out
        Airgap.allowNetworkAccess()
        XCTAssertTrue(AirgapURLProtocol.isAllowed)

        // Simulate the next test starting — allow flag should be reset
        observer.testCaseWillStart(self)
        XCTAssertFalse(AirgapURLProtocol.isAllowed)

        // The guard should now block requests again
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)
        XCTAssertTrue(AirgapURLProtocol.canInit(with: request))
    }
}

// MARK: - Warn mode integration tests

/// These tests verify that warn mode does NOT fail the test — no XCTExpectFailure wrapper
/// is needed because warn mode handles it internally via XCTExpectFailure.
/// If warn mode is broken, these tests would fail with an unexpected XCTFail.
final class AirgapWarnModeIntegrationTests: XCTestCase {

    private var originalMode: Airgap.Mode!

    override func setUp() {
        super.setUp()
        originalMode = Airgap.mode
        Airgap.mode = .warn
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.mode = originalMode
        super.tearDown()
    }

    func testWarnModeDoesNotFailTestWithDefaultHandler() {
        // No XCTExpectFailure here — warn mode should handle it internally.
        // If this test fails, warn mode is broken.
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/warn-integration")!

        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error, "Blocked request should still deliver an error")
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeWithAsyncAwaitDoesNotFailTest() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/warn-async")!
        do {
            _ = try await URLSession.shared.data(from: url)
        } catch {
            // Expected — blocked request delivers an error
        }
        // Test should pass — warn mode wraps failure in XCTExpectFailure
    }

    func testWarnModeWithCustomSessionDoesNotFailTest() {
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .default)
        let url = URL(string: "https://example.com/api/warn-custom-session")!

        session.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeWithEphemeralSessionDoesNotFailTest() {
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://example.com/api/warn-ephemeral")!

        session.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeCollectsViolationsForReport() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-warn-integration-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.clearViolations()
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/warn-report")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        Airgap.writeReport()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), "Report file should be created")
        let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content?.contains("warn-report") ?? false, "Report should contain the URL")

        // Cleanup
        Airgap.reportPath = nil
        Airgap.clearViolations()
        try? FileManager.default.removeItem(atPath: tempPath)
    }
}

// MARK: - Allowed hosts integration tests

/// These tests verify that the allowedHosts feature works correctly from
/// a consumer's perspective, including actual network request interception.
final class AirgapAllowedHostsIntegrationTests: XCTestCase {

    private var originalAllowedHosts: Set<String>!

    override func setUp() {
        super.setUp()
        originalAllowedHosts = Airgap.allowedHosts
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.allowedHosts = originalAllowedHosts
        super.tearDown()
    }

    func testAllowedHostDoesNotProduceXCTFailure() {
        Airgap.allowedHosts = ["example.com"]
        Airgap.activate()

        // No XCTExpectFailure — allowed host should pass cleanly.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testNonAllowedHostProducesXCTFailure() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        XCTExpectFailure("Non-allowed host should trigger XCTFail")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testAllowedHostWithActualDataTask() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        // localhost requests should not be intercepted
        let url = URL(string: "https://localhost/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testAllowedHostsWithWarnMode() {
        Airgap.allowedHosts = ["example.com"]
        Airgap.mode = .warn
        Airgap.activate()
        defer { Airgap.mode = .fail }

        // Allowed host should not produce any violation even in warn mode
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }
}

// MARK: - Violation summary integration tests

final class AirgapViolationSummaryIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Airgap.clearViolations()
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.reportPath = nil
        Airgap.clearViolations()
        super.tearDown()
    }

    func testViolationSummaryWithDefaultHandler() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-summary-int-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.activate()

        XCTExpectFailure("Violation should trigger XCTFail")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/summary")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        let summary = Airgap.violationSummary()
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("violation(s)") ?? false)

        try? FileManager.default.removeItem(atPath: tempPath)
    }
}
