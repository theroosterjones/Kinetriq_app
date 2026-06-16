import SwiftUI

struct SettingsView: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var purchases = PurchaseService.shared
    @State private var config = AnalysisConfig.default
    @State private var showAdvanced = false
    @State private var showPromoCode = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                brandHeader
                accountSection
                subscriptionSection

                Section("Advanced Settings") {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        Section("Pose Detection") {
                            HStack {
                                Text("Detection Confidence")
                                Spacer()
                                Text(String(format: "%.1f", config.minDetectionConfidence))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.minDetectionConfidence, in: 0.1...1.0, step: 0.1)

                            HStack {
                                Text("Tracking Confidence")
                                Spacer()
                                Text(String(format: "%.1f", config.minTrackingConfidence))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.minTrackingConfidence, in: 0.1...1.0, step: 0.1)
                        }

                        Section("Smoothing") {
                            HStack {
                                Text("Landmark Smoothing")
                                Spacer()
                                Text(String(format: "%.1f", config.smoothingAlpha))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.smoothingAlpha, in: 0.1...1.0, step: 0.1)
                        }

                        Section("Tempo Tracking") {
                            HStack {
                                Text("Velocity Threshold")
                                Spacer()
                                Text(String(format: "%.0f°/s", config.tempoVelocityThreshold))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.tempoVelocityThreshold, in: 5...50, step: 5)
                        }
                    } label: {
                        Label("Advanced Settings", systemImage: "slider.horizontal.3")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("3.4.3")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Processing")
                        Spacer()
                        Text("100% On-Device")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Tips, camera setup & FAQ", systemImage: "lightbulb.max.fill")
                    }
                }

                Section {
                    Text("Kinetriq is made and used by fitness professionals such as yourself. If you have any feedback, INCLUDING features you would like to have added, please reach out to me and let me know. I'd be happy to add the feature if it improves the functionality.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showPromoCode) { PromoCodeView() }
        .alert("Restore Purchases", isPresented: .init(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var brandHeader: some View {
        Section {
            HStack(spacing: KSpacing.md) {
                ZStack {
                    Circle().fill(KColor.accent.opacity(0.14)).frame(width: 56, height: 56)
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(KColor.brandGradient)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kinetriq")
                        .font(KFont.title2)
                    Text("Movement Intelligence · v3.4.3")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if auth.isAuthenticated {
                NavigationLink {
                    AccountView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.currentEmail ?? "Signed in")
                        Text("Manage account, promo codes, and deletion")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                NavigationLink("Sign In") {
                    LoginView()
                }
            }
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                Label(
                    purchases.hasProAccess ? "Kinetriq Pro" : "No active subscription",
                    systemImage: purchases.hasProAccess ? "checkmark.seal.fill" : "xmark.circle"
                )
                .foregroundStyle(purchases.hasProAccess ? AnyShapeStyle(KColor.accent) : AnyShapeStyle(.secondary))
                Spacer()
                Text(subscriptionStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let code = purchases.redeemedPromoCode() {
                LabeledContent("Promo code", value: code)
            }

            Button("Restore Purchases") {
                Task {
                    isRestoring = true
                    defer { isRestoring = false }
                    do {
                        try await purchases.restorePurchases()
                        restoreMessage = "Purchases restored successfully."
                    } catch {
                        restoreMessage = error.localizedDescription
                    }
                }
            }
            .disabled(isRestoring)

            Button("Redeem Promo Code") { showPromoCode = true }
                .foregroundStyle(KColor.accent)

            Button("Redeem App Store Offer Code") {
                purchases.presentAppStoreOfferCodeRedemption()
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await purchases.refreshStatus()
                }
            }
            .foregroundStyle(KColor.accent)

            Button("Manage Apple Subscription") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private var subscriptionStatusText: String {
        if purchases.developmentUnlocked {
            return "Dev unlocked"
        }
        if purchases.hasRedeemedPromoCode() {
            return "Promo"
        }
        if purchases.hasRevenueCatEntitlement {
            return "Active"
        }
        return "Inactive"
    }
}
