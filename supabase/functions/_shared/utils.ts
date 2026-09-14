// Shared helpers for Kinetriq Supabase Edge Functions.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export const ENTITLEMENT_ID = "kinetriq_pro";

/// The coach-tier entitlement. Must match one of `acceptedCoachEntitlementIDs` in
/// `PurchaseService`, and the entitlement identifier configured in RevenueCat.
export const COACH_ENTITLEMENT_ID = "Kinetriq Coach";

/// Roster size each coach product allows, mirroring `PurchaseService.CoachTier`.
///
/// The webhook writes this into `coaches.client_limit`, which is what
/// `create_coach_invite` enforces. Without it every coach sits on the column
/// default regardless of what they paid for.
const COACH_CLIENT_LIMITS: Record<string, number> = {
  "com.kevinkjones.kinetriq.coach.starter": 5,
  "com.kevinkjones.kinetriq.coach.pro": 15,
  "com.kevinkjones.kinetriq.coach.studio": 40,
};

/// Maps a coach product identifier to its roster size, ignoring the billing period
/// so `.monthly` and `.annual` of the same tier resolve identically.
export function coachClientLimit(productID: string | null | undefined): number | null {
  if (!productID) return null;
  const base = productID.replace(/\.(monthly|annual)$/, "");
  return COACH_CLIENT_LIMITS[base] ?? null;
}

export function isCoachProduct(productID: string | null | undefined): boolean {
  return coachClientLimit(productID) !== null;
}

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// ISO-8601 without fractional seconds. Swift's `JSONDecoder.dateDecodingStrategy
/// = .iso8601` uses `.withInternetDateTime` only, which FAILS on millisecond
/// precision (e.g. "2026-06-21T22:00:00.000Z"). Always emit second precision.
export function iso(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function addMonths(date: Date, months: number): Date {
  const d = new Date(date);
  d.setMonth(d.getMonth() + months);
  return d;
}

/// Service-role client that bypasses RLS. Mutations to entitlement tables must
/// only happen here, never from the app directly.
export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set");
  }
  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/// Resolve the authenticated user from the request's Bearer token.
export async function userFromRequest(
  req: Request,
  admin: SupabaseClient,
): Promise<{ id: string; email?: string } | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email ?? undefined };
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function text(message: string, status: number): Response {
  return new Response(message, {
    status,
    headers: { ...corsHeaders, "Content-Type": "text/plain" },
  });
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUUID(value: string | null | undefined): boolean {
  return !!value && UUID_RE.test(value);
}
