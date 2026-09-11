// revenuecat-webhook
//
// Receives RevenueCat webhook events, stores the raw payload for audit, and
// mirrors entitlement state into `subscriptions` so the (future) web UI can render
// subscription status without calling RevenueCat.
//
// Two entitlements are mirrored: `kinetriq_pro` (individual) and `Kinetriq Coach`
// (coach tier). The coach path additionally writes `coaches.client_limit`, which is
// the roster cap `create_coach_invite` enforces server-side.
//
// RevenueCat remains the source of truth; these tables are a query mirror.

import {
  adminClient,
  coachClientLimit,
  COACH_ENTITLEMENT_ID,
  corsHeaders,
  ENTITLEMENT_ID,
  isCoachProduct,
  isUUID,
  iso,
  json,
  text,
} from "../_shared/utils.ts";

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

// Event types that should NOT be treated as active access regardless of expiry.
const INACTIVE_TYPES = new Set([
  "EXPIRATION",
  "REFUND",
  "SUBSCRIPTION_PAUSED",
]);

interface RCEvent {
  id?: string;
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  product_id?: string;
  store?: string;
  period_type?: string;
  expiration_at_ms?: number;
  event_timestamp_ms?: number;
  entitlement_ids?: string[];
}

function resolveAppUserID(event: RCEvent): string | null {
  const candidates = [
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
  ];
  return candidates.find((c) => isUUID(c)) ?? null;
}

/// One row per user + entitlement. `subscriptions` has no unique constraint on that
/// pair, so this reads before writing rather than upserting.
async function mirrorSubscription(
  admin: SupabaseClient,
  row: Record<string, unknown>,
  userID: string,
  entitlement: string,
) {
  const { data: existing } = await admin
    .from("subscriptions")
    .select("id")
    .eq("user_id", userID)
    .eq("entitlement", entitlement)
    .maybeSingle();

  if (existing) {
    await admin.from("subscriptions").update(row).eq("id", existing.id);
  } else {
    await admin.from("subscriptions").insert(row);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return text("Method not allowed.", 405);
  }

  // 1. Authenticate the webhook via shared secret.
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (!expected) {
    return text("Webhook secret not configured.", 500);
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const provided = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (provided !== expected && authHeader !== expected) {
    return text("Unauthorized.", 401);
  }

  let payload: { event?: RCEvent };
  try {
    payload = await req.json();
  } catch {
    return text("Invalid JSON.", 400);
  }

  const event = payload.event ?? {};
  let admin: SupabaseClient;
  try {
    admin = adminClient();
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    return text(`Server not configured: ${reason}`, 500);
  }

  // 2. Store the raw event (idempotent on event_id).
  if (event.id) {
    await admin
      .from("revenuecat_events")
      .upsert(
        {
          event_id: event.id,
          app_user_id: event.app_user_id ?? null,
          event_type: event.type ?? null,
          payload,
        },
        { onConflict: "event_id", ignoreDuplicates: true },
      );
  }

  // 3. Resolve the RevenueCat app user ID to a Supabase auth user.
  const appUserID = resolveAppUserID(event);
  if (!appUserID) {
    // Anonymous / pre-login purchase — stored for audit, nothing to mirror yet.
    return json({ ok: true, mirrored: false });
  }

  // 4. Compute active/trial state.
  const now = Date.now();
  const expirationMs = event.expiration_at_ms ?? null;
  const entitlementIDs = event.entitlement_ids ?? [];

  // Some legacy and sandbox events omit entitlement_ids entirely. Treating that as
  // Pro preserves the behavior this function shipped with.
  const touchesPro = entitlementIDs.length === 0 ||
    entitlementIDs.includes(ENTITLEMENT_ID);

  // Trust the entitlement id when RevenueCat sends it, but fall back to the product
  // id so a renamed entitlement in the dashboard cannot silently strand a coach on
  // the default roster limit.
  const touchesCoach = entitlementIDs.includes(COACH_ENTITLEMENT_ID) ||
    isCoachProduct(event.product_id);

  const stillValid = !INACTIVE_TYPES.has(event.type ?? "") &&
    (expirationMs === null || expirationMs > now);

  const trial = (event.period_type ?? "").toUpperCase() === "TRIAL";
  const eventTime = event.event_timestamp_ms
    ? new Date(event.event_timestamp_ms)
    : new Date();

  const baseRow = {
    user_id: appUserID,
    revenuecat_app_user_id: event.app_user_id ?? appUserID,
    product_id: event.product_id ?? null,
    store: event.store ?? null,
    trial,
    current_period_ends_at: expirationMs ? iso(new Date(expirationMs)) : null,
    last_event_at: iso(eventTime),
    updated_at: iso(new Date()),
  };

  // 5. Mirror each entitlement this event touches.
  const proActive = touchesPro && stillValid;
  const coachActive = touchesCoach && stillValid;

  if (touchesPro) {
    await mirrorSubscription(
      admin,
      { ...baseRow, entitlement: ENTITLEMENT_ID, active: proActive },
      appUserID,
      ENTITLEMENT_ID,
    );
  }

  if (touchesCoach) {
    await mirrorSubscription(
      admin,
      { ...baseRow, entitlement: COACH_ENTITLEMENT_ID, active: coachActive },
      appUserID,
      COACH_ENTITLEMENT_ID,
    );

    // 6. Write the roster cap that `create_coach_invite` enforces.
    //
    // Never delete the `coaches` row on a lapse: `coach_invites` and
    // `coach_clients` both cascade from it, so a missed payment would silently
    // destroy the coach's entire roster. Zeroing the limit blocks *new* invites
    // while leaving existing client links intact, and a renewal restores it.
    const limit = coachActive ? (coachClientLimit(event.product_id) ?? 15) : 0;

    await admin
      .from("coaches")
      .upsert(
        { user_id: appUserID, client_limit: limit, updated_at: iso(new Date()) },
        { onConflict: "user_id" },
      );
  }

  return json({
    ok: true,
    mirrored: touchesPro || touchesCoach,
    active: proActive || coachActive,
    coach: touchesCoach,
  });
});
