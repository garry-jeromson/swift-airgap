import Testing
@testable import Airgap
import Foundation

extension AllAirgapSwiftTestingTests {

    @Suite(.airgapped(allowedHosts: ["localhost", "127.0.0.1"]))
    struct TraitWithAllowedHostsTests {

        @Test func `Allowed host is not blocked via trait`() {
            let localhostURL = URL(string: "https://localhost/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false,
                    "localhost should be allowed via trait parameter")
        }

        @Test func `Non-allowed host is still blocked via trait`() {
            let externalURL = URL(string: "https://example.com/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)) == true,
                    "Non-allowed host should still be blocked")
        }
    }

    @Suite(.airgapped(mode: .warn))
    struct TraitWithWarnModeTests {

        @Test func `Warn mode is set via trait`() {
            #expect(Airgap.mode == .warn, "Mode should be .warn when set via trait parameter")
        }
    }

    @Suite(.airgapped(mode: .warn, allowedHosts: ["localhost"]))
    struct TraitWithModeAndAllowedHostsTests {

        @Test func `Mode and allowed hosts combined`() {
            #expect(Airgap.mode == .warn)
            let localhostURL = URL(string: "https://localhost/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false)
        }
    }

    @Suite(.airgapped(mode: .warn))
    struct TraitWarnModeDoesNotFailTests {

        @Test func `Warn mode violation does not fail`() async throws {
            let url = URL(string: "https://example.com/api/warn-trait-test")!
            do {
                _ = try await URLSession.shared.data(from: url)
            } catch {
                // Expected — blocked request delivers an error
            }
            // If this test passes, warn mode correctly doesn't fail the test
            #expect(Airgap.violations.count >= 1, "Violation should be collected")
        }
    }
}
