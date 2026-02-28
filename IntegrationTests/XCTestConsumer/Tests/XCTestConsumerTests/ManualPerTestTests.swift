import Airgap
import XCTest

/// Tests manual activate/deactivate within individual test methods.
final class ManualPerTestTests: XCTestCase {

    @MainActor
    func testRequestIsBlockedInFailMode() {
        Airgap.inXCTestContext = true
        Airgap.activate()
        defer { Airgap.deactivate() }

        XCTAssertEqual(Airgap.mode, .fail)
        XCTExpectFailure("Airgap violation expected — verifying .fail mode fires XCTFail")

        let expectation = expectation(description: "blocked")
        URLSession.shared.dataTask(with: URL(string: "https://example.com")!) { _, _, error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as? NSError)?.code, NSURLErrorNotConnectedToInternet)
            expectation.fulfill()
        }.resume()
        waitForExpectations(timeout: 5)
    }

    func testActivateDeactivateCycle() {
        Airgap.activate()
        XCTAssertTrue(Airgap.isActive)
        Airgap.deactivate()
    }
}
