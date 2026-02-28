import Foundation

/// A URLProtocol subclass that intercepts HTTP/HTTPS requests when the network guard is active.
///
/// This protocol is registered via `URLProtocol.registerClass()` to catch `URLSession.shared` usage,
/// and injected into `URLSessionConfiguration.default` and `.ephemeral` via swizzling to catch
/// custom session configurations.
public final class AirgapURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Thread-safe state

    private static let lock = NSLock()

    #if compiler(>=6.0)
    nonisolated(unsafe) private static var _isActive = false
    #else
    private static var _isActive = false
    #endif
    /// Whether the protocol is currently intercepting HTTP/HTTPS requests.
    /// Set by `Airgap.activate()` and `Airgap.deactivate()`.
    public internal(set) static var isActive: Bool {
        get { lock.withLock { _isActive } }
        set { lock.withLock { _isActive = newValue } }
    }

    #if compiler(>=6.0)
    nonisolated(unsafe) private static var _isAllowed = false
    #else
    private static var _isAllowed = false
    #endif
    /// When `true`, requests pass through without interception. Set by `Airgap.allowNetworkAccess()`
    /// and reset to `false` on each `Airgap.activate()` call or by `AirgapObserver.testCaseWillStart`.
    public internal(set) static var isAllowed: Bool {
        get { lock.withLock { _isAllowed } }
        set { lock.withLock { _isAllowed = newValue } }
    }

    #if compiler(>=6.0)
    nonisolated(unsafe) private static var _currentTestName = ""
    #else
    private static var _currentTestName = ""
    #endif
    /// The name of the currently running test, set by the observer or test case.
    public internal(set) static var currentTestName: String {
        get { lock.withLock { _currentTestName } }
        set { lock.withLock { _currentTestName = newValue } }
    }

    /// Captured call stacks keyed by request URL string, for associating stack traces with violations.
    #if compiler(>=6.0)
    nonisolated(unsafe) private static var _capturedCallStacks: [String: [String]] = [:]
    #else
    private static var _capturedCallStacks: [String: [String]] = [:]
    #endif

    /// Captured request metadata keyed by URL string, for including body/header info in violations.
    #if compiler(>=6.0)
    nonisolated(unsafe) private static var _capturedRequests: [String: URLRequest] = [:]
    #else
    private static var _capturedRequests: [String: URLRequest] = [:]
    #endif

    // MARK: - URLProtocol overrides

    override public static func canInit(with request: URLRequest) -> Bool {
        guard isActive, !isAllowed else { return false }

        // Only intercept http and https schemes
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        // Allow requests to hosts in the allowlist
        if let host = request.url?.host, Airgap.isHostAllowed(host) {
            return false
        }

        // Yield to passthrough protocols (e.g., mock URLProtocols like Mocker's MockingURLProtocol).
        // If any passthrough protocol can handle this request, let it through instead of blocking.
        for proto in Airgap.passthroughProtocols where proto.canInit(with: request) {
            return false
        }

        // Capture the call stack and request if not already captured by the resume() swizzle.
        // The resume() swizzle provides better call stacks (user's code) vs canInit (URLProtocol internals).
        if let urlString = request.url?.absoluteString {
            lock.withLock {
                if _capturedCallStacks[urlString] == nil {
                    _capturedCallStacks[urlString] = Thread.callStackSymbols
                }
                if _capturedRequests[urlString] == nil {
                    _capturedRequests[urlString] = request
                }
            }
        }

        return true
    }

    override public static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override public func startLoading() {
        let url = request.url?.absoluteString ?? "<unknown URL>"
        let method = request.httpMethod ?? "GET"
        let testName = Self.currentTestName

        // Retrieve the call stack and original request captured in canInit
        let (storedStack, capturedRequest) = Self.lock.withLock {
            (Self._capturedCallStacks.removeValue(forKey: url),
             Self._capturedRequests.removeValue(forKey: url))
        }
        let callStack = storedStack ?? Thread.callStackSymbols

        Airgap.reportViolation(method: method, url: url, callStack: callStack, testName: testName, request: capturedRequest ?? request)

        // Deliver an error so the code under test receives a failure rather than hanging.
        let code = Airgap.errorCode
        let delay = Airgap.responseDelay

        let deliverError: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            let error = NSError(
                domain: NSURLErrorDomain,
                code: code,
                userInfo: [
                    NSLocalizedDescriptionKey: "Airgap: Network access is not allowed during tests."
                ]
            )
            self.client?.urlProtocol(self, didFailWithError: error)
        }

        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliverError)
        } else {
            deliverError()
        }
    }

    override public func stopLoading() {
        // Nothing to clean up
    }

    /// Stores a call stack and request captured at the `resume()` call site.
    ///
    /// Called by the swizzled `URLSessionTask.resume()` to provide accurate caller attribution.
    /// These take priority over stacks captured in `canInit(with:)`.
    static func storeCapturedCallStack(_ callStack: [String], request: URLRequest?, forURL urlString: String) {
        lock.withLock {
            _capturedCallStacks[urlString] = callStack
            if let request {
                _capturedRequests[urlString] = request
            }
        }
    }

    /// Clears any stale captured data (call stacks, requests). Called on deactivation.
    static func clearCapturedData() {
        lock.withLock {
            _capturedCallStacks.removeAll()
            _capturedRequests.removeAll()
        }
    }
}
