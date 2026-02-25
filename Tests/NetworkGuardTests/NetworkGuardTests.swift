import XCTest
@testable import NetworkGuard

final class NetworkGuardTests: XCTestCase {

    private var violations: [String] = []
    private var originalHandler: ((String) -> Void)!
    private var originalMode: NetworkGuard.Mode!
    private var originalReportPath: String?

    override func setUp() {
        super.setUp()
        violations = []
        originalHandler = NetworkGuard.violationHandler
        originalMode = NetworkGuard.mode
        originalReportPath = NetworkGuard.reportPath

        NetworkGuard.violationHandler = { [unowned self] message in
            self.violations.append(message)
        }
        NetworkGuard.mode = .fail
        NetworkGuard.reportPath = nil
        NetworkGuard.clearViolations()
    }

    override func tearDown() {
        NetworkGuard.deactivate()
        NetworkGuard.violationHandler = originalHandler
        NetworkGuard.mode = originalMode
        NetworkGuard.reportPath = originalReportPath
        NetworkGuard.clearViolations()
        super.tearDown()
    }

    // MARK: - Activation / Deactivation

    func testActivateRegistersProtocol() {
        NetworkGuard.activate()
        XCTAssertTrue(NetworkGuardURLProtocol.isActive)
    }

    func testDeactivateUnregistersProtocol() {
        NetworkGuard.activate()
        NetworkGuard.deactivate()
        XCTAssertFalse(NetworkGuardURLProtocol.isActive)
    }

    func testDoubleActivateIsIdempotent() {
        NetworkGuard.activate()
        NetworkGuard.activate()
        XCTAssertTrue(NetworkGuardURLProtocol.isActive)
        // No crash = success
    }

    // MARK: - Blocking requests

    func testURLSessionSharedDataTaskIsBlocked() {
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://httpbin.org/get")!

        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(violations.count, 1)
    }

    func testURLSessionSharedAsyncDataIsBlocked() async {
        NetworkGuard.activate()

        let url = URL(string: "https://httpbin.org/get")!

        do {
            _ = try await URLSession.shared.data(from: url)
            XCTFail("Expected an error to be thrown")
        } catch {
            // Expected
        }

        XCTAssertEqual(violations.count, 1)
    }

    func testURLSessionWithDefaultConfigIsBlocked() {
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let url = URL(string: "https://httpbin.org/get")!

        session.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(violations.count, 1)
    }

    func testURLSessionWithEphemeralConfigIsBlocked() {
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        let url = URL(string: "https://httpbin.org/get")!

        session.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(violations.count, 1)
    }

    func testHTTPSchemeIsBlocked() {
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "http://httpbin.org/get")!

        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(violations.count, 1)
    }

    // MARK: - Non-HTTP schemes

    func testLocalFileURLIsNotBlocked() {
        NetworkGuard.activate()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("networkguard-test.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "File load completes")

        URLSession.shared.dataTask(with: tempFile) { _, _, _ in
            // file:// should not be intercepted — it either succeeds or fails for file-system reasons
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(violations.isEmpty)

        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: - Inactive guard

    func testNoViolationWhenInactive() {
        // Guard is not activated — requests should not be intercepted.
        // We verify by checking that canInit returns false.
        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        XCTAssertFalse(NetworkGuardURLProtocol.canInit(with: request))
        XCTAssertTrue(violations.isEmpty)
    }

    // MARK: - Violation message

    func testViolationMessageContainsURLAndGuidance() {
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(violations.count, 1)

        let message = violations[0]
        XCTAssertTrue(message.contains("https://example.com/api/test"), "Message should contain the URL")
        XCTAssertTrue(message.contains("GET"), "Message should contain the HTTP method")
        XCTAssertTrue(message.contains("mock") || message.contains("stub"), "Message should contain guidance")
    }

    // MARK: - Allow network access

    func testAllowNetworkAccessDisablesGuard() {
        NetworkGuard.activate()
        NetworkGuard.allowNetworkAccess()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        XCTAssertFalse(NetworkGuardURLProtocol.canInit(with: request))
        XCTAssertTrue(violations.isEmpty)
    }

    func testActivateResetsAllowFlag() {
        NetworkGuard.activate()
        NetworkGuard.allowNetworkAccess()

        // Re-activate should reset the allow flag
        NetworkGuard.activate()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        XCTAssertTrue(NetworkGuardURLProtocol.canInit(with: request))
    }

    // MARK: - NetworkGuardTestCase lifecycle

    func testNetworkGuardTestCaseLifecycle() {
        let testCase = LifecycleTestCase()

        // Simulate setUp
        testCase.invokeSetUp()
        XCTAssertTrue(NetworkGuardURLProtocol.isActive)

        // Simulate tearDown
        testCase.invokeTearDown()
        XCTAssertFalse(NetworkGuardURLProtocol.isActive)
    }

    // MARK: - Warning mode

    func testWarnModeDoesNotFailTest() {
        NetworkGuard.mode = .warn
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/warn-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        // In warn mode, the violation is handled via XCTExpectFailure internally
        // and does NOT call the custom violationHandler, so the violations array
        // captured by our test handler should be empty.
        XCTAssertEqual(violations.count, 0)
    }

    func testFailModeCallsViolationHandlerDirectly() {
        NetworkGuard.mode = .fail
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/fail-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations[0].contains("fail-test"))
    }

    // MARK: - Violation collection

    func testViolationsCollectedWhenReportPathSet() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-test-\(UUID().uuidString).txt").path
        NetworkGuard.reportPath = tempPath
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/collect-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(NetworkGuard.violations.count, 1)
        XCTAssertEqual(NetworkGuard.violations[0].url, "https://example.com/api/collect-test")
        XCTAssertEqual(NetworkGuard.violations[0].httpMethod, "GET")

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testViolationsNotCollectedWhenReportPathNil() {
        NetworkGuard.reportPath = nil
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/no-collect-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(NetworkGuard.violations.isEmpty)
    }

    // MARK: - Report writing

    func testWriteReportCreatesFile() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-report-\(UUID().uuidString).txt").path
        NetworkGuard.reportPath = tempPath
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/report-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        NetworkGuard.writeReport()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testReportContainsMethodAndURL() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-report-content-\(UUID().uuidString).txt").path
        NetworkGuard.reportPath = tempPath
        NetworkGuardURLProtocol.currentTestName = "-[NetworkGuardTests testReportContainsMethodAndURL]"
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/report-content")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        NetworkGuard.writeReport()

        let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("Method: GET") ?? false)
        XCTAssertTrue(content?.contains("URL: https://example.com/api/report-content") ?? false)
        XCTAssertTrue(content?.contains("Test: -[NetworkGuardTests testReportContainsMethodAndURL]") ?? false)
        XCTAssertTrue(content?.contains("Call Stack:") ?? false)
        XCTAssertTrue(content?.contains("Total violations:") ?? false)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    // MARK: - Clear violations

    func testClearViolationsResetsCollection() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-clear-\(UUID().uuidString).txt").path
        NetworkGuard.reportPath = tempPath
        NetworkGuard.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/clear-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertFalse(NetworkGuard.violations.isEmpty)

        NetworkGuard.clearViolations()
        XCTAssertTrue(NetworkGuard.violations.isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    // MARK: - Mode is not reset by activate

    func testActivateDoesNotResetMode() {
        NetworkGuard.mode = .warn
        NetworkGuard.activate()
        XCTAssertEqual(NetworkGuard.mode, .warn)

        NetworkGuard.activate()
        XCTAssertEqual(NetworkGuard.mode, .warn)
    }
}

// MARK: - Helpers

/// A concrete subclass of NetworkGuardTestCase for testing the lifecycle methods.
private final class LifecycleTestCase: NetworkGuardTestCase {

    func invokeSetUp() {
        setUp()
    }

    func invokeTearDown() {
        tearDown()
    }
}
