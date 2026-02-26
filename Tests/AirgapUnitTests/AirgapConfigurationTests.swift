import Foundation
import Testing
@testable import Airgap

extension AllAirgapUnitTests {

@Suite(.serialized)
final class AirgapConfigurationTests {

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

    // MARK: - Warning mode

    @Test("Warn mode does not fail test") func warnModeDoesNotFailTest() async {
        Airgap.mode = .warn
        Airgap.activate()

        let url = URL(string: "https://example.com/api/warn-test")!
        _ = try? await URLSession.shared.data(from: url)

        // Warn mode with inXCTestContext=false calls handler directly (no main queue dispatch)
        #expect(capture.count == 1)
    }

    @Test("Warn mode calls violation handler directly") func warnModeCallsViolationHandlerDirectly() {
        Airgap.mode = .warn

        // Call reportViolation directly on the main thread to avoid async timing issues
        Airgap.reportViolation(method: "GET", url: "https://example.com/warn-direct", callStack: [], testName: "test")

        #expect(capture.count == 1, "Warn mode should call the configured violationHandler")
        #expect(capture.messages.first?.contains("warn-direct") ?? false)
    }

    @Test("Fail mode calls violation handler directly") func failModeCallsViolationHandlerDirectly() async {
        Airgap.mode = .fail
        Airgap.activate()

        let url = URL(string: "https://example.com/api/fail-test")!
        _ = try? await URLSession.shared.data(from: url)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("fail-test") ?? false)
    }

    // MARK: - Error code and response delay

    @Test("Custom error code is delivered") func customErrorCodeIsDelivered() async {
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

    @Test("Default error code is not connected to internet") func defaultErrorCodeIsNotConnectedToInternet() async {
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

    @Test("Response delay adds latency") func responseDelayAddsLatency() async {
        Airgap.responseDelay = 0.5
        Airgap.activate()

        let url = URL(string: "https://example.com/delay-test")!
        let start = Date()
        _ = try? await URLSession.shared.data(from: url)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.4, "Response should be delayed by at least 0.4s")
    }

    @Test("Default response delay is zero") func defaultResponseDelayIsZero() {
        #expect(Airgap.responseDelay == 0)
    }

    // MARK: - withConfiguration scoping

    @Test("With configuration restores mode") func withConfigurationRestoresMode() {
        Airgap.mode = .fail
        Airgap.withConfiguration(mode: .warn) {
            #expect(Airgap.mode == .warn)
        }
        #expect(Airgap.mode == .fail)
    }

    @Test("With configuration restores allowed hosts") func withConfigurationRestoresAllowedHosts() {
        Airgap.allowedHosts = ["original.com"]
        Airgap.withConfiguration(allowedHosts: ["override.com"]) {
            #expect(Airgap.allowedHosts == ["override.com"])
        }
        #expect(Airgap.allowedHosts == ["original.com"])
    }

    @Test("With configuration restores handler") func withConfigurationRestoresHandler() {
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

    @Test("With configuration restores on throw") func withConfigurationRestoresOnThrow() {
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

    @Test("With configuration restores error code") func withConfigurationRestoresErrorCode() {
        Airgap.errorCode = NSURLErrorNotConnectedToInternet
        Airgap.withConfiguration(errorCode: NSURLErrorTimedOut) {
            #expect(Airgap.errorCode == NSURLErrorTimedOut)
        }
        #expect(Airgap.errorCode == NSURLErrorNotConnectedToInternet)
    }

    @Test("With configuration restores response delay") func withConfigurationRestoresResponseDelay() {
        Airgap.responseDelay = 0
        Airgap.withConfiguration(responseDelay: 2.5) {
            #expect(Airgap.responseDelay == 2.5)
        }
        #expect(Airgap.responseDelay == 0)
    }

    @Test("With configuration partial override keeps other settings") func withConfigurationPartialOverrideKeepsOtherSettings() {
        Airgap.mode = .fail
        Airgap.errorCode = 42
        Airgap.withConfiguration(mode: .warn) {
            #expect(Airgap.mode == .warn)
            #expect(Airgap.errorCode == 42, "Non-overridden settings should be preserved")
        }
        #expect(Airgap.mode == .fail)
        #expect(Airgap.errorCode == 42)
    }

    // MARK: - configureFromEnvironment

    @Test("configureFromEnvironment does not crash with no env vars") func configureFromEnvironmentDoesNotCrashWithNoEnvVars() {
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.configureFromEnvironment()
        #expect(Airgap.mode == .fail)
        #expect(Airgap.reportPath == nil)
    }

    @Test("configureFromEnvironment is idempotent") func configureFromEnvironmentIsIdempotent() {
        Airgap.configureFromEnvironment()
        let modeAfterFirst = Airgap.mode
        let pathAfterFirst = Airgap.reportPath
        let hostsAfterFirst = Airgap.allowedHosts

        Airgap.configureFromEnvironment()
        #expect(Airgap.mode == modeAfterFirst)
        #expect(Airgap.reportPath == pathAfterFirst)
        #expect(Airgap.allowedHosts == hostsAfterFirst, "Calling configureFromEnvironment twice should not duplicate hosts")
    }

    @Test("configureFromEnvironment resets mode when env var absent") func configureFromEnvironmentResetsModeWhenEnvVarAbsent() {
        Airgap.mode = .warn
        Airgap.configureFromEnvironment()
        #expect(Airgap.mode == .fail, "configureFromEnvironment should reset mode to .fail when AIRGAP_MODE is not set")
    }

    @Test("configureFromEnvironment resets report path when env var absent") func configureFromEnvironmentResetsReportPathWhenEnvVarAbsent() {
        Airgap.reportPath = "/some/path/report.txt"
        Airgap.configureFromEnvironment()
        #expect(Airgap.reportPath == nil, "configureFromEnvironment should reset reportPath when AIRGAP_REPORT_PATH is not set")
    }

    @Test("configureFromEnvironment does not accumulate hosts") func configureFromEnvironmentDoesNotAccumulateHosts() {
        Airgap.allowedHosts = ["manually-added.com"]
        Airgap.configureFromEnvironment()
        #expect(!Airgap.allowedHosts.contains("manually-added.com"),
                "configureFromEnvironment should assign hosts, not union them")
    }

    // MARK: - Mode is not reset by activate

    @Test("Activate does not reset mode") func activateDoesNotResetMode() {
        Airgap.mode = .warn
        Airgap.activate()
        #expect(Airgap.mode == .warn)

        Airgap.activate()
        #expect(Airgap.mode == .warn)
    }

    // MARK: - currentTestName management

    @Test("Current test name is restorable") func currentTestNameIsRestorable() {
        let original = AirgapURLProtocol.currentTestName
        AirgapURLProtocol.currentTestName = "OuterScope/testOuter"

        let saved = AirgapURLProtocol.currentTestName
        AirgapURLProtocol.currentTestName = "InnerScope/testInner"
        #expect(AirgapURLProtocol.currentTestName == "InnerScope/testInner")

        AirgapURLProtocol.currentTestName = saved
        #expect(AirgapURLProtocol.currentTestName == "OuterScope/testOuter", "currentTestName should be restored after inner scope ends")

        AirgapURLProtocol.currentTestName = original
    }

    // MARK: - Violation reporter

    @Test("Violation reporter receives violation struct") func violationReporterReceivesViolationStruct() async {
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

    @Test("Violation reporter called alongside handler") func violationReporterCalledAlongsideHandler() async {
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

    @Test("Violation reporter is nil by default") func violationReporterIsNilByDefault() {
        #expect(Airgap.violationReporter == nil)
    }

    @Test("Violation reporter can be cleared") func violationReporterCanBeCleared() {
        Airgap.violationReporter = { _ in }
        #expect(Airgap.violationReporter != nil)
        Airgap.violationReporter = nil
        #expect(Airgap.violationReporter == nil)
    }

    // MARK: - Concurrent handler mutation

    @Test("Concurrent handler mutation does not crash") func concurrentHandlerMutationDoesNotCrash() {
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
}

} // extension AllAirgapUnitTests
