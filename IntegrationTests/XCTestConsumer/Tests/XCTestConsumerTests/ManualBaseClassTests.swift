import Airgap
import XCTest

/// Tests manual activate/deactivate in setUp/tearDown (base class pattern).
final class ManualBaseClassTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Airgap.inXCTestContext = true
        Airgap.activate()
    }

    override func tearDown() {
        Airgap.deactivate()
        super.tearDown()
    }

    @MainActor
    func testRequestIsBlockedInFailMode() {
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

    func testIsActiveDuringTest() {
        XCTAssertTrue(Airgap.isActive)
    }
}
