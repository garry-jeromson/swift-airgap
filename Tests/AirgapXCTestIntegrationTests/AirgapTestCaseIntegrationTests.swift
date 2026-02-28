import Airgap
import XCTest

// MARK: - AirgapTestCase consumer integration tests

/// Simulates how a consumer would use AirgapTestCase as their base class.
/// Network calls should produce XCTFail via the inherited setUp/tearDown lifecycle.
final class AirgapTestCaseIntegrationTests: AirgapTestCase {
    func testNetworkCallInTestCaseSubclassProducesXCTFailure() throws {
        XCTExpectFailure("AirgapTestCase should block network calls automatically")

        let expectation = expectation(description: "Data task completes")
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))

        URLSession.shared.dataTask(with: url) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)
    }

    func testFileURLInTestCaseSubclassDoesNotFail() {
        // No XCTExpectFailure — file:// URLs should not trigger the guard.
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("networkguard-testcase-test.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "File load completes")

        URLSession.shared.dataTask(with: tempFile) { _, _, _ in
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 5.0)

        try? FileManager.default.removeItem(at: tempFile)
    }
}

// MARK: - AirgapTestCase with configure() override

/// Simulates a consumer who overrides configure() to set custom mode and allowed hosts.
final class AirgapTestCaseConfigureIntegrationTests: AirgapTestCase {
    override func configure() {
        Airgap.mode = .warn
        Airgap.allowedHosts = ["localhost"]
    }

    func testConfigureOverrideSetsMode() {
        XCTAssertEqual(Airgap.mode, .warn, "configure() should set warn mode")
    }

    func testConfigureOverrideSetsAllowedHosts() {
        XCTAssertTrue(Airgap.allowedHosts.contains("localhost"),
                      "configure() should add localhost to allowed hosts")
    }

    func testConfigureOverrideAllowedHostPassesThrough() throws {
        let url = try XCTUnwrap(URL(string: "https://localhost/api"))
        let request = URLRequest(url: url)
        XCTAssertFalse(AirgapURLProtocol.canInit(with: request),
                       "localhost should pass through when set in configure()")
    }
}

// MARK: - AirgapTestCase with allowNetworkAccess opt-out

/// Simulates a consumer who inherits AirgapTestCase but opts out via allowNetworkAccess().
final class AirgapTestCaseOptOutIntegrationTests: AirgapTestCase {
    override func setUp() {
        super.setUp()
        Airgap.allowNetworkAccess()
    }

    func testOptedOutSuiteDoesNotProduceXCTFailure() throws {
        // No XCTExpectFailure — allowNetworkAccess() in setUp should prevent failures.
        let url = try XCTUnwrap(URL(string: "https://example.com/api"))
        let request = URLRequest(url: url)

        XCTAssertFalse(AirgapURLProtocol.canInit(with: request))
    }
}
