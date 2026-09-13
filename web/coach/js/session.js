/**
 * Session persistence.
 *
 * Mirrors `AuthSession` in Sources/Models/UserProfile.swift, including the rule that
 * a session carrying a refresh token counts as still-authenticated even after the
 * access token has expired — the iOS app learned that the hard way in 3.5.2, when
 * users were signed out on every launch because the refresh token was stored and
 * never used.
 */

const STORAGE_KEY = "kinetriq.coach.session";

/** Refresh this far ahead of expiry so an in-flight request can't land on a dead token. */
export const REFRESH_MARGIN_SECONDS = 120;

/**
 * @typedef {{accessToken: string, refreshToken: string|null, expiresAt: number|null,
 *            user: {id: string, email: string}|null}} StoredSession
 */

export function makeStore(storage = globalThis.localStorage) {
  return {
    /** @returns {StoredSession|null} */
    load() {
      try {
        const raw = storage?.getItem(STORAGE_KEY);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        return parsed && typeof parsed.accessToken === "string" ? parsed : null;
      } catch {
        // Corrupt or unreadable (private-mode Safari throws on access) — treat as
        // signed out rather than breaking the whole app on boot.
        return null;
      }
    },

    /** @param {StoredSession} session */
    save(session) {
      try {
        storage?.setItem(STORAGE_KEY, JSON.stringify(session));
      } catch {
        // Non-fatal: the session stays in memory for this tab.
      }
      return session;
    },

    clear() {
      try {
        storage?.removeItem(STORAGE_KEY);
      } catch {
        /* ignore */
      }
    },
  };
}

/** Builds a stored session from a GoTrue token response. */
export function fromTokenResponse(payload, previous = null) {
  const expiresAt =
    typeof payload.expires_at === "number"
      ? payload.expires_at
      : typeof payload.expires_in === "number"
        ? Math.floor(Date.now() / 1000) + payload.expires_in
        : null;

  return {
    accessToken: payload.access_token,
    // A refresh_token response omits the user object; keep whoever we already had.
    refreshToken: payload.refresh_token || previous?.refreshToken || null,
    expiresAt,
    user: payload.user
      ? { id: payload.user.id, email: payload.user.email || "" }
      : previous?.user || null,
  };
}

export function isExpired(session, now = Date.now()) {
  if (!session?.expiresAt) return false;
  return session.expiresAt * 1000 <= now;
}

export function needsRefresh(session, now = Date.now()) {
  if (!session?.expiresAt) return false;
  return session.expiresAt * 1000 - now <= REFRESH_MARGIN_SECONDS * 1000;
}

/**
 * An expired access token is not a signed-out user as long as it can be renewed.
 * Only a refusal from GoTrue ends the session.
 */
export function isUsable(session) {
  if (!session?.accessToken) return false;
  return Boolean(session.refreshToken) || !isExpired(session);
}
