/**
 * Port of `CoachTriage` in Sources/Services/CoachService.swift.
 *
 * The thresholds and the ordering are duplicated rather than fetched, because
 * `coach_roster()` deliberately returns signals and not a verdict — the phone sorts
 * client-side too. That means these numbers have to be kept in step by hand: a coach
 * looking at the same roster on both devices must see the same client at the top, or
 * neither reading is trustworthy. `tests/triage.test.js` pins the behaviour, and any
 * change here needs the matching change in `CoachTriage` and in `CoachTriageTests`.
 */

/** No session in this long and the client has effectively stopped. */
export const QUIET_THRESHOLD_DAYS = 10;

/** Score swings smaller than this are session-to-session noise (TrendInsights). */
export const SCORE_CHANGE_THRESHOLD = 5;

export const REASON = {
  neverStarted: "neverStarted",
  wentQuiet: "wentQuiet",
  scoreDropping: "scoreDropping",
  newAsymmetry: "newAsymmetry",
  improving: "improving",
  steady: "steady",
};

const RANK = {
  [REASON.neverStarted]: 0,
  [REASON.wentQuiet]: 1,
  [REASON.scoreDropping]: 2,
  [REASON.newAsymmetry]: 3,
  [REASON.improving]: 4,
  [REASON.steady]: 5,
};

const ATTENTION = new Set([
  REASON.neverStarted,
  REASON.wentQuiet,
  REASON.scoreDropping,
  REASON.newAsymmetry,
]);

/**
 * @typedef {{clientUserID: string, displayName: string, status: string,
 *            linkedAt: Date|null, lastSessionAt: Date|null, sessionsLast14Days: number,
 *            latestScore: number|null, previousScore: number|null,
 *            latestMovement: string|null, openAsymmetryFlag: boolean}} Client
 */

/** Whole days between the last session and now, floored, matching the iOS calculation. */
export function daysSinceLastSession(client, now = new Date()) {
  if (!client.lastSessionAt) return null;
  const ms = now.getTime() - client.lastSessionAt.getTime();
  return Math.floor(ms / 86_400_000);
}

export function scoreDelta(client) {
  if (client.latestScore === null || client.latestScore === undefined) return null;
  if (client.previousScore === null || client.previousScore === undefined) return null;
  return client.latestScore - client.previousScore;
}

/** @returns {{kind: string, value?: number}} */
export function reasonFor(client, now = new Date()) {
  if (!client.lastSessionAt) return { kind: REASON.neverStarted };

  const days = daysSinceLastSession(client, now);
  if (days !== null && days >= QUIET_THRESHOLD_DAYS) {
    return { kind: REASON.wentQuiet, value: days };
  }

  const delta = scoreDelta(client);
  if (delta !== null && delta <= -SCORE_CHANGE_THRESHOLD) {
    return { kind: REASON.scoreDropping, value: Math.abs(delta) };
  }
  if (client.openAsymmetryFlag) {
    return { kind: REASON.newAsymmetry };
  }
  if (delta !== null && delta >= SCORE_CHANGE_THRESHOLD) {
    return { kind: REASON.improving, value: delta };
  }
  return { kind: REASON.steady };
}

export function reasonLabel(reason) {
  switch (reason.kind) {
    case REASON.neverStarted: return "Hasn't started";
    case REASON.wentQuiet: return `Quiet ${reason.value} days`;
    case REASON.scoreDropping: return `Down ${reason.value} pts`;
    case REASON.newAsymmetry: return "Asymmetry flagged";
    case REASON.improving: return `Up ${reason.value} pts`;
    default: return "On track";
  }
}

export function needsAttention(reason) {
  return ATTENTION.has(reason.kind);
}

/**
 * Worst first, then most severe within a bucket, then alphabetically so the order is
 * stable between refreshes.
 */
export function sortClients(clients, now = new Date()) {
  return [...clients].sort((a, b) => {
    const ra = reasonFor(a, now);
    const rb = reasonFor(b, now);
    if (RANK[ra.kind] !== RANK[rb.kind]) return RANK[ra.kind] - RANK[rb.kind];

    if (ra.kind === rb.kind && (ra.kind === REASON.wentQuiet || ra.kind === REASON.scoreDropping)) {
      if (ra.value !== rb.value) return rb.value - ra.value;
    }
    return a.displayName.localeCompare(b.displayName, undefined, { sensitivity: "base" });
  });
}

export function attentionCount(clients, now = new Date()) {
  return clients.filter((client) => needsAttention(reasonFor(client, now))).length;
}
