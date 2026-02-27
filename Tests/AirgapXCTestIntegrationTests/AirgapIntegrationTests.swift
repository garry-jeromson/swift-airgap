import XCTest
import Airgap

// MARK: - Integration tests using the default XCTFail handler

/// These tests verify the package from a consumer's perspective — confirming that
/// network violations produce actual XCTest failures, and that allowed/inactive
/// scenarios pass cleanly.
final class AirgapIntegrationTests: XCTestCase {

    override func tearDown() {
        Airgap.deactivate()
        super.tearDown()
    }

    // MARK: - Tests that should fail (wrapped in XCTExpectFailure)

    func testNetworkCallWithDefaultHandlerProducesXCTFailure() {
        Airgap.activate()

        XCTExpectFailure("Airgap should trigger XCTFail for blocked requests")

        let expectation = expectation(description: "Data task completes")
        let url = URL(string: "https://example.com/api")!

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testCustomSessionDefaultConfigWithDefaultHandlerProducesXCTFailure() {
        Airgap.activate()

        XCTExpectFailure("Airgap should trigger XCTFail for custom session with .default config")

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .default)
        let url = URL(string: "https://example.com/api")!

        session.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testCustomSessionEphemeralConfigWithDefaultHandlerProducesXCTFailure() {
        Airgap.activate()

        XCTExpectFailure("Airgap should trigger XCTFail for custom session with .ephemeral config")

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://example.com/api")!

        session.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Tests that should pass (no expected failure)

    func testAllowNetworkAccessPreventsXCTFailure() {
        Airgap.activate()
        Airgap.allowNetworkAccess()

        // No XCTExpectFailure — this should genuinely pass without any failure.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        // canInit returning false proves the request would not be intercepted.
        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testDeactivatedGuardDoesNotProduceXCTFailure() {
        Airgap.activate()
        Airgap.deactivate()

        // No XCTExpectFailure — this should genuinely pass.
        let url = URL(string: "https://example.com/api")!
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testFileURLDoesNotProduceXCTFailure() {
        Airgap.activate()

        // No XCTExpectFailure — file:// should never trigger the guard.
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("networkguard-integration-test.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "File load completes")

        URLSession.shared.dataTask(with: tempFile) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        try? FileManager.default.removeItem(at: tempFile)
    }
}
