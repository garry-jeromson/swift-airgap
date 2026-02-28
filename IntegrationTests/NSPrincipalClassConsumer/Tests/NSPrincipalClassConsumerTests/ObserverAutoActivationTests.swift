import Airgap
import XCTest

/// Tests that the `AirgapObserver` auto-activates Airgap via `NSPrincipalClass`.
///
/// This test does NOT call `Airgap.activate()` manually. If `Airgap.isActive` is `true`,
/// it means the observer was instantiated by the test runner via the `NSPrincipalClass`
/// Info.plist key and called `activate()` in `testBundleWillStart(_:)`.
///
/// Must be run with `xcodebuild test` passing `INFOPLIST_KEY_NSPrincipalClass=AirgapObserver`.
final class ObserverAutoActivationTests: XCTestCase {

    func testAirgapIsAutoActivated() {
        XCTAssertTrue(Airgap.isActive, "Airgap should be auto-activated by AirgapObserver via NSPrincipalClass")
    }

    @MainActor
    func testRequestIsBlockedWithoutManualActivation() {
        // Observer uses .fail mode by default; violations call XCTFail.
        // Wrap in XCTExpectFailure so the violation doesn't fail this test —
        // we only care that the request was blocked (error code check below).
        XCTExpectFailure("Airgap violation expected — verifying request is blocked")

        let expectation = expectation(description: "blocked")
        URLSession.shared.dataTask(with: URL(string: "https://example.com")!) { _, _, error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as? NSError)?.code, NSURLErrorNotConnectedToInternet)
            expectation.fulfill()
        }.resume()
        waitForExpectations(timeout: 5)
    }
}
