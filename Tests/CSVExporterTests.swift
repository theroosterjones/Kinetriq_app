import XCTest
@testable import Kinetriq

final class CSVExporterTests: XCTestCase {

    // MARK: - Escaping

    func testPlainValuesAreNotQuoted() {
        XCTAssertEqual(CSVExporter.escape("Squat"), "Squat")
        XCTAssertEqual(CSVExporter.escape("3-1-2-1"), "3-1-2-1")
    }

    /// Coaching notes routinely contain commas, which is the whole reason this exists.
    func testCommasForceQuoting() {
        XCTAssertEqual(CSVExporter.escape("Depth was consistent, tempo drifted"),
                       "\"Depth was consistent, tempo drifted\"")
    }

    func testEmbeddedQuotesAreDoubled() {
        XCTAssertEqual(CSVExporter.escape("She said \"sit back\""),
                       "\"She said \"\"sit back\"\"\"")
    }

    func testNewlinesForceQuoting() {
        XCTAssertEqual(CSVExporter.escape("line one\nline two"), "\"line one\nline two\"")
        XCTAssertEqual(CSVExporter.escape("line one\r\nline two"), "\"line one\r\nline two\"")
    }

    // MARK: - Row encoding

    func testRowsUseCRLFSoSpreadsheetsParseThem() {
        let csv = CSVExporter.csvString(rows: [["a", "b"], ["1", "2"]])
        XCTAssertEqual(csv, "a,b\r\n1,2")
    }

    func testEscapingAppliesInsideRows() {
        let csv = CSVExporter.csvString(rows: [["movement", "note"],
                                               ["Squat", "deeper, slower"]])
        XCTAssertEqual(csv, "movement,note\r\nSquat,\"deeper, slower\"")
    }

    // MARK: - Files

    func testExportingNothingIsAnErrorRatherThanAnEmptyFile() {
        switch CSVExporter.writeSessions([], fileNameHint: "empty") {
        case .success:
            XCTFail("An empty export should not produce a file")
        case .failure(let error):
            XCTAssertTrue(error is CSVExporter.ExportError)
        }
    }

    func testSessionExportWritesAHeaderAndOneRowPerSession() throws {
        let records = [record(movement: "Squat", daysAgo: 2), record(movement: "Squat", daysAgo: 0)]

        let url = try XCTUnwrap(try CSVExporter.writeSessions(records, fileNameHint: "Kinetriq Sessions").get())
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("record_id"))
        XCTAssertTrue(lines[0].contains("mean_peak_angle_deg"))
    }

    /// Excel mis-reads UTF-8 without a BOM, which mangles the degree signs.
    func testExportedFileStartsWithAUTF8BOM() throws {
        let url = try XCTUnwrap(try CSVExporter.writeSessions([record()], fileNameHint: "bom").get())
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testFileNameHintIsSanitizedIntoASafeFileName() throws {
        let url = try XCTUnwrap(try CSVExporter.writeSessions([record()],
                                                             fileNameHint: "Kinetriq / Squat Sessions!").get())
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.lastPathComponent, "kinetriq-squat-sessions.csv")
    }

    func testSessionsAreWrittenOldestFirst() throws {
        let older = record(movement: "Deadlift", daysAgo: 5)
        let newer = record(movement: "Squat", daysAgo: 1)

        let url = try XCTUnwrap(try CSVExporter.writeSessions([newer, older], fileNameHint: "order").get())
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\r\n")
        XCTAssertTrue(lines[1].contains("Deadlift"))
        XCTAssertTrue(lines[2].contains("Squat"))
    }

    // MARK: - Rep export

    func testRepExportWritesOneRowPerRep() throws {
        let url = try XCTUnwrap(try CSVExporter.writeReps([record(repCount: 4)], fileNameHint: "reps").get())
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 5)
        XCTAssertTrue(lines[0].contains("rep_number"))
    }

    func testAssessmentsAreExcludedFromTheRepExport() {
        let assessment = AnalysisRecord(
            kind: .assessment,
            movementKey: AssessmentType.shoulderFlexion.rawValue,
            movementName: "Shoulder Flexion",
            side: .left,
            source: .savedVideo,
            duration: 10,
            poseDetectionRate: 0.9,
            payload: AnalysisPayload()
        )

        switch CSVExporter.writeReps([assessment], fileNameHint: "reps") {
        case .success:
            XCTFail("An assessment has no reps to export")
        case .failure(let error):
            XCTAssertTrue(error is CSVExporter.ExportError)
        }
    }

    /// The collector uses a sentinel peak angle when it never saw a usable frame;
    /// that must not reach the spreadsheet as a number.
    func testSentinelPeakAngleExportsAsBlank() throws {
        var payload = AnalysisPayload()
        payload.perRepMetrics = [
            RepMetric(repNumber: 1, peakFlexionAngle: .greatestFiniteMagnitude,
                      eccentricDuration: 2.0, pauseBottomDuration: 0.4,
                      concentricDuration: 1.5, pauseTopDuration: 0.4)
        ]
        let record = AnalysisRecord(
            kind: .exercise,
            movementKey: ExerciseType.squat.rawValue,
            movementName: "Squat",
            side: .left,
            source: .savedVideo,
            duration: 20,
            poseDetectionRate: 0.9,
            totalReps: 1,
            payload: payload
        )

        let url = try XCTUnwrap(try CSVExporter.writeReps([record], fileNameHint: "sentinel").get())
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\r\n")
        let columns = lines[1].components(separatedBy: ",")
        XCTAssertEqual(columns[5], "")
    }

    // MARK: - Helpers

    private func record(
        movement: String = "Squat",
        daysAgo: Int = 0,
        repCount: Int = 3
    ) -> AnalysisRecord {
        var payload = AnalysisPayload()
        payload.insights = ["Depth was consistent, tempo drifted"]
        payload.perRepMetrics = (1...repCount).map { n in
            RepMetric(repNumber: n, peakFlexionAngle: 90,
                      eccentricDuration: 2.0, pauseBottomDuration: 0.4,
                      concentricDuration: 1.5, pauseTopDuration: 0.4)
        }

        return AnalysisRecord(
            date: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            kind: .exercise,
            movementKey: ExerciseType.squat.rawValue,
            movementName: movement,
            side: .left,
            source: .savedVideo,
            duration: 30,
            poseDetectionRate: 0.94,
            totalReps: repCount,
            finalScore: 82,
            meanPeakAngle: 90,
            payload: payload
        )
    }
}
