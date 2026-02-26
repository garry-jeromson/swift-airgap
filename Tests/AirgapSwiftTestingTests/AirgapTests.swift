import Combine
import Foundation
import Testing
@testable import Airgap

extension AllAirgapSwiftTestingTests {

@Suite(.serialized)
final class AirgapUnitTests {

    private let capture = ViolationCapture()

    /// Drains the main queue so that async-dispatched violation handlers are processed.
    /// `reportViolation` dispatches the handler to `DispatchQueue.main.async` in `.fail` mode
    /// when called from a background thread (e.g., `com.apple.CFNetwork.CustomProtocols`).
    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    init() {
        Airgap.deactivate()
        capture.reset()

        let cap = capture
        Airgap.violationHandler = { message in
            cap.record(message)
        }
        Airgap.violationReporter = nil
        Airgap.inXCTestContext = false
        Airgap.errorCode = NSURLErrorNotConnectedToInternet
        Airgap.responseDelay = 0
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.allowedHosts = []
        Airgap.clearViolations()
    }

    // MARK: - Activation / Deactivation

    @Test func `Activate registers protocol`() {
        Airgap.activate()
        #expect(AirgapURLProtocol.isActive)
    }

    @Test func `Deactivate unregisters protocol`() {
        Airgap.activate()
        Airgap.deactivate()
        #expect(!AirgapURLProtocol.isActive)
    }

    @Test func `Double activate is idempotent`() {
        Airgap.activate()
        Airgap.activate()
        #expect(AirgapURLProtocol.isActive)
    }

    @Test func `isActive returns false before activation`() {
        #expect(!Airgap.isActive)
    }

    @Test func `isActive returns true after activation`() {
        Airgap.activate()
        #expect(Airgap.isActive)
    }

    @Test func `isActive returns false after deactivation`() {
        Airgap.activate()
        Airgap.deactivate()
        #expect(!Airgap.isActive)
    }

    // MARK: - Violation Reporter

    @Test func `Violation reporter receives violation struct`() async {
        let reporterCapture = ViolationReporterCapture()
        Airgap.violationReporter = { violation in
            reporterCapture.record(violation)
        }

        Airgap.activate()
        let url = URL(string: "https://example.com/reporter-test")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(reporterCapture.violations.count == 1)
        #expect(reporterCapture.violations.first?.url == "https://example.com/reporter-test")
        #expect(reporterCapture.violations.first?.httpMethod == "GET")
    }

    @Test func `Violation reporter called alongside handler`() async {
        let reporterCapture = ViolationReporterCapture()
        Airgap.violationReporter = { violation in
            reporterCapture.record(violation)
        }

        Airgap.activate()
        let url = URL(string: "https://example.com/alongside-test")!
        _ = try? await URLSession.shared.data(from: url)
        await drainMainQueue()

        #expect(reporterCapture.violations.count == 1, "Reporter should be called")
        #expect(capture.count == 1, "Handler should also be called")
    }

    @Test func `Violation reporter is nil by default`() {
        #expect(Airgap.violationReporter == nil)
    }

    @Test func `Violation reporter can be cleared`() {
        Airgap.violationReporter = { _ in }
        #expect(Airgap.violationReporter != nil)
        Airgap.violationReporter = nil
        #expect(Airgap.violationReporter == nil)
    }

    // MARK: - Error message hints

    @Test func `Violation message contains hint`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/hint-test")!
        _ = try? await URLSession.shared.data(from: url)

        let message = capture.messages.first ?? ""
        #expect(message.contains("Hint:"), "Message should contain 'Hint:'")
        #expect(message.contains("allowNetworkAccess()"), "Hint should mention allowNetworkAccess()")
        #expect(message.contains("allowedHosts"), "Hint should mention allowedHosts")
        #expect(message.contains(".warn"), "Hint should mention .warn mode")
        #expect(message.contains("mock"), "Original message text should be preserved")
    }

    // MARK: - Error code and response delay

    @Test func `Custom error code is delivered`() async {
        Airgap.errorCode = NSURLErrorTimedOut
        Airgap.activate()

        let url = URL(string: "https://example.com/error-code-test")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            let nsError = error as NSError
            #expect(nsError.code == NSURLErrorTimedOut)
        }
    }

    @Test func `Default error code is not connected to internet`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/default-error-test")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            let nsError = error as NSError
            #expect(nsError.code == NSURLErrorNotConnectedToInternet)
        }
    }

    @Test func `Response delay adds latency`() async {
        Airgap.responseDelay = 0.5
        Airgap.activate()

        let url = URL(string: "https://example.com/delay-test")!
        let start = Date()
        _ = try? await URLSession.shared.data(from: url)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.4, "Response should be delayed by at least 0.4s")
    }

    @Test func `Default response delay is zero`() {
        #expect(Airgap.responseDelay == 0)
    }

    // MARK: - withConfiguration scoping

    @Test func `With configuration restores mode`() {
        Airgap.mode = .fail
        Airgap.withConfiguration(mode: .warn) {
            #expect(Airgap.mode == .warn)
        }
        #expect(Airgap.mode == .fail)
    }

    @Test func `With configuration restores allowed hosts`() {
        Airgap.allowedHosts = ["original.com"]
        Airgap.withConfiguration(allowedHosts: ["override.com"]) {
            #expect(Airgap.allowedHosts == ["override.com"])
        }
        #expect(Airgap.allowedHosts == ["original.com"])
    }

    @Test func `With configuration restores handler`() {
        let outerCapture = ViolationCapture()
        Airgap.violationHandler = { outerCapture.record($0) }

        let innerCapture = ViolationCapture()
        Airgap.withConfiguration(violationHandler: { innerCapture.record($0) }) {
            // Call the handler directly to verify it's the inner one
            // (reportViolation dispatches to main thread async, which doesn't
            // complete before withConfiguration restores the handler)
            Airgap.violationHandler("test violation")
        }

        // After withConfiguration, handler should be restored
        Airgap.violationHandler("outer violation")

        #expect(innerCapture.count == 1, "Inner handler should be called inside withConfiguration")
        #expect(outerCapture.count == 1, "Outer handler should be restored after withConfiguration")
    }

    @Test func `With configuration restores on throw`() {
        Airgap.mode = .fail
        do {
            try Airgap.withConfiguration(mode: .warn) {
                #expect(Airgap.mode == .warn)
                throw NSError(domain: "test", code: 1)
            }
        } catch {
            // expected
        }
        #expect(Airgap.mode == .fail)
    }

    @Test func `With configuration partial override keeps other settings`() {
        Airgap.mode = .fail
        Airgap.errorCode = 42
        Airgap.withConfiguration(mode: .warn) {
            #expect(Airgap.mode == .warn)
            #expect(Airgap.errorCode == 42, "Non-overridden settings should be preserved")
        }
        #expect(Airgap.mode == .fail)
        #expect(Airgap.errorCode == 42)
    }

    // MARK: - WebSocket interception

    @Test func `WebSocket task produces violation`() {
        Airgap.activate()

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/ws")!)
        task.resume()

        // The swizzled resume() reports violations and cancels synchronously
        #expect(Airgap.violations.count == 1)
        #expect(Airgap.violations.first?.url.contains("example.com/ws") ?? false)
    }

    @Test func `WebSocket task not intercepted when inactive`() {
        // Don't activate
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/ws")!)
        task.resume()

        #expect(Airgap.violations.count == 0)
    }

    @Test func `WebSocket task respects allowed hosts`() {
        Airgap.allowedHosts = ["example.com"]
        Airgap.activate()

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/ws")!)
        task.resume()

        #expect(Airgap.violations.count == 0, "Allowed host should not produce a violation")
    }

    @Test func `WebSocket task is cancelled after violation`() async throws {
        Airgap.activate()

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/ws-cancel")!)
        task.resume()

        // cancel() is called synchronously in the swizzled resume(), but the task
        // state transition is asynchronous — give the run loop a moment to process it.
        try await Task.sleep(for: .milliseconds(100))

        #expect(
            task.state == .canceling || task.state == .completed,
            "Task should be cancelled after violation, got state: \(task.state.rawValue)"
        )
    }

    // MARK: - Blocking requests

    @Test func `URLSession.shared data task is blocked`() async {
        Airgap.activate()

        let url = URL(string: "https://httpbin.org/get")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test func `URLSession with default config is blocked`() async {
        Airgap.activate()

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let url = URL(string: "https://httpbin.org/get")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test func `URLSession with ephemeral config is blocked`() async {
        Airgap.activate()

        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        let url = URL(string: "https://httpbin.org/get")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test func `HTTP scheme is blocked`() async {
        Airgap.activate()

        let url = URL(string: "http://httpbin.org/get")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    // MARK: - Non-HTTP schemes

    @Test func `Local file URL is not blocked`() async {
        Airgap.activate()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("networkguard-test.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

        _ = try? await URLSession.shared.data(from: tempFile)
        #expect(capture.isEmpty)

        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: - Inactive guard

    @Test func `No violation when inactive`() {
        // Guard is not activated — requests should not be intercepted.
        // We verify by checking that canInit returns false.
        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request))
        #expect(capture.isEmpty)
    }

    // MARK: - Violation message

    @Test func `Violation message contains URL and guidance`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/test")!
        _ = try? await URLSession.shared.data(from: url)
        await drainMainQueue()

        #expect(capture.count == 1)

        let message = capture.messages.first ?? ""
        #expect(message.contains("https://example.com/api/test"), "Message should contain the URL")
        #expect(message.contains("GET"), "Message should contain the HTTP method")
        #expect(message.contains("mock") || message.contains("stub"), "Message should contain guidance")
    }

    // MARK: - Allow network access

    @Test func `Allow network access disables guard`() {
        Airgap.activate()
        Airgap.allowNetworkAccess()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request))
        #expect(capture.isEmpty)
    }

    @Test func `Activate resets allow flag`() {
        Airgap.activate()
        Airgap.allowNetworkAccess()

        // Re-activate should reset the allow flag
        Airgap.activate()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        #expect(AirgapURLProtocol.canInit(with: request))
    }

    // MARK: - AirgapTestCase lifecycle

    @Test func `AirgapTestCase lifecycle`() {
        let testCase = LifecycleTestCase()

        // Simulate setUp
        testCase.invokeSetUp()
        #expect(AirgapURLProtocol.isActive)

        // Simulate tearDown
        testCase.invokeTearDown()
        #expect(!AirgapURLProtocol.isActive)
    }

    // MARK: - Warning mode

    @Test func `Warn mode does not fail test`() async {
        Airgap.mode = .warn
        Airgap.activate()

        let url = URL(string: "https://example.com/api/warn-test")!
        _ = try? await URLSession.shared.data(from: url)

        // Warn mode with inXCTestContext=false calls handler directly (no main queue dispatch)
        #expect(capture.count == 1)
    }

    @Test func `Warn mode calls violation handler directly`() {
        Airgap.mode = .warn

        // Call reportViolation directly on the main thread to avoid async timing issues
        Airgap.reportViolation(method: "GET", url: "https://example.com/warn-direct", callStack: [], testName: "test")

        #expect(capture.count == 1, "Warn mode should call the configured violationHandler")
        #expect(capture.messages.first?.contains("warn-direct") ?? false)
    }

    @Test func `Fail mode calls violation handler directly`() async {
        Airgap.mode = .fail
        Airgap.activate()

        let url = URL(string: "https://example.com/api/fail-test")!
        _ = try? await URLSession.shared.data(from: url)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("fail-test") ?? false)
    }

    // MARK: - Violation collection

    @Test func `Violations collected when report path set`() async {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-test-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.activate()

        let url = URL(string: "https://example.com/api/collect-test")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(Airgap.violations.count == 1)
        #expect(Airgap.violations[0].url == "https://example.com/api/collect-test")
        #expect(Airgap.violations[0].httpMethod == "GET")

        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test func `Violations collected even when report path nil`() async {
        Airgap.reportPath = nil
        Airgap.activate()

        let url = URL(string: "https://example.com/api/collect-without-path")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(Airgap.violations.count == 1, "Violations should be collected regardless of reportPath")
        #expect(Airgap.violations[0].url == "https://example.com/api/collect-without-path")
    }

    // MARK: - Report writing

    @Test func `Write report creates file`() async {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-report-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.activate()

        let url = URL(string: "https://example.com/api/report-test")!
        _ = try? await URLSession.shared.data(from: url)

        Airgap.writeReport()

        #expect(FileManager.default.fileExists(atPath: tempPath))

        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test func `Report contains method and URL`() async {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-report-content-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        AirgapURLProtocol.currentTestName = "AirgapUnitTests/Report contains method and URL"
        Airgap.activate()

        let url = URL(string: "https://example.com/api/report-content")!
        _ = try? await URLSession.shared.data(from: url)

        Airgap.writeReport()

        let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(content != nil)
        #expect(content?.contains("Method: GET") ?? false)
        #expect(content?.contains("URL: https://example.com/api/report-content") ?? false)
        #expect(content?.contains("Test: AirgapUnitTests/Report contains method and URL") ?? false)
        #expect(content?.contains("Call Stack:") ?? false)
        #expect(content?.contains("Total violations:") ?? false)

        try? FileManager.default.removeItem(atPath: tempPath)
    }

    // MARK: - Clear violations

    @Test func `Clear violations resets collection`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/clear-test")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(!Airgap.violations.isEmpty)

        Airgap.clearViolations()
        #expect(Airgap.violations.isEmpty)
    }

    // MARK: - Mode is not reset by activate

    @Test func `Activate does not reset mode`() {
        Airgap.mode = .warn
        Airgap.activate()
        #expect(Airgap.mode == .warn)

        Airgap.activate()
        #expect(Airgap.mode == .warn)
    }

    // MARK: - configureFromEnvironment

    @Test func `configureFromEnvironment does not crash with no env vars`() {
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.configureFromEnvironment()
        #expect(Airgap.mode == .fail)
        #expect(Airgap.reportPath == nil)
    }

    @Test func `configureFromEnvironment is idempotent`() {
        Airgap.configureFromEnvironment()
        let modeAfterFirst = Airgap.mode
        let pathAfterFirst = Airgap.reportPath
        let hostsAfterFirst = Airgap.allowedHosts

        Airgap.configureFromEnvironment()
        #expect(Airgap.mode == modeAfterFirst)
        #expect(Airgap.reportPath == pathAfterFirst)
        #expect(Airgap.allowedHosts == hostsAfterFirst, "Calling configureFromEnvironment twice should not duplicate hosts")
    }

    @Test func `configureFromEnvironment resets mode when env var absent`() {
        Airgap.mode = .warn
        Airgap.configureFromEnvironment()
        #expect(Airgap.mode == .fail, "configureFromEnvironment should reset mode to .fail when AIRGAP_MODE is not set")
    }

    @Test func `configureFromEnvironment resets report path when env var absent`() {
        Airgap.reportPath = "/some/path/report.txt"
        Airgap.configureFromEnvironment()
        #expect(Airgap.reportPath == nil, "configureFromEnvironment should reset reportPath when AIRGAP_REPORT_PATH is not set")
    }

    @Test func `configureFromEnvironment does not accumulate hosts`() {
        Airgap.allowedHosts = ["manually-added.com"]
        Airgap.configureFromEnvironment()
        #expect(!Airgap.allowedHosts.contains("manually-added.com"),
                "configureFromEnvironment should assign hosts, not union them")
    }

    // MARK: - currentTestName management

    @Test func `Current test name is restorable`() {
        let original = AirgapURLProtocol.currentTestName
        AirgapURLProtocol.currentTestName = "OuterScope/testOuter"

        let saved = AirgapURLProtocol.currentTestName
        AirgapURLProtocol.currentTestName = "InnerScope/testInner"
        #expect(AirgapURLProtocol.currentTestName == "InnerScope/testInner")

        AirgapURLProtocol.currentTestName = saved
        #expect(AirgapURLProtocol.currentTestName == "OuterScope/testOuter", "currentTestName should be restored after inner scope ends")

        AirgapURLProtocol.currentTestName = original
    }

    // MARK: - Violation testName attribution

    @Test func `Violation contains correct test name`() async {
        AirgapURLProtocol.currentTestName = "MyTests/testSomething"
        Airgap.activate()

        let url = URL(string: "https://example.com/api/attribution")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(Airgap.violations.count == 1)
        #expect(Airgap.violations[0].testName == "MyTests/testSomething", "Violation should be attributed to the correct test name")
    }

    // MARK: - Deactivate does not clear violations

    @Test func `Deactivate does not clear violations`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/deactivate-test")!
        _ = try? await URLSession.shared.data(from: url)

        Airgap.deactivate()
        #expect(Airgap.violations.count == 1, "deactivate should not clear violations; call clearViolations() explicitly")
    }

    // MARK: - Allowed hosts

    @Test func `Allowed host is not blocked`() {
        Airgap.allowedHosts = ["example.com"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api/test")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request))
        #expect(capture.isEmpty)
    }

    @Test func `Non-allowed host is blocked`() async {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api/test")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(Airgap.violations.count == 1)
    }

    @Test func `Allowed hosts persist across activations`() {
        Airgap.allowedHosts = ["localhost", "127.0.0.1"]
        Airgap.activate()
        Airgap.deactivate()
        Airgap.activate()

        #expect(Airgap.allowedHosts.contains("localhost"))
        #expect(Airgap.allowedHosts.contains("127.0.0.1"))

        let url = URL(string: "https://localhost/api/test")!
        let request = URLRequest(url: url)
        #expect(!AirgapURLProtocol.canInit(with: request))
    }

    @Test func `Allowed hosts can be modified incrementally`() {
        Airgap.allowedHosts = []
        Airgap.allowedHosts.insert("localhost")
        Airgap.activate()

        let localhostURL = URL(string: "https://localhost/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

        let externalURL = URL(string: "https://example.com/api")!
        #expect(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
    }

    @Test func `Allowed hosts with multiple hosts`() {
        Airgap.allowedHosts = ["localhost", "127.0.0.1", "mock-server.local"]
        Airgap.activate()

        for host in ["localhost", "127.0.0.1", "mock-server.local"] {
            let url = URL(string: "https://\(host)/api")!
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "\(host) should not be blocked")
        }

        let blockedURL = URL(string: "https://real-api.example.com/data")!
        #expect(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)),
                "Non-allowed host should be blocked")
    }

    @Test func `Allowed hosts empty by default`() {
        #expect(Airgap.allowedHosts.isEmpty)
    }

    @Test func `Allowed hosts with http scheme`() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "http://localhost:8080/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)))
    }

    @Test func `Allowed hosts combined with allow network access`() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()
        Airgap.allowNetworkAccess()

        let externalURL = URL(string: "https://example.com/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
    }

    // MARK: - Wildcard host matching

    @Test func `Wildcard allowed host matches subdomain`() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://api.example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "*.example.com should match api.example.com")
    }

    @Test func `Wildcard allowed host matches base domain`() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "*.example.com should also match example.com itself")
    }

    @Test func `Wildcard allowed host matches deep subdomain`() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://deep.sub.example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "*.example.com should match deep.sub.example.com")
    }

    @Test func `Wildcard allowed host does not match different domain`() async {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://notexample.com/data")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(Airgap.violations.count == 1, "*.example.com should not match notexample.com")
    }

    @Test func `Wildcard allowed host is case insensitive`() {
        Airgap.allowedHosts = ["*.Example.COM"]
        Airgap.activate()

        let url = URL(string: "https://api.example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "Wildcard matching should be case-insensitive")
    }

    @Test func `Mixed exact and wildcard hosts`() {
        Airgap.allowedHosts = ["localhost", "*.mock-server.local"]
        Airgap.activate()

        let localhostURL = URL(string: "https://localhost/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

        let mockURL = URL(string: "https://api.mock-server.local/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: mockURL)))

        let blockedURL = URL(string: "https://real-api.com/data")!
        #expect(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)))
    }

    // MARK: - Case-insensitive host matching

    @Test func `Allowed hosts case insensitive`() {
        Airgap.allowedHosts = ["Example.COM"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "Host matching should be case-insensitive")
    }

    @Test func `Allowed hosts mixed case in URL`() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "https://LocalHost/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "URL host should be matched case-insensitively")
    }

    // MARK: - Non-GET HTTP methods

    @Test func `POST method is blocked`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/post")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"key":"value"}"#.utf8)

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("POST") ?? false)
    }

    @Test func `PUT method is blocked`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/put")!)
        request.httpMethod = "PUT"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("PUT") ?? false)
    }

    @Test func `DELETE method is blocked`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/delete")!)
        request.httpMethod = "DELETE"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("DELETE") ?? false)
    }

    @Test func `PATCH method is blocked`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/patch")!)
        request.httpMethod = "PATCH"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("PATCH") ?? false)
    }

    @Test func `HEAD method is blocked`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/head")!)
        request.httpMethod = "HEAD"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("HEAD") ?? false)
    }

    // MARK: - Violation message includes request details

    @Test func `Violation message includes content type`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/content-type")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("application/json") ?? false, "Violation should include Content-Type header")
    }

    @Test func `Violation message omits content type when absent`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/no-content-type")!
        _ = try? await URLSession.shared.data(from: url)
        await drainMainQueue()

        #expect(capture.count == 1)
        let message = capture.messages.first ?? ""
        #expect(!message.contains("Content-Type"), "GET without Content-Type should not include it")
    }

    // MARK: - Upload and download tasks

    @Test func `Upload task is blocked`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        request.httpMethod = "POST"
        let data = Data("file content".utf8)

        do {
            _ = try await URLSession.shared.upload(for: request, from: data)
            Issue.record("Upload should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test func `Download task is blocked`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/file.zip")!

        do {
            _ = try await URLSession.shared.download(from: url)
            Issue.record("Download should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    // MARK: - Concurrent requests

    @Test func `Concurrent blocked requests`() async {
        Airgap.activate()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                let url = URL(string: "https://example.com/api/concurrent/\(i)")!
                group.addTask {
                    do {
                        _ = try await URLSession.shared.data(from: url)
                        Issue.record("Expected an error")
                    } catch {
                        // Expected
                    }
                }
            }
        }

        #expect(Airgap.violations.count >= 5)
    }

    // MARK: - URL edge cases

    @Test func `URL with query string is blocked`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api?param=value&other=test")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test func `URL with fragment is blocked`() {
        Airgap.activate()

        let url = URL(string: "https://example.com/api#section")!
        let request = URLRequest(url: url)

        #expect(AirgapURLProtocol.canInit(with: request))
    }

    @Test func `URL with port is blocked`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com:8443/api")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test func `URL with basic auth is blocked`() {
        Airgap.activate()

        let url = URL(string: "https://user:password@example.com/api")!
        let request = URLRequest(url: url)

        #expect(AirgapURLProtocol.canInit(with: request))
    }

    // MARK: - Report edge cases

    @Test func `Write report handles unwritable path`() async {
        Airgap.reportPath = "/nonexistent/deep/path/airgap-report.txt"
        Airgap.activate()

        let url = URL(string: "https://example.com/api/unwritable")!
        _ = try? await URLSession.shared.data(from: url)

        // Should not crash
        Airgap.writeReport()
    }

    @Test func `Write report with no violations does not create file`() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-empty-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath

        Airgap.writeReport()

        #expect(!FileManager.default.fileExists(atPath: tempPath))
    }

    // MARK: - Violation summary

    @Test func `Violation summary returns nil when no violations`() {
        #expect(Airgap.violationSummary() == nil)
    }

    // MARK: - Call stack caller attribution

    /// Note: This test is inherently brittle. It matches against mangled Swift symbol
    /// names in the call stack, which are compiler-version-dependent. If the test module
    /// or type is renamed, or the compiler's name mangling changes, update the patterns below.
    @Test func `Violation call stack contains caller frame`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/caller-stack")!

        // Use callback pattern so .resume() is called from test code
        // (async/await resumes internally, so the test frame isn't in the stack)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            URLSession.shared.dataTask(with: url) { _, _, _ in
                continuation.resume()
            }.resume()
        }

        #expect(Airgap.violations.count >= 1)
        let callStack = Airgap.violations[0].callStack
        let testModulePatterns = ["AirgapTests", "AirgapUnitTests", "AirgapSwiftTestingTests"]
        let containsTestFrame = callStack.contains { frame in
            testModulePatterns.contains { frame.contains($0) }
        }
        #expect(containsTestFrame, "Call stack should contain the caller's frame. Got:\n\(callStack.prefix(10).joined(separator: "\n"))")
    }

    // MARK: - Same URL multiple requests

    @Test func `Multiple requests to same URL both recorded`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/same-url")!

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await URLSession.shared.data(from: url) }
            group.addTask { _ = try? await URLSession.shared.data(from: url) }
        }

        #expect(Airgap.violations.count == 2, "Both requests to the same URL should be recorded as violations")
    }

    // MARK: - Concurrent handler mutation

    @Test func `Concurrent handler mutation does not crash`() {
        Airgap.activate()

        let queue = DispatchQueue(label: "handler-mutation", attributes: .concurrent)
        let group = DispatchGroup()
        let iterations = 100

        for i in 0..<iterations {
            group.enter()
            queue.async {
                let capture = ViolationCapture()
                Airgap.violationHandler = { capture.record($0) }
                _ = Airgap.violations.count
                group.leave()
            }
            if i % 10 == 0 {
                group.enter()
                queue.async {
                    Airgap.reportViolation(method: "GET", url: "https://example.com/race/\(i)", callStack: [], testName: "test")
                    group.leave()
                }
            }
        }

        let result = group.wait(timeout: .now() + 10)
        #expect(result == .success, "Concurrent handler mutations should complete within timeout")
    }

    // MARK: - Violation model tests

    @Test func `Violation Codable roundtrip`() throws {
        let original = Violation(
            testName: "TestClass/testMethod",
            httpMethod: "POST",
            url: "https://example.com/api",
            callStack: ["frame1", "frame2"],
            timestamp: Date(timeIntervalSince1970: 1_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Violation.self, from: data)
        #expect(original == decoded)
    }

    @Test func `Violation timestamp is populated`() {
        let before = Date()
        let violation = Violation(testName: "test", httpMethod: "GET", url: "https://example.com", callStack: [])
        let after = Date()
        #expect(violation.timestamp >= before)
        #expect(violation.timestamp <= after)
    }

    // MARK: - IPv6 allowed hosts

    @Test func `IPv6 allowed host`() {
        Airgap.allowedHosts = ["::1"]
        Airgap.activate()

        let url = URL(string: "https://[::1]/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "IPv6 loopback should be allowed when in allowedHosts")
    }

    // MARK: - Concurrent violation collection

    @Test func `Concurrent violations are all collected in violations array`() async {
        Airgap.activate()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                let url = URL(string: "https://example.com/api/concurrent-violations/\(i)")!
                group.addTask {
                    _ = try? await URLSession.shared.data(from: url)
                }
            }
        }

        #expect(Airgap.violations.count == 5, "All concurrent violations should be collected in the violations array")
    }

    @Test func `Violation summary returns formatted string`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/summary-test")!
        _ = try? await URLSession.shared.data(from: url)

        let summary = Airgap.violationSummary()
        #expect(summary != nil)
        #expect(summary?.contains("1 violation(s)") ?? false)
        #expect(summary?.contains("1 test(s)") ?? false)
    }

    // MARK: - KMP / Ktor Darwin Engine Pattern

    /// Simulates what Ktor's Darwin engine does: creates a URLSession from
    /// URLSessionConfiguration.default after Airgap is active. The swizzled
    /// config getter should inject AirgapURLProtocol, so the request is caught.
    @Test func `Ktor Darwin engine pattern is intercepted`() async {
        Airgap.activate()

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let url = URL(string: "https://api.example.com/kmp/endpoint")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Request should be blocked by Airgap")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Violation should be captured for Ktor-style session")
    }

    /// Verifies that the URLSession.init swizzle injects AirgapURLProtocol even when
    /// the configuration was obtained before activate() — closing the timing gap for
    /// KMP/Ktor code that eagerly creates its URLSession during module load.
    @Test func `Session from pre activation config is intercepted via init swizzle`() async {
        // Grab config BEFORE activation — simulates Ktor initializing early.
        let preActivationConfig = URLSessionConfiguration.default

        Airgap.activate()

        let session = URLSession(configuration: preActivationConfig)
        let url = URL(string: "https://api.example.com/kmp/early-init")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Request should be blocked by Airgap")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Init swizzle should catch requests from pre-activation configs")
    }

    // MARK: - Combine dataTaskPublisher

    @Test func `Combine dataTaskPublisher is intercepted`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/combine")!

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            cancellable = URLSession.shared.dataTaskPublisher(for: url)
                .sink(receiveCompletion: { completion in
                    _ = cancellable  // prevent unused warning
                    continuation.resume()
                }, receiveValue: { _ in })
        }

        #expect(Airgap.violations.count >= 1, "Combine dataTaskPublisher should be intercepted")
    }

    // MARK: - Async upload and download

    @Test func `Async upload is intercepted`() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/async-upload")!)
        request.httpMethod = "POST"
        let body = Data("upload data".utf8)

        do {
            _ = try await URLSession.shared.upload(for: request, from: body)
            Issue.record("Upload should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Async upload should be intercepted")
    }

    @Test func `Async download is intercepted`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/async-download")!

        do {
            _ = try await URLSession.shared.download(from: url)
            Issue.record("Download should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Async download should be intercepted")
    }

    // MARK: - data: scheme pass-through

    @Test func `data URL is not intercepted`() {
        Airgap.activate()

        let url = URL(string: "data:text/plain;base64,SGVsbG8=")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request),
                "data: URLs should not be intercepted")
    }

    // MARK: - Custom URLProtocol coexistence

    @Test func `Custom URLProtocol coexists with Airgap`() {
        URLProtocol.registerClass(MockSchemeProtocol.self)
        defer { URLProtocol.unregisterClass(MockSchemeProtocol.self) }

        Airgap.activate()

        let mockURL = URL(string: "mock://test/resource")!
        let mockRequest = URLRequest(url: mockURL)
        #expect(!AirgapURLProtocol.canInit(with: mockRequest),
                "Airgap should not intercept mock:// scheme")
        #expect(MockSchemeProtocol.canInit(with: mockRequest),
                "MockSchemeProtocol should handle mock:// scheme")

        let httpsURL = URL(string: "https://example.com/api/coexistence")!
        let httpsRequest = URLRequest(url: httpsURL)
        #expect(AirgapURLProtocol.canInit(with: httpsRequest),
                "Airgap should still intercept https:// requests")
    }

    // MARK: - JSON report output

    @Test func `Write report as JSON`() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("airgap-test-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        Airgap.reportPath = tempPath
        Airgap.activate()

        let url = URL(string: "https://example.com/api/json-report")!
        _ = try? await URLSession.shared.data(from: url)

        Airgap.writeReport()

        let data = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let violations = try decoder.decode([Violation].self, from: data)
        #expect(violations.count == 1)
        #expect(violations[0].url == "https://example.com/api/json-report")
        #expect(violations[0].httpMethod == "GET")
    }

    /// Verifies that the URLSession.init swizzle injects AirgapURLProtocol into the
    /// config passed to the initializer, even for non-standard configs like background.
    @Test func `Init swizzle injects protocol into config before session creation`() {
        Airgap.activate()

        let config = URLSessionConfiguration.background(withIdentifier: "com.airgap.test.\(UUID().uuidString)")
        #expect(
            !(config.protocolClasses ?? []).contains(where: { $0 == AirgapURLProtocol.self }),
            "Background config should NOT have AirgapURLProtocol before session creation"
        )

        _ = URLSession(configuration: config, delegate: nil, delegateQueue: nil)

        #expect(
            (config.protocolClasses ?? []).contains(where: { $0 == AirgapURLProtocol.self }),
            "Init swizzle should have injected AirgapURLProtocol into the config"
        )
    }
}

} // extension AllAirgapSwiftTestingTests

// MARK: - Unit Test Helpers

/// Thread-safe violation reporter capture for use in tests with @Sendable closures.
final class ViolationReporterCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _violations: [Violation] = []

    var violations: [Violation] {
        lock.withLock { _violations }
    }

    func record(_ violation: Violation) {
        lock.withLock { _violations.append(violation) }
    }
}

/// A minimal URLProtocol subclass for the mock:// scheme, used to verify coexistence with Airgap.
final class MockSchemeProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "mock"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: NSError(domain: "MockScheme", code: 0))
    }

    override func stopLoading() {}
}

/// A concrete subclass of AirgapTestCase for testing the lifecycle methods.
final class LifecycleTestCase: AirgapTestCase {

    func invokeSetUp() {
        setUp()
    }

    func invokeTearDown() {
        tearDown()
    }
}
