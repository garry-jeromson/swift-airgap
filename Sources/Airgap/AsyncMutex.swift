import Foundation

/// A simple async-compatible mutex for serializing access across suspension points.
///
/// Unlike `NSLock`, this can safely be acquired before an `await` and released after,
/// because it does not require unlock on the same thread as lock. Waiters are resumed
/// in FIFO order.
final class AsyncMutex: @unchecked Sendable {
    private let nsLock = NSLock()
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            nsLock.lock()
            if isLocked {
                waiters.append(continuation)
                nsLock.unlock()
            } else {
                isLocked = true
                nsLock.unlock()
                continuation.resume()
            }
        }
    }

    func unlock() {
        nsLock.lock()
        if let next = waiters.first {
            waiters.removeFirst()
            nsLock.unlock()
            next.resume()
        } else {
            isLocked = false
            nsLock.unlock()
        }
    }
}
