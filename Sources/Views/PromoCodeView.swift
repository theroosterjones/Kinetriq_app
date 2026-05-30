import SwiftUI

struct PromoCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = PurchaseService.shared
    @State private var code = ""
    @State private var showInvalid = false
    @State private var showSuccess = false

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
                    Text("A valid code unlocks Kinetriq Pro at no charge.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("e.g. KINETRIQ-TRAINER", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: code) { showInvalid = false }

                if showInvalid {
                    Label("Code not recognised. Check the spelling and try again.", systemImage: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: redeem) {
                    Text("Redeem")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.cyan)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)

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
            .alert("Code Accepted!", isPresented: $showSuccess) {
                Button("Let's Go") { dismiss() }
            } message: {
                Text("Kinetriq Pro is now unlocked. Enjoy!")
            }
        }
    }

    private func redeem() {
        if service.redeemPromoCode(code) {
            showSuccess = true
        } else {
            showInvalid = true
        }
    }
}
