import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var purchases = PurchaseService.shared
    @ObservedObject private var sync = SyncService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var config = AnalysisConfig.default
    @State private var showAdvanced = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var showManagePlan = false

    var body: some View {
        NavigationStack {
            Form {
                brandHeader
                accountSection
                subscriptionSection
                progressSyncSection
                coachingSection

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
                        Text(Self.appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Processing")
                        Spacer()
                        Text("100% On-Device")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Video storage")
                        Spacer()
                        Text(AnalysisStorage.formattedTotalSize)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Tips, camera setup & FAQ", systemImage: "lightbulb.max.fill")
                    }
                    NavigationLink {
                        AttributionView()
                    } label: {
                        Label("Credits & licenses", systemImage: "text.book.closed.fill")
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
        .alert("Restore Purchases", isPresented: .init(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
        .sheet(isPresented: $showManagePlan) {
            PaywallView(isManagement: true)
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
                    Text("Movement Intelligence · v\(Self.appVersion)")
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
                        Text("Manage account and deletion")
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
        Section {
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

            Button(purchases.hasProAccess ? "Change or Upgrade Plan" : "View Plans") {
                showManagePlan = true
            }
            .foregroundStyle(KColor.accent)

            Button("Restore Purchases") {
                Task {
                    isRestoring = true
                    defer { isRestoring = false }
                    do {
                        try await purchases.restorePurchases()
                        restoreMessage = "Purchases restored successfully."
                    } catch {
                        restoreMessage = PurchaseService.userFacingMessage(for: error)
                            ?? "Restore cancelled."
                    }
                }
            }
            .disabled(isRestoring)

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
        } header: {
            Text("Subscription")
        } footer: {
            Text("Switch between monthly and yearly anytime with Change or Upgrade Plan. Cancel or change billing in Manage Apple Subscription. If you already subscribed but still see the paywall, tap Restore Purchases.")
        }
    }

    private var coachingSection: some View {
        Section {
            NavigationLink {
                CoachRosterView()
            } label: {
                Label(
                    purchases.hasCoachAccess ? "My Clients" : "Kinetriq for Coaches",
                    systemImage: "person.2.fill"
                )
            }
            NavigationLink {
                ConnectCoachView()
            } label: {
                Label("Connect with a Coach", systemImage: "link")
            }
        } header: {
            Text("Coaching")
        } footer: {
            Text("Coaches see their clients' measurements — reps, angles, tempo, scores, and grades. Video is never shared either way.")
        }
    }

    private var progressSyncSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { sync.isEnabledByUser },
                set: { sync.isEnabledByUser = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync progress to my account")
                    Text("Measurements only — video never leaves this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(KColor.accent)

            if sync.isEnabledByUser && sync.isAvailable {
                Button("Sync Now") {
                    Task { await sync.syncAll(context: modelContext) }
                }
                .foregroundStyle(KColor.accent)
                .disabled(sync.isSyncing)

                HStack {
                    Text("Last synced")
                    Spacer()
                    Text(sync.isSyncing
                         ? "Syncing…"
                         : sync.lastSyncedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = sync.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(KColor.warning)
                }
            }
        } header: {
            Text("Progress Sync")
        } footer: {
            Text("Reps, joint angles, tempo, scores, and grades sync to your Kinetriq account so your history survives a new phone. Your videos stay in Kinetriq's storage on this device and are never uploaded. Turn this off and everything still works — your history just stays here.")
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var subscriptionStatusText: String {
        #if DEBUG
        if purchases.developmentUnlocked {
            return "Dev unlocked"
        }
        #endif
        if purchases.hasRevenueCatEntitlement {
            return "Active"
        }
        return "Inactive"
    }
}
