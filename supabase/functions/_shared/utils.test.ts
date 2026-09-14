// Run with: deno test supabase/functions/_shared/utils.test.ts
//
// These identifiers are the seam between App Store Connect, RevenueCat, the Swift
// client, and the roster cap enforced in Postgres. A typo in one of them fails
// silently — the coach simply sits on the wrong client limit — so the exact strings
// are pinned here.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { coachClientLimit, isCoachProduct } from "./utils.ts";

Deno.test("coach product identifiers map to their roster sizes", () => {
  assertEquals(coachClientLimit("com.kevinkjones.kinetriq.coach.starter.monthly"), 5);
  assertEquals(coachClientLimit("com.kevinkjones.kinetriq.coach.pro.monthly"), 15);
  assertEquals(coachClientLimit("com.kevinkjones.kinetriq.coach.studio.monthly"), 40);
});

Deno.test("billing period does not change the roster size", () => {
  assertEquals(coachClientLimit("com.kevinkjones.kinetriq.coach.studio.annual"), 40);
  assertEquals(
    coachClientLimit("com.kevinkjones.kinetriq.coach.studio.annual"),
    coachClientLimit("com.kevinkjones.kinetriq.coach.studio.monthly"),
  );
});

Deno.test("individual Pro products are not coach products", () => {
  assertEquals(coachClientLimit("com.kevinkjones.kinetriq.monthly"), null);
  assertEquals(coachClientLimit("com.kevinkjones.kinetriq.annual"), null);
  assertEquals(isCoachProduct("com.kevinkjones.kinetriq.annual"), false);
});

Deno.test("unknown and missing product identifiers resolve to null", () => {
  assertEquals(coachClientLimit(null), null);
  assertEquals(coachClientLimit(undefined), null);
  assertEquals(coachClientLimit(""), null);
  assertEquals(coachClientLimit("com.example.something"), null);
});

/// The bundle id is `com.kevinjones.Kinetriq` but the products are `kevinkjones`.
/// AGENTS.md calls this out because it looks like a typo and is not.
Deno.test("the kevinkjones product spelling is required", () => {
  assertEquals(coachClientLimit("com.kevinjones.kinetriq.coach.pro.monthly"), null);
  assertEquals(coachClientLimit("com.kevinkjones.kinetriq.coach.pro.monthly"), 15);
});
