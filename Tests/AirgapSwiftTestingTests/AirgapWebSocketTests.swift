import Foundation
import Testing
@testable import Airgap

extension AllAirgapSwiftTestingTests {

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
}

} // extension AllAirgapSwiftTestingTests
