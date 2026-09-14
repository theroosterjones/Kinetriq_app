import XCTest
@testable import Kinetriq

/// Covers the download half of metrics sync: turning a PostgREST row back into an
/// `AnalysisRecord`.
///
/// The upload side can assume a well-formed device model. The download side cannot —
/// rows may have been written by an older build, or by a newer one that added columns
/// this build doesn't know. These tests pin the leniency so a schema change degrades
/// to a usable record instead of an empty Progress tab.
final class SyncRestoreTests: XCTestCase {

    private func decode(_ json: String) throws -> [RemoteAnalysisRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601Timestamp.decodingStrategy
        return try decoder.decode([RemoteAnalysisRecord].self, from: Data(json.utf8))
    }

    func testRestoresExerciseRecordWithEmbeddedReps() throws {
        let json = """
        [{
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "recorded_at": "2026-09-01T14:32:11.482913+00:00",
          "kind": "exercise",
          "movement_key": "Squat",
          "movement_name": "Squat",
          "side": "right",
          "plane": null,
          "source": "liveCamera",
          "duration_seconds": 41.5,
          "pose_detection_rate": 0.94,
          "total_reps": 3,
          "score": 82,
          "mean_peak_angle_deg": 88.4,
          "mean_eccentric_seconds": 2.1,
          "mean_concentric_seconds": 1.4,
          "grade": null,
          "left_rom_deg": null,
          "right_rom_deg": null,
          "asymmetry_deg": null,
          "asymmetry_flag": false,
          "average_angles": [{"joint": "knee", "degrees": 92.5}],
          "tempo_breakdown": {"eccentric": 2.1, "concentric": 1.4},
          "sub_grades": [],
          "details": [],
          "insights": ["Depth was consistent."],
          "analysis_reps": [
            {"rep_number": 2, "peak_flexion_angle_deg": 90.0, "eccentric_seconds": 2.0,
             "pause_bottom_seconds": 0.3, "concentric_seconds": 1.5, "pause_top_seconds": 0.4},
            {"rep_number": 1, "peak_flexion_angle_deg": 86.0, "eccentric_seconds": 2.2,
             "pause_bottom_seconds": 0.2, "concentric_seconds": 1.3, "pause_top_seconds": 0.5}
          ]
        }]
        """

        let remote = try XCTUnwrap(decode(json).first)
        let record = try XCTUnwrap(remote.makeRecord())

        XCTAssertEqual(record.recordID.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(record.kind, .exercise)
        XCTAssertEqual(record.movementKey, "Squat")
        XCTAssertEqual(record.exerciseType, .squat)
        XCTAssertEqual(record.side, .right)
        XCTAssertEqual(record.source, .liveCamera)
        XCTAssertEqual(record.totalReps, 3)
        XCTAssertEqual(record.finalScore, 82)
        XCTAssertEqual(record.meanPeakAngle ?? 0, 88.4, accuracy: 0.001)
        XCTAssertEqual(record.payload.insights, ["Depth was consistent."])
        XCTAssertEqual(record.payload.averageAngles.first?.joint, .knee)

        // Reps arrive in whatever order Postgres hands them back; the record has to
        // read 1, 2, 3 or every per-rep readout is scrambled.
        XCTAssertEqual(record.perRepMetrics.map(\.repNumber), [1, 2])
        XCTAssertEqual(record.perRepMetrics.first?.peakFlexionAngle ?? 0, 86.0, accuracy: 0.001)
    }

    func testRestoresAssessmentRecord() throws {
        let json = """
        [{
          "id": "33333333-3333-3333-3333-333333333333",
          "recorded_at": "2026-08-14T09:00:00Z",
          "kind": "assessment",
          "movement_key": "Shoulder Flexion",
          "movement_name": "Shoulder Flexion",
          "side": "left",
          "plane": "frontal",
          "source": "savedVideo",
          "duration_seconds": 12.0,
          "pose_detection_rate": 0.88,
          "total_reps": 0,
          "grade": "B",
          "left_rom_deg": 158.0,
          "right_rom_deg": 171.0,
          "asymmetry_deg": 13.0,
          "asymmetry_flag": true,
          "sub_grades": [{"label": "Range", "grade": "B"}],
          "details": ["Left side lagged."]
        }]
        """

        let record = try XCTUnwrap(try XCTUnwrap(decode(json).first).makeRecord())

        XCTAssertEqual(record.kind, .assessment)
        XCTAssertEqual(record.grade, .B)
        XCTAssertTrue(record.asymmetryFlag)
        XCTAssertEqual(record.asymmetryDeg ?? 0, 13.0, accuracy: 0.001)
        XCTAssertEqual(record.payload.subGrades.first?.grade, .B)
        XCTAssertEqual(record.payload.details, ["Left side lagged."])
    }

    /// A row written by a build that didn't have half these columns still has to open.
    func testMissingOptionalColumnsFallBackInsteadOfFailing() throws {
        let json = """
        [{
          "id": "44444444-4444-4444-4444-444444444444",
          "recorded_at": "2026-07-02T18:20:00Z",
          "movement_key": "Row"
        }]
        """

        let record = try XCTUnwrap(try XCTUnwrap(decode(json).first).makeRecord())

        XCTAssertEqual(record.kind, .exercise)
        XCTAssertEqual(record.movementName, "Row", "Falls back to the key when the display name is absent")
        XCTAssertEqual(record.totalReps, 0)
        XCTAssertNil(record.finalScore)
        XCTAssertFalse(record.asymmetryFlag)
        XCTAssertTrue(record.perRepMetrics.isEmpty)
    }

    /// Columns this build has never heard of must not fail the whole page — one
    /// unknown key would otherwise wipe out a user's entire restored history.
    func testUnknownColumnsAreIgnored() throws {
        let json = """
        [{
          "id": "55555555-5555-5555-5555-555555555555",
          "recorded_at": "2026-07-02T18:20:00Z",
          "movement_key": "Dips",
          "some_future_column": {"nested": [1, 2, 3]}
        }]
        """

        XCTAssertNotNil(try XCTUnwrap(decode(json).first).makeRecord())
    }

    func testRowWithAnUnusableIdentityIsSkipped() throws {
        let badUUID = """
        [{"id": "not-a-uuid", "recorded_at": "2026-07-02T18:20:00Z", "movement_key": "Squat"}]
        """
        XCTAssertNil(try XCTUnwrap(decode(badUUID).first).makeRecord())

        let noMovement = """
        [{"id": "66666666-6666-6666-6666-666666666666", "recorded_at": "2026-07-02T18:20:00Z", "movement_key": ""}]
        """
        XCTAssertNil(try XCTUnwrap(decode(noMovement).first).makeRecord())
    }

    /// `AnalysisRepPayload` nils out the collector's "never measured" sentinel because
    /// `.greatestFiniteMagnitude` is not valid JSON. Restore has to put it back, or
    /// every downstream average silently treats an unmeasured rep as 0°.
    func testUnmeasuredPeakAngleRestoresTheSentinelRatherThanZero() throws {
        let json = """
        [{
          "id": "77777777-7777-7777-7777-777777777777",
          "recorded_at": "2026-07-02T18:20:00Z",
          "movement_key": "Squat",
          "analysis_reps": [
            {"rep_number": 1, "peak_flexion_angle_deg": null, "eccentric_seconds": 1.0,
             "pause_bottom_seconds": 0.0, "concentric_seconds": 1.0, "pause_top_seconds": 0.0}
          ]
        }]
        """

        let record = try XCTUnwrap(try XCTUnwrap(decode(json).first).makeRecord())
        let rep = try XCTUnwrap(record.perRepMetrics.first)

        XCTAssertEqual(rep.peakFlexionAngle, .greatestFiniteMagnitude)
        XCTAssertFalse(rep.peakFlexionAngle < 1000, "Must not read as a real 0° measurement")
    }

    /// Restore brings back measurements only. Nothing on the download path may invent
    /// a video file name, because that would produce a player pointed at a file that
    /// does not exist on this device.
    func testRestoredRecordClaimsNoLocalMedia() throws {
        let json = """
        [{
          "id": "88888888-8888-8888-8888-888888888888",
          "recorded_at": "2026-07-02T18:20:00Z",
          "movement_key": "Squat"
        }]
        """

        let record = try XCTUnwrap(try XCTUnwrap(decode(json).first).makeRecord())

        XCTAssertNil(record.videoFileName)
        XCTAssertNil(record.thumbnailFileName)
        XCTAssertNil(record.videoURL)
        XCTAssertFalse(record.hasLocalVideo)
    }

    /// Postgres `timestamptz` renders with microseconds. Foundation's built-in
    /// `.iso8601` rejects those — the trap that broke Sign in with Apple in 3.5.3.
    func testMicrosecondTimestampsDecode() throws {
        let json = """
        [{
          "id": "99999999-9999-9999-9999-999999999999",
          "recorded_at": "2026-09-01T14:32:11.482913+00:00",
          "movement_key": "Squat"
        }]
        """

        let remote = try XCTUnwrap(decode(json).first)
        XCTAssertEqual(
            remote.recorded_at.timeIntervalSince1970,
            ISO8601Timestamp.parse("2026-09-01T14:32:11.482913Z")?.timeIntervalSince1970 ?? -1,
            accuracy: 0.001
        )
    }

    // MARK: - Failure wording

    /// A failed *download* must never tell the user their progress couldn't be saved.
    /// That describes the one thing that didn't happen, and to someone whose history
    /// hasn't appeared yet it reads as confirmation that it was lost.
    ///
    /// `@MainActor` because `SyncService` is, and that isolates its statics too — the
    /// same reason `AuthJSONDecodingTests` annotates its message test.
    @MainActor
    func testDownloadFailuresNeverClaimProgressWasNotSaved() {
        let errors: [Error] = [
            SyncService.SyncError.requestFailed(status: 500, detail: nil),
            SyncService.SyncError.invalidResponse,
            URLError(.notConnectedToInternet)
        ]

        for error in errors {
            let message = SyncService.userFacingMessage(for: error, direction: .download)
            XCTAssertFalse(message.contains("couldn't be saved"), "download wording: \(message)")
            XCTAssertFalse(message.contains("will retry automatically"), "download wording: \(message)")
        }
    }

    /// Upload wording is unchanged, and download codes are distinguishable in a
    /// screenshot so a support reply can tell the two directions apart.
    @MainActor
    func testUploadAndDownloadCarryDifferentReferenceCodes() {
        let error = SyncService.SyncError.requestFailed(status: 500, detail: nil)

        XCTAssertTrue(SyncService.userFacingMessage(for: error).contains("SYNC-500"))
        XCTAssertTrue(SyncService.userFacingMessage(for: error, direction: .download)
            .contains("SYNC-DL-500"))
    }

    /// An expired token is the same instruction either way, so it stays one string.
    @MainActor
    func test401TellsTheUserToSignInAgainInBothDirections() {
        let error = SyncService.SyncError.requestFailed(status: 401, detail: nil)

        for direction in [SyncService.Direction.upload, .download] {
            XCTAssertTrue(
                SyncService.userFacingMessage(for: error, direction: direction)
                    .contains("Sign out and back in")
            )
        }
    }
}
