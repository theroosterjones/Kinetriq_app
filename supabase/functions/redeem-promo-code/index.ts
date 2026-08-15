// redeem-promo-code
//
// Validates a promo code for the authenticated user and grants the matching
// account entitlement. Response shape matches the iOS `PromoRedeemResponse`
// (decoded by `PromoRedemptionService`).

import {
  addMonths,
  adminClient,
  ENTITLEMENT_ID,
  corsHeaders,
  iso,
  json,
  text,
  userFromRequest,
} from "../_shared/utils.ts";

type PromoType = "free_month" | "discount" | "unlimited";
type EntitlementSource =
  | "promo_free_month"
  | "promo_discount"
  | "manual_comp";

interface PromoCodeRow {
  id: string;
  code: string;
  type: PromoType;
  active: boolean;
  max_redemptions: number | null;
  redemption_count: number;
  starts_at: string | null;
  expires_at: string | null;
}

// Maps a promo code type to the entitlement source + how long it lasts.
function entitlementFor(
  type: PromoType,
  now: Date,
): { source: EntitlementSource; expiresAt: Date | null } {
  switch (type) {
    case "free_month":
      return { source: "promo_free_month", expiresAt: addMonths(now, 1) };
    case "discount":
      return { source: "promo_discount", expiresAt: addMonths(now, 1) };
    case "unlimited":
      return { source: "manual_comp", expiresAt: null };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return text("Method not allowed.", 405);
  }

  let admin;
  try {
    admin = adminClient();
  } catch (e) {
    return text(`Server not configured: ${e.message}`, 500);
  }

  const user = await userFromRequest(req, admin);
  if (!user) {
    return text("Sign in before redeeming a promo code.", 401);
  }

  let code = "";
  try {
    const body = await req.json();
    code = String(body?.code ?? "").trim().toUpperCase();
  } catch {
    return text("Invalid request body.", 400);
  }
  if (!code) {
    return text("Enter a promo code.", 400);
  }

  // 1. Find a matching, active, in-window promo code.
  const { data, error: codeErr } = await admin
    .from("promo_codes")
    .select("*")
    .eq("code", code)
    .eq("active", true)
    .maybeSingle();

  if (codeErr) {
    return text("Could not look up that promo code.", 500);
  }
  const codeRow = data as PromoCodeRow | null;
  if (!codeRow) {
    return text("That promo code is not valid.", 404);
  }

  const now = new Date();
  if (codeRow.starts_at && new Date(codeRow.starts_at) > now) {
    return text("That promo code is not active yet.", 400);
  }
  if (codeRow.expires_at && new Date(codeRow.expires_at) < now) {
    return text("That promo code has expired.", 400);
  }
  if (
    codeRow.max_redemptions !== null &&
    codeRow.redemption_count >= codeRow.max_redemptions
  ) {
    return text("That promo code has reached its redemption limit.", 400);
  }

  // 2. Enforce one redemption per user/code.
  const { data: existing } = await admin
    .from("promo_redemptions")
    .select("id")
    .eq("user_id", user.id)
    .eq("code_id", codeRow.id)
    .maybeSingle();

  if (existing) {
    return text("You have already redeemed that promo code.", 409);
  }

  // 3. Record the redemption.
  const platform = req.headers.get("x-client-platform") ?? "ios";

  const { error: redemptionErr } = await admin
    .from("promo_redemptions")
    .insert({
      user_id: user.id,
      code_id: codeRow.id,
      platform,
    });

  if (redemptionErr) {
    // Unique violation = race; treat as already redeemed.
    return text("You have already redeemed that promo code.", 409);
  }

  // 4. Grant the entitlement.
  const { source, expiresAt } = entitlementFor(codeRow.type, now);

  const { error: entitlementErr } = await admin
    .from("account_entitlements")
    .insert({
      user_id: user.id,
      entitlement: ENTITLEMENT_ID,
      source,
      starts_at: iso(now),
      expires_at: expiresAt ? iso(expiresAt) : null,
      active: true,
    });

  if (entitlementErr) {
    return text("Could not grant the entitlement.", 500);
  }

  // 5. Increment the redemption counter (best-effort).
  await admin
    .from("promo_codes")
    .update({ redemption_count: codeRow.redemption_count + 1 })
    .eq("id", codeRow.id);

  // 6. Respond in the shape the iOS app decodes.
  return json({
    entitlement: {
      entitlement: ENTITLEMENT_ID,
      source,
      startsAt: iso(now),
      expiresAt: expiresAt ? iso(expiresAt) : null,
      active: true,
    },
  });
});
