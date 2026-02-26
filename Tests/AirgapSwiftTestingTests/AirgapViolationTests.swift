import Foundation
import Testing
@testable import Airgap

extension AllAirgapSwiftTestingTests {

@Suite(.serialized)
final class AirgapViolationTests {

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

    // MARK: - Clear violations

    @Test func `Clear violations resets collection`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/clear-test")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(!Airgap.violations.isEmpty)

        Airgap.clearViolations()
        #expect(Airgap.violations.isEmpty)
    }

    // MARK: - Deactivate does not clear violations

    @Test func `Deactivate does not clear violations`() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/deactivate-test")!
        _ = try? await URLSession.shared.data(from: url)

        Airgap.deactivate()
        #expect(Airgap.violations.count == 1, "deactivate should not clear violations; call clearViolations() explicitly")
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
        let testModulePatterns = ["AirgapTests", "AirgapUnitTests", "AirgapSwiftTestingTests", "AirgapViolationTests"]
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
}

} // extension AllAirgapSwiftTestingTests
