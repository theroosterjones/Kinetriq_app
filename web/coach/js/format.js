/**
 * Formatting shared with the iOS app. Where a rule exists in Swift, this is a port of
 * it and the Swift version is the original.
 */

/**
 * Port of `TempoDurationFormatter.seconds`.
 *
 * All four tempo slots round up only at 0.6 s or more, so a 2.5 s eccentric reads as
 * 2 and a 2.6 s eccentric reads as 3. A coach comparing a tempo on the dashboard with
 * the same tempo on the phone has to see the same four digits.
 */
const ROUND_UP_FRACTION = 0.6;
const TOLERANCE = 1e-9;

export function tempoSeconds(duration) {
  if (!Number.isFinite(duration)) return 0;
  const value = Math.max(0, duration);
  const whole = Math.floor(value);
  const fraction = value - whole;
  return whole + (fraction >= ROUND_UP_FRACTION - TOLERANCE ? 1 : 0);
}

export function tempoString(eccentric, pauseBottom, concentric, pauseTop) {
  return [eccentric, pauseBottom, concentric, pauseTop].map(tempoSeconds).join("-");
}

/** Average tempo across a set, formatted like the per-rep strings. Null when repless. */
export function averageTempo(reps) {
  if (!reps || reps.length === 0) return null;
  const n = reps.length;
  const mean = (key) => reps.reduce((sum, rep) => sum + (Number(rep[key]) || 0), 0) / n;
  return tempoString(
    mean("eccentric_seconds"),
    mean("pause_bottom_seconds"),
    mean("concentric_seconds"),
    mean("pause_top_seconds"),
  );
}

/** Port of `KColor.score`: 80+ good, 60–79 fair, below 60 poor. */
export function scoreTone(score) {
  if (score === null || score === undefined) return "none";
  if (score >= 80) return "good";
  if (score >= 60) return "fair";
  return "poor";
}

export function parseDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function formatDate(date) {
  if (!date) return "—";
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

export function formatDateTime(date) {
  if (!date) return "—";
  return date.toLocaleString(undefined, {
    year: "numeric", month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  });
}

/** "Today", "1d", "12d" — the compact form the app's adherence tile uses. */
export function relativeDays(days) {
  if (days === null || days === undefined) return "—";
  if (days <= 0) return "Today";
  if (days === 1) return "1d";
  return `${days}d`;
}

export function formatNumber(value, places = 1) {
  if (value === null || value === undefined || !Number.isFinite(Number(value))) return "—";
  return Number(value).toFixed(places);
}

export function formatDegrees(value, places = 0) {
  if (value === null || value === undefined || !Number.isFinite(Number(value))) return "—";
  return `${Number(value).toFixed(places)}°`;
}

export function formatPercent(rate) {
  if (rate === null || rate === undefined || !Number.isFinite(Number(rate))) return "—";
  return `${Math.round(Number(rate) * 100)}%`;
}

export function pluralize(count, singular, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`;
}
