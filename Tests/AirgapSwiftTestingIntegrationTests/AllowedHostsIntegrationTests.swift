import Testing
@testable import Airgap
import Foundation

extension AllAirgapSwiftTestingTests {

    @Suite struct AllowedHostsTests {

        @Test func `Allowed host is not blocked`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["example.com"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test func `Non-allowed host is blocked`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["localhost"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let url = URL(string: "https://example.com/api")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
        }

        @Test func `Multiple allowed hosts work`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.allowedHosts = ["localhost", "127.0.0.1"]
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.allowedHosts = []
            }

            let localhostURL = URL(string: "https://localhost/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: localhostURL)) == false)

            let loopbackURL = URL(string: "https://127.0.0.1/api")!
            #expect(AirgapURLProtocol.canInit(with: URLRequest(url: loopbackURL)) == false)

            #expect(capture.isEmpty)
        }
    }
}
