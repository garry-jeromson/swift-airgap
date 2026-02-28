import Foundation

/// Represents a single network violation detected by Airgap.
public struct Violation: Sendable, Equatable, Codable {
    /// The name of the test that triggered the violation (e.g., `"-[MyTests testFetch]"` or `"MyTests/fetch"`).
    public let testName: String
    /// The HTTP method of the intercepted request (e.g., `"GET"`, `"POST"`).
    public let httpMethod: String
    /// The absolute URL string of the intercepted request.
    public let url: String
    /// Symbolicated stack frames captured at the call site. Truncated to 10 frames in text reports.
    public let callStack: [String]
    /// When the violation was detected. Encoded as ISO 8601 in JSON reports.
    public let timestamp: Date
    /// The `Content-Type` header of the intercepted request, if present.
    public let contentType: String?

    public init(testName: String, httpMethod: String, url: String, callStack: [String], timestamp: Date = Date(), contentType: String? = nil) {
        self.testName = testName
        self.httpMethod = httpMethod
        self.url = url
        self.callStack = callStack
        self.timestamp = timestamp
        self.contentType = contentType
    }
}
