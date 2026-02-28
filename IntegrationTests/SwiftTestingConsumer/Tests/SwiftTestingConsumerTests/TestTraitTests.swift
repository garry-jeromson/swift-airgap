import Airgap
import Foundation
import Testing

@Suite(.serialized)
struct TestTraitTests {
    @Test(.airgapped(mode: .warn))
    func requestIsBlockedInWarnMode() async throws {
        #expect(Airgap.mode == .warn)

        do {
            _ = try await URLSession.shared.data(from: #require(URL(string: "https://example.com")))
            Issue.record("Should have been blocked")
        } catch {
            #expect((error as NSError).code == URLError.notConnectedToInternet.rawValue)
        }
    }

    @Test(.airgapped)
    func airgapIsActive() {
        #expect(Airgap.isActive)
    }

    @Test(.airgapped)
    func defaultModeIsFail() {
        #expect(Airgap.mode == .fail)
    }

    /// Verifies that violations collected during the test body are picked up
    /// by the trait's defer block and reported as Issues within the test's task
    /// context. The key assertion is that `Airgap.violations` is populated before
    /// the test body returns (so the defer block has something to report).
    ///
    /// Issue attribution (violations showing as `Test violationsAreReportedInTestScope()`
    /// rather than `Test «unknown»` in the test runner) is verified by inspecting
    /// the test output — Swift Testing doesn't expose an API to check this
    /// programmatically.
    @Test(.airgapped(mode: .warn))
    func violationsAreReportedInTestScope() async throws {
        do {
            _ = try await URLSession.shared.data(from: #require(URL(string: "https://example.com")))
            Issue.record("Should have been blocked")
        } catch {
            #expect((error as NSError).code == URLError.notConnectedToInternet.rawValue)
        }

        // Violations must be collected synchronously during the test body
        // so the trait's defer block can report them via Issue.record().
        let violations = Airgap.violations
        #expect(violations.count == 1)
        #expect(violations.first?.url == "https://example.com")
        #expect(violations.first?.httpMethod == "GET")
        #expect(violations.first?.testName.contains("violationsAreReportedInTestScope") == true)
    }
}
