import Testing
@testable import Airgap
import Foundation

extension AllAirgapSwiftTestingTests {

    @Suite struct ViolationSummaryTests {

        @Test func `Summary is nil with no violations`() {
            Airgap.clearViolations()
            #expect(Airgap.violationSummary() == nil)
        }

        @Test func `Summary contains violation count`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.clearViolations()
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.clearViolations()
            }

            let url = URL(string: "https://example.com/api/summary")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            let summary = Airgap.violationSummary()
            #expect(summary != nil)
            #expect(summary?.contains("1 violation(s)") == true)
        }
    }

    @Suite struct ViolationCollectionTests {

        @Test func `Violations collected without report path`() {
            let capture = ViolationCapture()
            Airgap.violationHandler = { capture.record($0) }
            Airgap.reportPath = nil
            Airgap.clearViolations()
            Airgap.activate()
            defer {
                Airgap.deactivate()
                Airgap.reportPath = nil
                Airgap.clearViolations()
            }

            let url = URL(string: "https://example.com/api/collect-no-path")!
            let semaphore = DispatchSemaphore(value: 0)

            URLSession.shared.dataTask(with: url) { _, _, _ in
                semaphore.signal()
            }.resume()
            semaphore.wait()

            #expect(Airgap.violations.count == 1, "Violations should be collected even without reportPath")
        }
    }
}
