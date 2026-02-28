import Airgap
import XCTest

// MARK: - Violation summary integration tests

final class AirgapViolationSummaryIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Airgap.clearViolations()
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.reportPath = nil
        Airgap.clearViolations()
        super.tearDown()
    }

    func testViolationSummaryWithDefaultHandler() throws {
        Airgap.clearViolations()
        Airgap.activate()

        XCTExpectFailure("Violation should trigger XCTFail")

        let expectation = expectation(description: "Data task completes")
        let url = try XCTUnwrap(URL(string: "https://example.com/api/summary"))

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        let summary = Airgap.violationSummary()
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("violation(s)") ?? false)
    }
}
