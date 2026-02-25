import Testing
import Airgap
import Foundation

/// All Swift Testing integration tests are nested under a single serialized parent suite
/// because Airgap uses static state (violationHandler, isActive) that would race
/// if child suites ran in parallel.
@Suite(.serialized)
struct AllAirgapSwiftTestingTests {

    // MARK: - Manual activation integration tests

    @Suite struct ManualActivationTests {

        @Test func sharedSessionRequestIsBlocked() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let semaphore = DispatchSemaphore(value: 0)
            var receivedError: (any Error)?

            URLSession.shared.dataTask(with: url) { _, _, error in
                receivedError = error
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
            #expect(receivedError != nil, "Blocked request should deliver an error")
        }

        @Test func customSessionWithDefaultConfigIsBlocked() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let session = URLSession(configuration: .default)
            let semaphore = DispatchSemaphore(value: 0)

            session.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
        }

        @Test func customSessionWithEphemeralConfigIsBlocked() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let session = URLSession(configuration: .ephemeral)
            let semaphore = DispatchSemaphore(value: 0)

            session.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
        }

        @Test func violationMessageContainsURLAndGuidance() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api/test")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
            let message = capture.messages[0]
            #expect(message.contains("https://example.com/api/test"))
            #expect(message.contains("mock") || message.contains("stub"))
        }

        @Test func fileURLIsNotBlocked() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("networkguard-swift-testing-test.txt")
            try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

            let semaphore = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: tempFile) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.isEmpty, "file:// URLs should not trigger the guard")

            try? FileManager.default.removeItem(at: tempFile)
        }

        @Test func allowNetworkAccessPreventsBlocking() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            Airgap.allowNetworkAccess()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test func deactivatedGuardDoesNotBlock() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test func issueRecordHandlerPatternCompiles() {
            Airgap.violationHandler = { Issue.record("\($0)") }
            Airgap.activate()
            defer { Airgap.deactivate() }

            withKnownIssue("Direct handler call should record an issue") {
                Airgap.violationHandler("test violation from handler")
            }
        }
    }

    // MARK: - AirgapTrait integration tests

    @Suite(.airgapped)
    struct TraitSuiteLevelTests {

        @Test func traitBlocksNetworkRequests() {
            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == true)
        }

        @Test func traitAllowsOptOut() {
            Airgap.allowNetworkAccess()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }

        @Test func traitDoesNotBlockFileURLs() {
            let fileURL = URL(fileURLWithPath: "/tmp/networkguard-trait-test.txt")
            let request = URLRequest(url: fileURL)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    @Suite struct TraitPerTestTests {

        @Test(.airgapped) func guardedTestBlocksRequests() {
            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == true)
        }

        @Test func unguardedTestDoesNotBlock() {
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    @Suite struct TraitAbsenceTests {

        @Test func unguardedSuiteDoesNotBlock() {
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }
}

// MARK: - Helpers

/// Thread-safe violation capture for use in Swift Testing tests.
final class ViolationCapture: @unchecked Sendable {
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
}
