import Airgap
import XCTest

/// Tests that `Airgap.configureFromEnvironment()` reads environment variables correctly.
final class EnvironmentVariableTests: XCTestCase {

    override func tearDown() {
        // Clean up environment variables
        unsetenv("AIRGAP_MODE")
        unsetenv("AIRGAP_REPORT_PATH")
        unsetenv("AIRGAP_ALLOWED_HOSTS")
        unsetenv("AIRGAP_ERROR_CODE")

        // Reset Airgap state
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.allowedHosts = []
        Airgap.errorCode = NSURLErrorNotConnectedToInternet
        Airgap.deactivate()
        super.tearDown()
    }

    func testWarnModeFromEnvironment() {
        setenv("AIRGAP_MODE", "warn", 1)
        Airgap.configureFromEnvironment()
        XCTAssertEqual(Airgap.mode, .warn)
    }

    func testFailModeIsDefault() {
        Airgap.configureFromEnvironment()
        XCTAssertEqual(Airgap.mode, .fail)
    }

    func testReportPathFromEnvironment() {
        setenv("AIRGAP_REPORT_PATH", "/tmp/airgap-report.json", 1)
        Airgap.configureFromEnvironment()
        XCTAssertEqual(Airgap.reportPath, "/tmp/airgap-report.json")
    }

    func testAllowedHostsFromEnvironment() {
        setenv("AIRGAP_ALLOWED_HOSTS", "localhost,127.0.0.1,*.example.com", 1)
        Airgap.configureFromEnvironment()
        XCTAssertEqual(Airgap.allowedHosts, ["localhost", "127.0.0.1", "*.example.com"])
    }

    func testErrorCodeFromEnvironment() {
        setenv("AIRGAP_ERROR_CODE", "-1004", 1)
        Airgap.configureFromEnvironment()
        XCTAssertEqual(Airgap.errorCode, -1004)
    }

    func testAllPropertiesTogether() {
        setenv("AIRGAP_MODE", "warn", 1)
        setenv("AIRGAP_REPORT_PATH", "/tmp/report.txt", 1)
        setenv("AIRGAP_ALLOWED_HOSTS", "localhost", 1)
        setenv("AIRGAP_ERROR_CODE", "-1001", 1)

        Airgap.configureFromEnvironment()

        XCTAssertEqual(Airgap.mode, .warn)
        XCTAssertEqual(Airgap.reportPath, "/tmp/report.txt")
        XCTAssertEqual(Airgap.allowedHosts, ["localhost"])
        XCTAssertEqual(Airgap.errorCode, -1001)
    }
}
