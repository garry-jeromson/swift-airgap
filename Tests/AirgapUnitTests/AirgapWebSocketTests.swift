import Foundation
import Testing
@testable import Airgap

extension AllAirgapUnitTests {

@Suite(.serialized)
final class AirgapWebSocketTests {

    init() {
        Airgap.deactivate()
        Airgap.violationHandler = { _ in }
        Airgap.violationReporter = nil
        Airgap.inXCTestContext = false
        Airgap.errorCode = NSURLErrorNotConnectedToInternet
        Airgap.responseDelay = 0
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.allowedHosts = []
        Airgap.clearViolations()
    }

    // MARK: - WebSocket interception

    @Test("WebSocket task produces violation") func webSocketTaskProducesViolation() {
        Airgap.activate()

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/ws")!)
        task.resume()

        // The swizzled resume() reports violations and cancels synchronously
        #expect(Airgap.violations.count == 1)
        #expect(Airgap.violations.first?.url.contains("example.com/ws") ?? false)
    }

    @Test("Non-TLS WebSocket task produces violation") func nonTLSWebSocketTaskProducesViolation() {
        Airgap.activate()

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "ws://example.com/ws")!)
        task.resume()

        #expect(Airgap.violations.count == 1)
        #expect(Airgap.violations.first?.url.contains("example.com/ws") ?? false)
    }

    @Test("WebSocket violation contains URL and method") func webSocketViolationContainsURLAndMethod() {
        Airgap.activate()

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/chat")!)
        task.resume()

        #expect(Airgap.violations.count == 1)
        let violation = Airgap.violations.first
        #expect(violation?.url.contains("example.com/chat") ?? false)
        #expect(violation?.httpMethod == "GET")
    }

    @Test("WebSocket task not intercepted when inactive") func webSocketTaskNotInterceptedWhenInactive() {
        // Don't activate
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/ws")!)
        task.resume()

        #expect(Airgap.violations.count == 0)
    }

    @Test("WebSocket task respects allowed hosts") func webSocketTaskRespectsAllowedHosts() {
        Airgap.allowedHosts = ["example.com"]
        Airgap.activate()

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/ws")!)
        task.resume()

        #expect(Airgap.violations.count == 0, "Allowed host should not produce a violation")
    }

    @Test("WebSocket task is cancelled after violation") func webSocketTaskIsCancelledAfterViolation() async throws {
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
}

} // extension AllAirgapUnitTests
