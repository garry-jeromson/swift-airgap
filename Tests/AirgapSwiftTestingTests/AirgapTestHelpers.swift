import Foundation
@testable import Airgap

/// Thread-safe violation reporter capture for use in tests with @Sendable closures.
final class ViolationReporterCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _violations: [Violation] = []

    var violations: [Violation] {
        lock.withLock { _violations }
    }

    func record(_ violation: Violation) {
        lock.withLock { _violations.append(violation) }
    }
}

/// A minimal URLProtocol subclass for the mock:// scheme, used to verify coexistence with Airgap.
final class MockSchemeProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "mock"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: NSError(domain: "MockScheme", code: 0))
    }

    override func stopLoading() {}
}

/// A concrete subclass of AirgapTestCase for testing the lifecycle methods.
final class LifecycleTestCase: AirgapTestCase {

    func invokeSetUp() {
        setUp()
    }

    func invokeTearDown() {
        tearDown()
    }
}
