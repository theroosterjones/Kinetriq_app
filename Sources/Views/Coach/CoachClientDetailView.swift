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
    @State private var sessions: [CoachClientSession]?
    @State private var isLoadingSessions = true
    @Environment(\.dismiss) private var dismiss

    private var reason: TriageReason { CoachTriage.reason(for: client) }

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(spacing: KSpacing.lg) {
                    statusCard
                    adherenceCard
                    sessionsSection
                    privacyNote
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.top, KSpacing.xs)
                .padding(.bottom, KSpacing.xxl)
            }
            .refreshable { await loadSessions() }
        }
        .task { await loadSessions() }
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
                                 ? "Up \(delta) point\(delta == 1 ? "" : "s") from the session before"
                                 : "Down \(abs(delta)) point\(abs(delta) == 1 ? "" : "s") from the session before")
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

    /// `@MainActor` because a `private func` on a `View` is not main-actor isolated, and
    /// `.task` / `.refreshable` hand it a `@Sendable` closure that inherits nothing — so
    /// without this the two `@State` writes below land off the main thread.
    @MainActor
    private func loadSessions() async {
        sessions = await coach.fetchSessions(for: client.clientUserID)
        isLoadingSessions = false
    }

    // MARK: - Sessions

    /// The same rows the web dashboard lists, read through the same policy. A coach
    /// checking a client on their phone and on a laptop has to see one history.
    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            SectionHeader("Sessions", eyebrow: "Measurements")

            if isLoadingSessions {
                KCard { ProgressView().frame(maxWidth: .infinity) }
            } else if let sessions, !sessions.isEmpty {
                KCard(padding: KSpacing.sm) {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            if index > 0 { Divider().overlay(KColor.separator) }
                            row(for: session)
                        }
                    }
                }
            } else if sessions == nil {
                InfoBanner(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load sessions",
                    message: coach.sessionsErrorMessage
                        ?? "The roster above is still accurate. Pull down to try again.",
                    tint: KColor.warning
                )
            } else {
                KCard {
                    Text("Nothing analyzed yet. Sessions appear here as soon as \(client.displayName) analyzes a set with sync turned on.")
                        .font(KFont.caption)
                        .foregroundStyle(KColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row(for session: CoachClientSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.movementName)
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textPrimary)
                Spacer(minLength: KSpacing.xs)
                if let score = session.score {
                    Text("\(score)")
                        .font(KFont.numeral(20))
                        .monospacedDigit()
                        .foregroundStyle(KColor.score(score))
                } else if let grade = session.grade {
                    Text(grade.rawValue)
                        .font(KFont.numeral(20))
                        .foregroundStyle(KColor.grade(grade))
                }
            }
            Text(session.summaryLine)
                .font(KFont.caption)
                .foregroundStyle(KColor.textSecondary)
            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(KColor.textTertiary)

            // The tracking rate is the caveat on every number above it. A set detected
            // in 30% of frames has real measurements attached and they mean much less.
            if session.poseDetectionRate < 0.7 {
                TrackingQualityRow(rate: session.poseDetectionRate)
                    .padding(.top, 2)
            }
            if let insight = session.insights.first {
                Text(insight)
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, KSpacing.xs)
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
