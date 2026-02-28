import Airgap
import XCTest

/// Tests that AirgapTestCase writes a report file during tearDown when reportPath is set.
final class ReportTests: AirgapTestCase {

    private var tempPath: String!

    override func configure() {
        Airgap.mode = .warn
        tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("airgap-xctest-consumer-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
    }

    override func tearDown() {
        super.tearDown()
        // Clean up after assertions
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @MainActor
    func testTearDownWritesReport() {
        XCTAssertEqual(Airgap.reportPath, tempPath)

        let expectation = expectation(description: "blocked")
        URLSession.shared.dataTask(with: URL(string: "https://example.com/api/report")!) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()
        waitForExpectations(timeout: 5)

        XCTAssertEqual(Airgap.violations.count, 1)

        // Manually call writeReport() — same call tearDown() makes.
        Airgap.writeReport()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
        let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("Method: GET") ?? false)
        XCTAssertTrue(content?.contains("URL: https://example.com/api/report") ?? false)
        XCTAssertTrue(content?.contains("Total violations:") ?? false)
    }
}
