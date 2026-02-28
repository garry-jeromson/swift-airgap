import Airgap
import Foundation
import Testing

@Suite(.serialized, .airgapped(mode: .warn))
struct SuiteTraitTests {
    @Test
    func requestIsBlocked() async throws {
        do {
            _ = try await URLSession.shared.data(from: #require(URL(string: "https://example.com")))
            Issue.record("Should have been blocked")
        } catch {
            #expect((error as NSError).code == URLError.notConnectedToInternet.rawValue)
        }
    }

    @Test
    func airgapIsActive() {
        #expect(Airgap.isActive)
    }
}
