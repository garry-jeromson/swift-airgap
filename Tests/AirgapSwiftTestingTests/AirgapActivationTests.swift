import Foundation
import Testing
@testable import Airgap

extension AllAirgapSwiftTestingTests {

@Suite(.serialized)
final class AirgapActivationTests {

    private let capture = ViolationCapture()

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

    // MARK: - Activation / Deactivation

    @Test func `Activate registers protocol`() {
        Airgap.activate()
        #expect(AirgapURLProtocol.isActive)
    }

    @Test func `Deactivate unregisters protocol`() {
        Airgap.activate()
        Airgap.deactivate()
        #expect(!AirgapURLProtocol.isActive)
    }

    @Test func `Double activate is idempotent`() {
        Airgap.activate()
        Airgap.activate()
        #expect(AirgapURLProtocol.isActive)
    }

    @Test func `isActive returns false before activation`() {
        #expect(!Airgap.isActive)
    }

    @Test func `isActive returns true after activation`() {
        Airgap.activate()
        #expect(Airgap.isActive)
    }

    @Test func `isActive returns false after deactivation`() {
        Airgap.activate()
        Airgap.deactivate()
        #expect(!Airgap.isActive)
    }

    // MARK: - Allow network access

    @Test func `Allow network access disables guard`() {
        Airgap.activate()
        Airgap.allowNetworkAccess()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request))
        #expect(capture.isEmpty)
    }

    @Test func `Activate resets allow flag`() {
        Airgap.activate()
        Airgap.allowNetworkAccess()

        // Re-activate should reset the allow flag
        Airgap.activate()

        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        #expect(AirgapURLProtocol.canInit(with: request))
    }

    // MARK: - Inactive guard

    @Test func `No violation when inactive`() {
        // Guard is not activated — requests should not be intercepted.
        // We verify by checking that canInit returns false.
        let url = URL(string: "https://httpbin.org/get")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request))
        #expect(capture.isEmpty)
    }

    // MARK: - AirgapTestCase lifecycle

    @Test func `AirgapTestCase lifecycle`() {
        let testCase = LifecycleTestCase()

        // Simulate setUp
        testCase.invokeSetUp()
        #expect(AirgapURLProtocol.isActive)

        // Simulate tearDown
        testCase.invokeTearDown()
        #expect(!AirgapURLProtocol.isActive)
    }
}

} // extension AllAirgapSwiftTestingTests
