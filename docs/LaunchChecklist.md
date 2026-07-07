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
- [x] App icon updated to the new "K" logo (`k_logo_2.png`, flattened opaque,
      full size set regenerated). Old icons archived in `design/legacy/app-icon-v1/`.
      ⚠️ Source is only 227px → upscaled/soft; drop in a ≥1024px export before final submit.
- [x] Sign in with Apple + In-App Purchase capabilities confirmed on the
      `com.kevinjones.Kinetriq` App ID. *(you)*

## 2. Subscriptions — RevenueCat + StoreKit *(owner: you)*

- [x] `Config/KinetriqSecrets.xcconfig` populated with the real RevenueCat iOS public
      SDK key + Supabase URL (`gxurelxripxupcnmavef`) + publishable anon key.
      ⚠️ The real RevenueCat key disables the dev "free Pro" unlock — re-verify gating.
- [x] RevenueCat app bundle ID re-pointed to `com.kevinjones.Kinetriq`.
- [x] IAP subscription products created in the new App Store Connect record
      (monthly with a free first week; yearly created).
- [x] Privacy Policy + Terms pages published live (`kinetriq.net/privacy`,
      `kinetriq.net/terms`); secrets file URLs point at them.
- [ ] **Decide the yearly intro offer** — monthly is free-first-week; confirm whether
      yearly should also get a free trial or an intro discount, then set it in
      App Store Connect (the planned spec was a 7-day trial on both plans).
- [~] **Discount / promo codes** — approach + SQL documented in `docs/PromoCodes.md`.
      Permanent-free `unlimited` code: run the insert SQL in Supabase (`KINETRIQ-FOUNDER`).
      $2.99/mo launch promo: create an App Store **offer code** on the monthly product. *(you)*
- [ ] Add subscription **localizations + review screenshot** (required for IAP review).
- [ ] In RevenueCat: entitlement `kinetriq_pro`, attach both products, and create an
      **offering marked current** with monthly + annual packages.
- [ ] Verify in-app: paywall loads offering, trials/prices correct, **Restore
      Purchases** works, manage-subscription link works.

## 3. Backend — Supabase *(owner: you)*

- [x] Edge Function implementations written in-repo (`redeem-promo-code`,
      `revenuecat-webhook`, `delete-account`) + `schema.sql` indexes + `config.toml`.
      See `supabase/README.md` for deploy steps.
- [x] Supabase Auth enabled (email + Sign in with Apple; Apple Client IDs include
      `com.kevinjones.Kinetriq`). Confirmed working on device.
- [x] `supabase/schema.sql` applied (tables, RLS, indexes, profile auto-provision trigger).
- [x] `REVENUECAT_WEBHOOK_SECRET` set + all three functions deployed.
- [x] RevenueCat webhook URL + Authorization secret wired (test returned 200).
- [x] Promo redemption verified end-to-end on device (comp granted).
- [ ] Verify account deletion works end to end (App Store requirement).
- [ ] Verify RevenueCat customer is keyed by the Supabase user UUID (cross-device).

## 4. App Store Connect listing & compliance *(owner: you)*

> First-pass copy, privacy-label answers, age-rating answers, and review notes
> are drafted in **`docs/AppStoreListing.md`** — paste from there.

- [x] Listing copy + App Privacy answers + age-rating answers drafted
      (`docs/AppStoreListing.md`).
- [x] Privacy Policy URL + Terms URL live and reachable (`kinetriq.net/privacy`,
      `kinetriq.net/terms`). Source drafts in `docs/legal/`.
- [ ] Enter App Privacy "nutrition labels" per the drafted table (account email/name,
      user ID, purchases; **video analysis is on-device and not uploaded**).
- [ ] iPhone screenshots for required sizes (6.9"/6.7" and 6.5").
- [ ] Paste listing copy: subtitle, keywords, description, promo text, category, age rating.
- [ ] **Reviewer demo account** (login required) + App Review notes + a Pro comp code.

## 5. Pre-submission QA (from `docs/Subscriptions.md` sandbox checklist) *(owner: you)*

- [x] Automated unit test suite green (42 tests, incl. subscription-access gating). *(agent)*
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
