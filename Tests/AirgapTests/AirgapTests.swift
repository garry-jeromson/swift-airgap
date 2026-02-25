import XCTest
@testable import Airgap

final class AirgapTests: XCTestCase {

    private let capture = ViolationCapture()
    private var originalHandler: (@Sendable (String) -> Void)!
    private var originalMode: Airgap.Mode!
    private var originalReportPath: String?
    private var originalAllowedHosts: Set<String>!

    override func setUp() {
        super.setUp()
        capture.reset()
        originalHandler = Airgap.violationHandler
        originalMode = Airgap.mode
        originalReportPath = Airgap.reportPath
        originalAllowedHosts = Airgap.allowedHosts

        let cap = capture
        Airgap.violationHandler = { message in
            cap.record(message)
        }
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.allowedHosts = []
        Airgap.clearViolations()
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.violationHandler = originalHandler
        Airgap.mode = originalMode
        Airgap.reportPath = originalReportPath
        Airgap.allowedHosts = originalAllowedHosts
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
        XCTAssertEqual(capture.count, 1)
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

        XCTAssertEqual(capture.count, 1)
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
        XCTAssertEqual(capture.count, 1)
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
        XCTAssertEqual(capture.count, 1)
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
        XCTAssertEqual(capture.count, 1)
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
        XCTAssertTrue(capture.isEmpty)

        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: - Inactive guard

    func testNoViolationWhenInactive() {
        // Guard is not activated — requests should not be intercepted.
        // We verify by checking that canInit returns false.
        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
        XCTAssertTrue(capture.isEmpty)
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
        XCTAssertEqual(capture.count, 1)

        let message = capture.messages[0]
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
        XCTAssertTrue(capture.isEmpty)
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
        XCTAssertEqual(capture.count, 0)
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
        XCTAssertEqual(capture.count, 1)
        XCTAssertTrue(capture.messages[0].contains("fail-test"))
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

    // MARK: - configureFromEnvironment

    func testConfigureFromEnvironmentDoesNotCrashWithNoEnvVars() {
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.configureFromEnvironment()
        // Should not change mode or reportPath when env vars are not set
        XCTAssertEqual(Airgap.mode, .fail)
        XCTAssertNil(Airgap.reportPath)
    }

    // MARK: - Allowed hosts

    func testAllowedHostIsNotBlocked() {
        Airgap.allowedHosts = ["example.com"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api/test")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
        XCTAssertTrue(capture.isEmpty)
    }

    func testNonAllowedHostIsBlocked() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
    }

    func testAllowedHostsPersistAcrossActivations() {
        Airgap.allowedHosts = ["localhost", "127.0.0.1"]
        Airgap.activate()
        Airgap.deactivate()
        Airgap.activate()

        XCTAssertTrue(Airgap.allowedHosts.contains("localhost"))
        XCTAssertTrue(Airgap.allowedHosts.contains("127.0.0.1"))

        let url = URL(string: "https://localhost/api/test")!
        let request = URLRequest(url: url)
        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testAllowedHostsCanBeModifiedIncrementally() {
        Airgap.allowedHosts = []
        Airgap.allowedHosts.insert("localhost")
        Airgap.activate()

        let localhostURL = URL(string: "https://localhost/api")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

        let externalURL = URL(string: "https://example.com/api")!
        XCTAssertTrue(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
    }

    func testAllowedHostsWithMultipleHosts() {
        Airgap.allowedHosts = ["localhost", "127.0.0.1", "mock-server.local"]
        Airgap.activate()

        for host in ["localhost", "127.0.0.1", "mock-server.local"] {
            let url = URL(string: "https://\(host)/api")!
            XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                           "\(host) should not be blocked")
        }

        let blockedURL = URL(string: "https://real-api.example.com/data")!
        XCTAssertTrue(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)),
                      "Non-allowed host should be blocked")
    }

    func testAllowedHostsEmptyByDefault() {
        // After setUp resets allowedHosts to []
        XCTAssertTrue(Airgap.allowedHosts.isEmpty)
    }

    func testAllowedHostsWithHTTPScheme() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "http://localhost:8080/api")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)))
    }

    func testAllowedHostsCombinedWithAllowNetworkAccess() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()
        Airgap.allowNetworkAccess()

        // Both mechanisms should prevent blocking
        let externalURL = URL(string: "https://example.com/api")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
    }

    // MARK: - Wildcard host matching

    func testWildcardAllowedHostMatchesSubdomain() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://api.example.com/data")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                       "*.example.com should match api.example.com")
    }

    func testWildcardAllowedHostMatchesBaseDomain() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://example.com/data")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                       "*.example.com should also match example.com itself")
    }

    func testWildcardAllowedHostMatchesDeepSubdomain() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://deep.sub.example.com/data")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                       "*.example.com should match deep.sub.example.com")
    }

    func testWildcardAllowedHostDoesNotMatchDifferentDomain() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://notexample.com/data")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1, "*.example.com should not match notexample.com")
    }

    func testWildcardAllowedHostIsCaseInsensitive() {
        Airgap.allowedHosts = ["*.Example.COM"]
        Airgap.activate()

        let url = URL(string: "https://api.example.com/data")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                       "Wildcard matching should be case-insensitive")
    }

    func testMixedExactAndWildcardHosts() {
        Airgap.allowedHosts = ["localhost", "*.mock-server.local"]
        Airgap.activate()

        let localhostURL = URL(string: "https://localhost/api")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

        let mockURL = URL(string: "https://api.mock-server.local/data")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: mockURL)))

        let blockedURL = URL(string: "https://real-api.com/data")!
        XCTAssertTrue(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)))
    }

    // MARK: - Case-insensitive host matching

    func testAllowedHostsCaseInsensitive() {
        Airgap.allowedHosts = ["Example.COM"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                       "Host matching should be case-insensitive")
    }

    func testAllowedHostsMixedCaseInURL() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "https://LocalHost/api")!
        XCTAssertFalse(AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                       "URL host should be matched case-insensitively")
    }

    // MARK: - Non-GET HTTP methods

    func testPOSTMethodIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "POST completes")
        var request = URLRequest(url: URL(string: "https://example.com/api/post")!)
        request.httpMethod = "POST"
        request.httpBody = #"{"key":"value"}"#.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
        XCTAssertTrue(capture.messages[0].contains("POST"))
    }

    func testPUTMethodIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "PUT completes")
        var request = URLRequest(url: URL(string: "https://example.com/api/put")!)
        request.httpMethod = "PUT"

        URLSession.shared.dataTask(with: request) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
        XCTAssertTrue(capture.messages[0].contains("PUT"))
    }

    func testDELETEMethodIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "DELETE completes")
        var request = URLRequest(url: URL(string: "https://example.com/api/delete")!)
        request.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: request) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
        XCTAssertTrue(capture.messages[0].contains("DELETE"))
    }

    func testPATCHMethodIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "PATCH completes")
        var request = URLRequest(url: URL(string: "https://example.com/api/patch")!)
        request.httpMethod = "PATCH"

        URLSession.shared.dataTask(with: request) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
        XCTAssertTrue(capture.messages[0].contains("PATCH"))
    }

    func testHEADMethodIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "HEAD completes")
        var request = URLRequest(url: URL(string: "https://example.com/api/head")!)
        request.httpMethod = "HEAD"

        URLSession.shared.dataTask(with: request) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
        XCTAssertTrue(capture.messages[0].contains("HEAD"))
    }

    // MARK: - Violation message includes request details

    func testViolationMessageIncludesContentType() {
        Airgap.activate()

        let expectation = expectation(description: "POST completes")
        var request = URLRequest(url: URL(string: "https://example.com/api/content-type")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
        XCTAssertTrue(capture.messages[0].contains("application/json"),
                      "Violation should include Content-Type header")
    }

    func testViolationMessageOmitsContentTypeWhenAbsent() {
        Airgap.activate()

        let expectation = expectation(description: "GET completes")
        let url = URL(string: "https://example.com/api/no-content-type")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
        XCTAssertFalse(capture.messages[0].contains("Content-Type"),
                       "GET without Content-Type should not include it")
    }

    // MARK: - Upload and download tasks

    func testUploadTaskIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "Upload completes")
        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        request.httpMethod = "POST"
        let data = "file content".data(using: .utf8)!

        URLSession.shared.uploadTask(with: request, from: data) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
    }

    func testDownloadTaskIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "Download completes")
        let url = URL(string: "https://example.com/file.zip")!

        URLSession.shared.downloadTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
    }

    // MARK: - Concurrent requests

    func testConcurrentBlockedRequests() {
        Airgap.activate()

        let expectation = expectation(description: "All requests complete")
        expectation.expectedFulfillmentCount = 5

        for i in 0..<5 {
            let url = URL(string: "https://example.com/api/concurrent/\(i)")!
            URLSession.shared.dataTask(with: url) { _, _, error in
                XCTAssertNotNil(error)
                expectation.fulfill()
            }.resume()
        }

        wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(capture.count, 5)
    }

    // MARK: - URL edge cases

    func testURLWithQueryStringIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api?param=value&other=test")!

        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
    }

    func testURLWithFragmentIsBlocked() {
        Airgap.activate()

        let url = URL(string: "https://example.com/api#section")!
        let request = URLRequest(url: url)

        XCTAssertTrue(AirgapURLProtocol.canInit(with: request))
    }

    func testURLWithPortIsBlocked() {
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com:8443/api")!

        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(capture.count, 1)
    }

    func testURLWithBasicAuthIsBlocked() {
        Airgap.activate()

        let url = URL(string: "https://user:password@example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertTrue(AirgapURLProtocol.canInit(with: request))
    }

    // MARK: - Report edge cases

    func testWriteReportHandlesUnwritablePath() {
        Airgap.reportPath = "/nonexistent/deep/path/airgap-report.txt"
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/unwritable")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        // Should not crash
        Airgap.writeReport()
    }

    func testWriteReportWithNoViolationsDoesNotCreateFile() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-empty-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath

        Airgap.writeReport()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
    }

    // MARK: - Violation summary

    func testViolationSummaryReturnsNilWhenNoViolations() {
        XCTAssertNil(Airgap.violationSummary())
    }

    func testViolationSummaryReturnsFormattedString() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-summary-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api/summary-test")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        let summary = Airgap.violationSummary()
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("1 violation(s)") ?? false)
        XCTAssertTrue(summary?.contains("1 test(s)") ?? false)

        try? FileManager.default.removeItem(atPath: tempPath)
    }
}

// MARK: - Helpers

/// Thread-safe violation capture for use in tests with @Sendable closures.
private final class ViolationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []

    var messages: [String] {
        lock.withLock { _messages }
    }

    var count: Int {
        lock.withLock { _messages.count }
    }

    var isEmpty: Bool {
        lock.withLock { _messages.isEmpty }
    }

    func record(_ message: String) {
        lock.withLock { _messages.append(message) }
    }

    func reset() {
        lock.withLock { _messages = [] }
    }
}

/// A concrete subclass of AirgapTestCase for testing the lifecycle methods.
private final class LifecycleTestCase: AirgapTestCase {

    func invokeSetUp() {
        setUp()
    }

    func invokeTearDown() {
        tearDown()
    }
}
