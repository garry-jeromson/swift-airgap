import Foundation

#if canImport(Testing)
import Testing

/// A Swift Testing trait that activates Airgap for the duration of a test or suite.
///
/// ## Usage
///
/// Apply to an entire suite:
/// ```swift
/// @Suite(.airgapped)
/// struct MyFeatureTests {
///     @Test func fetchData() async throws {
///         // Any HTTP/HTTPS request here will record an Issue
///     }
/// }
/// ```
///
/// Apply to an individual test:
/// ```swift
/// @Test(.airgapped)
/// func fetchData() async throws { ... }
/// ```
///
/// ## Opting out individual tests
///
/// Within a guarded suite, call `Airgap.allowNetworkAccess()` at the start of
/// any test that legitimately needs network access:
/// ```swift
/// @Test func integrationTest() async throws {
///     Airgap.allowNetworkAccess()
///     // Real network calls are allowed here
/// }
/// ```
///
/// ## Violation reporting
///
/// Violations are reported via `Issue.record()` automatically.
///
/// > Note: The `provideScope` runtime scoping (which activates/deactivates Airgap around each
/// > test) requires Swift 6.1+ (`TestScoping` protocol). On Swift 6.0, the trait compiles and
/// > can be applied as metadata, but has no runtime scoping effect — use manual
/// > `Airgap.activate()`/`deactivate()` calls instead.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct AirgapTrait: TestTrait, SuiteTrait {

    /// Additional hosts to allow through the guard for the duration of this scope.
    private let additionalAllowedHosts: Set<String>

    /// Optional mode override for this scope.
    private let modeOverride: Airgap.Mode?

    public init(mode: Airgap.Mode? = nil, allowedHosts: Set<String> = []) {
        self.modeOverride = mode
        self.additionalAllowedHosts = allowedHosts
    }
}

#if swift(>=6.1)
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension AirgapTrait: TestScoping {
    /// Activates Airgap for the duration of a single test or suite scope.
    ///
    /// Acquires `Airgap.scopeLock` (unless already held by an outer scope), saves all mutable
    /// Airgap state, applies configuration from the trait parameters and environment, runs the
    /// test body, then restores all state. This ensures test-level isolation even though Airgap
    /// uses process-global static properties.
    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // If an outer scope (e.g. ScopeLockTrait) already holds the lock,
        // skip acquisition to avoid deadlock.
        let alreadyHeld = Airgap.scopeLockHeld
        if !alreadyHeld {
            await Airgap.scopeLock.lock()
        }
        defer {
            if !alreadyHeld {
                Airgap.scopeLock.unlock()
            }
        }

        // Save all mutable state
        let previousHandler = Airgap.violationHandler
        let previousReporter = Airgap.violationReporter
        let previousAllowedHosts = Airgap.allowedHosts
        let previousMode = Airgap.mode
        let previousErrorCode = Airgap.errorCode
        let previousResponseDelay = Airgap.responseDelay
        let previousTestName = AirgapURLProtocol.currentTestName

        Airgap.configureFromEnvironment()
        // In fail mode, record violations as Swift Testing Issues.
        // In warn mode, wrap violations in withKnownIssue so they appear in
        // the test navigator as known issues without failing the test.
        let effectiveMode = modeOverride ?? Airgap.mode
        if effectiveMode == .warn {
            Airgap.violationHandler = { message in
                withKnownIssue("Airgap violation (warning mode)") {
                    Issue.record("\(message)")
                }
            }
        } else {
            Airgap.violationHandler = { Issue.record("\($0)") }
        }
        if !additionalAllowedHosts.isEmpty {
            Airgap.allowedHosts = Airgap.allowedHosts.union(additionalAllowedHosts)
        }
        if let modeOverride {
            Airgap.mode = modeOverride
        }
        AirgapURLProtocol.currentTestName = test.name
        Airgap.clearViolations()
        Airgap.activate()

        defer {
            if let summary = Airgap.violationSummary() {
                print(summary)
            }
            Airgap.deactivate()
            Airgap.violationHandler = previousHandler
            Airgap.violationReporter = previousReporter
            Airgap.allowedHosts = previousAllowedHosts
            Airgap.mode = previousMode
            Airgap.errorCode = previousErrorCode
            Airgap.responseDelay = previousResponseDelay
            AirgapURLProtocol.currentTestName = previousTestName
        }

        try await Airgap.$scopeLockHeld.withValue(true) {
            try await function()
        }
    }
}
#endif

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension Trait where Self == AirgapTrait {
    /// Activates Airgap for the duration of the test or suite.
    public static var airgapped: Self { Self() }

    /// Activates Airgap with specific hosts allowed through the guard.
    public static func airgapped(allowedHosts: Set<String>) -> Self {
        Self(allowedHosts: allowedHosts)
    }

    /// Activates Airgap with a specific mode.
    public static func airgapped(mode: Airgap.Mode) -> Self {
        Self(mode: mode)
    }

    /// Activates Airgap with a specific mode and allowed hosts.
    public static func airgapped(mode: Airgap.Mode, allowedHosts: Set<String>) -> Self {
        Self(mode: mode, allowedHosts: allowedHosts)
    }
}
#endif
