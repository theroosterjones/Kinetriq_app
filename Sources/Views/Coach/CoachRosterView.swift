import SwiftUI

/// The coach's client roster, ordered as a triage queue.
///
/// Native rather than a web dashboard, at least to start. A coach already has
/// Kinetriq on the phone they film with, the roster reads the same Supabase tables
/// through the same RLS policies a web client would, and shipping a second
/// authenticated surface before anyone is paying for the first one is how a small
/// team runs out of time. The Postgres side (`coach_roster()`, the RLS policies) is
/// deliberately transport-agnostic, so a browser dashboard is additive later rather
/// than a rewrite.
struct CoachRosterView: View {
    @ObservedObject private var coach = CoachService.shared
    @ObservedObject private var purchases = PurchaseService.shared
    @ObservedObject private var auth = AuthService.shared

    @State private var showingInviteSheet = false
    @State private var generatedCode: String?
    @State private var inviteLabel = ""
    @State private var isCreatingInvite = false
    @State private var sharePayload: SharePayload?

    private var attentionCount: Int {
        CoachTriage.needingAttention(coach.clients).count
    }

    private var clientLimit: Int? {
        purchases.coachTier?.clientLimit
    }

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(spacing: KSpacing.lg) {
                    if !purchases.hasCoachAccess {
                        upsellCard
                    } else {
                        headerCard
                        if coach.clients.isEmpty {
                            emptyRoster
                        } else {
                            rosterList
                        }
                    }

                    if let error = coach.errorMessage {
                        InfoBanner(icon: "exclamationmark.triangle.fill",
                                   title: "Something went wrong",
                                   message: error,
                                   tint: KColor.warning)
                    }
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.top, KSpacing.xs)
                .padding(.bottom, KSpacing.xxl)
            }
        }
        .navigationTitle("Clients")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if purchases.hasCoachAccess {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        inviteLabel = ""
                        generatedCode = nil
                        showingInviteSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingInviteSheet) { inviteSheet }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .refreshable { await coach.refreshRoster() }
        .task {
            guard purchases.hasCoachAccess else { return }
            await coach.ensureCoachRecord(
                displayName: auth.session?.user.displayName,
                businessName: nil
            )
            await coach.refreshRoster()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Roster")
                        Text(attentionCount == 0
                             ? "Everyone's on track"
                             : "\(attentionCount) need\(attentionCount == 1 ? "s" : "") a look")
                            .font(KFont.title2)
                            .foregroundStyle(KColor.textPrimary)
                    }
                    Spacer()
                    if let clientLimit {
                        KPill(text: "\(coach.clients.count)/\(clientLimit)", tint: KColor.accent)
                    }
                }
                Text("Sorted by who needs attention first — clients who've gone quiet, whose consistency is falling, or who have a new asymmetry flag. Measurements only; client video never leaves their device.")
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - List

    private var rosterList: some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            SectionHeader("Clients", eyebrow: "Triage queue")
            KCard(padding: KSpacing.sm) {
                VStack(spacing: 0) {
                    ForEach(coach.clients) { client in
                        NavigationLink {
                            CoachClientDetailView(client: client)
                        } label: {
                            CoachClientRow(client: client)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await coach.removeClient(client) }
                            } label: {
                                Label("Remove client", systemImage: "person.badge.minus")
                            }
                        }
                        if client.id != coach.clients.last?.id {
                            Divider().overlay(KColor.separator)
                        }
                    }
                }
            }
        }
    }

    private var emptyRoster: some View {
        KCard {
            VStack(spacing: KSpacing.md) {
                KEmptyState(
                    icon: "person.2",
                    title: "No clients yet",
                    message: "Send a client an invite code. Once they redeem it in their own Kinetriq account, their measurements appear here — reps, angles, tempo, scores, and assessment grades."
                )
                Button {
                    inviteLabel = ""
                    generatedCode = nil
                    showingInviteSheet = true
                } label: {
                    Label("Invite a client", systemImage: "person.badge.plus")
                }
                .buttonStyle(KPrimaryButtonStyle())
            }
        }
    }

    // MARK: - Upsell

    private var upsellCard: some View {
        VStack(spacing: KSpacing.lg) {
            KCard {
                VStack(alignment: .leading, spacing: KSpacing.md) {
                    SectionHeader("Coach clients from one screen", eyebrow: "Kinetriq for coaches")
                    Text("Your clients run their own analyses. You see the measurements — not a folder of videos to sit through — sorted so the person who needs you is at the top.")
                        .font(KFont.subheadline)
                        .foregroundStyle(KColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().overlay(KColor.separator)

                    bullet("scope", "Triage, not an inbox", "Who's gone quiet, whose consistency is slipping, who has a new asymmetry flag.")
                    bullet("lock.shield", "Client video stays with the client", "Only measurements sync. You never receive their footage, which keeps this out of HIPAA territory for clinicians.")
                    bullet("square.and.arrow.up", "Export whenever", "CSV of any client's history, so your records stay yours.")

                    Divider().overlay(KColor.separator)

                    ForEach(PurchaseService.CoachTier.allCases) { tier in
                        HStack {
                            Text(tier.displayName)
                                .font(KFont.callout)
                                .foregroundStyle(KColor.textPrimary)
                            Spacer()
                            Text("up to \(tier.clientLimit) clients")
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                        }
                    }
                    Text("You pay for the seats; your clients are never billed for being on your roster.")
                        .font(.system(size: 11))
                        .foregroundStyle(KColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            InfoBanner(
                icon: "hourglass",
                title: "Not yet available for purchase",
                message: "The coach plans are still being set up in the App Store. If you train clients and want early access, get in touch from Settings.",
                tint: KColor.amber
            )
        }
    }

    private func bullet(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: KSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KColor.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textPrimary)
                Text(body)
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Invite sheet

    private var inviteSheet: some View {
        NavigationStack {
            ZStack {
                KScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: KSpacing.lg) {
                        if let code = generatedCode {
                            KCard {
                                VStack(spacing: KSpacing.md) {
                                    Eyebrow(text: "Invite code")
                                    Text(code)
                                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                                        .foregroundStyle(KColor.accent)
                                        .textSelection(.enabled)
                                    Text("Your client enters this under Settings → Connect with a coach. It expires in 30 days and works once.")
                                        .font(KFont.caption)
                                        .foregroundStyle(KColor.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            Button {
                                sharePayload = SharePayload(items: [
                                    "Join me on Kinetriq — open the app, go to Settings, tap Connect with a coach, and enter code \(code)."
                                ])
                            } label: {
                                Label("Send to client", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(KPrimaryButtonStyle())
                        } else {
                            KCard {
                                VStack(alignment: .leading, spacing: KSpacing.sm) {
                                    Eyebrow(text: "Label (optional)")
                                    TextField("e.g. Jamie — knee rehab", text: $inviteLabel)
                                        .textFieldStyle(.roundedBorder)
                                    Text("Only you see this. It helps tell unredeemed codes apart.")
                                        .font(KFont.caption)
                                        .foregroundStyle(KColor.textSecondary)
                                }
                            }

                            Button {
                                Task {
                                    isCreatingInvite = true
                                    defer { isCreatingInvite = false }
                                    generatedCode = await coach.createInvite(
                                        label: inviteLabel.isEmpty ? nil : inviteLabel
                                    )
                                }
                            } label: {
                                if isCreatingInvite {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Generate code", systemImage: "wand.and.stars")
                                }
                            }
                            .buttonStyle(KPrimaryButtonStyle())
                            .disabled(isCreatingInvite)

                            if let error = coach.errorMessage {
                                Text(error)
                                    .font(KFont.caption)
                                    .foregroundStyle(KColor.warning)
                            }
                        }
                    }
                    .padding(.horizontal, KSpacing.screenH)
                    .padding(.vertical, KSpacing.lg)
                }
            }
            .navigationTitle("Invite a client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingInviteSheet = false
                        Task { await coach.refreshRoster() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Row

struct CoachClientRow: View {
    let client: CoachClient

    private var reason: TriageReason { CoachTriage.reason(for: client) }

    var body: some View {
        HStack(spacing: KSpacing.sm) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: reason.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                KPill(text: reason.label, tint: tint, filled: reason.isAttention)
                if let score = client.latestScore {
                    Text("\(score)")
                        .font(KFont.numeral(18))
                        .monospacedDigit()
                        .foregroundStyle(KColor.score(score))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        guard client.lastSessionAt != nil else { return "No sessions yet" }
        var parts: [String] = []
        if let movement = client.latestMovement { parts.append(movement) }
        if let days = client.daysSinceLastSession {
            parts.append(days == 0 ? "today" : days == 1 ? "yesterday" : "\(days)d ago")
        }
        parts.append("\(client.sessionsLast14Days) in 14d")
        return parts.joined(separator: " · ")
    }

    private var tint: Color {
        switch reason {
        case .neverStarted:  return KColor.textTertiary
        case .wentQuiet:     return KColor.amber
        case .scoreDropping: return KColor.danger
        case .newAsymmetry:  return KColor.warning
        case .improving:     return KColor.success
        case .steady:        return KColor.teal
        }
    }
}
