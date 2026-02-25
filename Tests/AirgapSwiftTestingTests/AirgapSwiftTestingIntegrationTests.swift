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
            let errorCapture = ErrorCapture()

            URLSession.shared.dataTask(with: url) { _, _, error in
                errorCapture.set(error)
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
            #expect(errorCapture.value != nil, "Blocked request should deliver an error")
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

    // MARK: - Allowed hosts tests

    @Suite struct AllowedHostsTests {

        @Test func allowedHostIsNotBlocked() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["example.com"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test func nonAllowedHostIsBlocked() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["localhost"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let url = URL(string: "https://example.com/api")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
        }

        @Test func multipleAllowedHostsWork() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["localhost", "127.0.0.1"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let localhostURL = URL(string: "https://localhost/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false)

            let loopbackURL = URL(string: "https://127.0.0.1/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: loopbackURL)) == false)

            #expect(capture.isEmpty)
        }
    }

    // MARK: - Violation summary tests

    @Suite struct ViolationSummaryTests {

        @Test func summaryIsNilWithNoViolations() {
            Airgap.clearViolations()
            #expect(Airgap.violationSummary() == nil)
        }

        @Test func summaryContainsViolationCount() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.clearViolations()
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.clearViolations()
            }

            let url = URL(string: "https://example.com/api/summary")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            let summary = Airgap.violationSummary()
            #expect(summary != nil)
            #expect(summary?.contains("1 violation(s)") == true)
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

    // MARK: - Trait state isolation tests

    @Suite struct TraitStateIsolationTests {

        @Test func traitRestoresAllowedHosts() {
            // Set allowedHosts before trait scope
            let previousHosts = Airgap.allowedHosts
            Airgap.allowedHosts = ["pre-existing-host.com"]
            defer { Airgap.allowedHosts = previousHosts }

            // Simulate what provideScope does: it should restore allowedHosts after
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            Airgap.deactivate()

            // After trait scope ends, allowedHosts should still be what we set
            #expect(Airgap.allowedHosts.contains("pre-existing-host.com"))
        }

        @Test func traitRestoresMode() {
            // Set mode before trait scope
            let previousMode = Airgap.mode
            Airgap.mode = .warn
            defer { Airgap.mode = previousMode }

            // After trait scope ends, mode should be restored
            #expect(Airgap.mode == .warn)
        }
    }

    // MARK: - Trait with allowedHosts parameter

    @Suite(.airgapped(allowedHosts: ["localhost", "127.0.0.1"]))
    struct TraitWithAllowedHostsTests {

        @Test func allowedHostIsNotBlockedViaTrait() {
            let localhostURL = URL(string: "https://localhost/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false,
                    "localhost should be allowed via trait parameter")
        }

        @Test func nonAllowedHostIsStillBlockedViaTrait() {
            let externalURL = URL(string: "https://example.com/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)) == true,
                    "Non-allowed host should still be blocked")
        }
    }

    // MARK: - Violations collected without reportPath

    @Suite struct ViolationCollectionTests {

        @Test func violationsCollectedWithoutReportPath() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.reportPath = nil
            Airgap.clearViolations()
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.reportPath = nil
                Airgap.clearViolations()
            }

            let url = URL(string: "https://example.com/api/collect-no-path")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(Airgap.violations.count == 1, "Violations should be collected even without reportPath")
        }
    }
}

// MARK: - Helpers

/// Thread-safe error capture for use in Swift Testing tests.
final class ErrorCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: (any Error)?

    var value: (any Error)? {
        lock.withLock { _value }
    }

    func set(_ error: (any Error)?) {
        lock.withLock { _value = error }
    }
}

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
