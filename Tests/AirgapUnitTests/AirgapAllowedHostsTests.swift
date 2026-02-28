@testable import Airgap
import Foundation
import Testing

extension AllAirgapUnitTests {
    @Suite(.serialized)
    final class AirgapAllowedHostsTests {
        private let capture = ViolationCapture()

        init() {
            resetAirgapState(capture: capture)
        }

        // MARK: - Allowed hosts

        @Test("Allowed host is not blocked") func allowedHostIsNotBlocked() throws {
            Airgap.allowedHosts = ["example.com"]
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/test"))
            let request = URLRequest(url: url)

            #expect(!AirgapURLProtocol.canInit(with: request))
            #expect(capture.isEmpty)
        }

        @Test("Non-allowed host is blocked") func nonAllowedHostIsBlocked() async throws {
            Airgap.allowedHosts = ["localhost"]
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/test"))
            _ = try? await URLSession.shared.data(from: url)

            #expect(Airgap.violations.count == 1)
        }

        @Test("Allowed hosts persist across activations") func allowedHostsPersistAcrossActivations() throws {
            Airgap.allowedHosts = ["localhost", "127.0.0.1"]
            Airgap.activate()
            Airgap.deactivate()
            Airgap.activate()

            #expect(Airgap.allowedHosts.contains("localhost"))
            #expect(Airgap.allowedHosts.contains("127.0.0.1"))

            let url = try #require(URL(string: "https://localhost/api/test"))
            let request = URLRequest(url: url)
            #expect(!AirgapURLProtocol.canInit(with: request))
        }

        @Test("Allowed hosts can be modified incrementally") func allowedHostsCanBeModifiedIncrementally() throws {
            Airgap.allowedHosts = []
            Airgap.allowedHosts.insert("localhost")
            Airgap.activate()

            let localhostURL = try #require(URL(string: "https://localhost/api"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

            let externalURL = try #require(URL(string: "https://example.com/api"))
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
        }

        @Test("Allowed hosts with multiple hosts") func allowedHostsWithMultipleHosts() throws {
            Airgap.allowedHosts = ["localhost", "127.0.0.1", "mock-server.local"]
            Airgap.activate()

            for host in ["localhost", "127.0.0.1", "mock-server.local"] {
                let url = try #require(URL(string: "https://\(host)/api"))
                #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                        "\(host) should not be blocked")
            }

            let blockedURL = try #require(URL(string: "https://real-api.example.com/data"))
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)),
                    "Non-allowed host should be blocked")
        }

        @Test("Allowed hosts empty by default") func allowedHostsEmptyByDefault() {
            #expect(Airgap.allowedHosts.isEmpty)
        }

        @Test("Allowed hosts with http scheme") func allowedHostsWithHTTPScheme() throws {
            Airgap.allowedHosts = ["localhost"]
            Airgap.activate()

            let url = try #require(URL(string: "http://localhost:8080/api"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)))
        }

        @Test("Allowed hosts combined with allow network access") func allowedHostsCombinedWithAllowNetworkAccess() throws {
            Airgap.allowedHosts = ["localhost"]
            Airgap.activate()
            Airgap.allowNetworkAccess()

            let externalURL = try #require(URL(string: "https://example.com/api"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
        }

        // MARK: - Wildcard host matching

        @Test("Wildcard allowed host matches subdomain") func wildcardAllowedHostMatchesSubdomain() throws {
            Airgap.allowedHosts = ["*.example.com"]
            Airgap.activate()

            let url = try #require(URL(string: "https://api.example.com/data"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "*.example.com should match api.example.com")
        }

        @Test("Wildcard allowed host matches base domain") func wildcardAllowedHostMatchesBaseDomain() throws {
            Airgap.allowedHosts = ["*.example.com"]
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/data"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "*.example.com should also match example.com itself")
        }

        @Test("Wildcard allowed host matches deep subdomain") func wildcardAllowedHostMatchesDeepSubdomain() throws {
            Airgap.allowedHosts = ["*.example.com"]
            Airgap.activate()

            let url = try #require(URL(string: "https://deep.sub.example.com/data"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "*.example.com should match deep.sub.example.com")
        }

        @Test("Wildcard allowed host does not match different domain") func wildcardAllowedHostDoesNotMatchDifferentDomain() async throws {
            Airgap.allowedHosts = ["*.example.com"]
            Airgap.activate()

            let url = try #require(URL(string: "https://notexample.com/data"))
            _ = try? await URLSession.shared.data(from: url)

            #expect(Airgap.violations.count == 1, "*.example.com should not match notexample.com")
        }

        @Test("Wildcard allowed host is case insensitive") func wildcardAllowedHostIsCaseInsensitive() throws {
            Airgap.allowedHosts = ["*.Example.COM"]
            Airgap.activate()

            let url = try #require(URL(string: "https://api.example.com/data"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "Wildcard matching should be case-insensitive")
        }

        @Test("Mixed exact and wildcard hosts") func mixedExactAndWildcardHosts() throws {
            Airgap.allowedHosts = ["localhost", "*.mock-server.local"]
            Airgap.activate()

            let localhostURL = try #require(URL(string: "https://localhost/api"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

            let mockURL = try #require(URL(string: "https://api.mock-server.local/data"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: mockURL)))

            let blockedURL = try #require(URL(string: "https://real-api.com/data"))
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)))
        }

        // MARK: - Case-insensitive host matching

        @Test("Allowed hosts case insensitive") func allowedHostsCaseInsensitive() throws {
            Airgap.allowedHosts = ["Example.COM"]
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "Host matching should be case-insensitive")
        }

        @Test("Allowed hosts mixed case in URL") func allowedHostsMixedCaseInURL() throws {
            Airgap.allowedHosts = ["localhost"]
            Airgap.activate()

            let url = try #require(URL(string: "https://LocalHost/api"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "URL host should be matched case-insensitively")
        }

        // MARK: - IPv6 allowed hosts

        @Test("IPv6 allowed host") func IPv6AllowedHost() throws {
            Airgap.allowedHosts = ["::1"]
            Airgap.activate()

            let url = try #require(URL(string: "https://[::1]/api"))
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "IPv6 loopback should be allowed when in allowedHosts")
        }
    }
} // extension AllAirgapUnitTests
