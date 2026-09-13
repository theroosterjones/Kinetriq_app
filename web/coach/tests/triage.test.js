import { test } from "node:test";
import assert from "node:assert/strict";

import {
  REASON, QUIET_THRESHOLD_DAYS, SCORE_CHANGE_THRESHOLD,
  reasonFor, reasonLabel, needsAttention, sortClients, attentionCount,
  daysSinceLastSession, scoreDelta,
} from "../js/triage.js";

const NOW = new Date("2026-09-11T12:00:00Z");

function daysAgo(days) {
  return new Date(NOW.getTime() - days * 86_400_000);
}

function client(overrides = {}) {
  return {
    clientUserID: overrides.clientUserID || "id",
    displayName: "Client",
    status: "active",
    linkedAt: daysAgo(60),
    lastSessionAt: daysAgo(1),
    sessionsLast14Days: 4,
    latestScore: 80,
    previousScore: 80,
    latestMovement: "Squat",
    openAsymmetryFlag: false,
    ...overrides,
  };
}

// These values are duplicated from CoachTriage / TrendInsights on purpose (the roster
// RPC returns signals, not a verdict). If either side moves, the two surfaces start
// disagreeing about who needs attention, so pin them.
test("thresholds match the iOS constants", () => {
  assert.equal(QUIET_THRESHOLD_DAYS, 10);
  assert.equal(SCORE_CHANGE_THRESHOLD, 5);
});

test("a client with no sessions has never started", () => {
  const reason = reasonFor(client({ lastSessionAt: null }), NOW);
  assert.equal(reason.kind, REASON.neverStarted);
  assert.equal(reasonLabel(reason), "Hasn't started");
  assert.ok(needsAttention(reason));
});

test("quiet only past the threshold, and the boundary counts as quiet", () => {
  assert.equal(reasonFor(client({ lastSessionAt: daysAgo(9) }), NOW).kind, REASON.steady);
  const reason = reasonFor(client({ lastSessionAt: daysAgo(10) }), NOW);
  assert.equal(reason.kind, REASON.wentQuiet);
  assert.equal(reasonLabel(reason), "Quiet 10 days");
});

test("going quiet outranks a falling score", () => {
  const reason = reasonFor(
    client({ lastSessionAt: daysAgo(20), latestScore: 50, previousScore: 90 }),
    NOW,
  );
  assert.equal(reason.kind, REASON.wentQuiet);
});

test("score changes inside the noise band are steady", () => {
  assert.equal(reasonFor(client({ latestScore: 76, previousScore: 80 }), NOW).kind, REASON.steady);
  assert.equal(reasonFor(client({ latestScore: 84, previousScore: 80 }), NOW).kind, REASON.steady);
});

test("a drop of exactly the threshold is a drop", () => {
  const reason = reasonFor(client({ latestScore: 75, previousScore: 80 }), NOW);
  assert.equal(reason.kind, REASON.scoreDropping);
  assert.equal(reasonLabel(reason), "Down 5 pts");
});

test("a falling score outranks an asymmetry flag", () => {
  const reason = reasonFor(
    client({ latestScore: 60, previousScore: 80, openAsymmetryFlag: true }),
    NOW,
  );
  assert.equal(reason.kind, REASON.scoreDropping);
});

test("asymmetry surfaces when nothing worse is happening", () => {
  const reason = reasonFor(client({ openAsymmetryFlag: true }), NOW);
  assert.equal(reason.kind, REASON.newAsymmetry);
  assert.ok(needsAttention(reason));
});

test("improving is reported but is not an attention item", () => {
  const reason = reasonFor(client({ latestScore: 90, previousScore: 80 }), NOW);
  assert.equal(reason.kind, REASON.improving);
  assert.equal(reasonLabel(reason), "Up 10 pts");
  assert.equal(needsAttention(reason), false);
});

test("a single scored session cannot produce a delta", () => {
  assert.equal(scoreDelta(client({ previousScore: null })), null);
  assert.equal(reasonFor(client({ previousScore: null }), NOW).kind, REASON.steady);
});

test("days since last session floors to whole days", () => {
  assert.equal(daysSinceLastSession(client({ lastSessionAt: NOW }), NOW), 0);
  assert.equal(
    daysSinceLastSession(client({ lastSessionAt: new Date(NOW.getTime() - 47 * 3_600_000) }), NOW),
    1,
  );
  assert.equal(daysSinceLastSession(client({ lastSessionAt: null }), NOW), null);
});

test("the queue is worst first, most severe within a bucket, then alphabetical", () => {
  const clients = [
    client({ clientUserID: "steady", displayName: "Zoe" }),
    client({ clientUserID: "quiet-12", displayName: "Bo", lastSessionAt: daysAgo(12) }),
    client({ clientUserID: "never", displayName: "Ada", lastSessionAt: null }),
    client({ clientUserID: "quiet-30", displayName: "Cy", lastSessionAt: daysAgo(30) }),
    client({ clientUserID: "asym", displayName: "Dee", openAsymmetryFlag: true }),
    client({ clientUserID: "dropping", displayName: "Eli", latestScore: 60, previousScore: 80 }),
    client({ clientUserID: "improving", displayName: "Fay", latestScore: 92, previousScore: 80 }),
  ];

  assert.deepEqual(
    sortClients(clients, NOW).map((entry) => entry.clientUserID),
    ["never", "quiet-30", "quiet-12", "dropping", "asym", "improving", "steady"],
  );
});

test("ties inside a bucket sort by name, case-insensitively", () => {
  const clients = [
    client({ clientUserID: "b", displayName: "bravo" }),
    client({ clientUserID: "a", displayName: "Alpha" }),
    client({ clientUserID: "c", displayName: "Charlie" }),
  ];
  assert.deepEqual(sortClients(clients, NOW).map((entry) => entry.clientUserID), ["a", "b", "c"]);
});

test("sorting does not mutate the roster it was handed", () => {
  const clients = [
    client({ clientUserID: "steady", displayName: "Zoe" }),
    client({ clientUserID: "never", displayName: "Ada", lastSessionAt: null }),
  ];
  const before = clients.map((entry) => entry.clientUserID);
  sortClients(clients, NOW);
  assert.deepEqual(clients.map((entry) => entry.clientUserID), before);
});

test("attention count ignores the clients who are fine", () => {
  const clients = [
    client({ clientUserID: "1", lastSessionAt: null }),
    client({ clientUserID: "2", openAsymmetryFlag: true }),
    client({ clientUserID: "3" }),
    client({ clientUserID: "4", latestScore: 95, previousScore: 80 }),
  ];
  assert.equal(attentionCount(clients, NOW), 2);
});
