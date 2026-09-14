# Coach tier: App Store Connect + RevenueCat setup

Six products and one entitlement. Until these exist, `CoachRosterView` renders the
tier cards with a "not yet available for purchase" banner — the code is shipped and
waiting on configuration.

Do this in order. Apple can take a few hours to surface new products to RevenueCat,
and RevenueCat cannot attach a product it cannot see.

> **Authoritative identifiers.** `docs/Subscriptions.md` predates the bundle-ID
> migration and lists `com.kevinjones.kinetriq.pro.monthly` / `.pro.yearly`. Those are
> **not** what ships. The live individual products are
> `com.kevinkjones.kinetriq.monthly` and `com.kevinkjones.kinetriq.annual`, and the
> live entitlement is `Kinetriq Pro` with a space. AGENTS.md is the source of truth
> and was verified against live `CustomerInfo`. Note the `kevink` spelling — the
> bundle id is `com.kevinjones.Kinetriq` but the products are `kevinkjones`. It looks
> like a typo and is not.

---

## 1. Decide the group first (this one matters)

**Put the coach products in the *same* subscription group as Kinetriq Pro.**

App Store Connect only allows one active subscription per group, and that is exactly
what you want here. The coach entitlement already grants individual Pro access in the
app (`SubscriptionAccessState.hasProAccess` is true when `hasCoachEntitlement` is),
so Coach is a superset of Pro, not a parallel product.

Same group gives you:

- A Pro subscriber upgrading to Coach gets automatic proration and an immediate
  switch, with Apple refunding the unused remainder.
- Nobody can accidentally pay for Pro *and* Coach at the same time.
- Tier changes between Coach levels are handled by Apple, not by your code.

Separate groups would let a trainer hold two overlapping subscriptions and pay twice
for access they already have. That generates refund requests and support mail.

### Levels within the group

Level 1 is the highest tier. Set them like this so upgrade and downgrade proration is
correct, with monthly and annual of the same tier sharing a level (Apple treats a
same-level change as a crossgrade, deferred to the next renewal):

| Level | Products |
|---|---|
| 1 | Coach Studio (monthly, annual) |
| 2 | Coach Pro (monthly, annual) |
| 3 | Coach Starter (monthly, annual) |
| 4 | Kinetriq Pro (monthly, annual) — existing |

## 2. Create the six products

**App Store Connect → Kinetriq → Subscriptions → the existing Kinetriq Pro group →
Create.**

Product IDs must match `PurchaseService.CoachTier` exactly. They are asserted in
`supabase/functions/_shared/utils.test.ts`, so if you deviate, run that test and it
will tell you.

| Reference name | Product ID | Duration |
|---|---|---|
| Coach Starter Monthly | `com.kevinkjones.kinetriq.coach.starter.monthly` | 1 month |
| Coach Starter Annual | `com.kevinkjones.kinetriq.coach.starter.annual` | 1 year |
| Coach Pro Monthly | `com.kevinkjones.kinetriq.coach.pro.monthly` | 1 month |
| Coach Pro Annual | `com.kevinkjones.kinetriq.coach.pro.annual` | 1 year |
| Coach Studio Monthly | `com.kevinkjones.kinetriq.coach.studio.monthly` | 1 month |
| Coach Studio Annual | `com.kevinkjones.kinetriq.coach.studio.annual` | 1 year |

**Product IDs are permanent.** A typo means creating a new product and abandoning the
old one, so paste rather than type them.

For each product you must fill in:

- **Subscription duration** and **level** (above)
- **Price** (below)
- **Localization** — display name and description, at minimum for English (U.S.)
- **Review information** — a screenshot of the paywall and a note for the reviewer

### Pricing

The coach pays for seats; clients pay nothing. That is how every coaching platform
with real adoption prices it, and asking a trainer to chase fifteen clients for $5
each is how a coach tier dies.

| Tier | Clients | Monthly | Annual | Effective per client |
|---|---|---|---|---|
| Coach Starter | 5 | $19.99 | $199.99 | ~$4.00/client/mo |
| Coach Pro | 15 | $39.99 | $399.99 | ~$2.67/client/mo |
| Coach Studio | 40 | $79.99 | $799.99 | ~$2.00/client/mo |

Annual is priced at ten months, matching the ~30% discount on the individual plan
($4.99 → $34.99). The per-client rate falling as the roster grows is deliberate: it
rewards the trainers who bring the most clients onto the platform, and those are the
accounts worth keeping.

For calibration, TrueCoach starts around $25/month for a handful of clients and
Trainerize is in similar territory. Starter deliberately undercuts that entry point,
because Kinetriq is not trying to replace their scheduling and billing — the wedge is
measurement they cannot get anywhere else. Do not price as though you are selling a
full coaching platform; you are selling the analysis layer.

### Free trials on coach products

Do **not** add an introductory free trial to the coach tiers at launch. A trainer
needs to onboard real clients before the tier demonstrates anything, and a 7-day
window mostly produces trials that expire mid-setup. Offer codes handle the cases
that matter — see step 6.

## 3. Localization copy

Paste-ready. Apple truncates descriptions, so the important part is first.

**Coach Starter**
> Name: Coach Starter — 5 Clients
> Description: Invite up to 5 clients and see every client's reps, tempo, range of motion, and consistency scores in one triage-ordered roster. Client video never leaves their device.

**Coach Pro**
> Name: Coach Pro — 15 Clients
> Description: Invite up to 15 clients. See who has gone quiet, whose scores are slipping, and who has a new asymmetry flag — before your next session. Client video never leaves their device.

**Coach Studio**
> Name: Coach Studio — 40 Clients
> Description: Invite up to 40 clients for studios and multi-trainer practices. Adherence and progress for your whole roster in one place, plus CSV export. Client video never leaves their device.

That last sentence is on every one of them on purpose. It is the differentiator, and
it is also the answer to the first question any physical therapist will ask.

## 4. RevenueCat

**RevenueCat → Products → +.** Add all six identifiers. If they do not appear,
Apple has not propagated them yet; wait and retry rather than creating them by hand
with a different spelling.

**Then create the entitlement.** RevenueCat → Entitlements → New:

| Field | Value |
|---|---|
| Identifier | `Kinetriq Coach` |

The space is intentional. `PurchaseService.acceptedCoachEntitlementIDs` is
`["Kinetriq Coach", "kinetriq_coach"]`, so either works, but use the spaced form to
match how the live Pro entitlement is configured.

**Attach all six coach products to `Kinetriq Coach`.**

> **Do not attach the coach products to `Kinetriq Pro`.** They are deliberately
> separate entitlement lists in `PurchaseService`. The app grants Pro *access* to
> coach subscribers in Swift; it does not need Apple to conflate them, and conflating
> them makes it impossible to tell a coach from an individual subscriber in your own
> dashboard.

**Offerings.** Create a `coach` offering with three packages (one per tier, monthly
and annual). The roster screen reads tier labels from product identifiers today, so
this is for future paywall work and for RevenueCat's own charts — but set it up now
while the context is fresh.

**Verify the webhook.** RevenueCat → Integrations → Webhooks should already point at
your Supabase function. Confirm it is still there, then check step 5.

## 5. Redeploy the webhook first

The webhook is what turns a purchase into a working roster cap:

```bash
supabase functions deploy revenuecat-webhook
```

Before this release it only handled `kinetriq_pro` and never wrote
`coaches.client_limit`. Without the redeploy, a Studio subscriber is capped at 15
clients and a Starter subscriber gets 15 instead of 5 — because everyone lands on the
column default. Full context in `docs/SupabaseDeploy.md`.

The mapping lives in `supabase/functions/_shared/utils.ts` and is pinned by tests:

```bash
deno test supabase/functions/_shared/utils.test.ts
```

## 6. Comping a coach before the products exist

You do not need App Store Connect to put a real trainer on the roster today. Grant
the entitlement directly:

1. **RevenueCat → Customers →** search the Supabase user UUID **→ Grant entitlement
   → `Kinetriq Coach`**, with an expiry date.
2. Set their roster cap in Supabase, because a manual grant fires no webhook:

```sql
insert into coaches (user_id, display_name, client_limit)
values ('<their-uuid>', 'Their Name', 15)
on conflict (user_id) do update set client_limit = 15;
```

Both steps are required. RevenueCat decides whether the app shows the coach screens;
`coaches.client_limit` decides how many invites they can mint.

Once the products exist, prefer **App Store offer codes** for free or discounted
access. Never add an in-app unlock path — Guideline 3.1.1, and it is the thing that
got builds 38 and 39 rejected.

## 7. Sandbox test before you rely on it

**App Store Connect → Users and Access → Sandbox Testers**, then sign in to that
account under Settings → Developer on the device.

1. Purchase Coach Starter. Confirm the roster unlocks.
2. Check RevenueCat → Customers that `Kinetriq Coach` is active.
3. Confirm the webhook wrote the cap:

```sql
select user_id, client_limit, updated_at from coaches order by updated_at desc limit 5;
```

Starter must show `client_limit = 5`. If it shows 15, the webhook was not redeployed.

4. Create 5 invites, then try a 6th. It must fail with the limit message rather than
   minting a code — the cap is enforced in `create_coach_invite`, counting active
   clients plus outstanding invites.
5. Upgrade to Coach Pro in the sandbox. The cap should become 15 within seconds.
6. Let a sandbox subscription expire (sandbox renewals are accelerated — a month runs
   in minutes). Confirm `client_limit` goes to **0** and, critically, that
   `coach_clients` rows still exist. A lapse must never delete the roster; the
   `coaches` row cascades to invites and clients, which is why the webhook zeroes the
   limit instead of deleting.

## 8. App Review notes

Add to the review notes for the build that ships purchasable coach tiers:

> The Coach tiers are for personal trainers. A coach subscribes, generates an invite
> code in the app, and gives it to a client. The client enters that code to link their
> account, which lets the coach see the client's measurements — reps, tempo, joint
> angles, and consistency scores. No video is ever uploaded or shared; analyzed clips
> remain in the app container on the client's own device. Either party can end the
> link at any time.
>
> To test: sign in, go to Settings → Coach → My Clients, and subscribe to Coach
> Starter. Use the generated code from a second account under Settings → Coach →
> Connect to a Coach.

Expect a question about the client-side account. Be ready to say plainly that clients
are not charged, do not need a paid subscription to be linked, and that the coach's
subscription is what is being sold.

## Checklist

- [ ] Six products created in the **existing** Kinetriq Pro group, correct levels
- [ ] Prices and localizations set on all six
- [ ] Products visible in RevenueCat
- [ ] `Kinetriq Coach` entitlement created, all six attached, **not** attached to Pro
- [ ] `coach` offering created
- [ ] `revenuecat-webhook` redeployed
- [ ] `deno test supabase/functions/_shared/utils.test.ts` passes
- [ ] Sandbox purchase sets `coaches.client_limit` to the tier's size
- [ ] Invite cap enforced at the limit
- [ ] Expiry zeroes the limit and preserves `coach_clients`
- [ ] Review notes added
