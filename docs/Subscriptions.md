# Kinetriq subscriptions and accounts

Kinetriq uses two separate systems:

- **Supabase Auth** owns user login and the stable cross-device user ID.
- **RevenueCat** owns store purchase state and the `kinetriq_pro` entitlement.

The app combines those with backend promo/comp entitlements into one access decision:

```text
hasProAccess = active RevenueCat entitlement OR active backend comp/promo entitlement OR development unlock
```

Development unlock is active only while the RevenueCat API key is still the placeholder in `project.yml`.

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

Configure:

1. Create one RevenueCat project for Kinetriq.
2. Add the iOS app with bundle ID `com.kevinjones.Kinetriq` (matches `project.yml`).
3. Create entitlement `kinetriq_pro`.
4. Add App Store products:
   - `com.kevinjones.kinetriq.pro.monthly`
   - `com.kevinjones.kinetriq.pro.yearly`
5. Attach both products to `kinetriq_pro`.
6. Create an offering, mark it current, and include monthly and annual packages.
7. Configure Customer Center or keep the Apple manage-subscriptions link as the fallback.

## Promo codes

Three promo paths are supported:

| Code type | Recommended source | Notes |
|-----------|--------------------|-------|
| Free month | App Store offer code / promotional offer | RevenueCat mirrors the entitlement after redemption |
| Discount | App Store offer code / promotional offer | Define discount amount and duration before launch |
| Unlimited free access | Supabase `redeem-promo-code` Edge Function | Tied to user account and works across devices |

Local development fallback codes are available only while Supabase is unconfigured:

- `KINETRIQ-MONTH`
- `KINETRIQ-DISCOUNT`
- `KINETRIQ-COMP`

Do not rely on app-binary hardcoded codes for production campaigns.

## Sandbox checklist

- [ ] Real RevenueCat iOS public SDK key is in the generated Info.plist.
- [ ] Real Supabase URL and anon key are in the generated Info.plist.
- [ ] User can create account and sign in.
- [ ] RevenueCat customer uses the Supabase user UUID.
- [ ] Paywall loads current offering.
- [ ] Monthly purchase sheet shows 7-day free trial and $4.99/mo.
- [ ] Annual purchase sheet shows 7-day free trial and annual discount.
- [ ] Restore purchases works.
- [ ] App Store offer-code sheet opens.
- [ ] Supabase promo redemption works for a comp account.
- [ ] Account deletion Edge Function is configured before App Store submission.
