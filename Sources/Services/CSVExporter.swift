import Foundation

/// Writes analysis history to CSV for trainers who already keep records somewhere
/// else — Google Drive, a spreadsheet, their existing coaching platform.
///
/// Deliberately the least sticky feature in the app. A coach who cannot get their
/// data out will not put their clients' data in, and the export costs far less to
/// build than the trust it buys.
enum CSVExporter {

    enum ExportError: LocalizedError {
        case nothingToExport
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .nothingToExport:
                return "There are no saved analyses to export yet."
            case .writeFailed(let details):
                return "Could not write the CSV file. \(details)"
            }
        }
    }

    // MARK: - Session-level export

    private static let sessionHeader = [
        "record_id", "date", "kind", "movement", "side", "plane", "source",
        "duration_seconds", "pose_detection_rate",
        "total_reps", "score", "mean_peak_angle_deg",
        "mean_eccentric_seconds", "mean_concentric_seconds", "average_tempo",
        "grade", "left_rom_deg", "right_rom_deg", "asymmetry_deg", "asymmetry_flag",
        "coaching_notes"
    ]

    /// One row per session — the shape most people want for a progress spreadsheet.
    static func writeSessions(
        _ records: [AnalysisRecord],
        fileNameHint: String
    ) -> Result<URL, Error> {
        guard !records.isEmpty else { return .failure(ExportError.nothingToExport) }

        var rows: [[String]] = [sessionHeader]
        // Oldest first reads better in a spreadsheet than the newest-first order the
        // history list uses.
        for record in records.sorted(by: { $0.date < $1.date }) {
            rows.append([
                record.recordID.uuidString,
                isoFormatter.string(from: record.date),
                record.kind.rawValue,
                record.movementName,
                record.sideRaw,
                record.planeRaw ?? "",
                record.sourceRaw,
                format(record.duration, places: 2),
                format(record.poseDetectionRate, places: 4),
                record.kind == .exercise ? "\(record.totalReps)" : "",
                record.finalScore.map(String.init) ?? "",
                record.meanPeakAngle.map { format($0, places: 1) } ?? "",
                record.meanEccentric.map { format($0, places: 2) } ?? "",
                record.meanConcentric.map { format($0, places: 2) } ?? "",
                record.averageTempoString ?? "",
                record.grade?.rawValue ?? "",
                record.leftROM.map { format($0, places: 1) } ?? "",
                record.rightROM.map { format($0, places: 1) } ?? "",
                record.asymmetryDeg.map { format($0, places: 1) } ?? "",
                record.kind == .assessment ? (record.asymmetryFlag ? "true" : "false") : "",
                record.payload.insights.joined(separator: " | ")
            ])
        }

        return write(rows: rows, fileNameHint: fileNameHint)
    }

    // MARK: - Rep-level export

    private static let repHeader = [
        "record_id", "date", "movement", "side", "rep_number",
        "peak_flexion_angle_deg", "tempo",
        "eccentric_seconds", "pause_bottom_seconds",
        "concentric_seconds", "pause_top_seconds"
    ]

    /// One row per rep, for anyone who wants to do their own analysis.
    static func writeReps(
        _ records: [AnalysisRecord],
        fileNameHint: String
    ) -> Result<URL, Error> {
        let exercises = records.filter { $0.kind == .exercise && !$0.perRepMetrics.isEmpty }
        guard !exercises.isEmpty else { return .failure(ExportError.nothingToExport) }

        var rows: [[String]] = [repHeader]
        for record in exercises.sorted(by: { $0.date < $1.date }) {
            for rep in record.perRepMetrics {
                rows.append([
                    record.recordID.uuidString,
                    isoFormatter.string(from: record.date),
                    record.movementName,
                    record.sideRaw,
                    "\(rep.repNumber)",
                    rep.peakFlexionAngle.isFinite && rep.peakFlexionAngle < 1000
                        ? format(Double(rep.peakFlexionAngle), places: 1)
                        : "",
                    rep.tempoString,
                    format(rep.eccentricDuration, places: 2),
                    format(rep.pauseBottomDuration, places: 2),
                    format(rep.concentricDuration, places: 2),
                    format(rep.pauseTopDuration, places: 2)
                ])
            }
        }

        return write(rows: rows, fileNameHint: fileNameHint)
    }

    // MARK: - Encoding

    /// RFC 4180 escaping: wrap in quotes when the value contains a comma, quote, or
    /// newline, and double any embedded quotes. Coaching notes routinely contain
    /// commas, so this is not optional.
    ///
    /// Scanning `unicodeScalars` rather than `Characters` matters: Swift treats CRLF
    /// as a single grapheme cluster that equals neither "\r" nor "\n", so a
    /// Character-wise check silently lets a Windows line break through unquoted and
    /// splits the row in two.
    static func escape(_ value: String) -> String {
        let needsQuoting = value.unicodeScalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
        }
        guard needsQuoting else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func csvString(rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
    }

    private static func write(rows: [[String]], fileNameHint: String) -> Result<URL, Error> {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitize(fileNameHint)).csv")

        do {
            // A BOM makes Excel open UTF-8 correctly instead of mangling the degree signs.
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(csvString(rows: rows).utf8))
            try data.write(to: url, options: .atomic)
            return .success(url)
        } catch {
            return .failure(ExportError.writeFailed(error.localizedDescription))
        }
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
        let collapsed = cleaned
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "kinetriq-export" : collapsed.lowercased()
    }

    private static func format(_ value: Double, places: Int) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.\(places)f", value)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
