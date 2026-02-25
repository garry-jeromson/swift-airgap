import Foundation
#if canImport(XCTest)
import XCTest
#endif

/// Detects and fails any test that attempts a real HTTP/HTTPS network request.
///
/// Supports activation at the test-target, suite, or individual-test level.
/// Tests that legitimately need network access can opt out via `allowNetworkAccess()`.
public enum NetworkGuard {

    /// Controls how violations are reported.
    public enum Mode {
        /// Default: calls the violation handler directly (XCTFail by default).
        case fail
        /// Wraps the violation in XCTExpectFailure so it appears in Xcode's issue navigator
        /// as an expected failure without failing the test.
        case warn
    }

    /// The current violation reporting mode. Defaults to `.fail`.
    public static var mode: Mode = .fail

    /// When set, violations are collected and written to this file path.
    public static var reportPath: String?

    /// Collected violations when `reportPath` is set.
    public private(set) static var violations: [Violation] = []

    private static let violationsLock = NSLock()

    /// Called when a network violation is detected. Defaults to `XCTFail()`.
    /// Set to `{ Issue.record($0) }` for Swift Testing, or any custom handler.
    public static var violationHandler: (String) -> Void = { message in
        #if canImport(XCTest)
        XCTFail(message)
        #else
        assertionFailure(message)
        #endif
    }

    /// Whether swizzling has been applied (only needs to happen once).
    private static var hasSwizzled = false

    /// Activates the network guard. Registers the URLProtocol and swizzles session configurations.
    ///
    /// Safe to call multiple times — activation is idempotent.
    public static func activate() {
        NetworkGuardURLProtocol.isActive = true
        NetworkGuardURLProtocol.isAllowed = false
        URLProtocol.registerClass(NetworkGuardURLProtocol.self)

        if !hasSwizzled {
            swizzleSessionConfigurations()
            hasSwizzled = true
        }
    }

    /// Deactivates the network guard. Unregisters the URLProtocol.
    public static func deactivate() {
        NetworkGuardURLProtocol.isActive = false
        URLProtocol.unregisterClass(NetworkGuardURLProtocol.self)
    }

    /// Disables the guard for the remainder of the current test.
    ///
    /// The guard is re-activated automatically on the next `activate()` call.
    public static func allowNetworkAccess() {
        NetworkGuardURLProtocol.isAllowed = true
    }

    /// Resets the collected violations list.
    public static func clearViolations() {
        violationsLock.withLock {
            violations = []
        }
    }

    /// Reads environment variables to configure mode and report path.
    ///
    /// - `NETWORK_GUARD_MODE=warn` sets `mode = .warn`
    /// - `NETWORK_GUARD_REPORT_PATH=/path` sets `reportPath`
    public static func configureFromEnvironment() {
        if let modeValue = ProcessInfo.processInfo.environment["NETWORK_GUARD_MODE"],
           modeValue.lowercased() == "warn" {
            mode = .warn
        }
        if let path = ProcessInfo.processInfo.environment["NETWORK_GUARD_REPORT_PATH"],
           !path.isEmpty {
            reportPath = path
        }
    }

    /// Reports a network violation through the configured handler.
    static func reportViolation(method: String, url: String, callStack: [String], testName: String) {
        let message = """
        NetworkGuard: Blocked \(method) request to \(url). \
        Tests must not make real network calls. \
        Use a mock or stub instead.
        """

        // Collect violation if reportPath is set
        if reportPath != nil {
            let violation = Violation(
                testName: testName,
                httpMethod: method,
                url: url,
                callStack: callStack
            )
            violationsLock.withLock {
                violations.append(violation)
            }
        }

        switch mode {
        case .fail:
            violationHandler(message)
        case .warn:
            // XCTExpectFailure must run on the main thread — startLoading() is
            // called on com.apple.CFNetwork.CustomProtocols which would crash.
            #if canImport(XCTest)
            let work = {
                XCTExpectFailure("NetworkGuard violation (warning mode)") {
                    XCTFail(message)
                }
            }
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.sync { work() }
            }
            #else
            violationHandler(message)
            #endif
        }
    }

    /// Legacy report method for backward compatibility.
    static func reportViolation(message: String) {
        violationHandler(message)
    }

    /// Writes collected violations to the configured `reportPath`.
    public static func writeReport() {
        guard let path = reportPath else { return }

        let currentViolations = violationsLock.withLock { violations }
        guard !currentViolations.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var report = """
        NetworkGuard Violation Report
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
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? report.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Configuration swizzling

    /// Swizzles `URLSessionConfiguration.default` and `.ephemeral` property getters
    /// to inject `NetworkGuardURLProtocol` into any newly-created session configuration.
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
            if !protocols.contains(where: { $0 == NetworkGuardURLProtocol.self }) {
                protocols.insert(NetworkGuardURLProtocol.self, at: 0)
            }
            config.protocolClasses = protocols
            return config
        }

        let swizzledIMP = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(method, swizzledIMP)
    }
}
