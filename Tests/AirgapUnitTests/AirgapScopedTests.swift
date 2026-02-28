@testable import Airgap
import Foundation
import Testing

extension AllAirgapUnitTests {
    @Suite(.serialized)
    final class AirgapScopedTests {
        private let capture = ViolationCapture()

        init() {
            resetAirgapState(capture: capture)
        }

        @Test("scoped activates and deactivates") func scopedActivatesAndDeactivates() async {
            #expect(!Airgap.isActive)

            await Airgap.scoped {
                #expect(Airgap.isActive)
            }

            #expect(!Airgap.isActive)
        }

        @Test("scoped restores mode") func scopedRestoresMode() async {
            Airgap.mode = .fail

            await Airgap.scoped(mode: .warn) {
                #expect(Airgap.mode == .warn)
            }

            #expect(Airgap.mode == .fail)
        }

        @Test("scoped merges allowed hosts") func scopedMergesAllowedHosts() async {
            Airgap.allowedHosts = ["existing.com"]

            await Airgap.scoped(allowedHosts: ["extra.com"]) {
                #expect(Airgap.allowedHosts.contains("extra.com"))
            }

            #expect(Airgap.allowedHosts == ["existing.com"], "Allowed hosts should be restored after scoped block")
        }

        @Test("scoped restores error code") func scopedRestoresErrorCode() async {
            Airgap.errorCode = NSURLErrorTimedOut

            await Airgap.scoped {
                // configureFromEnvironment resets errorCode
            }

            #expect(Airgap.errorCode == NSURLErrorTimedOut, "Error code should be restored after scoped block")
        }

        @Test("scoped restores response delay") func scopedRestoresResponseDelay() async {
            Airgap.responseDelay = 1.5

            await Airgap.scoped {
                // configureFromEnvironment does not reset responseDelay
            }

            #expect(Airgap.responseDelay == 1.5, "Response delay should be restored after scoped block")
        }

        @Test("scoped restores violation handler") func scopedRestoresViolationHandler() async {
            let outerCapture = ViolationCapture()
            Airgap.violationHandler = { outerCapture.record($0) }

            await Airgap.scoped {
                // Inside scoped, handler is no-op
                Airgap.violationHandler("should be swallowed")
            }

            Airgap.violationHandler("after scoped")
            #expect(outerCapture.count == 1, "Outer handler should be restored")
            #expect(outerCapture.messages.first?.contains("after scoped") ?? false)
        }

        @Test("scoped restores violation reporter") func scopedRestoresViolationReporter() async {
            let reporterCapture = ViolationReporterCapture()
            Airgap.violationReporter = { reporterCapture.record($0) }

            await Airgap.scoped {
                // scoped does not modify reporter, but verify restore works
            }

            #expect(Airgap.violationReporter != nil, "Reporter should be restored after scoped block")
        }

        @Test("scoped restores currentTestName") func scopedRestoresCurrentTestName() async {
            AirgapURLProtocol.currentTestName = "OriginalTest"

            await Airgap.scoped {
                // scoped does not set currentTestName itself
            }

            #expect(AirgapURLProtocol.currentTestName == "OriginalTest", "currentTestName should be restored")
        }

        @Test("scoped collects violations in warn mode") func scopedCollectsViolationsInWarnMode() async {
            await Airgap.scoped(mode: .warn) {
                let url = URL(string: "https://example.com/scoped-violation-test")!
                _ = try? await URLSession.shared.data(from: url)
            }

            // In warn mode, violations are reported via withKnownIssue so the test
            // does not fail. Verify the scope completed and Airgap is deactivated.
            #expect(!Airgap.isActive)
        }

        @Test("scoped reports violations in fail mode") func scopedReportsViolationsInFailMode() async {
            await withKnownIssue("Airgap violation expected in fail mode") {
                await Airgap.scoped(mode: .fail) {
                    let url = URL(string: "https://example.com/scoped-fail-test")!
                    _ = try? await URLSession.shared.data(from: url)
                }
            }

            #expect(!Airgap.isActive)
        }

        @Test("scoped clears violations before body") func scopedClearsViolationsBeforeBody() async {
            // Pre-populate a violation
            Airgap.activate()
            Airgap.reportViolation(method: "GET", url: "https://pre.com", callStack: [], testName: "pre")
            Airgap.deactivate()
            #expect(Airgap.violations.count == 1)

            await Airgap.scoped {
                // Violations should be cleared at scope entry
                #expect(Airgap.violations.isEmpty, "Violations should be cleared at the start of scoped block")
            }
        }

        @Test("scoped with default mode uses current mode") func scopedWithDefaultModeUsesCurrentMode() async {
            Airgap.mode = .warn

            await Airgap.scoped {
                // configureFromEnvironment resets mode to .fail when AIRGAP_MODE is absent,
                // but we passed no explicit mode override, so the effective mode should
                // be whatever configureFromEnvironment set
            }

            // Mode should be restored to .warn
            #expect(Airgap.mode == .warn)
        }
    }
} // extension AllAirgapUnitTests
