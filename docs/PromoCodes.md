# Kinetriq promo & discount codes

Two very different mechanisms, one for each request:

| Goal | Mechanism | Where it lives | Cost to user |
|------|-----------|----------------|--------------|
| **Permanent free access** (traceable) | Supabase `unlimited` promo code | `promo_codes` table + `redeem-promo-code` Edge Function | $0 forever |
| **$2.99/mo launch promo** | App Store **subscription offer code** | App Store Connect → your subscription → Offer Codes | $2.99/mo for the promo window |

> Why two systems? The Supabase promo path grants an in-app *comp* entitlement — it can make the app free, but it **cannot** charge a real (discounted) price through Apple. Any actual money/price change must go through an App Store offer so Apple handles billing and RevenueCat mirrors it automatically.

---

## 1. Permanent free-access code (traceable)

Uses the `unlimited` code type → grants a `manual_comp` entitlement with **no expiry**. Every redemption is logged per user in `promo_redemptions`, so you always know exactly who used it.

### Create the code

Run in **Supabase → SQL Editor** (rename the code / notes as you like):

```sql
insert into promo_codes (code, type, active, notes)
values ('KINETRIQ-FOUNDER', 'unlimited', true, 'Permanent free access — launch VIPs / founders');
```

Optional guard rails:

```sql
-- Cap how many people can ever use it (omit for unlimited seats):
insert into promo_codes (code, type, active, max_redemptions, notes)
values ('KINETRIQ-FOUNDER', 'unlimited', true, 100, 'Permanent free access — first 100 VIPs');

-- Or make several single-use codes so each code = one known person:
insert into promo_codes (code, type, active, max_redemptions, notes) values
  ('VIP-ALEX',  'unlimited', true, 1, 'Alex — permanent comp'),
  ('VIP-JAMIE', 'unlimited', true, 1, 'Jamie — permanent comp');
```

Users redeem it in-app on the paywall / redeem screen (the app calls the
`redeem-promo-code` function). Codes are matched **case-insensitively** (the
function upper-cases input), so store them uppercase.

### See who has redeemed it

```sql
select u.email,
       pr.redeemed_at,
       pr.platform,
       pc.code,
       pc.notes
from promo_redemptions pr
join promo_codes pc on pc.id = pr.code_id
join auth.users   u  on u.id = pr.user_id
where pc.code = 'KINETRIQ-FOUNDER'
order by pr.redeemed_at desc;
```

Active comp entitlements (should show `source = manual_comp`, `expires_at = null`):

```sql
select u.email, ae.source, ae.starts_at, ae.expires_at, ae.active
from account_entitlements ae
join auth.users u on u.id = ae.user_id
where ae.source = 'manual_comp'
order by ae.starts_at desc;
```

### Turn it off later

```sql
update promo_codes set active = false where code = 'KINETRIQ-FOUNDER';
```

(Disabling the code stops new redemptions; people who already redeemed keep
their comp. To revoke an individual, set that user's `account_entitlements.active = false`.)

---

## 2. $2.99/mo launch promotion (App Store offer code)

This is a real discounted price, so it must be configured in Apple, **not** Supabase.

### Set it up in App Store Connect

1. **App Store Connect → your app → Subscriptions →** open the monthly product
   (`com.kevinjones.kinetriq.pro.monthly`).
2. Scroll to **Subscription Prices → Offer Codes → (+)** (or **Promotional Offers**
   if you want to apply it programmatically; **Offer Codes** are simplest for a
   launch campaign because users just redeem a code).
3. Create an offer code campaign:
   - **Reference name:** `Launch $2.99/mo`
   - **Offer type:** *Pay as you go* (recurring) at a **custom price of $2.99**
   - **Duration:** how long the $2.99 price lasts (e.g. 3, 6, or 12 months), then
     it rolls to the standard price.
   - **Eligibility:** New + existing subscribers as desired.
   - **Number of codes / distribution:** one-time-use codes, or a single custom
     code + a distribution URL you can share for launch.
4. Save. Apple generates the codes / redemption URL.

### RevenueCat / app side — nothing to build

- RevenueCat reads the offer through StoreKit automatically; the discounted
  price and the `kinetriq_pro` entitlement flow through with no code changes.
- Users redeem via the App Store (the offer-code URL or Settings → redeem), or
  you can present it in-app with `SKPaymentQueue`/StoreKit later if you want.

### Tracking

- **App Store Connect → Analytics / Sales & Trends** shows offer-code redemptions
  and the resulting subscriptions.
- **RevenueCat → Customer history** shows each subscriber's product + price.

---

## Quick reference

| Code | Type | Effect | Managed in | Tracked in |
|------|------|--------|------------|-----------|
| `KINETRIQ-FOUNDER` | `unlimited` | Free forever (comp) | Supabase `promo_codes` | `promo_redemptions`, `account_entitlements` |
| `Launch $2.99/mo` | App Store offer code | $2.99/mo for promo window | App Store Connect | ASC Analytics + RevenueCat |
