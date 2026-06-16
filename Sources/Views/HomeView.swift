import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            ZStack {
                KScreenBackground()
                ScrollView {
                    VStack(spacing: KSpacing.lg) {
                        greeting
                        heroAnalyzeCard
                        weeklySummary
                        trendCard
                        toolsRow
                        librarySection
                        helpLink
                    }
                    .padding(.horizontal, KSpacing.screenH)
                    .padding(.top, KSpacing.xs)
                    .padding(.bottom, KSpacing.xxl)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Greeting / brand bar

    private var greeting: some View {
        HStack(alignment: .center, spacing: KSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Movement Intelligence")
                Text("Kinetriq")
                    .font(KFont.display(34))
                    .foregroundStyle(KColor.textPrimary)
            }
            Spacer()
            NavigationLink {
                HelpView()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(KColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(KColor.surface, in: Circle())
                    .kSoftShadow()
            }
            .accessibilityLabel("Help and FAQ")
        }
        .padding(.top, KSpacing.sm)
    }

    // MARK: Primary CTA — fewer taps to analyze

    private var heroAnalyzeCard: some View {
        VStack(alignment: .leading, spacing: KSpacing.md) {
            HStack(spacing: KSpacing.sm) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyze a movement")
                        .font(KFont.title2)
                        .foregroundStyle(.white)
                    Text("On-device form analysis in seconds")
                        .font(KFont.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }

            HStack(spacing: KSpacing.sm) {
                heroAction(title: "Record", icon: "camera.fill") {
                    router.goToWorkout(.liveCamera)
                }
                heroAction(title: "Upload", icon: "square.and.arrow.up.on.square.fill") {
                    router.goToWorkout(.savedVideo)
                }
            }
        }
        .padding(KSpacing.lg)
        .background(KColor.brandGradient, in: RoundedRectangle(cornerRadius: KRadius.lg, style: .continuous))
        .shadow(color: KColor.accent.opacity(0.35), radius: 22, x: 0, y: 14)
    }

    private func heroAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(KFont.callout)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: Weekly summary (honest empty state until progress sync lands)

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            SectionHeader("This week", eyebrow: "Summary") {
                KPill(text: "Preview")
            }
            HStack(spacing: KSpacing.sm) {
                StatTile(icon: "figure.run", value: "0", label: "Analyses", tint: KColor.accent)
                StatTile(icon: "rosette", value: "—", label: "Avg score", tint: KColor.teal)
                StatTile(icon: "checklist", value: "0", label: "Assessments", tint: KColor.violet)
            }
            Text("Your activity and scores will populate here once progress sync is enabled.")
                .font(KFont.caption)
                .foregroundStyle(KColor.textTertiary)
        }
    }

    // MARK: Assessment trend

    private var trendCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Assessment trend")
                        Text("Movement quality")
                            .font(KFont.headline)
                            .foregroundStyle(KColor.textPrimary)
                    }
                    Spacer()
                    KPill(text: "Sample", tint: KColor.textTertiary)
                }
                Sparkline(values: [62, 68, 65, 74, 78, 76, 84], tint: KColor.teal)
                    .frame(height: 64)
                    .opacity(0.85)
                HStack {
                    Text("Track grades over time to see mobility and control improve.")
                        .font(KFont.caption)
                        .foregroundStyle(KColor.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Tools

    private var toolsRow: some View {
        HStack(spacing: KSpacing.sm) {
            Button { router.goToWorkout(.assessment) } label: {
                toolTile(title: "Assessment", subtitle: "Mobility & control", icon: "stethoscope", tint: KColor.violet)
            }
            .buttonStyle(.plain)

            NavigationLink {
                LiveAnalysisView()
            } label: {
                toolTile(title: "Live Camera", subtitle: "Real-time coaching", icon: "camera.viewfinder", tint: KColor.teal)
            }
            .buttonStyle(.plain)
        }
    }

    private func toolTile(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textPrimary)
                Text(subtitle)
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KSpacing.md)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KRadius.md, style: .continuous)
                .strokeBorder(KColor.separator.opacity(0.6), lineWidth: 0.75)
        )
        .kSoftShadow()
    }

    // MARK: Exercise library shortcuts

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            SectionHeader("Exercise library", eyebrow: "Browse") {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    Text("See all")
                        .font(KFont.callout)
                        .foregroundStyle(KColor.accent)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KSpacing.sm) {
                    ForEach(ExerciseLibrary.featured) { item in
                        NavigationLink {
                            ExerciseLibraryView(initialQuery: item.displayName)
                        } label: {
                            libraryChip(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func libraryChip(_ item: ExerciseLibrary.Item) -> some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            Image(systemName: item.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 48, height: 48)
                .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
            Text(item.displayName)
                .font(KFont.callout)
                .foregroundStyle(KColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(item.plane)
                .font(KFont.caption)
                .foregroundStyle(KColor.textTertiary)
        }
        .frame(width: 150, alignment: .leading)
        .padding(KSpacing.md)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KRadius.md, style: .continuous)
                .strokeBorder(KColor.separator.opacity(0.6), lineWidth: 0.75)
        )
        .kSoftShadow()
    }

    // MARK: Help

    private var helpLink: some View {
        NavigationLink {
            HelpView()
        } label: {
            HStack(spacing: KSpacing.sm) {
                Image(systemName: "lightbulb.max.fill")
                    .foregroundStyle(KColor.amber)
                Text("Tips, camera setup & FAQ")
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KColor.textTertiary)
            }
            .padding(KSpacing.md)
            .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KRadius.md, style: .continuous)
                    .strokeBorder(KColor.separator.opacity(0.6), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }
}
