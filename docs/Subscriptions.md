# RevenueCat subscription setup — Kinetriq Pro

Kinetriq uses RevenueCat as the **single entitlement layer** across platforms. Stores (Apple, Google) own **prices and trials**; RevenueCat maps products → one entitlement; the app checks **`Kinetriq Pro`** via `PurchaseService`.

**Production pricing (target):**

| Plan | Price (USD) | Intro offer | Effective monthly |
|------|-------------|-------------|-------------------|
| **Monthly** | **$4.99/mo** | **7-day free trial** | $4.99 |
| **Annual** | **$34.99/yr** | **7-day free trial** | ~$2.92 (~**42% off** vs 12×$4.99 = $59.88) |

User chooses **monthly or annual at subscribe time**. After 7 days, Apple/Google bills the plan they selected.

---

## What to configure where

| Layer | You configure | You do **not** configure here |
|-------|---------------|-------------------------------|
| **App Store Connect / Google Play** | Product IDs, $4.99 / $34.99, 7-day free trial | Entitlement logic in Swift |
| **RevenueCat dashboard** | Entitlement, product mapping, **Offering**, API keys | Dollar amounts (pulled from stores) |
| **App (`PurchaseService`)** | Product ID constants, entitlement ID, API key | Trial length or prices |
| **RevenueCat Paywall templates / AI** | Optional marketing UI only | Products, trials, or cross-platform rules |

Use the **manual dashboard + store consoles** for structure. Templates/AI are optional polish after Sandbox works.

---

## Architecture (current + future)

```text
                    ┌─────────────────────────────────────┐
                    │     Entitlement: "Kinetriq Pro"      │
                    │     (one name on all platforms)      │
                    └─────────────────────────────────────┘
                                        ▲
          ┌─────────────────────────────┼─────────────────────────────┐
          │                             │                             │
   ┌──────┴──────┐              ┌───────┴───────┐            ┌───────┴───────┐
   │  iOS (now)  │              │ Android later │            │   Web later   │
   │  monthly    │              │ monthly plan  │            │ RC Web Billing│
   │  yearly     │              │ yearly plan   │            │ or Stripe     │
   └─────────────┘              └───────────────┘            └───────────────┘
          │                             │                             │
   App Store Connect              Google Play Console          Stripe / RC Web
```

**App User ID:** Use a stable ID across devices (`Purchases.logIn(userId)` when you add accounts). Required for web + multi-device later.

---

## App code (this branch)

| Piece | Location |
|-------|----------|
| SDK | `RevenueCat`, `RevenueCatUI` in `project.yml` |
| Service | `Sources/Services/PurchaseService.swift` |
| Paywall | `Sources/Views/PaywallView.swift` |
| Launch gate | `ContentView` — paywall when `!isProUser` |
| Settings | Subscription status, restore, Customer Center, promo codes, App Store offer codes |

**Constants (must match dashboard + stores):**

| Constant | Value |
|----------|--------|
| Entitlement | `Kinetriq Pro` (legacy `pro` also accepted during setup) |
| Monthly product ID | `monthly` |
| Yearly product ID | `yearly` |
| API key | Replace `test_…` in `PurchaseService.apiKey` with **iOS public SDK key** for production |

Branch: **`feature/revenuecat-subscriptions`**

---

## Part 1 — App Store Connect (iOS)

### 1. Subscription group

1. [App Store Connect](https://appstoreconnect.apple.com) → your app → **Subscriptions**.
2. Create **one subscription group** (e.g. `Kinetriq Pro`).
3. Set group display name and optional review notes (form-analysis / fitness app).

### 2. Monthly product

| Field | Value |
|-------|--------|
| **Reference name** | Kinetriq Pro Monthly |
| **Product ID** | `monthly` |
| **Duration** | 1 month |
| **Price** | **$4.99** (USD Tier 1; add other territories as needed) |
| **Introductory offer** | **Free trial — 7 days** |
| **Subscription level** | 1 (if Apple asks for ordering within group) |

### 3. Yearly product

| Field | Value |
|-------|--------|
| **Reference name** | Kinetriq Pro Annual |
| **Product ID** | `yearly` |
| **Duration** | 1 year |
| **Price** | **$34.99** |
| **Introductory offer** | **Free trial — 7 days** |
| **Marketing** | “Save ~42% vs monthly” (paywall copy; Apple shows store price) |

### 4. If Apple rejects short product IDs

Use reverse-DNS IDs and update **both** App Store Connect **and** `PurchaseService`:

```text
com.kevinjones.kinetriq.pro.monthly
com.kevinjones.kinetriq.pro.yearly
```

### 5. Before review

- Subscription localization (display name, description).
- **App Review screenshot** for subscriptions.
- Privacy policy URL (required for subscriptions).
- Sandbox tester account under **Users and Access → Sandbox**.

---

## Part 2 — RevenueCat dashboard (iOS)

### 1. Project & app

1. [app.revenuecat.com](https://app.revenuecat.com) → project **Kinetriq**.
2. **Apps** → add **iOS** app:
   - Bundle ID: `com.kevinjones.KevLines2-0`
   - App Store Connect shared secret / App Store Server API (follow RC onboarding).

### 2. Entitlement

| Identifier | Display name |
|------------|--------------|
| `Kinetriq Pro` | Kinetriq Pro |

All paid products attach to **this one** entitlement.

### 3. Products

| Store | Product identifier | Type |
|-------|-------------------|------|
| App Store | `monthly` | Subscription |
| App Store | `yearly` | Subscription |

Link each to entitlement **`Kinetriq Pro`**.

### 4. Offering (current)

Create offering identifier **`default`** (or `main`) and mark as **Current**.

| Package type | Package identifier (RC default) | Product |
|--------------|----------------------------------|---------|
| Monthly | `$rc_monthly` (or custom `monthly`) | `monthly` |
| Annual | `$rc_annual` (or custom `annual`) | `yearly` |

App loads `offerings.current` in `PurchaseService.fetchOfferings()`.

### 5. Paywall (optional)

- **RevenueCat Paywall:** attach to current offering if using `RevenueCatUI` hosted paywall in `PaywallView`.
- **Custom paywall:** keep `PaywallView`; still need Offering + packages above.

Templates / AI only change layout and copy — not IDs or trials.

### 6. Customer Center

Configure in RevenueCat → **Customer Center** (manage subscription, restore, support links).

### 7. API keys

| Key | Use |
|-----|-----|
| **Public iOS SDK key** | `PurchaseService.apiKey` in production builds |
| **Secret key** | Server only — never in the app |

Test key in repo is for development; swap before App Store submission.

---

## Part 3 — Google Play (when you ship Android)

1. **Play Console** → app → **Monetize → Subscriptions**.
2. One subscription product with **two base plans** (or two products in one group):
   - **Monthly** — $4.99, **7-day free trial**
   - **Yearly** — $34.99, **7-day free trial**
3. Product IDs may match iOS (`monthly`, `yearly`) or use Play-specific IDs (e.g. `kinetriq_pro_monthly`).
4. **RevenueCat** → add **Android** app to the **same project** → map Play products → same entitlement **`Kinetriq Pro`**.
5. Add **Google Play service credentials** to RevenueCat (JSON key).
6. Android SDK: `purchases-android` (separate integration when you build the Android app).

---

## Part 4 — Web (when you ship a web app)

1. Keep **same RevenueCat project** and entitlement **`Kinetriq Pro`**.
2. Pick billing:
   - **RevenueCat Web Billing** (recommended if starting fresh) — Stripe as processor, RC owns catalog sync.
   - **Stripe Billing** + RevenueCat Web SDK / Purchase Links — if you already use Stripe.
3. Create web products at **$4.99/mo** and **$34.99/yr** with **7-day trial** in the billing engine RC uses.
4. **App User ID:** user signs in on web and mobile with the same ID; call `Purchases.logIn(userId)` on each platform.
5. **Redemption links:** RC can deep-link web buyers into the iOS app with entitlements applied.
6. **US iOS (optional later):** RevenueCat **Web Purchase Button** for Stripe checkout from in-app paywall where Apple allows external purchase links — keep **native IAP as default** worldwide unless you deliberately A/B test US web checkout.

---

## Promo / free access (outside subscriptions)

| Path | Use |
|------|-----|
| **Private codes** | `PurchaseService.validPromoCodes` — trainers, beta, press (rotate via app update) |
| **App Store offer codes** | `presentAppStoreOfferCodeRedemption()` — codes configured in App Store Connect |

Promo codes bypass RevenueCat; they are for humans you trust, not public distribution.

---

## Sandbox testing checklist (iOS)

- [ ] Build from `feature/revenuecat-subscriptions` with **non-placeholder** RevenueCat iOS SDK key.
- [ ] Device signed into **Sandbox** Apple ID (Settings → App Store → Sandbox Account).
- [ ] App shows paywall when no active entitlement.
- [ ] **Monthly:** purchase sheet shows **7-day free trial**, then $4.99/mo.
- [ ] **Annual:** purchase sheet shows **7-day free trial**, then $34.99/yr.
- [ ] After purchase, `isProUser == true` and paywall dismisses.
- [ ] **Restore purchases** works from paywall and Settings.
- [ ] **Customer Center** opens from Settings.
- [ ] Private promo code unlocks without network.
- [ ] App Store offer-code sheet opens (optional smoke test).

Accelerate Sandbox trial expiry: [Apple Sandbox subscription renewal rates](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases_with_sandbox).

---

## Launch sequence (recommended)

| Phase | Monetization |
|-------|----------------|
| **TestFlight (main fixes)** | Free — stay on `fix/saved-video-loading` without paywall |
| **Paid beta** | Merge `feature/revenuecat-subscriptions`; Sandbox only |
| **App Store v1** | ASC products live + production RC key + Option A pricing ($4.99 / $34.99) |
| **Android** | Play products + RC Android app |
| **Web** | RC Web Billing + shared App User ID |

Broader pricing context and competitor tables: [monetization/Monetization-Review.md](monetization/Monetization-Review.md) and CSVs in `docs/monetization/`.

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Paywall shows no prices | Offering not **Current**; products not linked in RC; ASC agreements/tax/banking incomplete |
| Purchase succeeds but still locked | Entitlement ID mismatch — must be `Kinetriq Pro` in RC and active on customer |
| Wrong price in app | Price is from Apple, not RC — fix in App Store Connect |
| Works in dev, locks everyone in prod | `apiKey` still placeholder or wrong platform key |
| Restore finds nothing | Wrong Sandbox Apple ID; purchased with different Apple ID |

---

## Quick reference

```text
Entitlement:     Kinetriq Pro
Product IDs:     monthly ($4.99/mo, 7-day trial)
                 yearly  ($34.99/yr, 7-day trial)
Offering:        default (current)
Packages:        monthly + annual → same entitlement
```
