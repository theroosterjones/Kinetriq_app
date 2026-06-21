// revenuecat-webhook
//
// Receives RevenueCat webhook events, stores the raw payload for audit, and
// mirrors the `kinetriq_pro` entitlement state into `subscriptions` so the
// (future) web UI can render subscription status without calling RevenueCat.
//
// RevenueCat remains the source of truth; this table is a query mirror.

import {
  adminClient,
  ENTITLEMENT_ID,
  corsHeaders,
  isUUID,
  iso,
  json,
  text,
} from "../_shared/utils.ts";

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
  let admin;
  try {
    admin = adminClient();
  } catch (e) {
    return text(`Server not configured: ${e.message}`, 500);
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
  const grantsEntitlement = (event.entitlement_ids ?? []).length === 0 ||
    (event.entitlement_ids ?? []).includes(ENTITLEMENT_ID);

  const active = grantsEntitlement &&
    !INACTIVE_TYPES.has(event.type ?? "") &&
    (expirationMs === null || expirationMs > now);

  const trial = (event.period_type ?? "").toUpperCase() === "TRIAL";
  const eventTime = event.event_timestamp_ms
    ? new Date(event.event_timestamp_ms)
    : new Date();

  const row = {
    user_id: appUserID,
    revenuecat_app_user_id: event.app_user_id ?? appUserID,
    entitlement: ENTITLEMENT_ID,
    product_id: event.product_id ?? null,
    store: event.store ?? null,
    active,
    trial,
    current_period_ends_at: expirationMs ? iso(new Date(expirationMs)) : null,
    last_event_at: iso(eventTime),
    updated_at: iso(new Date()),
  };

  // 5. Upsert the subscription mirror (one row per user + entitlement).
  const { data: existing } = await admin
    .from("subscriptions")
    .select("id")
    .eq("user_id", appUserID)
    .eq("entitlement", ENTITLEMENT_ID)
    .maybeSingle();

  if (existing) {
    await admin.from("subscriptions").update(row).eq("id", existing.id);
  } else {
    await admin.from("subscriptions").insert(row);
  }

  return json({ ok: true, mirrored: true, active });
});
