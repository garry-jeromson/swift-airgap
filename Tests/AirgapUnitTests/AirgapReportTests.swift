@testable import Airgap
import Foundation
import Testing

extension AllAirgapUnitTests {
    @Suite(.serialized)
    final class AirgapReportTests {
        init() {
            resetAirgapState()
        }

        // MARK: - Report writing

        @Test("Write report creates file") func writeReportCreatesFile() async throws {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("ng-report-\(UUID().uuidString).txt").path
            Airgap.reportPath = tempPath
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/report-test"))
            _ = try? await URLSession.shared.data(from: url)

            Airgap.writeReport()

            #expect(FileManager.default.fileExists(atPath: tempPath))

            try? FileManager.default.removeItem(atPath: tempPath)
        }

        @Test("Report contains method and URL") func reportContainsMethodAndURL() async throws {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("ng-report-content-\(UUID().uuidString).txt").path
            Airgap.reportPath = tempPath
            AirgapURLProtocol.currentTestName = "AirgapReportTests/Report contains method and URL"
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/report-content"))
            _ = try? await URLSession.shared.data(from: url)

            Airgap.writeReport()

            let content = try? String(contentsOfFile: tempPath, encoding: .utf8)
            #expect(content != nil)
            #expect(content?.contains("Method: GET") ?? false)
            #expect(content?.contains("URL: https://example.com/api/report-content") ?? false)
            #expect(content?.contains("Test: AirgapReportTests/Report contains method and URL") ?? false)
            #expect(content?.contains("Call Stack:") ?? false)
            #expect(content?.contains("Total violations:") ?? false)

            try? FileManager.default.removeItem(atPath: tempPath)
        }

        // MARK: - Report edge cases

        @Test("Write report handles unwritable path") func writeReportHandlesUnwritablePath() async throws {
            Airgap.reportPath = "/nonexistent/deep/path/airgap-report.txt"
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/unwritable"))
            _ = try? await URLSession.shared.data(from: url)

            // Should not crash
            Airgap.writeReport()
        }

        @Test("Write report with nil path is a no-op") func writeReportWithNilPathIsANoOp() async throws {
            Airgap.reportPath = nil
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/nil-path-test"))
            _ = try? await URLSession.shared.data(from: url)

            // Should not crash or create any file
            Airgap.writeReport()

            #expect(Airgap.violations.count == 1, "Violations should still be collected")
        }

        @Test("Write report with no violations does not create file") func writeReportWithNoViolationsDoesNotCreateFile() {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("ng-empty-\(UUID().uuidString).txt").path
            Airgap.reportPath = tempPath

            Airgap.writeReport()

            #expect(!FileManager.default.fileExists(atPath: tempPath))
        }

        // MARK: - JSON report output

        @Test("Write report as JSON") func writeReportAsJSON() async throws {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("airgap-test-\(UUID().uuidString).json").path
            defer { try? FileManager.default.removeItem(atPath: tempPath) }

            Airgap.reportPath = tempPath
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/json-report"))
            _ = try? await URLSession.shared.data(from: url)

            Airgap.writeReport()

            let data = try Data(contentsOf: URL(fileURLWithPath: tempPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let violations = try decoder.decode([Violation].self, from: data)
            #expect(violations.count == 1)
            #expect(violations[0].url == "https://example.com/api/json-report")
            #expect(violations[0].httpMethod == "GET")
        }

        // MARK: - Violation summary

        @Test("Violation summary returns nil when no violations") func violationSummaryReturnsNilWhenNoViolations() {
            #expect(Airgap.violationSummary() == nil)
        }

        @Test("Violation summary returns formatted string") func violationSummaryReturnsFormattedString() async throws {
            Airgap.activate()

            let url = try #require(URL(string: "https://example.com/api/summary-test"))
            _ = try? await URLSession.shared.data(from: url)

            let summary = Airgap.violationSummary()
            #expect(summary != nil)
            #expect(summary?.contains("1 violation(s)") ?? false)
            #expect(summary?.contains("1 test(s)") ?? false)
        }
    }
} // extension AllAirgapUnitTests
