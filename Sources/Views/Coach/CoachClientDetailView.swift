import SwiftUI

/// What a coach sees for one client.
///
/// Measurements and the coaching notes generated alongside them. No video — the
/// backing tables have no video column, so there is nothing to show even if the UI
/// wanted to, which is exactly the property the privacy claim depends on.
struct CoachClientDetailView: View {
    let client: CoachClient

    @ObservedObject private var coach = CoachService.shared
    @State private var showingRemoveConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private var reason: TriageReason { CoachTriage.reason(for: client) }

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(spacing: KSpacing.lg) {
                    statusCard
                    adherenceCard
                    privacyNote
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.top, KSpacing.xs)
                .padding(.bottom, KSpacing.xxl)
            }
        }
        .navigationTitle(client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingRemoveConfirmation = true
                    } label: {
                        Label("Remove client", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Remove \(client.displayName)?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    await coach.removeClient(client)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop seeing their measurements. Their own history is untouched, and they can be re-invited later.")
        }
    }

    private var statusCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack(spacing: KSpacing.md) {
                    if let score = client.latestScore {
                        ScoreRing(value: score, size: 96, lineWidth: 10, caption: "LATEST")
                    }
                    VStack(alignment: .leading, spacing: KSpacing.xs) {
                        KPill(text: reason.label,
                              tint: reason.isAttention ? KColor.warning : KColor.teal,
                              filled: true)
                        if let delta = client.scoreDelta {
                            Text(delta >= 0
                                 ? "Up \(delta) points from the session before"
                                 : "Down \(abs(delta)) points from the session before")
                                .font(KFont.caption)
                                .foregroundStyle(delta >= 0 ? KColor.success : KColor.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let movement = client.latestMovement {
                            Text("Last analyzed: \(movement)")
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if client.openAsymmetryFlag {
                    InfoBanner(
                        icon: "arrow.left.arrow.right",
                        title: "Asymmetry flagged",
                        message: "An assessment in the last 30 days showed a side-to-side difference large enough to flag. Worth reviewing before adding load.",
                        tint: KColor.warning
                    )
                }
            }
        }
    }

    private var adherenceCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                Eyebrow(text: "Adherence")
                HStack(spacing: KSpacing.sm) {
                    StatTile(icon: "calendar",
                             value: "\(client.sessionsLast14Days)",
                             label: "Last 14 days",
                             tint: client.sessionsLast14Days > 0 ? KColor.teal : KColor.textTertiary)
                    StatTile(icon: "clock.arrow.circlepath",
                             value: lastSessionValue,
                             label: "Last session",
                             tint: KColor.accent)
                }
                Text("Linked since \(client.linkedAt.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.textTertiary)
            }
        }
    }

    private var lastSessionValue: String {
        guard let days = client.daysSinceLastSession else { return "—" }
        if days == 0 { return "Today" }
        if days == 1 { return "1d" }
        return "\(days)d"
    }

    private var privacyNote: some View {
        InfoBanner(
            icon: "lock.shield",
            title: "Measurements only",
            message: "You see what Kinetriq measured — reps, joint angles, tempo, scores, and assessment grades. \(client.displayName)'s video stays on their device and is never uploaded. If you need to watch a rep, ask them to share the clip directly.",
            tint: KColor.teal
        )
    }
}
