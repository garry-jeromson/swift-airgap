@testable import Airgap
import Foundation
import Testing

extension AllAirgapUnitTests {
    @Suite(.serialized)
    final class AirgapActivationTests {
        private let capture = ViolationCapture()

        init() {
            resetAirgapState(capture: capture)
        }

        // MARK: - Activation / Deactivation

        @Test("Activate registers protocol") func activateRegistersProtocol() {
            Airgap.activate()
            #expect(AirgapURLProtocol.isActive)
        }

        @Test("Deactivate unregisters protocol") func deactivateUnregistersProtocol() {
            Airgap.activate()
            Airgap.deactivate()
            #expect(!AirgapURLProtocol.isActive)
        }

        @Test("Double activate is idempotent") func doubleActivateIsIdempotent() {
            Airgap.activate()
            Airgap.activate()
            #expect(AirgapURLProtocol.isActive)
        }

        @Test("isActive returns false before activation") func isActiveReturnsFalseBeforeActivation() {
            #expect(!Airgap.isActive)
        }

        @Test("isActive returns true after activation") func isActiveReturnsTrueAfterActivation() {
            Airgap.activate()
            #expect(Airgap.isActive)
        }

        @Test("isActive returns false after deactivation") func isActiveReturnsFalseAfterDeactivation() {
            Airgap.activate()
            Airgap.deactivate()
            #expect(!Airgap.isActive)
        }

        // MARK: - Allow network access

        @Test("Allow network access disables guard") func allowNetworkAccessDisablesGuard() throws {
            Airgap.activate()
            Airgap.allowNetworkAccess()

            let url = try #require(URL(string: "https://httpbin.org/get"))
            let request = URLRequest(url: url)

            #expect(!AirgapURLProtocol.canInit(with: request))
            #expect(capture.isEmpty)
        }

        @Test("Activate resets allow flag") func activateResetsAllowFlag() throws {
            Airgap.activate()
            Airgap.allowNetworkAccess()

            // Re-activate should reset the allow flag
            Airgap.activate()

            let url = try #require(URL(string: "https://httpbin.org/get"))
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request))
        }

        // MARK: - Inactive guard

        @Test("No violation when inactive") func noViolationWhenInactive() throws {
            // Guard is not activated — requests should not be intercepted.
            // We verify by checking that canInit returns false.
            let url = try #require(URL(string: "https://httpbin.org/get"))
            let request = URLRequest(url: url)

            #expect(!AirgapURLProtocol.canInit(with: request))
            #expect(capture.isEmpty)
        }

        // MARK: - AirgapTestCase lifecycle

        @Test("AirgapTestCase lifecycle") func airgapTestCaseLifecycle() {
            let testCase = LifecycleTestCase()

            // Simulate setUp
            testCase.invokeSetUp()
            #expect(AirgapURLProtocol.isActive)

            // Simulate tearDown
            testCase.invokeTearDown()
            #expect(!AirgapURLProtocol.isActive)
        }
    }
} // extension AllAirgapUnitTests
