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
        /// In Swift Testing with the `.airgapped` trait, violations are collected silently.
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
    nonisolated(unsafe) public private(set) static var violations: [Violation] = []

    /// Hosts that are allowed through even when the guard is active.
    /// Useful for tests that hit localhost or mock servers.
    nonisolated(unsafe) private static var _allowedHosts: Set<String> = []
    public static var allowedHosts: Set<String> {
        get { lock.withLock { _allowedHosts } }
        set { lock.withLock { _allowedHosts = newValue } }
    }

    /// Called when a network violation is detected. Defaults to `XCTFail()`.
    /// Set to `{ Issue.record($0) }` for Swift Testing, or any custom handler.
    nonisolated(unsafe) public static var violationHandler: @Sendable (String) -> Void = { message in
        #if canImport(XCTest)
        XCTFail(message)
        #else
        assertionFailure(message)
        #endif
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
            violations = []
        }
    }

    /// Returns a summary string of collected violations, or `nil` if there are none.
    public static func violationSummary() -> String? {
        let currentViolations = lock.withLock { violations }
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
            violations.append(violation)
        }

        switch mode {
        case .fail:
            violationHandler(message)
        case .warn:
            // In warn mode, call the configured handler inside XCTExpectFailure so that:
            // - Default handler (XCTFail): caught by XCTExpectFailure → appears in issue navigator, doesn't fail
            // - Custom handler (e.g., Issue.record for Swift Testing): runs normally, strict:false means
            //   XCTExpectFailure tolerates no XCTFail being raised
            #if canImport(XCTest)
            let handler = violationHandler
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
            #else
            violationHandler(message)
            #endif
        }
    }

    /// Writes collected violations to the configured `reportPath`.
    public static func writeReport() {
        guard let path = reportPath else { return }

        let currentViolations = lock.withLock { violations }
        guard !currentViolations.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var report = """
        Airgap Violation Report
        Generated: \(dateFormatter.string(from: Date()))
        Total violations: \(currentViolations.count)
        """

        for violation in currentViolations {
            report += "\n\n---\n"
            report += "Test: \(violation.testName)\n"
            report += "Method: \(violation.httpMethod)\n"
            report += "URL: \(violation.url)\n"
            report += "Call Stack:\n"
            for symbol in violation.callStack.prefix(10) {
                report += "  \(symbol)\n"
            }
        }

        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try report.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            fputs("Airgap: Failed to write report to \(path): \(error)\n", stderr)
        }
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
}
