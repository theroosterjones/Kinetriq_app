# Kinetriq App Store launch checklist

Tracks the remaining work to ship **Kinetriq** (`com.kevinjones.Kinetriq`) on the
App Store with the Pro subscription. Items are grouped by who can do them.

> Status legend: `[x]` done in the repo · `[ ]` open. "Owner: you" means it
> requires an Apple/RevenueCat/Supabase account action the codebase can't perform.

---

## 1. Identity migration (KevLines → Kinetriq)

- [x] New App ID `com.kevinjones.Kinetriq` created in the Developer portal. *(you)*
- [x] New App Store Connect app record "Kinetriq" created. *(you)*
- [x] `project.yml` bundle IDs → `com.kevinjones.Kinetriq` / `com.kevinjones.KinetriqTests`.
- [x] Version: 3.5.x lineage carried onto the new record (now `3.5.0 (35)`).
- [x] Logging subsystem + docs updated to the new bundle ID.
- [x] Sign in with Apple entitlement wired (`Kinetriq.entitlements`).
- [x] Export-compliance flag set (`ITSAppUsesNonExemptEncryption = NO`).
- [x] App icon asset set present (`AppIcon.appiconset`).
- [x] Sign in with Apple + In-App Purchase capabilities confirmed on the
      `com.kevinjones.Kinetriq` App ID. *(you)*

## 2. Subscriptions — RevenueCat + StoreKit *(owner: you)*

- [x] `Config/KinetriqSecrets.xcconfig` populated with the real RevenueCat iOS public
      SDK key + Supabase URL (`gxurelxripxupcnmavef`) + publishable anon key.
      ⚠️ The real RevenueCat key disables the dev "free Pro" unlock — re-verify gating.
- [x] RevenueCat app bundle ID re-pointed to `com.kevinjones.Kinetriq`.
- [x] IAP subscription products created in the new App Store Connect record
      (monthly with a free first week; yearly created).
- [ ] Replace the placeholder `KINETRIQ_PRIVACY_POLICY_URL` / `KINETRIQ_TERMS_URL`
      in the secrets file with the **live** policy/terms URLs.
- [ ] **Decide the yearly intro offer** — monthly is free-first-week; confirm whether
      yearly should also get a free trial or an intro discount, then set it in
      App Store Connect (the planned spec was a 7-day trial on both plans).
- [ ] **Discount / promo codes** — create App Store **offer codes** (and/or
      promotional offers) for the discount + free-month campaigns. Unlimited comp
      access goes through the Supabase `redeem-promo-code` Edge Function.
- [ ] Add subscription **localizations + review screenshot** (required for IAP review).
- [ ] In RevenueCat: entitlement `kinetriq_pro`, attach both products, and create an
      **offering marked current** with monthly + annual packages.
- [ ] Verify in-app: paywall loads offering, trials/prices correct, **Restore
      Purchases** works, manage-subscription link works.

## 3. Backend — Supabase *(owner: you)*

- [x] Edge Function implementations written in-repo (`redeem-promo-code`,
      `revenuecat-webhook`, `delete-account`) + `schema.sql` indexes + `config.toml`.
      See `supabase/README.md` for deploy steps.
- [ ] Enable Supabase Auth: email/password (or magic link) **and** Sign in with Apple.
- [ ] Apply `supabase/schema.sql` (tables, RLS, indexes).
- [ ] `supabase secrets set REVENUECAT_WEBHOOK_SECRET=…`, then
      `supabase functions deploy` all three functions.
- [ ] In RevenueCat, add the webhook URL + matching Authorization secret.
- [ ] Verify account deletion works end to end (App Store requirement).
- [ ] Verify RevenueCat customer is keyed by the Supabase user UUID (cross-device).

## 4. App Store Connect listing & compliance *(owner: you)*

- [ ] Privacy Policy URL + Terms URL live and reachable.
- [ ] App Privacy "nutrition labels" — declare account email/auth + analytics;
      note that **video analysis is on-device and videos are not uploaded**.
- [ ] iPhone screenshots for required sizes (6.9"/6.7" and 6.5").
- [ ] Listing copy: name, subtitle, keywords, description, support URL,
      category (Health & Fitness), age rating.
- [ ] **Reviewer demo account** (login required) + App Review notes covering how to
      reach Pro (comp promo code or sandbox steps).

## 5. Pre-submission QA (from `docs/Subscriptions.md` sandbox checklist) *(owner: you)*

- [ ] Account create / sign-in + Sign in with Apple on a real device.
- [ ] Sandbox monthly + annual purchase; correct trial/price; restore works.
- [ ] Offer-code sheet opens; Supabase promo redemption comps an account.
- [ ] RevenueCat webhook updates Supabase `subscriptions`.
- [ ] Saved-video + live analysis still work; `pose_landmarker_full.task` is bundled.

## 6. Final build & submit *(owner: you)*

- [ ] `xcodegen generate`, select Team (automatic signing), destination **Any iOS
      Device (arm64)**.
- [ ] Product → Archive → upload to the Kinetriq TestFlight.
- [ ] Submit for review with the IAP attached to the same submission.

---

### Notes

- Marketing/build version lives in `project.yml` (`MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION`); run `xcodegen generate` after edits.
- The `pose_landmarker_full.task` model is gitignored — see README for the curl
  command; it must be present locally before archiving.
