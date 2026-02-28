@testable import Airgap
import Foundation
import Testing

extension AllAirgapUnitTests {
    @Suite(.serialized)
    final class AsyncMutexTests {
        // MARK: - Basic lock/unlock

        @Test("Lock and unlock works") func lockAndUnlockWorks() async {
            let mutex = AsyncMutex()
            await mutex.lock()
            mutex.unlock()
        }

        @Test("Lock serializes access") func lockSerializesAccess() async {
            let mutex = AsyncMutex()

            // Track the order of operations to verify serialization
            let orderTracker = OrderTracker()
            let iterations = 5

            await withTaskGroup(of: Void.self) { group in
                for i in 0 ..< iterations {
                    group.addTask {
                        await mutex.lock()
                        await orderTracker.recordEntry(i)
                        // Small delay to make overlap detectable if serialization fails
                        try? await Task.sleep(for: .milliseconds(10))
                        await orderTracker.recordExit(i)
                        mutex.unlock()
                    }
                }
            }

            // Verify no overlapping entries — each entry should be followed by its exit
            let events = await orderTracker.events
            var activeCount = 0
            for event in events {
                switch event {
                case .entry:
                    activeCount += 1
                    #expect(activeCount <= 1, "Multiple tasks should not be in the critical section simultaneously")
                case .exit:
                    activeCount -= 1
                }
            }
            #expect(activeCount == 0, "All tasks should have exited")
        }

        @Test("Multiple waiters all eventually acquire the lock") func multipleWaitersAllAcquireLock() async {
            let mutex = AsyncMutex()
            let orderTracker = OrderTracker()

            // Lock the mutex first
            await mutex.lock()

            // Spawn tasks that will queue up as waiters
            let tasks = (0 ..< 3).map { i in
                Task {
                    await mutex.lock()
                    await orderTracker.recordEntry(i)
                    mutex.unlock()
                }
            }

            // Give tasks time to queue up
            try? await Task.sleep(for: .milliseconds(50))

            // Release the lock — all waiters should eventually run
            mutex.unlock()

            for task in tasks {
                await task.value
            }

            let events = await orderTracker.events
            let entryIDs = Set(events.compactMap { event -> Int? in
                if case let .entry(id) = event { return id }
                return nil
            })
            #expect(entryIDs == [0, 1, 2], "All waiters should eventually acquire the lock")
        }
    }
}

/// Actor-isolated tracker for verifying serialization behavior in async mutex tests.
private actor OrderTracker {
    enum Event {
        case entry(Int)
        case exit(Int)
    }

    private var _events: [Event] = []

    var events: [Event] {
        _events
    }

    func recordEntry(_ id: Int) {
        _events.append(.entry(id))
    }

    func recordExit(_ id: Int) {
        _events.append(.exit(id))
    }
}
