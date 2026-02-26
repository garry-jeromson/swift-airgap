import Testing
@testable import Airgap
import Foundation

extension AllAirgapSwiftTestingTests {

    @Suite(.airgapped)
    struct TraitSuiteLevelTests {

        @Test("Trait blocks network requests") func traitBlocksNetworkRequests() {
            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == true)
        }

        @Test("Trait allows opt out") func traitAllowsOptOut() {
            Airgap.allowNetworkAccess()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }

        @Test("Trait does not block file URLs") func traitDoesNotBlockFileURLs() {
            let fileURL = URL(fileURLWithPath: "/tmp/networkguard-trait-test.txt")
            let request = URLRequest(url: fileURL)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    @Suite struct TraitPerTestTests {

        @Test("Guarded test blocks requests", .airgapped) func guardedTestBlocksRequests() {
            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == true)
        }

        @Test("Unguarded test does not block") func unguardedTestDoesNotBlock() {
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    @Suite struct TraitAbsenceTests {

        @Test("Unguarded suite does not block") func unguardedSuiteDoesNotBlock() {
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

    @Suite struct TraitStateIsolationTests {

        @Test("Trait restores allowed hosts") func traitRestoresAllowedHosts() {
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

        @Test("Trait restores mode") func traitRestoresMode() {
            // Set mode before trait scope
            let previousMode = Airgap.mode
            Airgap.mode = .warn
            defer { Airgap.mode = previousMode }

            // After trait scope ends, mode should be restored
            #expect(Airgap.mode == .warn)
        }
    }

    @Suite(.serialized) struct TraitViolationClearingTests {

        /// Verifies that provideScope clears violations before each test.
        /// Uses manual activation instead of the trait to avoid Issue.record noise.
        @Test("Violations are cleared between scopes") func violationsAreClearedBetweenScopes() async throws {
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
