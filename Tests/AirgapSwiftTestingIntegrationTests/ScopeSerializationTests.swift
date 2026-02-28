@testable import Airgap
import Foundation
import Testing

/// Lives outside `AllAirgapSwiftTestingTests` because the test body acquires
/// `Airgap.scopeLock` directly. Nesting it under the `.scopeLocked` parent
/// would deadlock (the trait holds the lock, then the test tries to acquire it again).
@Suite struct ScopeSerializationTests {
    @Test("Scope lock serializes concurrent access") func scopeLockSerializesConcurrentAccess() async {
        // Verify that the scopeLock prevents concurrent scopes from overlapping.
        // Two tasks try to acquire the lock, modify global state, sleep, and check
        // that their state wasn't stomped by the other task.

        let orderLog = OrderLog()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await Airgap.scopeLock.lock()
                defer { Airgap.scopeLock.unlock() }
                orderLog.append("alpha-start")
                Airgap.allowedHosts = ["alpha.example.com"]
                try? await Task.sleep(nanoseconds: 50_000_000)
                #expect(Airgap.allowedHosts == ["alpha.example.com"],
                        "Alpha's allowedHosts should not be stomped by beta")
                orderLog.append("alpha-end")
            }

            group.addTask {
                await Airgap.scopeLock.lock()
                defer { Airgap.scopeLock.unlock() }
                orderLog.append("beta-start")
                Airgap.allowedHosts = ["beta.example.com"]
                try? await Task.sleep(nanoseconds: 50_000_000)
                #expect(Airgap.allowedHosts == ["beta.example.com"],
                        "Beta's allowedHosts should not be stomped by alpha")
                orderLog.append("beta-end")
            }

            await group.waitForAll()
        }

        // Verify serialization: one scope must fully complete before the other starts
        let log = orderLog.entries
        #expect(log.count == 4)
        // Either alpha runs fully before beta, or beta runs fully before alpha
        let alphaFirst = log == ["alpha-start", "alpha-end", "beta-start", "beta-end"]
        let betaFirst = log == ["beta-start", "beta-end", "alpha-start", "alpha-end"]
        #expect(alphaFirst || betaFirst,
                "Scopes must be fully serialized, got: \(log)")
    }
}
