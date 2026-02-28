import Combine
import Foundation
import Testing
@testable import Airgap

extension AllAirgapUnitTests {

@Suite(.serialized)
final class AirgapBlockingTests {

    private let capture = ViolationCapture()

    init() {
        resetAirgapState(capture: capture)
    }

    // MARK: - Blocking requests

    @Test("URLSession.shared data task is blocked") func uRLSessionSharedDataTaskIsBlocked() async {
        Airgap.activate()

        let url = URL(string: "https://httpbin.org/get")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test("URLSession with default config is blocked") func uRLSessionWithDefaultConfigIsBlocked() async {
        Airgap.activate()

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let url = URL(string: "https://httpbin.org/get")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test("URLSession with ephemeral config is blocked") func uRLSessionWithEphemeralConfigIsBlocked() async {
        Airgap.activate()

        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        let url = URL(string: "https://httpbin.org/get")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test("HTTP scheme is blocked") func HTTPSchemeIsBlocked() async {
        Airgap.activate()

        let url = URL(string: "http://httpbin.org/get")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    // MARK: - Non-HTTP schemes

    @Test("Local file URL is not blocked") func localFileURLIsNotBlocked() async {
        Airgap.activate()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("networkguard-test.txt")
        try? "test".write(to: tempFile, atomically: true, encoding: .utf8)

        _ = try? await URLSession.shared.data(from: tempFile)
        #expect(capture.isEmpty)

        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: - Non-GET HTTP methods

    @Test("POST method is blocked") func pOSTMethodIsBlocked() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/post")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"key":"value"}"#.utf8)

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("POST") ?? false)
    }

    @Test("PUT method is blocked") func pUTMethodIsBlocked() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/put")!)
        request.httpMethod = "PUT"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("PUT") ?? false)
    }

    @Test("DELETE method is blocked") func dELETEMethodIsBlocked() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/delete")!)
        request.httpMethod = "DELETE"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("DELETE") ?? false)
    }

    @Test("PATCH method is blocked") func pATCHMethodIsBlocked() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/patch")!)
        request.httpMethod = "PATCH"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("PATCH") ?? false)
    }

    @Test("HEAD method is blocked") func hEADMethodIsBlocked() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/head")!)
        request.httpMethod = "HEAD"

        _ = try? await URLSession.shared.data(for: request)
        await drainMainQueue()

        #expect(capture.count == 1)
        #expect(capture.messages.first?.contains("HEAD") ?? false)
    }

    // MARK: - Upload and download tasks

    @Test("Upload task is blocked") func uploadTaskIsBlocked() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        request.httpMethod = "POST"
        let data = Data("file content".utf8)

        do {
            _ = try await URLSession.shared.upload(for: request, from: data)
            Issue.record("Upload should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test("Download task is blocked") func downloadTaskIsBlocked() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/file.zip")!

        do {
            _ = try await URLSession.shared.download(from: url)
            Issue.record("Download should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    // MARK: - URL edge cases

    @Test("URL with query string is blocked") func URLWithQueryStringIsBlocked() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api?param=value&other=test")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test("URL with fragment is blocked") func URLWithFragmentIsBlocked() {
        Airgap.activate()

        let url = URL(string: "https://example.com/api#section")!
        let request = URLRequest(url: url)

        #expect(AirgapURLProtocol.canInit(with: request))
    }

    @Test("URL with port is blocked") func URLWithPortIsBlocked() async {
        Airgap.activate()

        let url = URL(string: "https://example.com:8443/api")!
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1)
    }

    @Test("URL with basic auth is blocked") func URLWithBasicAuthIsBlocked() {
        Airgap.activate()

        let url = URL(string: "https://user:password@example.com/api")!
        let request = URLRequest(url: url)

        #expect(AirgapURLProtocol.canInit(with: request))
    }

    // MARK: - data: scheme pass-through

    @Test("data URL is not intercepted") func dataURLIsNotIntercepted() {
        Airgap.activate()

        let url = URL(string: "data:text/plain;base64,SGVsbG8=")!
        let request = URLRequest(url: url)

        #expect(!AirgapURLProtocol.canInit(with: request),
                "data: URLs should not be intercepted")
    }

    // MARK: - Custom URLProtocol coexistence

    @Test("Custom URLProtocol coexists with Airgap") func customURLProtocolCoexistsWithAirgap() {
        URLProtocol.registerClass(MockSchemeProtocol.self)
        defer { URLProtocol.unregisterClass(MockSchemeProtocol.self) }

        Airgap.activate()

        let mockURL = URL(string: "mock://test/resource")!
        let mockRequest = URLRequest(url: mockURL)
        #expect(!AirgapURLProtocol.canInit(with: mockRequest),
                "Airgap should not intercept mock:// scheme")
        #expect(MockSchemeProtocol.canInit(with: mockRequest),
                "MockSchemeProtocol should handle mock:// scheme")

        let httpsURL = URL(string: "https://example.com/api/coexistence")!
        let httpsRequest = URLRequest(url: httpsURL)
        #expect(AirgapURLProtocol.canInit(with: httpsRequest),
                "Airgap should still intercept https:// requests")
    }

    // MARK: - Combine dataTaskPublisher

    @Test("Combine dataTaskPublisher is intercepted") func combineDataTaskPublisherIsIntercepted() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/combine")!

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            cancellable = URLSession.shared.dataTaskPublisher(for: url)
                .sink(receiveCompletion: { _ in
                    _ = cancellable  // prevent unused warning
                    continuation.resume()
                }, receiveValue: { _ in })
        }

        #expect(Airgap.violations.count >= 1, "Combine dataTaskPublisher should be intercepted")
    }

    // MARK: - Async upload and download

    @Test("Async upload is intercepted") func asyncUploadIsIntercepted() async {
        Airgap.activate()

        var request = URLRequest(url: URL(string: "https://example.com/api/async-upload")!)
        request.httpMethod = "POST"
        let body = Data("upload data".utf8)

        do {
            _ = try await URLSession.shared.upload(for: request, from: body)
            Issue.record("Upload should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Async upload should be intercepted")
    }

    @Test("Async download is intercepted") func asyncDownloadIsIntercepted() async {
        Airgap.activate()

        let url = URL(string: "https://example.com/api/async-download")!

        do {
            _ = try await URLSession.shared.download(from: url)
            Issue.record("Download should have thrown an error")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Async download should be intercepted")
    }

    // MARK: - KMP / Ktor Darwin Engine Pattern

    /// Simulates what Ktor's Darwin engine does: creates a URLSession from
    /// URLSessionConfiguration.default after Airgap is active. The swizzled
    /// config getter should inject AirgapURLProtocol, so the request is caught.
    @Test("Ktor Darwin engine pattern is intercepted") func ktorDarwinEnginePatternIsIntercepted() async {
        Airgap.activate()

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let url = URL(string: "https://api.example.com/kmp/endpoint")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Request should be blocked by Airgap")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Violation should be captured for Ktor-style session")
    }

    /// Verifies that the URLSession.init swizzle injects AirgapURLProtocol even when
    /// the configuration was obtained before activate() — closing the timing gap for
    /// KMP/Ktor code that eagerly creates its URLSession during module load.
    // swiftlint:disable:next line_length
    @Test("Session from pre activation config is intercepted via init swizzle") func sessionFromPreActivationConfigIsInterceptedViaInitSwizzle() async {
        // Grab config BEFORE activation — simulates Ktor initializing early.
        let preActivationConfig = URLSessionConfiguration.default

        Airgap.activate()

        let session = URLSession(configuration: preActivationConfig)
        let url = URL(string: "https://api.example.com/kmp/early-init")!

        do {
            _ = try await session.data(from: url)
            Issue.record("Request should be blocked by Airgap")
        } catch {
            // Expected
        }

        #expect(Airgap.violations.count == 1, "Init swizzle should catch requests from pre-activation configs")
    }

    /// Verifies that the URLSession.init swizzle injects AirgapURLProtocol into the
    /// config passed to the initializer, even for non-standard configs like background.
    @Test("Init swizzle injects protocol into config before session creation") func initSwizzleInjectsProtocolIntoConfigBeforeSessionCreation() {
        Airgap.activate()

        let config = URLSessionConfiguration.background(withIdentifier: "com.airgap.test.\(UUID().uuidString)")
        #expect(
            !(config.protocolClasses ?? []).contains(where: { $0 == AirgapURLProtocol.self }),
            "Background config should NOT have AirgapURLProtocol before session creation"
        )

        _ = URLSession(configuration: config, delegate: nil, delegateQueue: nil)

        #expect(
            (config.protocolClasses ?? []).contains(where: { $0 == AirgapURLProtocol.self }),
            "Init swizzle should have injected AirgapURLProtocol into the config"
        )
    }

    // MARK: - Passthrough protocols

    @Test("Passthrough protocol yields to mock for matching requests") func passthroughProtocolYieldsToMock() {
        Airgap.passthroughProtocols = [MockHTTPProtocol.self]
        Airgap.activate()

        let mockedURL = URL(string: "https://mocked.example.com/api/resource")!
        let mockedRequest = URLRequest(url: mockedURL)
        #expect(!AirgapURLProtocol.canInit(with: mockedRequest),
                "Airgap should yield to passthrough protocol for matching requests")
        #expect(MockHTTPProtocol.canInit(with: mockedRequest),
                "MockHTTPProtocol should handle the request")
    }

    @Test("Non-matching passthrough protocol still blocks") func nonMatchingPassthroughStillBlocks() {
        Airgap.passthroughProtocols = [MockHTTPProtocol.self]
        Airgap.activate()

        let unmockedURL = URL(string: "https://unmocked.example.com/api/resource")!
        let unmockedRequest = URLRequest(url: unmockedURL)
        #expect(AirgapURLProtocol.canInit(with: unmockedRequest),
                "Airgap should still block requests the passthrough protocol doesn't handle")
    }

    @Test("Empty passthrough list blocks normally") func emptyPassthroughListBlocksNormally() {
        Airgap.passthroughProtocols = []
        Airgap.activate()

        let url = URL(string: "https://example.com/api/resource")!
        let request = URLRequest(url: url)
        #expect(AirgapURLProtocol.canInit(with: request),
                "Airgap should block requests when no passthrough protocols are set")
    }

    // MARK: - Concurrent requests

    @Test("Concurrent blocked requests") func concurrentBlockedRequests() async {
        Airgap.activate()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                let url = URL(string: "https://example.com/api/concurrent/\(i)")!
                group.addTask {
                    do {
                        _ = try await URLSession.shared.data(from: url)
                        Issue.record("Expected an error")
                    } catch {
                        // Expected
                    }
                }
            }
        }

        #expect(Airgap.violations.count >= 5)
    }
}

} // extension AllAirgapUnitTests
