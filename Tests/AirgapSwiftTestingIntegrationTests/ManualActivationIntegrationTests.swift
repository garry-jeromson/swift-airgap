import Testing
@testable import Airgap
import Foundation

extension AllAirgapSwiftTestingTests {

    @Suite struct ManualActivationTests {

        @Test func `Shared session request is blocked`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let semaphore = DispatchSemaphore(value: 0)
            let errorCapture = ErrorCapture()

            URLSession.shared.dataTask(with: url) { _, _, error in
                errorCapture.set(error)
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
            #expect(errorCapture.value != nil, "Blocked request should deliver an error")
        }

        @Test func `Custom session with default config is blocked`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let session = URLSession(configuration: .default)
            let semaphore = DispatchSemaphore(value: 0)

            session.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
        }

        @Test func `Custom session with ephemeral config is blocked`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let session = URLSession(configuration: .ephemeral)
            let semaphore = DispatchSemaphore(value: 0)

            session.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
        }

        @Test func `Violation message contains URL and guidance`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api/test")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.count == 1)
            let message = capture.messages[0]
            #expect(message.contains("https://example.com/api/test"))
            #expect(message.contains("mock") || message.contains("stub"))
        }

        @Test func `File URL is not blocked`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            defer { Airgap.deactivate() }

            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("networkguard-swift-testing-test.txt")
            try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

            let semaphore = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: tempFile) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(capture.isEmpty, "file:// URLs should not trigger the guard")

            try? FileManager.default.removeItem(at: tempFile)
        }

        @Test func `allowNetworkAccess prevents blocking`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            Airgap.allowNetworkAccess()
            defer { Airgap.deactivate() }

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test func `Deactivated guard does not block`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.activate()
            Airgap.deactivate()

            let url = URL(string: "https://example.com/api")!
            let request = URLRequest(url: url)

            #expect(AirgapURLProtocol.canInit(with: request) == false)
            #expect(capture.isEmpty)
        }

        @Test func `Issue record handler pattern compiles`() {
            Airgap.violationHandler = { Issue.record("\($0)") }
            Airgap.activate()
            defer { Airgap.deactivate() }

            withKnownIssue("Direct handler call should record an issue") {
                Airgap.violationHandler("test violation from handler")
            }
        }
    }
}
