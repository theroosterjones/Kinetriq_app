import { test } from "node:test";
import assert from "node:assert/strict";

import {
  tempoSeconds, tempoString, averageTempo, scoreTone,
  relativeDays, formatDegrees, formatPercent, pluralize, parseDate,
} from "../js/format.js";

// Port of TempoDurationFormatter. The 0.6 rule is a product decision documented in
// AGENTS.md, and a coach comparing a tempo in the browser with the same tempo on the
// phone has to see the same four digits.
test("tempo rounds down below 0.6 and up at 0.6", () => {
  assert.equal(tempoSeconds(2.5), 2);
  assert.equal(tempoSeconds(2.59), 2);
  assert.equal(tempoSeconds(2.6), 3);
  assert.equal(tempoSeconds(3.0), 3);
  assert.equal(tempoSeconds(0.6), 1);
  assert.equal(tempoSeconds(0.59), 0);
});

test("tempo clamps nonsense inputs instead of printing them", () => {
  assert.equal(tempoSeconds(-4), 0);
  assert.equal(tempoSeconds(Number.NaN), 0);
  assert.equal(tempoSeconds(Number.POSITIVE_INFINITY), 0);
});

test("floating-point representation does not lose a boundary value", () => {
  // 0.1 + 0.5 is 0.6 only within tolerance, which is why the Swift original carries a
  // comparison epsilon and this port does too.
  assert.equal(tempoSeconds(0.1 + 0.5), 1);
});

test("tempo strings are four dash-separated whole seconds", () => {
  assert.equal(tempoString(3.2, 0.4, 1.7, 0.6), "3-0-2-1");
});

test("average tempo averages before rounding, and is null without reps", () => {
  assert.equal(averageTempo([]), null);
  assert.equal(averageTempo(null), null);
  assert.equal(
    averageTempo([
      { eccentric_seconds: 2.0, pause_bottom_seconds: 0, concentric_seconds: 1.0, pause_top_seconds: 0 },
      { eccentric_seconds: 3.2, pause_bottom_seconds: 0, concentric_seconds: 1.0, pause_top_seconds: 0 },
    ]),
    // mean eccentric is 2.6, which rounds up; rounding each rep first would give 2.
    "3-0-1-0",
  );
});

test("score tone matches the KColor.score ramp", () => {
  assert.equal(scoreTone(100), "good");
  assert.equal(scoreTone(80), "good");
  assert.equal(scoreTone(79), "fair");
  assert.equal(scoreTone(60), "fair");
  assert.equal(scoreTone(59), "poor");
  assert.equal(scoreTone(null), "none");
});

test("relative days reads the way the adherence tile does", () => {
  assert.equal(relativeDays(0), "Today");
  assert.equal(relativeDays(1), "1d");
  assert.equal(relativeDays(14), "14d");
  assert.equal(relativeDays(null), "—");
});

test("missing measurements render as an em dash, not as zero", () => {
  assert.equal(formatDegrees(null), "—");
  assert.equal(formatDegrees(undefined), "—");
  assert.equal(formatDegrees(88.4, 1), "88.4°");
  assert.equal(formatPercent(null), "—");
  assert.equal(formatPercent(0.94), "94%");
  // A real zero still has to print, because 0% tracking is a meaningful reading.
  assert.equal(formatPercent(0), "0%");
  assert.equal(formatDegrees(0), "0°");
});

test("pluralize", () => {
  assert.equal(pluralize(1, "session"), "1 session");
  assert.equal(pluralize(0, "session"), "0 sessions");
  assert.equal(pluralize(2, "session"), "2 sessions");
});

test("Postgres microsecond timestamps parse", () => {
  const date = parseDate("2026-09-01T14:32:11.482913+00:00");
  assert.ok(date instanceof Date);
  assert.equal(date.toISOString(), "2026-09-01T14:32:11.482Z");
  assert.equal(parseDate(null), null);
  assert.equal(parseDate("not a date"), null);
});
