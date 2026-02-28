import Foundation
@testable import Airgap

/// Drains the main queue so that async-dispatched violation handlers are processed.
/// `reportViolation` dispatches the handler to `DispatchQueue.main.async` in `.fail` mode
/// when called from a background thread (e.g., `com.apple.CFNetwork.CustomProtocols`).
func drainMainQueue() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async { continuation.resume() }
    }
}

/// Resets all mutable Airgap state to defaults with the given capture as violation handler.
func resetAirgapState(capture: ViolationCapture) {
    Airgap.deactivate()
    capture.reset()
    let cap = capture
    Airgap.violationHandler = { cap.record($0) }
    Airgap.violationReporter = nil
    Airgap.inXCTestContext = false
    Airgap.errorCode = NSURLErrorNotConnectedToInternet
    Airgap.responseDelay = 0
    Airgap.mode = .fail
    Airgap.reportPath = nil
    Airgap.allowedHosts = []
    Airgap.passthroughProtocols = []
    Airgap.clearViolations()
}

/// Resets all mutable Airgap state to defaults with a no-op violation handler.
func resetAirgapState() {
    Airgap.deactivate()
    Airgap.violationHandler = { _ in }
    Airgap.violationReporter = nil
    Airgap.inXCTestContext = false
    Airgap.errorCode = NSURLErrorNotConnectedToInternet
    Airgap.responseDelay = 0
    Airgap.mode = .fail
    Airgap.reportPath = nil
    Airgap.allowedHosts = []
    Airgap.passthroughProtocols = []
    Airgap.clearViolations()
}

/// Thread-safe violation reporter capture for use in tests with @Sendable closures.
final class ViolationReporterCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _violations: [Violation] = []

    var violations: [Violation] {
        lock.withLock { _violations }
    }

    func record(_ violation: Violation) {
        lock.withLock { _violations.append(violation) }
    }
}

/// A minimal URLProtocol subclass for the mock:// scheme, used to verify coexistence with Airgap.
final class MockSchemeProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "mock"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: NSError(domain: "MockScheme", code: 0))
    }

    override func stopLoading() {}
}

/// A concrete subclass of AirgapTestCase for testing the lifecycle methods.
final class LifecycleTestCase: AirgapTestCase {

    func invokeSetUp() {
        setUp()
    }

    func invokeTearDown() {
        tearDown()
    }
}

/// Thread-safe violation capture for use in unit tests.
final class ViolationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []

    var messages: [String] {
        lock.withLock { _messages }
    }

    var count: Int {
        lock.withLock { _messages.count }
    }

    var isEmpty: Bool {
        lock.withLock { _messages.isEmpty }
    }

    func record(_ message: String) {
        lock.withLock { _messages.append(message) }
    }

    func reset() {
        lock.withLock { _messages = [] }
    }
}

/// A URLProtocol subclass that claims to handle HTTPS requests to a specific host.
/// Used in passthrough protocol tests to verify Airgap yields to mock protocols.
final class MockHTTPProtocol: URLProtocol {
    /// The host this protocol claims to handle.
    static let mockedHost = "mocked.example.com"

    override static func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return false
        }
        return request.url?.host == mockedHost
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: NSError(domain: "MockHTTP", code: 0))
    }

    override func stopLoading() {}
}

/// Thread-safe error capture for use in unit tests.
final class ErrorCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: (any Error)?

    var value: (any Error)? {
        lock.withLock { _value }
    }

    func set(_ error: (any Error)?) {
        lock.withLock { _value = error }
    }
}
