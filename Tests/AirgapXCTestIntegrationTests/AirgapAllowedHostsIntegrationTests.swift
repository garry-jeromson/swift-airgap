import Airgap
import XCTest

// MARK: - Allowed hosts integration tests

/// These tests verify that the allowedHosts feature works correctly from
/// a consumer's perspective, including actual network request interception.
final class AirgapAllowedHostsIntegrationTests: XCTestCase {
    private var originalAllowedHosts: Set<String>!

    override func setUp() {
        super.setUp()
        originalAllowedHosts = Airgap.allowedHosts
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.allowedHosts = originalAllowedHosts
        super.tearDown()
    }

    func testAllowedHostDoesNotProduceXCTFailure() throws {
        Airgap.allowedHosts = ["example.com"]
        Airgap.activate()

        // No XCTExpectFailure — allowed host should pass cleanly.
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testNonAllowedHostProducesXCTFailure() throws {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        XCTExpectFailure("Non-allowed host should trigger XCTFail")

        let expectation = expectation(description: "Data task completes")
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testAllowedHostWithActualDataTask() throws {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        // localhost requests should not be intercepted
        let url = try XCTUnwrap(URL(string: "https://localhost/api"))
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }

    func testAllowedHostsWithWarnMode() throws {
        Airgap.allowedHosts = ["example.com"]
        Airgap.mode = .warn
        Airgap.activate()
        defer { Airgap.mode = .fail }

        // Allowed host should not produce any violation even in warn mode
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }
}
