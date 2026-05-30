import SwiftUI

struct SettingsView: View {
    @ObservedObject private var purchases = PurchaseService.shared
    @State private var config = AnalysisConfig.default
    @State private var showAdvanced = false
    @State private var showPromoCode = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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
                        Text("3.4.2")
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
                    Text("Kinetriq is made and used by fitness professionals such as yourself. If you have any feedback, INCLUDING features you would like to have added, please reach out to me and let me know. I'd be happy to add the feature if it improves the functionality.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
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

    // MARK: - Subscription section

    @ViewBuilder
    private var subscriptionSection: some View {
        Section("Subscription") {
            if purchases.hasRedeemedPromoCode() {
                HStack {
                    Label("Kinetriq Pro", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text("Promo access")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if purchases.isProUser {
                HStack {
                    Label("Kinetriq Pro", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text("Active")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Manage Subscription") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.blue)
            } else {
                HStack {
                    Label("No active subscription", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
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

                Button("Have a promo code?") { showPromoCode = true }
                    .foregroundStyle(.cyan)
            }
        }
    }
}
