import RevenueCat
import RevenueCatUI
import SwiftUI

struct PaywallView: View {
    @ObservedObject private var service = PurchaseService.shared
    @State private var selectedPlan: PlanType = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showPromoCode = false
    @State private var errorMessage: String?

    enum PlanType { case monthly, yearly }

    var body: some View {
        if service.hasConfiguredAPIKey {
            revenueCatPaywall
        } else {
            fallbackPaywall
        }
    }

    private var revenueCatPaywall: some View {
        ZStack(alignment: .topTrailing) {
            RevenueCatUI.PaywallView(displayCloseButton: false)
                .onPurchaseCompleted { customerInfo in
                    service.updateSubscriptionStatus(from: customerInfo)
                }
                .onRestoreCompleted { customerInfo in
                    service.updateSubscriptionStatus(from: customerInfo)
                }
                .onPurchaseFailure { error in
                    errorMessage = error.localizedDescription
                }
                .onRestoreFailure { error in
                    errorMessage = error.localizedDescription
                }

            accessOptionsMenu
                .padding(.top, 16)
                .padding(.trailing, 16)
        }
        .sheet(isPresented: $showPromoCode) { PromoCodeView() }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var fallbackPaywall: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    featuresSection
                    planPicker
                    trialNote
                    ctaButton
                    secondaryActions
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .task { await service.fetchOfferings() }
        .sheet(isPresented: $showPromoCode) { PromoCodeView() }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var accessOptionsMenu: some View {
        Menu {
            Button("Enter Promo Code") { showPromoCode = true }
            Button("Redeem App Store Offer Code") {
                service.presentAppStoreOfferCodeRedemption()
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await service.refreshStatus()
                }
            }
        } label: {
            Label("Access Options", systemImage: "ellipsis.circle")
                .font(.footnote.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.white)
                .padding(.top, 48)

            Text("Kinetriq Pro")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("Movement Intelligence, Unlimited.")
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(icon: "figure.strengthtraining.traditional", text: "Unlimited exercise analysis")
            FeatureRow(icon: "checkmark.seal.fill", text: "All movement assessments")
            FeatureRow(icon: "waveform.path.ecg", text: "Tempo tracking and rep counting")
            FeatureRow(icon: "square.and.arrow.up", text: "Export annotated videos")
            FeatureRow(icon: "iphone", text: "On-device analysis with account-based access")
        }
        .padding(.horizontal, 4)
    }

    private var planPicker: some View {
        HStack(spacing: 12) {
            PlanCard(
                title: "Monthly",
                price: monthlyPrice,
                perUnit: "/ month",
                badge: nil,
                isSelected: selectedPlan == .monthly,
                onTap: { selectedPlan = .monthly }
            )
            PlanCard(
                title: "Annual",
                price: yearlyPrice,
                perUnit: "/ year",
                badge: "Best Value",
                isSelected: selectedPlan == .yearly,
                onTap: { selectedPlan = .yearly }
            )
        }
    }

    private var trialNote: some View {
        Text("Start your **7-day free trial**. Monthly is $4.99 after trial; annual uses the discounted yearly price configured in App Store Connect.")
            .font(.footnote)
            .foregroundStyle(.gray)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private var ctaButton: some View {
        Button {
            Task {
                isPurchasing = true
                defer { isPurchasing = false }
                guard let package = selectedPackage else { return }
                do {
                    try await service.purchase(package)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text("Start Free Trial")
                        .font(.headline.bold())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(selectedPackage == nil || isPurchasing || isRestoring)
    }

    private var secondaryActions: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    isRestoring = true
                    defer { isRestoring = false }
                    do {
                        try await service.restorePurchases()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Group {
                    if isRestoring {
                        ProgressView().tint(.gray)
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.gray)
            }
            .disabled(isPurchasing || isRestoring)

            Button("Have a promo code?") { showPromoCode = true }
                .font(.footnote)
                .foregroundStyle(.cyan)

            Button("Redeem App Store Offer Code") {
                service.presentAppStoreOfferCodeRedemption()
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await service.refreshStatus()
                }
            }
            .font(.footnote)
            .foregroundStyle(.cyan)
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("Subscription auto-renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in iOS Settings or your Apple account.")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.35))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                if let termsURL = AppEnvironment.termsURL {
                    Link("Terms", destination: termsURL)
                }
                if let privacyURL = AppEnvironment.privacyPolicyURL {
                    Link("Privacy", destination: privacyURL)
                }
            }
            .font(.caption2)
        }
        .padding(.horizontal, 4)
    }

    private var selectedPackage: Package? {
        let current = service.offerings?.current
        switch selectedPlan {
        case .monthly:
            return package(productID: PurchaseService.monthlyProductID) ?? current?.monthly
        case .yearly:
            return package(productID: PurchaseService.yearlyProductID) ?? current?.annual
        }
    }

    private func package(productID: String) -> Package? {
        service.offerings?.current?.availablePackages.first {
            $0.storeProduct.productIdentifier == productID || $0.identifier == productID
        }
    }

    private var monthlyPrice: String {
        (package(productID: PurchaseService.monthlyProductID) ?? service.offerings?.current?.monthly)?
            .localizedPriceString ?? "$4.99"
    }

    private var yearlyPrice: String {
        (package(productID: PurchaseService.yearlyProductID) ?? service.offerings?.current?.annual)?
            .localizedPriceString ?? "$34.99"
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.cyan)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
        }
    }
}

private struct PlanCard: View {
    let title: String
    let price: String
    let perUnit: String
    let badge: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                } else {
                    Spacer().frame(height: 18)
                }
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(price)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(perUnit)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2)
            )
        }
    }
}
