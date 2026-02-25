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
@available(iOS 16.0, macOS 13.0, *)
public struct AirgapTrait: TestTrait, SuiteTrait, TestScoping {

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let previousHandler = Airgap.violationHandler
        Airgap.violationHandler = { Issue.record("\($0)") }
        Airgap.activate()

        defer {
            Airgap.deactivate()
            Airgap.violationHandler = previousHandler
        }

        try await function()
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension Trait where Self == AirgapTrait {
    /// Activates Airgap for the duration of the test or suite.
    public static var airgapped: Self { Self() }
}
#endif
