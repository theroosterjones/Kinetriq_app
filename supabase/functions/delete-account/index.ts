// delete-account
//
// App Store account-deletion compliance. Removes the authenticated user's
// app-owned data and deletes their Supabase Auth account. Called by the iOS
// app via `AuthService.requestAccountDeletion()`.

import {
  adminClient,
  corsHeaders,
  json,
  text,
  userFromRequest,
} from "../_shared/utils.ts";

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
    return text("Account deletion requires a logged-in user.", 401);
  }

  // 1. Anonymize audit-only rows that are not removed by the auth cascade.
  //    `revenuecat_events` has no FK to auth.users; null the user reference so
  //    financial/audit records can be retained without identifying the user.
  await admin
    .from("revenuecat_events")
    .update({ app_user_id: null })
    .eq("app_user_id", user.id);

  // 2. Explicitly remove app-owned rows. These also cascade from the auth user
  //    delete below, but we delete first so a partial failure still clears data.
  //    `profiles` is keyed by `id`; the rest are keyed by `user_id`.
  await admin.from("account_entitlements").delete().eq("user_id", user.id);
  await admin.from("promo_redemptions").delete().eq("user_id", user.id);
  await admin.from("subscriptions").delete().eq("user_id", user.id);
  await admin.from("profiles").delete().eq("id", user.id);

  // 3. Delete the Supabase Auth user (cascades any remaining owned rows).
  const { error: deleteErr } = await admin.auth.admin.deleteUser(user.id);
  if (deleteErr) {
    return text(`Could not delete account: ${deleteErr.message}`, 500);
  }

  return json({ success: true });
});
