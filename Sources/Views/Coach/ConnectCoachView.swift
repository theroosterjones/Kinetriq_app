import SwiftUI

/// The client half of coach linking: enter the code a coach sent you.
///
/// Linking is always coach-initiated and client-accepted. A coach can never reach
/// into an account that did not opt in, and the same screen is where the client
/// takes it back.
struct ConnectCoachView: View {
    @ObservedObject private var coach = CoachService.shared
    @ObservedObject private var sync = SyncService.shared

    @State private var code = ""
    @State private var isRedeeming = false
    @State private var linkedCoachName: String?

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(spacing: KSpacing.lg) {
                    if let linkedCoachName {
                        successCard(coachName: linkedCoachName)
                    } else {
                        entryCard
                    }
                    whatTheySeeCard
                    if !sync.isEnabledByUser {
                        InfoBanner(
                            icon: "exclamationmark.triangle.fill",
                            title: "Progress sync is off",
                            message: "A coach reads your measurements from your Kinetriq account. With sync turned off there's nothing for them to see — turn it on in Settings if you want them to follow your progress.",
                            tint: KColor.warning
                        )
                    }
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.top, KSpacing.xs)
                .padding(.bottom, KSpacing.xxl)
            }
        }
        .navigationTitle("Connect with a coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var entryCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                Eyebrow(text: "Invite code")
                TextField("8-character code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        isRedeeming = true
                        defer { isRedeeming = false }
                        linkedCoachName = await coach.redeemInvite(code: code)
                    }
                } label: {
                    if isRedeeming {
                        ProgressView().tint(.white)
                    } else {
                        Label("Connect", systemImage: "link")
                    }
                }
                .buttonStyle(KPrimaryButtonStyle())
                .disabled(isRedeeming || code.trimmingCharacters(in: .whitespaces).count < 4)

                if let error = coach.errorMessage {
                    Text(error)
                        .font(KFont.caption)
                        .foregroundStyle(KColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func successCard(coachName: String) -> some View {
        KCard {
            VStack(spacing: KSpacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(KColor.success)
                Text("Connected to \(coachName)")
                    .font(KFont.title2)
                    .foregroundStyle(KColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Your measurements will appear on their roster from your next analysis.")
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var whatTheySeeCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                SectionHeader("What your coach can see", eyebrow: "Before you connect")
                row("checkmark.circle.fill", KColor.success,
                    "Reps, joint angles, tempo, consistency scores, and assessment grades")
                row("checkmark.circle.fill", KColor.success,
                    "When you last trained and how often")
                row("xmark.circle.fill", KColor.danger,
                    "Your videos — never. They stay on this device and are never uploaded")
                row("xmark.circle.fill", KColor.danger,
                    "Anything from before you connected, or after you disconnect")
                Text("You can disconnect at any time, and access stops immediately.")
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func row(_ icon: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: KSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(KFont.caption)
                .foregroundStyle(KColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
