import Foundation
import Testing
@testable import Airgap

extension AllAirgapUnitTests {

@Suite(.serialized)
final class AirgapAllowedHostsTests {

    private let capture = ViolationCapture()

    init() {
        Airgap.deactivate()
        capture.reset()

        let cap = capture
        Airgap.violationHandler = { message in
            cap.record(message)
        }
        Airgap.violationReporter = nil
        Airgap.inXCTestContext = false
        Airgap.errorCode = NSURLErrorNotConnectedToInternet
        Airgap.responseDelay = 0
        Airgap.mode = .fail
        Airgap.reportPath = nil
        Airgap.allowedHosts = []
        Airgap.clearViolations()
    }

    // MARK: - Allowed hosts

    @Test func `Allowed host is not blocked`() {
        Airgap.allowedHosts = ["example.com"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api/test")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request))
        #expect(capture.isEmpty)
    }

    @Test func `Non-allowed host is blocked`() async {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api/test")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(Airgap.violations.count == 1)
    }

    @Test func `Allowed hosts persist across activations`() {
        Airgap.allowedHosts = ["localhost", "127.0.0.1"]
        Airgap.activate()
        Airgap.deactivate()
        Airgap.activate()

        #expect(Airgap.allowedHosts.contains("localhost"))
        #expect(Airgap.allowedHosts.contains("127.0.0.1"))

        let url = URL(string: "https://localhost/api/test")!
        let request = URLRequest(url: url)
        #expect(!AirgapURLProtocol.canInit(with: request))
    }

    @Test func `Allowed hosts can be modified incrementally`() {
        Airgap.allowedHosts = []
        Airgap.allowedHosts.insert("localhost")
        Airgap.activate()

        let localhostURL = URL(string: "https://localhost/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

        let externalURL = URL(string: "https://example.com/api")!
        #expect(AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
    }

    @Test func `Allowed hosts with multiple hosts`() {
        Airgap.allowedHosts = ["localhost", "127.0.0.1", "mock-server.local"]
        Airgap.activate()

        for host in ["localhost", "127.0.0.1", "mock-server.local"] {
            let url = URL(string: "https://\(host)/api")!
            #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                    "\(host) should not be blocked")
        }

        let blockedURL = URL(string: "https://real-api.example.com/data")!
        #expect(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)),
                "Non-allowed host should be blocked")
    }

    @Test func `Allowed hosts empty by default`() {
        #expect(Airgap.allowedHosts.isEmpty)
    }

    @Test func `Allowed hosts with http scheme`() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "http://localhost:8080/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)))
    }

    @Test func `Allowed hosts combined with allow network access`() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()
        Airgap.allowNetworkAccess()

        let externalURL = URL(string: "https://example.com/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: externalURL)))
    }

    // MARK: - Wildcard host matching

    @Test func `Wildcard allowed host matches subdomain`() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://api.example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "*.example.com should match api.example.com")
    }

    @Test func `Wildcard allowed host matches base domain`() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "*.example.com should also match example.com itself")
    }

    @Test func `Wildcard allowed host matches deep subdomain`() {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://deep.sub.example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "*.example.com should match deep.sub.example.com")
    }

    @Test func `Wildcard allowed host does not match different domain`() async {
        Airgap.allowedHosts = ["*.example.com"]
        Airgap.activate()

        let url = URL(string: "https://notexample.com/data")!
        _ = try? await URLSession.shared.data(from: url)

        #expect(Airgap.violations.count == 1, "*.example.com should not match notexample.com")
    }

    @Test func `Wildcard allowed host is case insensitive`() {
        Airgap.allowedHosts = ["*.Example.COM"]
        Airgap.activate()

        let url = URL(string: "https://api.example.com/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "Wildcard matching should be case-insensitive")
    }

    @Test func `Mixed exact and wildcard hosts`() {
        Airgap.allowedHosts = ["localhost", "*.mock-server.local"]
        Airgap.activate()

        let localhostURL = URL(string: "https://localhost/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)))

        let mockURL = URL(string: "https://api.mock-server.local/data")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: mockURL)))

        let blockedURL = URL(string: "https://real-api.com/data")!
        #expect(AirgapURLProtocol.canInit(with: URLRequest(url: blockedURL)))
    }

    // MARK: - Case-insensitive host matching

    @Test func `Allowed hosts case insensitive`() {
        Airgap.allowedHosts = ["Example.COM"]
        Airgap.activate()

        let url = URL(string: "https://example.com/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "Host matching should be case-insensitive")
    }

    @Test func `Allowed hosts mixed case in URL`() {
        Airgap.allowedHosts = ["localhost"]
        Airgap.activate()

        let url = URL(string: "https://LocalHost/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "URL host should be matched case-insensitively")
    }

    // MARK: - IPv6 allowed hosts

    @Test func `IPv6 allowed host`() {
        Airgap.allowedHosts = ["::1"]
        Airgap.activate()

        let url = URL(string: "https://[::1]/api")!
        #expect(!AirgapURLProtocol.canInit(with: URLRequest(url: url)),
                "IPv6 loopback should be allowed when in allowedHosts")
    }
}

} // extension AllAirgapUnitTests
