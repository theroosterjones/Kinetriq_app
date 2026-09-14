/**
 * CSV export, byte-for-byte compatible with `CSVExporter` in
 * Sources/Services/CSVExporter.swift — same column names, same order, same RFC 4180
 * escaping, same CRLF line endings, same UTF-8 BOM so Excel doesn't mangle the degree
 * signs. A coach who exports one client from the browser and another from the phone
 * has to be able to paste both into the same spreadsheet.
 */

import { averageTempo, tempoString } from "./format.js";

export const SESSION_HEADER = [
  "record_id", "date", "kind", "movement", "side", "plane", "source",
  "duration_seconds", "pose_detection_rate",
  "total_reps", "score", "mean_peak_angle_deg",
  "mean_eccentric_seconds", "mean_concentric_seconds", "average_tempo",
  "grade", "left_rom_deg", "right_rom_deg", "asymmetry_deg", "asymmetry_flag",
  "coaching_notes",
];

export const REP_HEADER = [
  "record_id", "date", "movement", "side", "rep_number",
  "peak_flexion_angle_deg", "tempo",
  "eccentric_seconds", "pause_bottom_seconds",
  "concentric_seconds", "pause_top_seconds",
];

/** Wrap in quotes when the value contains a comma, quote, or newline; double quotes. */
export function escape(value) {
  const text = value === null || value === undefined ? "" : String(value);
  if (!/[",\r\n]/.test(text)) return text;
  return `"${text.replaceAll('"', '""')}"`;
}

export function csvString(rows) {
  return rows.map((row) => row.map(escape).join(",")).join("\r\n");
}

function fixed(value, places) {
  const number = Number(value);
  if (value === null || value === undefined || !Number.isFinite(number)) return "";
  return number.toFixed(places);
}

function iso(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return "";
  // Second precision without fractional digits, matching ISO8601DateFormatter with
  // `.withInternetDateTime`.
  return `${date.toISOString().split(".")[0]}Z`;
}

/** @param {object[]} records rows straight from `analysis_records`, reps embedded */
export function sessionRows(records) {
  const rows = [SESSION_HEADER];
  // Oldest first reads better in a spreadsheet than the newest-first roster order.
  for (const record of [...records].sort((a, b) => new Date(a.recorded_at) - new Date(b.recorded_at))) {
    const isExercise = (record.kind || "exercise") === "exercise";
    rows.push([
      record.id || "",
      iso(record.recorded_at),
      record.kind || "",
      record.movement_name || record.movement_key || "",
      record.side || "",
      record.plane || "",
      record.source || "",
      fixed(record.duration_seconds, 2),
      fixed(record.pose_detection_rate, 4),
      isExercise ? String(record.total_reps ?? 0) : "",
      record.score === null || record.score === undefined ? "" : String(record.score),
      fixed(record.mean_peak_angle_deg, 1),
      fixed(record.mean_eccentric_seconds, 2),
      fixed(record.mean_concentric_seconds, 2),
      averageTempo(record.analysis_reps) || "",
      record.grade || "",
      fixed(record.left_rom_deg, 1),
      fixed(record.right_rom_deg, 1),
      fixed(record.asymmetry_deg, 1),
      isExercise ? "" : record.asymmetry_flag ? "true" : "false",
      (record.insights || []).join(" | "),
    ]);
  }
  return rows;
}

export function repRows(records) {
  const rows = [REP_HEADER];
  const exercises = records
    .filter((r) => (r.kind || "exercise") === "exercise" && (r.analysis_reps || []).length > 0)
    .sort((a, b) => new Date(a.recorded_at) - new Date(b.recorded_at));

  for (const record of exercises) {
    const reps = [...record.analysis_reps].sort((a, b) => a.rep_number - b.rep_number);
    for (const rep of reps) {
      rows.push([
        record.id || "",
        iso(record.recorded_at),
        record.movement_name || record.movement_key || "",
        record.side || "",
        String(rep.rep_number),
        fixed(rep.peak_flexion_angle_deg, 1),
        tempoString(
          rep.eccentric_seconds || 0,
          rep.pause_bottom_seconds || 0,
          rep.concentric_seconds || 0,
          rep.pause_top_seconds || 0,
        ),
        fixed(rep.eccentric_seconds, 2),
        fixed(rep.pause_bottom_seconds, 2),
        fixed(rep.concentric_seconds, 2),
        fixed(rep.pause_top_seconds, 2),
      ]);
    }
  }
  return rows;
}

export function sanitizeFileName(name) {
  const cleaned = String(name || "")
    .replace(/[^A-Za-z0-9\-_]+/g, "-")
    .split("-")
    .filter(Boolean)
    .join("-")
    .toLowerCase();
  return cleaned || "kinetriq-export";
}

/** Triggers a browser download. The BOM is what makes Excel read UTF-8 correctly. */
export function download(rows, fileNameHint) {
  const blob = new Blob(["\uFEFF", csvString(rows)], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `${sanitizeFileName(fileNameHint)}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  // Give Safari a moment to start the download before the blob goes away.
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
