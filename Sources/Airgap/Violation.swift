import Foundation

/// Represents a single network violation detected by Airgap.
public struct Violation: Sendable {
    public let testName: String
    public let httpMethod: String
    public let url: String
    public let callStack: [String]
    public let timestamp: Date

    public init(testName: String, httpMethod: String, url: String, callStack: [String], timestamp: Date = Date()) {
        self.testName = testName
        self.httpMethod = httpMethod
        self.url = url
        self.callStack = callStack
        self.timestamp = timestamp
    }
}
