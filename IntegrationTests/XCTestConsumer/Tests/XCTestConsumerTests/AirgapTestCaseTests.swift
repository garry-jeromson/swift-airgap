import Airgap
import XCTest

/// Tests AirgapTestCase in default (.fail) mode.
final class AirgapTestCaseTests: AirgapTestCase {
    @MainActor
    func testRequestIsBlockedInFailMode() throws {
        XCTAssertEqual(Airgap.mode, .fail)

        // The violation handler calls XCTFail — expect that failure.
        XCTExpectFailure("Airgap violation expected — verifying .fail mode fires XCTFail")

        let expectation = expectation(description: "blocked")
        try URLSession.shared.dataTask(with: XCTUnwrap(URL(string: "https://example.com"))) { _, _, error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as? NSError)?.code, NSURLErrorNotConnectedToInternet)
            expectation.fulfill()
        }.resume()
        waitForExpectations(timeout: 5)

        // Verify the violation is attributed to this test method.
        let violations = Airgap.violations
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.testName.contains("testRequestIsBlockedInFailMode") == true)
    }

    func testIsActiveDuringTest() {
        XCTAssertTrue(Airgap.isActive)
    }

    func testDefaultModeIsFail() {
        XCTAssertEqual(Airgap.mode, .fail)
    }
}
