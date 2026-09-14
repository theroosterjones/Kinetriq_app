/**
 * Supabase transport: GoTrue for auth, PostgREST for data.
 *
 * Written against the REST APIs directly rather than pulling in supabase-js, for the
 * same reason `AuthService` and `CoachService` do it by hand on iOS: the surface used
 * here is four auth endpoints and three table reads, and hand-rolling it keeps this
 * dashboard a zero-dependency static folder. Nothing to build, nothing to audit, no
 * CDN in the request path for a page that reads other people's health measurements.
 *
 * Every read below is protected server-side by the row-level security in
 * supabase/schema.sql. The dashboard adds an explicit `user_id=eq.` filter on client
 * reads anyway, so a policy change can never quietly widen what a coach sees.
 */

import { config } from "./config.js";
import * as session from "./session.js";

export class ApiError extends Error {
  /** @param {{status?: number, detail?: string, code?: string}} info */
  constructor(message, info = {}) {
    super(message);
    this.name = "ApiError";
    this.status = info.status ?? 0;
    this.detail = info.detail ?? "";
    this.code = info.code ?? "";
  }
}

const store = session.makeStore();
let current = store.load();
let refreshInFlight = null;
const listeners = new Set();

export function currentSession() {
  return current;
}

export function isAuthenticated() {
  return session.isUsable(current);
}

export function onSessionChange(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function setSession(next) {
  current = next;
  if (next) store.save(next);
  else store.clear();
  for (const listener of listeners) listener(next);
  return next;
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

async function authRequest(path, { method = "POST", body, token, query } = {}) {
  const url = new URL(`${config.supabaseUrl}/auth/v1/${path}`);
  for (const [key, value] of Object.entries(query || {})) {
    if (value !== undefined && value !== null) url.searchParams.set(key, value);
  }

  let response;
  try {
    response = await fetch(url, {
      method,
      headers: {
        apikey: config.supabaseAnonKey,
        Authorization: `Bearer ${token || config.supabaseAnonKey}`,
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (cause) {
    throw new ApiError("Network request failed", { code: "NET" });
  }

  const text = await response.text();
  const payload = text ? safeParse(text) : null;

  if (!response.ok) {
    throw new ApiError(
      payload?.error_description || payload?.msg || payload?.message || "Authentication failed",
      {
        status: response.status,
        detail: payload?.error_code || payload?.error || "",
      },
    );
  }
  return payload;
}

function safeParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export async function signInWithPassword(email, password) {
  const payload = await authRequest("token", {
    query: { grant_type: "password" },
    body: { email: email.trim(), password },
  });
  return setSession(session.fromTokenResponse(payload));
}

/**
 * Emails a sign-in link.
 *
 * The important case is a coach who created their account with Sign in with Apple on
 * the phone: they have no password to type here. Apple's private relay forwards the
 * link, so this is the only path that works for them, which is why it is offered as
 * a peer of password sign-in rather than buried under "forgot password".
 *
 * `create_user: false` keeps the dashboard from minting accounts — a coach signs up
 * in the app, where the subscription lives.
 */
export async function sendMagicLink(email) {
  const redirect = `${location.origin}${location.pathname}`;
  await authRequest("otp", {
    query: { redirect_to: redirect },
    body: { email: email.trim(), create_user: false },
  });
}

export async function signOut() {
  const token = current?.accessToken;
  setSession(null);
  if (token) {
    // Best effort. The local session is already gone, which is what the user asked for.
    try {
      await authRequest("logout", { token });
    } catch {
      /* ignore */
    }
  }
}

/**
 * Picks up the tokens GoTrue appends to the redirect URL after a magic link, then
 * strips them from the address bar so a shared or bookmarked URL cannot hand someone
 * else a live session.
 *
 * @returns {Promise<{status: 'signed-in'|'error'|'none', message?: string}>}
 */
export async function captureSessionFromURL() {
  const hash = location.hash.startsWith("#") ? location.hash.slice(1) : location.hash;
  if (!hash.includes("access_token=") && !hash.includes("error=")) return { status: "none" };

  const params = new URLSearchParams(hash);
  const cleanURL = `${location.pathname}${location.search}`;

  if (params.get("error") || params.get("error_description")) {
    history.replaceState(null, "", cleanURL);
    return {
      status: "error",
      message: params.get("error_description") || "That sign-in link is no longer valid.",
    };
  }

  const accessToken = params.get("access_token");
  if (!accessToken) return { status: "none" };

  const expiresIn = Number(params.get("expires_in"));
  setSession(
    session.fromTokenResponse({
      access_token: accessToken,
      refresh_token: params.get("refresh_token") || null,
      expires_in: Number.isFinite(expiresIn) ? expiresIn : undefined,
    }),
  );
  history.replaceState(null, "", cleanURL);

  // The hash carries tokens but no user, and the roster needs the id.
  try {
    const user = await authRequest("user", { method: "GET", token: accessToken });
    setSession({ ...current, user: { id: user.id, email: user.email || "" } });
  } catch (error) {
    setSession(null);
    return { status: "error", message: "Signed in, but the account could not be loaded." };
  }

  return { status: "signed-in" };
}

/** Restores an existing session on boot, renewing the access token if it is stale. */
export async function bootstrapSession() {
  if (!current) return null;
  if (!session.isUsable(current)) return setSession(null);
  if (session.needsRefresh(current)) await refreshSession();
  return current;
}

async function refreshSession() {
  if (!current?.refreshToken) return current;
  if (refreshInFlight) return refreshInFlight;

  refreshInFlight = (async () => {
    try {
      const payload = await authRequest("token", {
        query: { grant_type: "refresh_token" },
        body: { refresh_token: current.refreshToken },
      });
      return setSession(session.fromTokenResponse(payload, current));
    } catch (error) {
      // Only a definitive rejection ends the session. Offline or a 5xx must not sign
      // a coach out mid-review — same rule as AuthService.refreshSessionIfNeeded.
      if (error instanceof ApiError && error.status >= 400 && error.status < 500) {
        setSession(null);
      }
      throw error;
    } finally {
      refreshInFlight = null;
    }
  })();

  return refreshInFlight;
}

async function accessToken() {
  if (!current) throw new ApiError("Not signed in", { status: 401 });
  if (session.needsRefresh(current)) {
    try {
      await refreshSession();
    } catch {
      // Fall through with the token we have; a 401 below is handled by the caller.
    }
  }
  return current?.accessToken;
}

// ---------------------------------------------------------------------------
// PostgREST
// ---------------------------------------------------------------------------

async function restRequest(path, { method = "GET", body, query, prefer } = {}) {
  const token = await accessToken();
  const url = new URL(`${config.supabaseUrl}/rest/v1/${path}`);
  for (const [key, value] of Object.entries(query || {})) {
    if (value !== undefined && value !== null) url.searchParams.set(key, value);
  }

  let response;
  try {
    response = await fetch(url, {
      method,
      headers: {
        apikey: config.supabaseAnonKey,
        Authorization: `Bearer ${token}`,
        ...(body ? { "Content-Type": "application/json" } : {}),
        ...(prefer ? { Prefer: prefer } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError("Network request failed", { code: "NET" });
  }

  const text = await response.text();
  const payload = text ? safeParse(text) : null;

  if (!response.ok) {
    throw new ApiError(payload?.message || "Request failed", {
      status: response.status,
      // Postgres `raise exception 'CLIENT_LIMIT_REACHED'` lands in `message`; the
      // caller matches on these names.
      detail: payload?.message || payload?.details || "",
      code: payload?.code || "",
    });
  }
  return payload;
}

export function rpc(fn, args = {}) {
  return restRequest(`rpc/${fn}`, { method: "POST", body: args });
}

export function select(table, query) {
  return restRequest(table, { method: "GET", query });
}

export function remove(table, query) {
  return restRequest(table, { method: "DELETE", query, prefer: "return=minimal" });
}

/**
 * Plain-language message plus a short reference code, matching
 * `CoachService.userFacingMessage(for:)` so a coach reporting a problem quotes the
 * same code whichever device they were on.
 */
export function userFacingMessage(error) {
  if (!(error instanceof ApiError)) {
    return { message: "Something went wrong. Please try again.", code: "COACH-UNKNOWN" };
  }
  if (error.code === "NET") {
    return {
      message: "You appear to be offline. Check your connection and try again.",
      code: "NET-0",
    };
  }

  const detail = `${error.detail} ${error.message}`;
  const named = [
    ["INVITE_NOT_FOUND", "That code doesn't match an invite. Check for typos and try again.", "COACH-INVITE-404"],
    ["INVITE_ALREADY_USED", "That invite has already been used. Create a new one.", "COACH-INVITE-USED"],
    ["INVITE_EXPIRED", "That invite has expired. Create a new one.", "COACH-INVITE-EXP"],
    ["CLIENT_LIMIT_REACHED", "You've reached the client limit for your plan. Remove a client or upgrade to add more.", "COACH-LIMIT"],
    ["NOT_A_COACH", "This account isn't set up as a coach yet.", "COACH-NOTCOACH"],
  ];
  for (const [needle, message, code] of named) {
    if (detail.includes(needle)) return { message, code };
  }

  if (error.status === 401 || error.status === 403) {
    return { message: "Your session expired. Sign in again to continue.", code: `COACH-${error.status}` };
  }
  return {
    message: "Something went wrong talking to your roster. Please try again.",
    code: `COACH-${error.status || "0"}`,
  };
}

export function authMessage(error) {
  if (!(error instanceof ApiError)) {
    return { message: "Something went wrong signing in. Please try again.", code: "AUTH-UNKNOWN" };
  }
  if (error.code === "NET") {
    return { message: "You appear to be offline. Check your connection and try again.", code: "NET-0" };
  }
  if (error.status === 400 && /invalid[_ ]?(login|credentials|grant)/i.test(`${error.detail} ${error.message}`)) {
    return {
      message: "That email and password don't match an account. If you signed up with Apple on your phone, use the email link instead.",
      code: "AUTH-400-invalid_credentials",
    };
  }
  if (error.status === 400 && /signup|not[_ ]?found|user/i.test(`${error.detail} ${error.message}`)) {
    return {
      message: "No Kinetriq account uses that email. Create your account in the iOS app first — that is where your subscription lives.",
      code: "AUTH-400-no_account",
    };
  }
  if (error.status === 429) {
    return { message: "Too many attempts. Wait a minute and try again.", code: "AUTH-429" };
  }
  return { message: error.message || "Sign-in failed.", code: `AUTH-${error.status || "0"}` };
}
