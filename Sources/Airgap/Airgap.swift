import Foundation
#if canImport(XCTest)
    import XCTest
#endif

/// Detects and fails any test that attempts a real HTTP/HTTPS network request.
///
/// Supports activation at the test-target, suite, or individual-test level.
/// Tests that legitimately need network access can opt out via `allowNetworkAccess()`.
public enum Airgap {
    // MARK: - Types

    /// Controls how violations are reported.
    public enum Mode: Equatable, Sendable {
        /// Default: calls the violation handler directly (XCTFail by default).
        case fail
        /// Calls the violation handler without failing the test. In XCTest, the call is wrapped
        /// in XCTExpectFailure so it appears in Xcode's issue navigator as an expected failure.
        /// In Swift Testing with the `.airgapped` trait, violations are wrapped in `withKnownIssue`
        /// so they appear as known issues in the test navigator.
        case warn
    }

    // MARK: - Thread-safe properties

    private static let lock = NSLock()

    /// Async mutex that serializes test scopes that mutate Airgap's global state.
    /// Used by AirgapTrait.provideScope to prevent concurrent scopes from
    /// stomping on each other's configuration.
    static let scopeLock = AsyncMutex()

    /// Task-local flag indicating the current task already holds `scopeLock`.
    /// Checked by `AirgapTrait.provideScope` to allow reentrant scoping when
    /// an outer trait (e.g. `ScopeLockTrait`) already holds the lock.
    @TaskLocal static var scopeLockHeld = false

    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _mode: Mode = .fail
    #else
        private static var _mode: Mode = .fail
    #endif
    /// The current violation reporting mode. Defaults to `.fail`.
    public static var mode: Mode {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }

    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _reportPath: String?
    #else
        private static var _reportPath: String?
    #endif
    /// When set, violations are collected and written to this file path.
    public static var reportPath: String? {
        get { lock.withLock { _reportPath } }
        set { lock.withLock { _reportPath = newValue } }
    }

    // Violations collected since the last `clearViolations()` call.
    //
    // Violations accumulate across tests until explicitly cleared. When using `AirgapObserver`,
    // this accumulates for the entire bundle lifetime. When using `AirgapTestCase`, violations
    // are cleared automatically in `setUp`. Call `clearViolations()` if you need to reset manually.
    //
    // Thread-safe: reads and writes are protected by an internal lock.
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _violations: [Violation] = []
    #else
        private static var _violations: [Violation] = []
    #endif
    public static var violations: [Violation] {
        lock.withLock { _violations }
    }

    // Hosts that are allowed through even when the guard is active.
    // Useful for tests that hit localhost or mock servers.
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _allowedHosts: Set<String> = []
    #else
        private static var _allowedHosts: Set<String> = []
    #endif
    public static var allowedHosts: Set<String> {
        get { lock.withLock { _allowedHosts } }
        set { lock.withLock { _allowedHosts = newValue } }
    }

    // URLProtocol classes that take priority over Airgap's interception.
    //
    // When a request arrives, Airgap checks each passthrough protocol's `canInit(with:)`.
    // If any returns `true`, Airgap yields and lets that protocol handle the request.
    // This allows mock URLProtocol implementations (e.g., Mocker's `MockingURLProtocol`)
    // to coexist with Airgap — mocked requests go through the mock, unmocked requests are blocked.
    //
    // Example:
    // ```swift
    // Airgap.passthroughProtocols = [MockingURLProtocol.self]
    // ```
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _passthroughProtocols: [URLProtocol.Type] = []
    #else
        private static var _passthroughProtocols: [URLProtocol.Type] = []
    #endif
    public static var passthroughProtocols: [URLProtocol.Type] {
        get { lock.withLock { _passthroughProtocols } }
        set { lock.withLock { _passthroughProtocols = newValue } }
    }

    // Called when a network violation is detected. Defaults to `XCTFail()`.
    //
    // When using the `.airgapped` Swift Testing trait, this handler is managed by the trait
    // (set to a no-op during the test body; violations are reported via `Issue.record()` in the
    // trait's scope teardown for correct test attribution). For custom reporting in Swift Testing,
    // use `violationReporter` instead.
    //
    // Thread-safe: reads and writes are protected by an internal lock.
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _violationHandler: @Sendable (String) -> Void = { message in
            #if canImport(XCTest)
                XCTFail(message)
            #else
                assertionFailure(message)
            #endif
        }
    #else
        private static var _violationHandler: @Sendable (String) -> Void = { message in
            #if canImport(XCTest)
                XCTFail(message)
            #else
                assertionFailure(message)
            #endif
        }
    #endif
    public static var violationHandler: @Sendable (String) -> Void {
        get { lock.withLock { _violationHandler } }
        set { lock.withLock { _violationHandler = newValue } }
    }

    /// Whether the network guard is currently active.
    public static var isActive: Bool {
        AirgapURLProtocol.isActive
    }

    // Called when a network violation is detected with the full `Violation` struct.
    // Use for structured analytics, CI integration, or custom reporting. Called in addition
    // to `violationHandler`; `nil` by default.
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _violationReporter: (@Sendable (Violation) -> Void)?
    #else
        private static var _violationReporter: (@Sendable (Violation) -> Void)?
    #endif
    public static var violationReporter: (@Sendable (Violation) -> Void)? {
        get { lock.withLock { _violationReporter } }
        set { lock.withLock { _violationReporter = newValue } }
    }

    // The URL error code delivered to intercepted requests. Defaults to `NSURLErrorNotConnectedToInternet`.
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _errorCode: Int = NSURLErrorNotConnectedToInternet
    #else
        private static var _errorCode: Int = NSURLErrorNotConnectedToInternet
    #endif
    public static var errorCode: Int {
        get { lock.withLock { _errorCode } }
        set { lock.withLock { _errorCode = newValue } }
    }

    // An optional delay (in seconds) before delivering the error to intercepted requests.
    // Defaults to `0` (no delay). Useful for testing timeout handling or loading states.
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _responseDelay: TimeInterval = 0
    #else
        private static var _responseDelay: TimeInterval = 0
    #endif
    public static var responseDelay: TimeInterval {
        get { lock.withLock { _responseDelay } }
        set { lock.withLock { _responseDelay = newValue } }
    }

    // Whether we're running in an XCTest context (vs Swift Testing or standalone).
    //
    // Set automatically by `AirgapObserver` and `AirgapTestCase`. When `true`, warn mode
    // uses `XCTExpectFailure` to show violations in Xcode's issue navigator without failing.
    // When `false` (e.g., Swift Testing), warn mode calls the violation handler directly.
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var _inXCTestContext = false
    #else
        private static var _inXCTestContext = false
    #endif
    public static var inXCTestContext: Bool {
        get { lock.withLock { _inXCTestContext } }
        set { lock.withLock { _inXCTestContext = newValue } }
    }

    // Whether swizzling has been applied (only needs to happen once).
    #if compiler(>=6.0)
        private nonisolated(unsafe) static var hasSwizzled = false
    #else
        private static var hasSwizzled = false
    #endif

    // MARK: - Public API

    /// Activates the network guard. Registers the URLProtocol and swizzles session configurations.
    ///
    /// Safe to call multiple times — activation is idempotent.
    public static func activate() {
        AirgapURLProtocol.isActive = true
        AirgapURLProtocol.isAllowed = false
        URLProtocol.registerClass(AirgapURLProtocol.self)

        lock.withLock {
            if !hasSwizzled {
                swizzleSessionConfigurations()
                swizzleSessionInit()
                swizzleTaskResume()
                hasSwizzled = true
            }
        }
    }

    /// Deactivates the network guard. Unregisters the URLProtocol and clears captured data.
    public static func deactivate() {
        AirgapURLProtocol.isActive = false
        URLProtocol.unregisterClass(AirgapURLProtocol.self)
        AirgapURLProtocol.clearCapturedData()
    }

    /// Disables the guard for the remainder of the current test.
    ///
    /// The guard is re-activated automatically on the next `activate()` call.
    public static func allowNetworkAccess() {
        AirgapURLProtocol.isAllowed = true
    }

    /// Runs `body` with network access temporarily allowed, restoring the previous state afterward.
    ///
    /// This is a scoped alternative to `allowNetworkAccess()` — network access is only allowed
    /// for the duration of the block, then the previous allow state is restored.
    @discardableResult
    public static func withNetworkAccessAllowed<T>(_ body: () throws -> T) rethrows -> T {
        let saved = AirgapURLProtocol.isAllowed
        AirgapURLProtocol.isAllowed = true
        defer { AirgapURLProtocol.isAllowed = saved }
        return try body()
    }

    /// Async overload of `withNetworkAccessAllowed(_:)`.
    @discardableResult
    public static func withNetworkAccessAllowed<T>(_ body: () async throws -> T) async rethrows -> T {
        let saved = AirgapURLProtocol.isAllowed
        AirgapURLProtocol.isAllowed = true
        defer { AirgapURLProtocol.isAllowed = saved }
        return try await body()
    }

    /// Returns `true` if the given host matches any entry in `allowedHosts`.
    ///
    /// Supports exact matches and wildcard patterns:
    /// - `"localhost"` — matches `localhost` exactly
    /// - `"*.example.com"` — matches `api.example.com`, `deep.sub.example.com`, and `example.com` itself
    ///
    /// Matching is case-insensitive per RFC 3986.
    static func isHostAllowed(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        return lock.withLock {
            _allowedHosts.contains { pattern in
                let p = pattern.lowercased()
                if p == lowercased { return true }
                if p.hasPrefix("*.") {
                    let domain = String(p.dropFirst(2))
                    return lowercased.hasSuffix("." + domain) || lowercased == domain
                }
                return false
            }
        }
    }

    /// Resets the collected violations list.
    public static func clearViolations() {
        lock.withLock {
            _violations = []
        }
    }

    /// Runs `body` with temporary configuration overrides, restoring all state afterward.
    ///
    /// Only the parameters you pass are changed; `nil` means "keep the current value."
    /// All mutable Airgap state (mode, allowedHosts, violationHandler, violationReporter,
    /// errorCode, responseDelay) is saved before and restored after, even if `body` throws.
    ///
    /// - Note: The body is synchronous. For async test scopes, use the `.airgapped` trait instead.
    @discardableResult
    public static func withConfiguration<T>(
        mode: Mode? = nil,
        allowedHosts: Set<String>? = nil,
        violationHandler: (@Sendable (String) -> Void)? = nil,
        violationReporter: (@Sendable (Violation) -> Void)? = .none,
        errorCode: Int? = nil,
        responseDelay: TimeInterval? = nil,
        body: () throws -> T) rethrows -> T {
        let savedMode = self.mode
        let savedAllowedHosts = self.allowedHosts
        let savedHandler = self.violationHandler
        let savedReporter = self.violationReporter
        let savedErrorCode = self.errorCode
        let savedResponseDelay = self.responseDelay

        if let mode { self.mode = mode }
        if let allowedHosts { self.allowedHosts = allowedHosts }
        if let violationHandler { self.violationHandler = violationHandler }
        if let violationReporter { self.violationReporter = violationReporter }
        if let errorCode { self.errorCode = errorCode }
        if let responseDelay { self.responseDelay = responseDelay }

        defer {
            self.mode = savedMode
            self.allowedHosts = savedAllowedHosts
            self.violationHandler = savedHandler
            self.violationReporter = savedReporter
            self.errorCode = savedErrorCode
            self.responseDelay = savedResponseDelay
        }

        return try body()
    }

    /// Returns a summary string of collected violations, or `nil` if there are none.
    public static func violationSummary() -> String? {
        let currentViolations = lock.withLock { _violations }
        guard !currentViolations.isEmpty else { return nil }

        let testNames = Set(currentViolations.map(\.testName))
        return "Airgap: \(currentViolations.count) violation(s) detected across \(testNames.count) test(s)"
    }

    /// Reads environment variables to configure mode, report path, allowed hosts, and error code.
    ///
    /// - `AIRGAP_MODE=warn` sets `mode = .warn` (absent → `.fail`)
    /// - `AIRGAP_REPORT_PATH=/path` sets `reportPath` (absent → `nil`)
    /// - `AIRGAP_ALLOWED_HOSTS=localhost,127.0.0.1` sets `allowedHosts` (absent → `[]`)
    /// - `AIRGAP_ERROR_CODE=<int>` sets `errorCode` (absent → `NSURLErrorNotConnectedToInternet`)
    ///
    /// **Not reset by this method:** `responseDelay`, `violationHandler`, and `violationReporter`
    /// retain their current values. Only the four properties above are driven by environment variables.
    ///
    /// Safe to call multiple times — each call resets the above properties from the environment.
    public static func configureFromEnvironment() {
        if let modeValue = ProcessInfo.processInfo.environment["AIRGAP_MODE"],
           modeValue.lowercased() == "warn" {
            mode = .warn
        } else {
            mode = .fail
        }
        if let path = ProcessInfo.processInfo.environment["AIRGAP_REPORT_PATH"],
           !path.isEmpty {
            reportPath = path
        } else {
            reportPath = nil
        }
        if let hostsValue = ProcessInfo.processInfo.environment["AIRGAP_ALLOWED_HOSTS"],
           !hostsValue.isEmpty {
            let hosts = hostsValue.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            allowedHosts = Set(hosts)
        } else {
            allowedHosts = []
        }
        if let codeValue = ProcessInfo.processInfo.environment["AIRGAP_ERROR_CODE"],
           let code = Int(codeValue) {
            errorCode = code
        } else {
            errorCode = NSURLErrorNotConnectedToInternet
        }
    }

    // MARK: - Violation reporting

    /// Builds the human-readable violation message from a `Violation` struct.
    public static func violationMessage(for violation: Violation) -> String {
        var message = """
        Airgap: Blocked \(violation.httpMethod) request to \(violation.url). \
        Tests must not make real network calls. \
        Use a mock or stub instead.
        """

        if let contentType = violation.contentType {
            message += "\nContent-Type: \(contentType)"
        }

        // swiftlint:disable:next line_length
        message += "\nHint: Use Airgap.allowNetworkAccess() for this test, add the host to Airgap.allowedHosts, or use .warn mode for non-blocking violations."

        return message
    }

    /// Reports a network violation through the configured handler.
    static func reportViolation(method: String, url: String, callStack: [String], testName: String, request: URLRequest? = nil) {
        // Always collect violations for programmatic access via violations/violationSummary()
        let violation = Violation(
            testName: testName,
            httpMethod: method,
            url: url,
            callStack: callStack,
            contentType: request?.value(forHTTPHeaderField: "Content-Type"))
        lock.withLock {
            _violations.append(violation)
        }

        let message = violationMessage(for: violation)

        // Notify the structured reporter if one is configured.
        if let reporter = violationReporter {
            reporter(violation)
        }

        // XCTest APIs (XCTFail, XCTExpectFailure) must be called on the main thread.
        // startLoading() runs on com.apple.CFNetwork.CustomProtocols, so we dispatch when needed.
        let handler = violationHandler

        switch mode {
        case .fail:
            onMainThread { handler(message) }
        case .warn:
            // In warn mode, report the violation without failing the test.
            // XCTExpectFailure is only safe in an XCTest context — calling it from Swift Testing
            // crashes because there is no active XCTestCase.
            #if canImport(XCTest)
                if inXCTestContext {
                    onMainThread {
                        XCTExpectFailure("Airgap violation (warning mode)", strict: false) {
                            handler(message)
                        }
                    }
                } else {
                    handler(message)
                }
            #else
                handler(message)
            #endif
        }
    }

    // MARK: - Report generation

    /// Writes collected violations to the configured `reportPath`.
    ///
    /// The output format is determined by the file extension:
    /// - `.json` — writes a JSON array of violation objects using `JSONEncoder`
    /// - Any other extension — writes a human-readable plain text report
    @discardableResult
    public static func writeReport() -> Bool {
        guard let path = reportPath else { return true }

        let currentViolations = lock.withLock { _violations }
        guard !currentViolations.isEmpty else { return true }

        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

            if (path as NSString).pathExtension.lowercased() == "json" {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(currentViolations)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            } else {
                let report = buildTextReport(currentViolations)
                try report.write(toFile: path, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            fputs("Airgap: Failed to write report to \(path): \(error)\n", stderr)
            return false
        }
    }

    private static func buildTextReport(_ violations: [Violation]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var report = """
        Airgap Violation Report
        Generated: \(dateFormatter.string(from: Date()))
        Total violations: \(violations.count)
        """

        for violation in violations {
            report += "\n\n---\n"
            report += "Test: \(violation.testName)\n"
            report += "Method: \(violation.httpMethod)\n"
            report += "URL: \(violation.url)\n"
            report += "Call Stack:\n"
            for symbol in violation.callStack.prefix(10) {
                report += "  \(symbol)\n"
            }
        }

        return report
    }

    // MARK: - Private helpers

    private static func onMainThread(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync { work() }
        }
    }

    private static func injectProtocol(into config: URLSessionConfiguration) {
        var protocols = config.protocolClasses ?? []
        if !protocols.contains(where: { $0 == AirgapURLProtocol.self }) {
            protocols.insert(AirgapURLProtocol.self, at: 0)
        }
        config.protocolClasses = protocols
    }

    private static func interceptWebSocketIfNeeded(
        _ task: URLSessionTask,
        url: URL?,
        urlString: String) -> Bool {
        let scheme = url?.scheme?.lowercased()
        let isWebSocket = task is URLSessionWebSocketTask
            || scheme == "ws" || scheme == "wss"

        guard isWebSocket, AirgapURLProtocol.isActive, !AirgapURLProtocol.isAllowed else {
            return false
        }

        if let host = url?.host, isHostAllowed(host) {
            return false
        }

        let method = task.currentRequest?.httpMethod ?? "GET"
        reportViolation(
            method: method, url: urlString,
            callStack: Thread.callStackSymbols,
            testName: AirgapURLProtocol.currentTestName,
            request: task.currentRequest)
        task.cancel()
        return true
    }

    // MARK: - Swizzling

    /// Swizzles `URLSessionConfiguration.default` and `.ephemeral` property getters
    /// to inject `AirgapURLProtocol` into any newly-created session configuration.
    private static func swizzleSessionConfigurations() {
        swizzleConfigurationProperty(
            getter: #selector(getter: URLSessionConfiguration.default),
            label: "default")
        swizzleConfigurationProperty(
            getter: #selector(getter: URLSessionConfiguration.ephemeral),
            label: "ephemeral")
    }

    private static func swizzleConfigurationProperty(getter original: Selector, label _: String) {
        guard let method = class_getClassMethod(URLSessionConfiguration.self, original) else {
            return
        }

        let originalIMP = method_getImplementation(method)

        typealias OriginalFunction = @convention(c) (AnyObject, Selector) -> URLSessionConfiguration

        let originalFunction = unsafeBitCast(originalIMP, to: OriginalFunction.self)

        let swizzledBlock: @convention(block) (AnyObject) -> URLSessionConfiguration = { obj in
            let config = originalFunction(obj, original)
            injectProtocol(into: config)
            return config
        }

        let swizzledIMP = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(method, swizzledIMP)
    }

    /// Swizzles `URLSession.sessionWithConfiguration:delegate:delegateQueue:` (the class
    /// method that backs Swift's `URLSession(configuration:delegate:delegateQueue:)`) to inject
    /// `AirgapURLProtocol` into the configuration at session creation time.
    ///
    /// This closes the gap where a configuration is obtained before `activate()` is called
    /// (e.g., KMP/Ktor eagerly initializing during module load). Even if the config missed
    /// the property-getter swizzle, the protocol is injected when the session is created.
    private static func swizzleSessionInit() {
        let selector = NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")
        guard let method = class_getClassMethod(URLSession.self, selector) else {
            return
        }

        let originalIMP = method_getImplementation(method)
        typealias OriginalFunction = @convention(c) (AnyObject, Selector, URLSessionConfiguration, URLSessionDelegate?, OperationQueue?) -> URLSession
        let originalFunction = unsafeBitCast(originalIMP, to: OriginalFunction.self)

        let swizzledBlock: @convention(block) (
            AnyObject, URLSessionConfiguration, URLSessionDelegate?, OperationQueue?) -> URLSession = { obj, config, delegate, queue in
            injectProtocol(into: config)
            return originalFunction(obj, selector, config, delegate, queue)
        }

        let swizzledIMP = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(method, swizzledIMP)
    }

    /// Swizzles `URLSessionTask.resume()` to capture the call stack at the actual call site.
    ///
    /// Without this, the call stack captured in `AirgapURLProtocol.canInit(with:)` only contains
    /// URL loading system internals, not the user's code that initiated the request.
    private static func swizzleTaskResume() {
        let selector = #selector(URLSessionTask.resume)
        guard let method = class_getInstanceMethod(URLSessionTask.self, selector) else {
            return
        }

        let originalIMP = method_getImplementation(method)
        typealias OriginalFunction = @convention(c) (AnyObject, Selector) -> Void
        let originalFunction = unsafeBitCast(originalIMP, to: OriginalFunction.self)

        let swizzledBlock: @convention(block) (AnyObject) -> Void = { task in
            guard let sessionTask = task as? URLSessionTask else {
                originalFunction(task, selector)
                return
            }

            let url = sessionTask.currentRequest?.url ?? sessionTask.originalRequest?.url
            let urlString = url?.absoluteString ?? "<unknown URL>"

            // Capture the call stack at the point where resume() is called —
            // this is the user's code, not the URL loading system internals.
            AirgapURLProtocol.storeCapturedCallStack(Thread.callStackSymbols, request: sessionTask.currentRequest, forURL: urlString)

            // WebSocket tasks (URLSessionWebSocketTask) and ws:///wss:// schemes are not
            // intercepted by URLProtocol. Detect them here, report the violation, and cancel.
            if interceptWebSocketIfNeeded(sessionTask, url: url, urlString: urlString) {
                return
            }

            originalFunction(task, selector)
        }

        let swizzledIMP = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(method, swizzledIMP)
    }
}
