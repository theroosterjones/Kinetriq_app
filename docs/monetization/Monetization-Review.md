# Kinetriq — monetization & competitor pricing review

**Purpose:** Compare App Store form-analysis apps, pricing models, and revenue scenarios for Kinetriq.  
**Last updated:** June 2026  
**US App Store prices** unless noted — confirm live listings before launch.

---

## How to use this pack

| File | Open in | Contents |
|------|---------|----------|
| [competitor-apps.csv](competitor-apps.csv) | Excel / Numbers / Sheets | Apps, positioning, similarity to Kinetriq |
| [competitor-pricing.csv](competitor-pricing.csv) | Excel / Numbers / Sheets | Each app’s model and dollar amounts |
| [kinetriq-pricing-options.csv](kinetriq-pricing-options.csv) | Excel / Numbers / Sheets | Options A–E (subs + hybrid) |
| [ad-revenue-scenarios.csv](ad-revenue-scenarios.csv) | Excel / Numbers / Sheets | Ads-only revenue at different MAU |
| [subscription-revenue-scenarios.csv](subscription-revenue-scenarios.csv) | Excel / Numbers / Sheets | Sub revenue at different MAU & conversion |
| [hybrid-revenue-example.csv](hybrid-revenue-example.csv) | Excel / Numbers / Sheets | Ads + subs combined (example) |
| [decision-matrix.csv](decision-matrix.csv) | Excel / Numbers / Sheets | Which option when |
| [ad-formats-reference.csv](ad-formats-reference.csv) | Excel / Numbers / Sheets | Ad types, eCPM, placement in Kinetriq |

**Tip:** In Excel, use **Data → From Text/CSV** and set delimiter to comma. In Numbers, **File → Open** each CSV.

---

## Executive summary

| Path | Typical price | Best when |
|------|---------------|-----------|
| **Option A — Specialist wedge** | $4.99/mo or $34.99/yr; optional $14.99 lifetime | Early growth, reviews, undercut squat-only apps |
| **Option B — Trainer bundle** ⭐ | $7.99/mo or $59.99/yr (+ optional Pro+) | **Recommended App Store v1** — aligns with Gymaholic, lift-specific |
| **Option C — Serious barbell** | $9.99/mo or $79.99/yr (+ higher Pro tier later) | Strong retention; coach / competitive lifters |
| **Option D — Ads only** | $0 + AdMob/mediation | Rarely enough alone until large MAU |
| **Option E — Hybrid** | Free with ads + paid removes ads | Best long-term if free tier gets weekly use |

**Revenue rule of thumb (1k–10k MAU):** subscriptions usually beat ads by **~10×** at similar user counts. Hybrid (Option E) wins once free users return weekly.

**TestFlight now:** stay **free, no ads** until form quality and retention are validated.

---

## Kinetriq positioning (vs market)

- **Closer to:** Lift Pro, Gymaholic form check, upload-and-score tools  
- **Less like:** Squat-only apps, general home-workout posture apps  
- **Differentiators:** on-device, saved video + live, reps/tempo, assessments, export overlay  

---

## Recommended launch sequence

1. **TestFlight** — free, no paywall, no ads  
2. **App Store v1** — **Option B** + optional **rewarded ad** for +1 analysis (test ads without blocking core flow)  
3. **After retention data** — tune toward Option C or add Pro+ for coaches; **no ads on any paid tier**

---

## Formulas (for your own models)

**Ads (monthly):**

```text
Revenue ≈ (monthly_impressions ÷ 1000) × blended_eCPM
monthly_impressions ≈ MAU × impressions_per_user_per_month
```

**Subscriptions (monthly net, rough):**

```text
Net ≈ paying_subscribers × price_per_month × (1 − 0.30 Apple fee)
paying_subscribers ≈ MAU × conversion_rate
```

---

## Related repo work

- RevenueCat integration lives on branch `feature/revenuecat-subscriptions` (not merged to main fix branch).  
- Example product IDs: `monthly`, `yearly`; entitlement: `Kinetriq Pro`.

---

## Disclaimer

Competitor prices change by region, promo, and App Store experiments. Ad eCPMs vary by geo, season (Q4 higher), ATT opt-in, and mediation setup. Figures here are **planning estimates**, not financial projections.
