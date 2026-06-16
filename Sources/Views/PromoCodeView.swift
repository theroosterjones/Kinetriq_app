import SwiftUI

struct PromoCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var purchases = PurchaseService.shared
    @State private var code = ""
    @State private var showInvalid = false
    @State private var showSuccess = false
    @State private var isRedeeming = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan)
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    Text("Enter Promo Code")
                        .font(.headline)
                    Text("Codes can unlock a free month, a discount, or comp access depending on the campaign.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("e.g. KINETRIQ-COMP", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: code) { _, _ in showInvalid = false }

                if showInvalid {
                    Label(purchases.purchaseError ?? "Code not recognized. Check the spelling and try again.", systemImage: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: redeem) {
                    Group {
                        if isRedeeming {
                            ProgressView().tint(.black)
                        } else {
                            Text("Redeem")
                                .font(.headline.bold())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(code.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.4) : Color.cyan)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming)

                if AppEnvironment.isSupabaseConfigured && !auth.isAuthenticated {
                    Label("Sign in before redeeming production promo codes.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Promo Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Code Accepted", isPresented: $showSuccess) {
                Button("Let's Go") { dismiss() }
            } message: {
                Text("Kinetriq Pro access is now active on this account.")
            }
        }
    }

    private func redeem() {
        Task {
            isRedeeming = true
            defer { isRedeeming = false }
            let success = await purchases.redeemPromoCode(code, authSession: auth.session)
            showSuccess = success
            showInvalid = !success
        }
    }
}
