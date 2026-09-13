/**
 * Coach data access. Thin wrapper over the same RPCs and tables `CoachService` uses
 * on iOS, so the phone and the browser are two views of one source of truth rather
 * than two datasets that can disagree.
 */

import { rpc, select, remove, currentSession } from "./api.js";
import { parseDate } from "./format.js";
import { sortClients } from "./triage.js";

/**
 * The coach's own row.
 *
 * This is the entitlement gate on the web. There is no RevenueCat SDK in the browser,
 * and there should not be one: `coaches.client_limit` is written by the
 * revenuecat-webhook Edge Function and is the value Postgres itself enforces inside
 * `create_coach_invite`. Gating on it means the dashboard cannot be more permissive
 * than the database, which a client-side entitlement check could easily become.
 *
 * A lapse sets the limit to 0 rather than deleting the row, so an unsubscribed coach
 * keeps read access to clients they already have and simply cannot add more — exactly
 * what the webhook and the SQL function already do.
 *
 * @returns {Promise<{displayName: string|null, businessName: string|null, clientLimit: number}|null>}
 */
export async function fetchCoachRecord() {
  const userID = currentSession()?.user?.id;
  if (!userID) return null;

  const rows = await select("coaches", {
    select: "user_id,display_name,business_name,client_limit",
    user_id: `eq.${userID}`,
    limit: "1",
  });
  const row = rows?.[0];
  if (!row) return null;

  return {
    displayName: row.display_name || null,
    businessName: row.business_name || null,
    clientLimit: Number(row.client_limit ?? 0),
  };
}

/** The triage queue, ordered exactly as the phone orders it. */
export async function fetchRoster() {
  const rows = (await rpc("coach_roster", {})) || [];
  return sortClients(rows.map(toClient));
}

function toClient(row) {
  return {
    clientUserID: row.client_user_id,
    displayName: row.display_name || "Client",
    status: row.status || "active",
    linkedAt: parseDate(row.linked_at),
    lastSessionAt: parseDate(row.last_session_at),
    sessionsLast14Days: Number(row.sessions_last_14_days ?? 0),
    latestScore: row.latest_score ?? null,
    previousScore: row.previous_score ?? null,
    latestMovement: row.latest_movement || null,
    openAsymmetryFlag: Boolean(row.open_asymmetry_flag),
  };
}

/** Server-generated so a coach cannot mint codes past their client limit. */
export function createInvite(label) {
  return rpc("create_coach_invite", { label: label?.trim() || null });
}

export async function fetchInvites() {
  const userID = currentSession()?.user?.id;
  if (!userID) return [];

  const rows = await select("coach_invites", {
    select: "code,label,created_at,expires_at,redeemed_by,redeemed_at",
    coach_user_id: `eq.${userID}`,
    order: "created_at.desc",
  });

  return (rows || []).map((row) => ({
    code: row.code,
    label: row.label || null,
    createdAt: parseDate(row.created_at),
    expiresAt: parseDate(row.expires_at),
    redeemed: Boolean(row.redeemed_by),
    redeemedAt: parseDate(row.redeemed_at),
  }));
}

export function revokeInvite(code) {
  return remove("coach_invites", { code: `eq.${code}` });
}

/** Ends a link. Either side may do this; the RLS policy allows both. */
export function removeClient(clientUserID) {
  const userID = currentSession()?.user?.id;
  if (!userID) throw new Error("Not signed in");
  return remove("coach_clients", {
    coach_user_id: `eq.${userID}`,
    client_user_id: `eq.${clientUserID}`,
  });
}

/**
 * One client's sessions, reps embedded.
 *
 * There is no video column to select, and no bucket to fetch from. The privacy claim
 * in the app, on the website, and in the App Store listing all rest on that, and for
 * clinicians it is also what keeps a Kinetriq coach account outside HIPAA
 * business-associate scope. Do not add media here.
 *
 * The `user_id` filter is redundant with the "Coaches read linked client analyses"
 * policy, and stays anyway: a policy edit must not be able to silently widen this.
 */
export function fetchClientSessions(clientUserID, { limit = 100 } = {}) {
  return select("analysis_records", {
    select: "*,analysis_reps(*)",
    user_id: `eq.${clientUserID}`,
    order: "recorded_at.desc",
    limit: String(limit),
  });
}
