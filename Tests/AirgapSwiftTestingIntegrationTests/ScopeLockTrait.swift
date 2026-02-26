#if swift(>=6.1)
import Testing
@testable import Airgap

/// A lightweight trait that acquires `Airgap.scopeLock` for the duration of each test,
/// serializing execution with any other scope that uses the same lock (including `.airgapped`
/// tests in other targets). This prevents cross-target state races when `swift test` runs
/// all targets in a single process.
struct ScopeLockTrait: TestTrait, SuiteTrait, TestScoping {
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        if Airgap.scopeLockHeld {
            try await function()
        } else {
            await Airgap.scopeLock.lock()
            defer { Airgap.scopeLock.unlock() }
            try await Airgap.$scopeLockHeld.withValue(true) {
                try await function()
            }
        }
    }
}

extension Trait where Self == ScopeLockTrait {
    /// Acquires `Airgap.scopeLock` for the duration of each test in this scope.
    static var scopeLocked: Self { Self() }
}
#endif
