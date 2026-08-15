import SwiftUI

struct AccountView: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var purchases = PurchaseService.shared
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: auth.currentEmail ?? "Unknown")
                LabeledContent("User ID", value: auth.currentUserID ?? "Unknown")
                    .font(.footnote)
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }

            Section("Access") {
                HStack {
                    Label(
                        purchases.hasProAccess ? "Kinetriq Pro" : "No active Pro access",
                        systemImage: purchases.hasProAccess ? "checkmark.seal.fill" : "xmark.circle"
                    )
                    .foregroundStyle(purchases.hasProAccess ? .cyan : .secondary)
                    Spacer()
                    Text(accessLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Redeem App Store Offer Code") {
                    purchases.presentAppStoreOfferCodeRedemption()
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await purchases.refreshStatus()
                    }
                }
            }

            Section {
                Button("Request Account Deletion", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } header: {
                Text("Account Management")
            } footer: {
                Text("Account deletion requires the Supabase delete-account Edge Function before launch.")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Request Account Deletion", role: .destructive) {
                Task { await auth.requestAccountDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out after the backend deletion function succeeds.")
        }
    }

    private var accessLabel: String {
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
