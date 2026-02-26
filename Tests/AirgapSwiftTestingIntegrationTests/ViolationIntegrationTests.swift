import Testing
@testable import Airgap
import Foundation

extension AllAirgapSwiftTestingTests {

    @Suite struct ViolationSummaryTests {

        @Test("Summary is nil with no violations") func summaryIsNilWithNoViolations() {
            Airgap.clearViolations()
            #expect(Airgap.violationSummary() == nil)
        }

        @Test("Summary contains violation count") func summaryContainsViolationCount() {
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

        @Test("Violations collected without report path") func violationsCollectedWithoutReportPath() {
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
