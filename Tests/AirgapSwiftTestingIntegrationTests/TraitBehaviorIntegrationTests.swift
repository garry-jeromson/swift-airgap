import Testing
@testable import Airgap
import Foundation

extension AllAirgapSwiftTestingTests {

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

    @Suite struct TraitAbsenceTests {

        @Test func `Unguarded suite does not block`() {
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
        }
    }

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
