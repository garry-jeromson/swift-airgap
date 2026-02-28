import Airgap
import XCTest

// MARK: - Warn mode integration tests

/// These tests verify that warn mode does NOT fail the test — no XCTExpectFailure wrapper
/// is needed because warn mode handles it internally via XCTExpectFailure.
/// If warn mode is broken, these tests would fail with an unexpected XCTFail.
final class AirgapWarnModeIntegrationTests: XCTestCase {
    private var originalMode: Airgap.Mode!

    override func setUp() {
        super.setUp()
        Airgap.inXCTestContext = true
        originalMode = Airgap.mode
        Airgap.mode = .warn
    }

    override func tearDown() {
        Airgap.deactivate()
        Airgap.mode = originalMode
        super.tearDown()
    }

    func testWarnModeDoesNotFailTestWithDefaultHandler() throws {
        // No XCTExpectFailure here — warn mode should handle it internally.
        // If this test fails, warn mode is broken.
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = try XCTUnwrap(URL(string: "https://example.com/api/warn-integration"))

        URLSession.shared.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error, "Blocked request should still deliver an error")
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeWithAsyncAwaitDoesNotFailTest() async throws {
        Airgap.activate()

        let url = try XCTUnwrap(URL(string: "https://example.com/api/warn-async"))
        do {
            _ = try await URLSession.shared.data(from: url)
        } catch {
            // Expected — blocked request delivers an error
        }
        // Test should pass — warn mode wraps failure in XCTExpectFailure
    }

    func testWarnModeWithCustomSessionDoesNotFailTest() throws {
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .default)
        let url = try XCTUnwrap(URL(string: "https://example.com/api/warn-custom-session"))

        session.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeWithEphemeralSessionDoesNotFailTest() throws {
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let session = URLSession(configuration: .ephemeral)
        let url = try XCTUnwrap(URL(string: "https://example.com/api/warn-ephemeral"))

        session.dataTask(with: url) { _, _, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testWarnModeCollectsViolationsForReport() throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ng-warn-integration-\(UUID().uuidString).txt").path
        Airgap.reportPath = tempPath
        Airgap.clearViolations()
        Airgap.activate()

        let expectation = expectation(description: "Data task completes")
        let url = try XCTUnwrap(URL(string: "https://example.com/api/warn-report"))

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        Airgap.writeReport()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath), "Report file should be created")
        let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content?.contains("warn-report") ?? false, "Report should contain the URL")

        // Cleanup
        Airgap.reportPath = nil
        Airgap.clearViolations()
        try? FileManager.default.removeItem(atPath: tempPath)
    }
}
