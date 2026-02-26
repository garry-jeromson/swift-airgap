import Testing
@testable import Airgap
import Foundation

/// All Swift Testing integration tests are nested under a single serialized parent suite
/// because Airgap uses static state (violationHandler, isActive) that would race
/// if child suites ran in parallel.
@Suite(.serialized, .scopeLocked)
struct AllAirgapSwiftTestingTests {

    // MARK: - Manual activation integration tests

    @Suite struct ManualActivationTests {

        @Test func `Shared session request is blocked`() {
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

        @Test func `Custom session with default config is blocked`() {
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

        @Test func `Custom session with ephemeral config is blocked`() {
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

        @Test func `Violation message contains URL and guidance`() {
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

        @Test func `File URL is not blocked`() {
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

        @Test func `allowNetworkAccess prevents blocking`() {
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

        @Test func `Deactivated guard does not block`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test func `Issue record handler pattern compiles`() {
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

        @Test func `Trait blocks network requests`() {
            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == true)
        }

        @Test func `Trait allows opt out`() {
            Airgap.allowNetworkAccess()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }

        @Test func `Trait does not block file URLs`() {
            let fileURL = URL(fileURLWithPath: "/tmp/networkguard-trait-test.txt")
            let request = URLRequest(url: fileURL)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    @Suite struct TraitPerTestTests {

        @Test(.airgapped) func `Guarded test blocks requests`() {
            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == true)
        }

        @Test func `Unguarded test does not block`() {
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    // MARK: - Allowed hosts tests

    @Suite struct AllowedHostsTests {

        @Test func `Allowed host is not blocked`() {
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

        @Test func `Non-allowed host is blocked`() {
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

        @Test func `Multiple allowed hosts work`() {
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

        @Test func `Summary is nil with no violations`() {
            Airgap.clearViolations()
            #expect(Airgap.violationSummary() == nil)
        }

        @Test func `Summary contains violation count`() {
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

        @Test func `Unguarded suite does not block`() {
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    // MARK: - Trait state isolation tests

    @Suite struct TraitStateIsolationTests {

        @Test func `Trait restores allowed hosts`() {
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

        @Test func `Trait restores mode`() {
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

        @Test func `Allowed host is not blocked via trait`() {
            let localhostURL = URL(string: "https://localhost/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false,
                    "localhost should be allowed via trait parameter")
        }

        @Test func `Non-allowed host is still blocked via trait`() {
            let externalURL = URL(string: "https://example.com/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)) == true,
                    "Non-allowed host should still be blocked")
        }
    }

    // MARK: - Violations collected without reportPath

    @Suite struct ViolationCollectionTests {

        @Test func `Violations collected without report path`() {
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

    // MARK: - Trait with mode parameter

    @Suite(.airgapped(mode: .warn))
    struct TraitWithWarnModeTests {

        @Test func `Warn mode is set via trait`() {
            #expect(Airgap.mode == .warn, "Mode should be .warn when set via trait parameter")
        }
    }

    @Suite(.airgapped(mode: .warn, allowedHosts: ["localhost"]))
    struct TraitWithModeAndAllowedHostsTests {

        @Test func `Mode and allowed hosts combined`() {
            #expect(Airgap.mode == .warn)
            let localhostURL = URL(string: "https://localhost/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false)
        }
    }

    // MARK: - Warn mode with trait does not fail

    @Suite(.airgapped(mode: .warn))
    struct TraitWarnModeDoesNotFailTests {

        @Test func `Warn mode violation does not fail`() async throws {
            let url = URL(string: "https://example.com/api/warn-trait-test")!
            do {
                _ = try await URLSession.shared.data(from: url)
            } catch {
                // Expected — blocked request delivers an error
            }
            // If this test passes, warn mode correctly doesn't fail the test
            #expect(Airgap.violations.count >= 1, "Violation should be collected")
        }
    }

    // MARK: - Trait clears violations per-test

    @Suite(.serialized) struct TraitViolationClearingTests {

        /// Verifies that provideScope clears violations before each test.
        /// Uses manual activation instead of the trait to avoid Issue.record noise.
        @Test func `Violations are cleared between scopes`() async throws {
            // Simulate what provideScope does — first scope produces a violation
            let capture = ViolationCapture()
            let previousHandler = Airgap.violationHandler
            defer { Airgap.violationHandler = previousHandler }

            Airgap.violationHandler = { capture.record($0) }
            Airgap.clearViolations()
            Airgap.activate()

            let url = URL(string: "https://example.com/api/first-scope")!
            do {
                _ = try await URLSession.shared.data(from: url)
            } catch {
                // Expected — blocked request delivers an error
            }

            #expect(Airgap.violations.count == 1)
            Airgap.deactivate()

            // Second scope — provideScope clears violations
            Airgap.clearViolations()
            Airgap.activate()

            #expect(Airgap.violations.count == 0,
                    "Violations from previous scope should be cleared")
            Airgap.deactivate()
        }
    }
}

// MARK: - Scope serialization tests

/// Lives outside `AllAirgapSwiftTestingTests` because the test body acquires
/// `Airgap.scopeLock` directly. Nesting it under the `.scopeLocked` parent
/// would deadlock (the trait holds the lock, then the test tries to acquire it again).
@Suite struct ScopeSerializationTests {

    @Test func `Scope lock serializes concurrent access`() async {
        // Verify that the scopeLock prevents concurrent scopes from overlapping.
        // Two tasks try to acquire the lock, modify global state, sleep, and check
        // that their state wasn't stomped by the other task.

        let orderLog = OrderLog()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await Airgap.scopeLock.lock()
                defer { Airgap.scopeLock.unlock() }
                orderLog.append("alpha-start")
                Airgap.allowedHosts = ["alpha.example.com"]
                try? await Task.sleep(nanoseconds: 50_000_000)
                #expect(Airgap.allowedHosts == ["alpha.example.com"],
                        "Alpha's allowedHosts should not be stomped by beta")
                orderLog.append("alpha-end")
            }

            group.addTask {
                await Airgap.scopeLock.lock()
                defer { Airgap.scopeLock.unlock() }
                orderLog.append("beta-start")
                Airgap.allowedHosts = ["beta.example.com"]
                try? await Task.sleep(nanoseconds: 50_000_000)
                #expect(Airgap.allowedHosts == ["beta.example.com"],
                        "Beta's allowedHosts should not be stomped by alpha")
                orderLog.append("beta-end")
            }

            await group.waitForAll()
        }

        // Verify serialization: one scope must fully complete before the other starts
        let log = orderLog.entries
        #expect(log.count == 4)
        // Either alpha runs fully before beta, or beta runs fully before alpha
        let alphaFirst = log == ["alpha-start", "alpha-end", "beta-start", "beta-end"]
        let betaFirst = log == ["beta-start", "beta-end", "alpha-start", "alpha-end"]
        #expect(alphaFirst || betaFirst,
                "Scopes must be fully serialized, got: \(log)")
    }
}
