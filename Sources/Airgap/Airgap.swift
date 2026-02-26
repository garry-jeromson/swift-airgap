import Foundation
#if canImport(XCTest)
import XCTest
#endif

/// Detects and fails any test that attempts a real HTTP/HTTPS network request.
///
/// Supports activation at the test-target, suite, or individual-test level.
/// Tests that legitimately need network access can opt out via `allowNetworkAccess()`.
public enum Airgap {

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

    private static let lock = NSLock()

    nonisolated(unsafe) private static var _mode: Mode = .fail
    /// The current violation reporting mode. Defaults to `.fail`.
    public static var mode: Mode {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }

    nonisolated(unsafe) private static var _reportPath: String?
    /// When set, violations are collected and written to this file path.
    public static var reportPath: String? {
        get { lock.withLock { _reportPath } }
        set { lock.withLock { _reportPath = newValue } }
    }

    /// Violations collected since the last `clearViolations()` call.
    ///
    /// Violations accumulate across tests until explicitly cleared. When using `AirgapObserver`,
    /// this accumulates for the entire bundle lifetime. When using `AirgapTestCase`, violations
    /// are cleared automatically in `setUp`. Call `clearViolations()` if you need to reset manually.
    ///
    /// Thread-safe: reads and writes are protected by an internal lock.
    nonisolated(unsafe) private static var _violations: [Violation] = []
    public static var violations: [Violation] {
        lock.withLock { _violations }
    }

    /// Hosts that are allowed through even when the guard is active.
    /// Useful for tests that hit localhost or mock servers.
    nonisolated(unsafe) private static var _allowedHosts: Set<String> = []
    public static var allowedHosts: Set<String> {
        get { lock.withLock { _allowedHosts } }
        set { lock.withLock { _allowedHosts = newValue } }
    }

    /// Called when a network violation is detected. Defaults to `XCTFail()`.
    /// Set to `{ Issue.record($0) }` for Swift Testing, or any custom handler.
    ///
    /// Thread-safe: reads and writes are protected by an internal lock.
    nonisolated(unsafe) private static var _violationHandler: @Sendable (String) -> Void = { message in
        #if canImport(XCTest)
        XCTFail(message)
        #else
        assertionFailure(message)
        #endif
    }
    public static var violationHandler: @Sendable (String) -> Void {
        get { lock.withLock { _violationHandler } }
        set { lock.withLock { _violationHandler = newValue } }
    }

    /// Whether the network guard is currently active.
    public static var isActive: Bool {
        AirgapURLProtocol.isActive
    }

    /// Called when a network violation is detected with the full `Violation` struct.
    /// Use for structured analytics, CI integration, or custom reporting. Called in addition
    /// to `violationHandler`; `nil` by default.
    nonisolated(unsafe) private static var _violationReporter: (@Sendable (Violation) -> Void)?
    public static var violationReporter: (@Sendable (Violation) -> Void)? {
        get { lock.withLock { _violationReporter } }
        set { lock.withLock { _violationReporter = newValue } }
    }

    /// Whether we're running in an XCTest context (vs Swift Testing or standalone).
    ///
    /// Set automatically by `AirgapObserver` and `AirgapTestCase`. When `true`, warn mode
    /// uses `XCTExpectFailure` to show violations in Xcode's issue navigator without failing.
    /// When `false` (e.g., Swift Testing), warn mode calls the violation handler directly.
    nonisolated(unsafe) private static var _inXCTestContext = false
    public static var inXCTestContext: Bool {
        get { lock.withLock { _inXCTestContext } }
        set { lock.withLock { _inXCTestContext = newValue } }
    }

    /// Whether swizzling has been applied (only needs to happen once).
    nonisolated(unsafe) private static var hasSwizzled = false

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

    /// Returns a summary string of collected violations, or `nil` if there are none.
    public static func violationSummary() -> String? {
        let currentViolations = lock.withLock { _violations }
        guard !currentViolations.isEmpty else { return nil }

        let testNames = Set(currentViolations.map(\.testName))
        return "Airgap: \(currentViolations.count) violation(s) detected across \(testNames.count) test(s)"
    }

    /// Reads environment variables to configure mode, report path, and allowed hosts.
    ///
    /// - `AIRGAP_MODE=warn` sets `mode = .warn`
    /// - `AIRGAP_REPORT_PATH=/path` sets `reportPath`
    /// - `AIRGAP_ALLOWED_HOSTS=localhost,127.0.0.1` sets `allowedHosts`
    ///
    /// Safe to call multiple times — each call resets configuration from the environment.
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
    }

    /// Reports a network violation through the configured handler.
    static func reportViolation(method: String, url: String, callStack: [String], testName: String, request: URLRequest? = nil) {
        var message = """
        Airgap: Blocked \(method) request to \(url). \
        Tests must not make real network calls. \
        Use a mock or stub instead.
        """

        // Include Content-Type if present (helps identify the type of request)
        if let contentType = request?.value(forHTTPHeaderField: "Content-Type") {
            message += "\nContent-Type: \(contentType)"
        }

        // Always collect violations for programmatic access via violations/violationSummary()
        let violation = Violation(
            testName: testName,
            httpMethod: method,
            url: url,
            callStack: callStack
        )
        lock.withLock {
            _violations.append(violation)
        }

        // Notify the structured reporter if one is configured.
        if let reporter = violationReporter {
            reporter(violation)
        }

        // XCTest APIs (XCTFail, XCTExpectFailure) must be called on the main thread.
        // startLoading() runs on com.apple.CFNetwork.CustomProtocols, so we dispatch when needed.
        let handler = violationHandler

        switch mode {
        case .fail:
            if Thread.isMainThread {
                handler(message)
            } else {
                DispatchQueue.main.async { handler(message) }
            }
        case .warn:
            // In warn mode, report the violation without failing the test.
            // XCTExpectFailure is only safe in an XCTest context — calling it from Swift Testing
            // crashes because there is no active XCTestCase.
            #if canImport(XCTest)
            if inXCTestContext {
                let work = {
                    XCTExpectFailure("Airgap violation (warning mode)", strict: false) {
                        handler(message)
                    }
                }
                if Thread.isMainThread {
                    work()
                } else {
                    DispatchQueue.main.async { work() }
                }
            } else {
                handler(message)
            }
            #else
            handler(message)
            #endif
        }
    }

    /// Writes collected violations to the configured `reportPath`.
    ///
    /// The output format is determined by the file extension:
    /// - `.json` — writes a JSON array of violation objects using `JSONEncoder`
    /// - Any other extension — writes a human-readable plain text report
    public static func writeReport() {
        guard let path = reportPath else { return }

        let currentViolations = lock.withLock { _violations }
        guard !currentViolations.isEmpty else { return }

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
        } catch {
            fputs("Airgap: Failed to write report to \(path): \(error)\n", stderr)
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

    // MARK: - Configuration swizzling

    /// Swizzles `URLSessionConfiguration.default` and `.ephemeral` property getters
    /// to inject `AirgapURLProtocol` into any newly-created session configuration.
    private static func swizzleSessionConfigurations() {
        swizzleConfigurationProperty(
            getter: #selector(getter: URLSessionConfiguration.`default`),
            label: "default"
        )
        swizzleConfigurationProperty(
            getter: #selector(getter: URLSessionConfiguration.ephemeral),
            label: "ephemeral"
        )
    }

    private static func swizzleConfigurationProperty(getter original: Selector, label: String) {
        guard let method = class_getClassMethod(URLSessionConfiguration.self, original) else {
            return
        }

        let originalIMP = method_getImplementation(method)

        typealias OriginalFunction = @convention(c) (AnyObject, Selector) -> URLSessionConfiguration

        let originalFunction = unsafeBitCast(originalIMP, to: OriginalFunction.self)

        let swizzledBlock: @convention(block) (AnyObject) -> URLSessionConfiguration = { obj in
            let config = originalFunction(obj, original)
            var protocols = config.protocolClasses ?? []
            if !protocols.contains(where: { $0 == AirgapURLProtocol.self }) {
                protocols.insert(AirgapURLProtocol.self, at: 0)
            }
            config.protocolClasses = protocols
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
            AnyObject, URLSessionConfiguration, URLSessionDelegate?, OperationQueue?
        ) -> URLSession = { obj, config, delegate, queue in
            var protocols = config.protocolClasses ?? []
            if !protocols.contains(where: { $0 == AirgapURLProtocol.self }) {
                protocols.insert(AirgapURLProtocol.self, at: 0)
            }
            config.protocolClasses = protocols
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
            // Capture the call stack at the point where resume() is called —
            // this is the user's code, not the URL loading system internals.
            if let sessionTask = task as? URLSessionTask,
               let urlString = sessionTask.currentRequest?.url?.absoluteString ?? sessionTask.originalRequest?.url?.absoluteString {
                AirgapURLProtocol.storeCapturedCallStack(Thread.callStackSymbols, request: sessionTask.currentRequest, forURL: urlString)
            }
            originalFunction(task, selector)
        }

        let swizzledIMP = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(method, swizzledIMP)
    }
}
