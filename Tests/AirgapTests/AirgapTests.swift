import XCTest
@testable import Airgap

final class AirgapTests: XCTestCase {

    private var violations: [String] = []
    private var originalHandler: ((String) -> Void)!
    private var originalMode: Airgap.Mode!
    private var originalReportPath: String?

    override func setUp() {
        super.setUp()
        violations = []
        originalHandler = Airgap.violationHandler
        originalMode = Airgap.mode
        originalReportPath = Airgap.reportPath

        Airgap.violationHandler = { [unowned self] message in
            self.violations.append(message)
        }
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.clearViolations()
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.violationHandler = originalHandler
        Airgap.mode = originalMode
        Airgap.reportPath = originalReportPath
        Airgap.clearViolations()
        super.tearDown()
    }

    // MARK: - Activation / Deactivation

    func testActivateRegistersProtocol() {
        Airgap.activate()
        XCTAssertTrue(AirgapURLProtocol.isActive)
    }

    func testDeactivateUnregistersProtocol() {
        Airgap.activate()
        Airgap.deactivate()
        XCTAssertFalse(AirgapURLProtocol.isActive)
    }

    func testDoubleActivateIsIdempotent() {
        Airgap.activate()
        Airgap.activate()
        XCTAssertTrue(AirgapURLProtocol.isActive)
        // No crash = success
    }

    // MARK: - Blocking requests

    func testURLSessionSharedDataTaskIsBlocked() {
        Airgap.activate()

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
        Airgap.activate()

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
        Airgap.activate()

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
        Airgap.activate()

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
        Airgap.activate()

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
        Airgap.activate()

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

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
        XCTAssertTrue(violations.isEmpty)
    }

    // MARK: - Violation message

    func testViolationMessageContainsURLAndGuidance() {
        Airgap.activate()

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
        Airgap.activate()
        Airgap.allowNetworkAccess()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
        XCTAssertTrue(violations.isEmpty)
    }

    func testActivateResetsAllowFlag() {
        Airgap.activate()
        Airgap.allowNetworkAccess()

        // Re-activate should reset the allow flag
        Airgap.activate()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        XCTAssertTrue(AirgapURLProtocol.canInit(with: request))
    }

    // MARK: - AirgapTestCase lifecycle

    func testAirgapTestCaseLifecycle() {
        let testCase = LifecycleTestCase()

        // Simulate setUp
        testCase.invokeSetUp()
        XCTAssertTrue(AirgapURLProtocol.isActive)

        // Simulate tearDown
        testCase.invokeTearDown()
        XCTAssertFalse(AirgapURLProtocol.isActive)
    }

    // MARK: - Warning mode

    func testWarnModeDoesNotFailTest() {
        Airgap.mode = .warn
        Airgap.activate()

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
        Airgap.mode = .fail
        Airgap.activate()

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
        Airgap.reportPath = tempPath
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/collect-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(Airgap.violations.count, 1)
        XCTAssertEqual(Airgap.violations[0].url, "https://example.com/api/collect-test")
        XCTAssertEqual(Airgap.violations[0].httpMethod, "GET")

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testViolationsNotCollectedWhenReportPathNil() {
        Airgap.reportPath = nil
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/no-collect-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(Airgap.violations.isEmpty)
    }

    // MARK: - Report writing

    func testWriteReportCreatesFile() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-report-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/report-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        Airgap.writeReport()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testReportContainsMethodAndURL() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-report-content-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        AirgapURLProtocol.currentTestName = "-[AirgapTests testReportContainsMethodAndURL]"
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/report-content")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        Airgap.writeReport()

        let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("Method: GET") ?? false)
        XCTAssertTrue(content?.contains("URL: https://example.com/api/report-content") ?? false)
        XCTAssertTrue(content?.contains("Test: -[AirgapTests testReportContainsMethodAndURL]") ?? false)
        XCTAssertTrue(content?.contains("Call Stack:") ?? false)
        XCTAssertTrue(content?.contains("Total violations:") ?? false)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    // MARK: - Clear violations

    func testClearViolationsResetsCollection() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-clear-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/clear-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertFalse(Airgap.violations.isEmpty)

        Airgap.clearViolations()
        XCTAssertTrue(Airgap.violations.isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    // MARK: - Mode is not reset by activate

    func testActivateDoesNotResetMode() {
        Airgap.mode = .warn
        Airgap.activate()
        XCTAssertEqual(Airgap.mode, .warn)

        Airgap.activate()
        XCTAssertEqual(Airgap.mode, .warn)
    }
}

// MARK: - Helpers

/// A concrete subclass of AirgapTestCase for testing the lifecycle methods.
private final class LifecycleTestCase: AirgapTestCase {

    func invokeSetUp() {
        setUp()
    }

    func invokeTearDown() {
        tearDown()
    }
}
