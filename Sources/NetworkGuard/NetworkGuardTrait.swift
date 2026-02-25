import Foundation

#if canImport(Testing)
import Testing

/// A Swift Testing trait that activates NetworkGuard for the duration of a test or suite.
///
/// ## Usage
///
/// Apply to an entire suite:
/// ```swift
/// @Suite(.networkGuarded)
/// struct MyFeatureTests {
///     @Test func fetchData() async throws {
///         // Any HTTP/HTTPS request here will record an Issue
///     }
/// }
/// ```
///
/// Apply to an individual test:
/// ```swift
/// @Test(.networkGuarded)
/// func fetchData() async throws { ... }
/// ```
///
/// ## Opting out individual tests
///
/// Within a guarded suite, call `NetworkGuard.allowNetworkAccess()` at the start of
/// any test that legitimately needs network access:
/// ```swift
/// @Test func integrationTest() async throws {
///     NetworkGuard.allowNetworkAccess()
///     // Real network calls are allowed here
/// }
/// ```
///
/// ## Violation reporting
///
/// Violations are reported via `Issue.record()` automatically.
@available(iOS 16.0, *)
public struct NetworkGuardTrait: TestTrait, SuiteTrait, TestScoping {

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let previousHandler = NetworkGuard.violationHandler
        NetworkGuard.violationHandler = { Issue.record("\($0)") }
        NetworkGuard.activate()

        defer {
            NetworkGuard.deactivate()
            NetworkGuard.violationHandler = previousHandler
        }

        try await function()
    }
}

@available(iOS 16.0, *)
extension Trait where Self == NetworkGuardTrait {
    /// Activates NetworkGuard for the duration of the test or suite.
    public static var networkGuarded: Self { Self() }
}
#endif
