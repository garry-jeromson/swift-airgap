import Foundation

/// Thread-safe ordered log for verifying serialization.
final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [String] = []

    var entries: [String] {
        lock.withLock { _entries }
    }

    func append(_ entry: String) {
        lock.withLock { _entries.append(entry) }
    }
}

/// Thread-safe error capture for use in Swift Testing tests.
final class ErrorCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: (any Error)?

    var value: (any Error)? {
        lock.withLock { _value }
    }

    func set(_ error: (any Error)?) {
        lock.withLock { _value = error }
    }
}

/// Thread-safe violation capture for integration tests.
final class ViolationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []

    var messages: [String] {
        lock.withLock { _messages }
    }

    var count: Int {
        lock.withLock { _messages.count }
    }

    var isEmpty: Bool {
        lock.withLock { _messages.isEmpty }
    }

    func record(_ message: String) {
        lock.withLock { _messages.append(message) }
    }

    func reset() {
        lock.withLock { _messages = [] }
    }
}
