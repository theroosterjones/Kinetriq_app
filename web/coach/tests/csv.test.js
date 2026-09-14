import { test } from "node:test";
import assert from "node:assert/strict";

import {
  escape, csvString, sessionRows, repRows, sanitizeFileName,
  SESSION_HEADER, REP_HEADER,
} from "../js/csv.js";

// The headers are duplicated from CSVExporter so a coach can paste a browser export
// and a phone export into the same sheet. If they drift, that silently stops working.
test("headers match the iOS exporter", () => {
  assert.deepEqual(SESSION_HEADER.slice(0, 7), [
    "record_id", "date", "kind", "movement", "side", "plane", "source",
  ]);
  assert.equal(SESSION_HEADER.at(-1), "coaching_notes");
  assert.equal(SESSION_HEADER.length, 21);
  assert.equal(REP_HEADER.length, 11);
});

test("only values that need quoting get quoted", () => {
  assert.equal(escape("Squat"), "Squat");
  assert.equal(escape("Depth fell, tempo held"), '"Depth fell, tempo held"');
  assert.equal(escape('say "deep"'), '"say ""deep"""');
  assert.equal(escape("line\nbreak"), '"line\nbreak"');
  assert.equal(escape("carriage\rreturn"), '"carriage\rreturn"');
});

// This is the bug that shipped in the Swift version: a CRLF is one grapheme cluster in
// Swift and matched neither "\r" nor "\n", so a Windows line break went out unquoted
// and split the row. JS strings are UTF-16 code units so the regex is safe, but the
// case is worth pinning on both sides.
test("a CRLF forces quoting", () => {
  assert.equal(escape("windows\r\nbreak"), '"windows\r\nbreak"');
});

test("rows join with CRLF", () => {
  assert.equal(csvString([["a", "b"], ["c", "d"]]), "a,b\r\nc,d");
});

test("empty and missing values become empty fields, never the word undefined", () => {
  assert.equal(escape(null), "");
  assert.equal(escape(undefined), "");
});

const exerciseRecord = {
  id: "11111111-1111-1111-1111-111111111111",
  recorded_at: "2026-09-01T14:32:11.482913+00:00",
  kind: "exercise",
  movement_name: "Squat",
  movement_key: "Squat",
  side: "right",
  plane: null,
  source: "liveCamera",
  duration_seconds: 41.5,
  pose_detection_rate: 0.9412,
  total_reps: 2,
  score: 82,
  mean_peak_angle_deg: 88.42,
  mean_eccentric_seconds: 2.1,
  mean_concentric_seconds: 1.4,
  grade: null,
  left_rom_deg: null,
  right_rom_deg: null,
  asymmetry_deg: null,
  asymmetry_flag: false,
  insights: ["Depth held", "Tempo slowed, likely fatigue"],
  analysis_reps: [
    { rep_number: 2, peak_flexion_angle_deg: 90.0, eccentric_seconds: 3.2, pause_bottom_seconds: 0.4, concentric_seconds: 1.7, pause_top_seconds: 0.6 },
    { rep_number: 1, peak_flexion_angle_deg: 86.84, eccentric_seconds: 2.0, pause_bottom_seconds: 0.2, concentric_seconds: 1.3, pause_top_seconds: 0.5 },
  ],
};

const assessmentRecord = {
  id: "22222222-2222-2222-2222-222222222222",
  recorded_at: "2026-08-14T09:00:00Z",
  kind: "assessment",
  movement_name: "Shoulder Flexion",
  side: "left",
  plane: "frontal",
  source: "savedVideo",
  duration_seconds: 12,
  pose_detection_rate: 0.88,
  total_reps: 0,
  score: null,
  grade: "B",
  left_rom_deg: 158,
  right_rom_deg: 171,
  asymmetry_deg: 13,
  asymmetry_flag: true,
  details: ["Left side lagged"],
  analysis_reps: [],
};

test("session rows are oldest first and shaped like the iOS export", () => {
  const rows = sessionRows([exerciseRecord, assessmentRecord]);

  assert.deepEqual(rows[0], SESSION_HEADER);
  assert.equal(rows.length, 3);
  assert.equal(rows[1][0], assessmentRecord.id, "oldest session comes first");

  const exercise = rows[2];
  assert.equal(exercise[1], "2026-09-01T14:32:11Z", "seconds precision, no fraction");
  assert.equal(exercise[7], "41.50");
  assert.equal(exercise[8], "0.9412");
  assert.equal(exercise[9], "2");
  assert.equal(exercise[10], "82");
  assert.equal(exercise[11], "88.4");
  // Means are 2.6 / 0.3 / 1.5 / 0.55. Rounding each rep first and then averaging
  // would give 3-0-2-1 — the per-rep value of rep 2 — which is a different number.
  assert.equal(exercise[14], "3-0-1-0", "average tempo, averaged before rounding");
  assert.equal(exercise[19], "", "asymmetry_flag is blank on an exercise row");
  assert.equal(exercise[20], "Depth held | Tempo slowed, likely fatigue");
});

test("assessment columns fill in and exercise columns stay blank", () => {
  const assessment = sessionRows([assessmentRecord])[1];
  assert.equal(assessment[9], "", "no rep count on an assessment");
  assert.equal(assessment[15], "B");
  assert.equal(assessment[16], "158.0");
  assert.equal(assessment[18], "13.0");
  assert.equal(assessment[19], "true");
});

test("a note containing a comma survives the round trip quoted", () => {
  const csv = csvString(sessionRows([exerciseRecord]));
  assert.ok(csv.includes('"Depth held | Tempo slowed, likely fatigue"'));
});

test("rep rows are sorted by rep number and skip records without reps", () => {
  const rows = repRows([exerciseRecord, assessmentRecord]);
  assert.deepEqual(rows[0], REP_HEADER);
  assert.equal(rows.length, 3, "two reps, and nothing from the assessment");
  assert.equal(rows[1][4], "1");
  assert.equal(rows[2][4], "2");
  assert.equal(rows[1][5], "86.8");
  assert.equal(rows[2][6], "3-0-2-1");
});

test("an unmeasured peak angle exports as blank, not as zero", () => {
  const rows = repRows([{
    ...exerciseRecord,
    analysis_reps: [{ rep_number: 1, peak_flexion_angle_deg: null, eccentric_seconds: 1, pause_bottom_seconds: 0, concentric_seconds: 1, pause_top_seconds: 0 }],
  }]);
  assert.equal(rows[1][5], "");
});

test("file names are safe and never empty", () => {
  assert.equal(sanitizeFileName("Kinetriq — Jamie's Squat!"), "kinetriq-jamie-s-squat");
  assert.equal(sanitizeFileName("../../etc/passwd"), "etc-passwd");
  assert.equal(sanitizeFileName("!!!"), "kinetriq-export");
  assert.equal(sanitizeFileName(""), "kinetriq-export");
});
