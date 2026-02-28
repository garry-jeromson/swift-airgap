@testable import Airgap
import Foundation
import Testing

extension AllAirgapSwiftTestingTests {
    @Suite struct AllowedHostsTests {
        @Test("Allowed host is not blocked") func allowedHostIsNotBlocked() throws {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["example.com"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let url = try #require(URL(string: "https://example.com/api"))
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test("Non-allowed host is blocked") func nonAllowedHostIsBlocked() throws {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["localhost"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let url = try #require(URL(string: "https://example.com/api"))
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
        }

        @Test("Multiple allowed hosts work") func multipleAllowedHostsWork() throws {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["localhost", "127.0.0.1"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let localhostURL = try #require(URL(string: "https://localhost/api"))
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false)

            let loopbackURL = try #require(URL(string: "https://127.0.0.1/api"))
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: loopbackURL)) == false)

            #expect(capture.isEmpty)
        }
    }
}
