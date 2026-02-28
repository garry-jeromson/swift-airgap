import Airgap
import XCTest

final class AirgapTestCaseConfigureTests: AirgapTestCase {

    override func configure() {
        Airgap.mode = .warn
        Airgap.allowedHosts = ["localhost"]
    }

    func testWarnModeIsSet() {
        XCTAssertEqual(Airgap.mode, .warn)
    }

    func testAllowedHostsAreSet() {
        XCTAssertTrue(Airgap.allowedHosts.contains("localhost"))
    }

    @MainActor
    func testAllowedHostPassesThrough() {
        // Requests to allowed hosts should not produce a violation error code
        let expectation = expectation(description: "request")
        // Use a URL that will fail for a different reason (connection refused)
        // but NOT with the Airgap error code
        let url = URL(string: "http://localhost:1")!
        URLSession.shared.dataTask(with: url) { _, _, error in
            let nsError = error as? NSError
            // Should NOT be the Airgap error code — it should be a real connection error
            XCTAssertNotEqual(nsError?.code, NSURLErrorNotConnectedToInternet)
            expectation.fulfill()
        }.resume()
        waitForExpectations(timeout: 5)
    }
}
