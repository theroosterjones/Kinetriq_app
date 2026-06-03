# RevenueCat subscription setup

Kinetriq uses RevenueCat for subscription state so the same entitlement model can work across iOS now and Android / desktop later.

## Current implementation

- SDK packages: `RevenueCat` and `RevenueCatUI` from `purchases-ios-spm`
- Service: `Sources/Services/PurchaseService.swift`
- Paywall: `Sources/Views/PaywallView.swift`
- App gate: `ContentView` presents the paywall on launch when `isProUser == false`
- Settings support: `SettingsView` exposes subscription status, App Store subscription management, Customer Center, private promo codes, and App Store offer-code redemption

## RevenueCat dashboard

Create or verify:

1. App: iOS app with bundle ID `com.kevinjones.KevLines2-0`
2. Entitlement: `Kinetriq Pro`
3. Products:
   - `monthly`
   - `yearly`
4. Offering: set a current offering that includes monthly and yearly packages
5. Paywall: configure a RevenueCat Paywall for the current offering
6. Customer Center: configure support / cancellation / restore behavior in RevenueCat

`PurchaseService` also accepts entitlement identifier `pro` while setup is being finalized, but `Kinetriq Pro` is the intended production entitlement.

## App Store Connect

Create one subscription group with:

- Monthly subscription product ID: `monthly`
- Yearly subscription product ID: `yearly`
- 7-day free trial on both products

If Apple requires globally unique product IDs for the existing app, update `PurchaseService.monthlyProductID` and `PurchaseService.yearlyProductID` to the final App Store product IDs and mirror those IDs in RevenueCat.

## Promo / free access

Two paths exist:

- Private offline codes in `PurchaseService.validPromoCodes` for trainer, beta, and press access.
- Native App Store offer-code redemption via `SKPaymentQueue.default().presentCodeRedemptionSheet()` for production subscription offer codes configured in App Store Connect.

## Testing checklist

1. Build from `feature/revenuecat-subscriptions`.
2. Confirm the app opens to RevenueCat's hosted paywall when no active entitlement exists.
3. Start a sandbox trial for monthly and yearly.
4. Confirm purchase completion dismisses the gate by setting `isProUser == true`.
5. Restore purchases from the paywall and Settings.
6. Redeem a private promo code and confirm the app unlocks offline.
7. Open Customer Center from Settings.
