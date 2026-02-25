import Foundation

/// A URLProtocol subclass that intercepts HTTP/HTTPS requests when the network guard is active.
///
/// This protocol is registered via `URLProtocol.registerClass()` to catch `URLSession.shared` usage,
/// and injected into `URLSessionConfiguration.default` and `.ephemeral` via swizzling to catch
/// custom session configurations.
public final class AirgapURLProtocol: URLProtocol {

    // MARK: - Thread-safe state

    private static let lock = NSLock()

    private static var _isActive = false
    public internal(set) static var isActive: Bool {
        get { lock.withLock { _isActive } }
        set { lock.withLock { _isActive = newValue } }
    }

    private static var _isAllowed = false
    public internal(set) static var isAllowed: Bool {
        get { lock.withLock { _isAllowed } }
        set { lock.withLock { _isAllowed = newValue } }
    }

    private static var _currentTestName = ""
    /// The name of the currently running test, set by the observer or test case.
    public internal(set) static var currentTestName: String {
        get { lock.withLock { _currentTestName } }
        set { lock.withLock { _currentTestName = newValue } }
    }

    /// Captured call stacks keyed by request URL string, for associating stack traces with violations.
    private static var _capturedCallStacks: [String: [String]] = [:]
    private static var capturedCallStacks: [String: [String]] {
        get { lock.withLock { _capturedCallStacks } }
        set { lock.withLock { _capturedCallStacks = newValue } }
    }

    /// Key used to mark requests as already handled, preventing infinite interception loops.
    private static let handledKey = "AirgapHandled"

    // MARK: - URLProtocol overrides

    override public class func canInit(with request: URLRequest) -> Bool {
        guard isActive, !isAllowed else { return false }

        // Only intercept http and https schemes
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        // Prevent re-interception of already-handled requests
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }

        // Capture the call stack at interception time (more likely to contain the originating call)
        let callStack = Thread.callStackSymbols
        if let urlString = request.url?.absoluteString {
            lock.withLock {
                _capturedCallStacks[urlString] = callStack
            }
        }

        return true
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override public func startLoading() {
        let url = request.url?.absoluteString ?? "<unknown URL>"
        let method = request.httpMethod ?? "GET"
        let testName = Self.currentTestName

        // Retrieve the call stack captured in canInit
        let callStack: [String]
        if let stored = Self.lock.withLock({ Self._capturedCallStacks.removeValue(forKey: url) }) {
            callStack = stored
        } else {
            callStack = Thread.callStackSymbols
        }

        Airgap.reportViolation(method: method, url: url, callStack: callStack, testName: testName)

        // Deliver an error so the code under test receives a failure rather than hanging.
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [
                NSLocalizedDescriptionKey: "Airgap: Network access is not allowed during tests.",
            ]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override public func stopLoading() {
        // Nothing to clean up
    }
}
