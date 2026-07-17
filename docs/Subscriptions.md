# Kinetriq subscriptions and accounts

Kinetriq uses two separate systems:

- **Supabase Auth** owns user login and the stable cross-device user ID.
- **RevenueCat** owns store purchase state and the `kinetriq_pro` entitlement.

Shipping-build access is decided by the RevenueCat entitlement alone:

```text
// Release builds
hasProAccess = active RevenueCat `kinetriq_pro` entitlement

// DEBUG builds only
hasProAccess = active RevenueCat entitlement OR developmentUnlocked
```

`developmentUnlocked` is `true` only when no RevenueCat key is configured, and it is compiled out of Release builds with `#if DEBUG`. There is **no** in-app promo/comp path — App Review Guideline 3.1.1 prohibits unlocking paid features outside In-App Purchase. All free/discounted access is granted through **Apple App Store offer codes** (see "Promo codes" below).

## Product setup

Use one paid tier for launch:

| Item | Value |
|------|-------|
| Display name | Kinetriq Pro |
| Entitlement ID | `kinetriq_pro` |
| Monthly product ID | `com.kevinjones.kinetriq.pro.monthly` |
| Annual product ID | `com.kevinjones.kinetriq.pro.yearly` |
| Monthly price | $4.99/mo |
| Annual price | $34.99/yr target |
| Intro offer | 7-day free trial on both plans |

RevenueCat also accepts `pro` and `Kinetriq Pro` in app code during dashboard migration, but new dashboard setup should use `kinetriq_pro`.

## Required app configuration

`project.yml` maps generated Info.plist values to local build settings. Copy the example file before adding real service values:

```bash
cp Config/KinetriqSecrets.example.xcconfig Config/KinetriqSecrets.xcconfig
```

Then edit `Config/KinetriqSecrets.xcconfig`. This local file is gitignored.

| Key | Purpose |
|-----|---------|
| `KINETRIQ_REVENUECAT_API_KEY` | RevenueCat iOS public SDK key |
| `KINETRIQ_SUPABASE_URL` | Supabase project URL |
| `KINETRIQ_SUPABASE_ANON_KEY` | Supabase anon/public key |
| `KINETRIQ_PRIVACY_POLICY_URL` | Public privacy policy |
| `KINETRIQ_TERMS_URL` | Public terms URL |

Never put RevenueCat secret keys, Supabase service-role keys, or App Store API private keys in the app.

## Supabase Auth

The iOS app uses Supabase Auth REST endpoints through `AuthService`.

Enable:

- Email/password or magic-link login.
- Sign in with Apple before App Store launch.
- Google sign-in later for Android and web.

After sign-in, the app calls RevenueCat login with the Supabase user UUID. This is what makes a subscription follow a user across iOS, future Android, and future web.

## RevenueCat

A misconfigured entitlement/offering is the most common cause of "purchased but the
paywall never dismissed" (App Review Guideline 2.1(b)): if the purchased product is
not attached to the `kinetriq_pro` entitlement, `customerInfo.entitlements["kinetriq_pro"].isActive`
stays `false`, so `hasProAccess` never flips and the full-screen paywall stays up.
Work through every step and verify.

1. **Project + app**: one RevenueCat project for Kinetriq; add an **App Store** app bound to bundle ID `com.kevinjones.Kinetriq` (matches `project.yml`). The KevLines testing identity is retired.
2. **App Store Connect API key / shared secret**: in RevenueCat → Project settings → Apps → your App Store app, upload the **In-App Purchase Key** (App Store Connect API key) and the **app-specific shared secret** so RevenueCat can validate receipts. Without this, sandbox purchases won't post back reliably.
3. **Products** (RevenueCat → Products → +):
   - `com.kevinjones.kinetriq.pro.monthly`
   - `com.kevinjones.kinetriq.pro.yearly`
   Import them from the store; confirm each shows its price and the **7-day free trial** intro offer pulled from App Store Connect.
4. **Entitlement** (RevenueCat → Entitlements): create/confirm an entitlement whose identifier is exactly `kinetriq_pro`. **Attach BOTH products to it** (Entitlement → Attach products). This is the step that fixes the stuck-paywall bug.
5. **Offering + packages** (RevenueCat → Offerings):
   - Create an offering (e.g. `default`) and click **Make current** (the app reads `offerings.current`).
   - Add a **Monthly** package pointing to the monthly product and an **Annual** package pointing to the yearly product.
6. **Paywall** (RevenueCat → Paywalls): build/select a paywall for the current offering and **Publish** it. Make sure it clearly shows the plan **title, length, price, and price-per-unit** and the **7-day free trial** terms. (The app also overlays a legal footer with the subscription disclosure + Terms of Use (EULA)/Privacy links, but the price/length/trial come from this template.)
7. **Verify end-to-end in sandbox** on an iPad + iPhone: sign in, open the paywall, confirm the Apple sheet shows the free trial, buy, and confirm the paywall auto-dismisses to the main tabs. Then confirm **Settings → Subscription** reads "Active".
8. Configure Customer Center or keep the Apple manage-subscriptions link as the fallback.

## Promo / discount / free access (Apple offer codes only)

In-app promo-code redemption was **removed** (Guideline 3.1.1). All free months, discounts, and comp/free access must be delivered through **Apple App Store offer codes**, which the app redeems via `SKPaymentQueue.presentCodeRedemptionSheet()` ("Redeem App Store Offer Code" on the paywall and in Settings/Account) or via the App Store redemption URL.

| Goal | Apple offer type | Notes |
|------|------------------|-------|
| Free month | Offer code — *Free* introductory/promo offer | RevenueCat mirrors the entitlement after redemption |
| Discount | Offer code — *Pay as you go / pay up front* at a custom price | Define amount and duration in App Store Connect |
| Free forever (comp) | Offer code — *Free* for a long duration, or a promo/complimentary campaign | Apple has no true "permanent free" IAP; use a long free offer and renew as needed |

The Supabase `redeem-promo-code` Edge Function and `promo_codes` table remain in the repo for history but are no longer wired to in-app access. Do not reintroduce app-binary hardcoded codes for production campaigns.

## Sandbox checklist

- [ ] Real RevenueCat iOS public SDK key is in the generated Info.plist.
- [ ] Real Supabase URL and anon key are in the generated Info.plist.
- [ ] User can create account and sign in.
- [ ] RevenueCat customer uses the Supabase user UUID.
- [ ] Paywall loads current offering.
- [ ] Monthly purchase sheet shows 7-day free trial and $4.99/mo.
- [ ] Annual purchase sheet shows 7-day free trial and annual discount.
- [ ] **After purchasing, the paywall dismisses automatically and lands on the main tabs.**
- [ ] Terms of Use (EULA) and Privacy Policy links on the paywall open live pages.
- [ ] Restore purchases works.
- [ ] App Store offer-code sheet opens and a redeemed offer unlocks Pro.
- [ ] Account deletion Edge Function is configured before App Store submission.
