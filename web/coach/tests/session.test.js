import { test } from "node:test";
import assert from "node:assert/strict";

import {
  makeStore, fromTokenResponse, isExpired, needsRefresh, isUsable,
  REFRESH_MARGIN_SECONDS,
} from "../js/session.js";

function memoryStorage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => map.set(key, value),
    removeItem: (key) => map.delete(key),
    size: () => map.size,
  };
}

test("a session round-trips through storage", () => {
  const storage = memoryStorage();
  const store = makeStore(storage);
  const session = { accessToken: "a", refreshToken: "r", expiresAt: 100, user: { id: "u", email: "e" } };

  store.save(session);
  assert.deepEqual(store.load(), session);

  store.clear();
  assert.equal(store.load(), null);
});

test("unreadable or corrupt storage reads as signed out rather than throwing", () => {
  assert.equal(makeStore(memoryStorage({ "kinetriq.coach.session": "{not json" })).load(), null);
  assert.equal(makeStore(memoryStorage({ "kinetriq.coach.session": "{}" })).load(), null);

  const hostile = {
    getItem() { throw new Error("Safari private mode"); },
    setItem() { throw new Error("nope"); },
    removeItem() { throw new Error("nope"); },
  };
  const store = makeStore(hostile);
  assert.equal(store.load(), null);
  // Saving must not throw either; the session stays in memory for the tab.
  assert.doesNotThrow(() => store.save({ accessToken: "a" }));
  assert.doesNotThrow(() => store.clear());
});

test("expires_in becomes an absolute expiry", () => {
  const before = Math.floor(Date.now() / 1000);
  const session = fromTokenResponse({ access_token: "a", refresh_token: "r", expires_in: 3600 });
  assert.ok(session.expiresAt >= before + 3600);
  assert.ok(session.expiresAt <= before + 3601);
});

test("an explicit expires_at wins over expires_in", () => {
  const session = fromTokenResponse({ access_token: "a", expires_in: 60, expires_at: 999 });
  assert.equal(session.expiresAt, 999);
});

// A refresh_token grant returns no user object. Losing the id here would break every
// query that filters on it.
test("a refresh keeps the user and the refresh token when the response omits them", () => {
  const previous = { accessToken: "old", refreshToken: "r1", expiresAt: 1, user: { id: "u", email: "e" } };
  const session = fromTokenResponse({ access_token: "new", expires_in: 3600 }, previous);

  assert.equal(session.accessToken, "new");
  assert.equal(session.refreshToken, "r1");
  assert.deepEqual(session.user, { id: "u", email: "e" });
});

test("a rotated refresh token replaces the old one", () => {
  const previous = { accessToken: "old", refreshToken: "r1", expiresAt: 1, user: null };
  assert.equal(fromTokenResponse({ access_token: "n", refresh_token: "r2" }, previous).refreshToken, "r2");
});

test("expiry is read from the absolute timestamp", () => {
  const now = Date.UTC(2026, 8, 11, 12, 0, 0);
  const at = (offsetSeconds) => ({ accessToken: "a", expiresAt: Math.floor(now / 1000) + offsetSeconds });

  assert.equal(isExpired(at(60), now), false);
  assert.equal(isExpired(at(-1), now), true);
  assert.equal(isExpired({ accessToken: "a", expiresAt: null }, now), false);
});

test("refresh happens ahead of expiry, not at it", () => {
  const now = Date.UTC(2026, 8, 11, 12, 0, 0);
  const at = (offsetSeconds) => ({ accessToken: "a", expiresAt: Math.floor(now / 1000) + offsetSeconds });

  assert.equal(needsRefresh(at(REFRESH_MARGIN_SECONDS + 30), now), false);
  assert.equal(needsRefresh(at(REFRESH_MARGIN_SECONDS - 1), now), true);
  assert.equal(needsRefresh(at(-100), now), true);
});

// The 3.5.2 lesson: an expired access token is not a signed-out user while a refresh
// token exists. Treating it as one signed everybody out on every launch.
test("an expired session with a refresh token is still usable", () => {
  const expired = { accessToken: "a", refreshToken: "r", expiresAt: 1 };
  assert.equal(isUsable(expired), true);

  assert.equal(isUsable({ accessToken: "a", refreshToken: null, expiresAt: 1 }), false);
  assert.equal(isUsable({ accessToken: "a", refreshToken: null, expiresAt: null }), true);
  assert.equal(isUsable(null), false);
  assert.equal(isUsable({ refreshToken: "r" }), false);
});
