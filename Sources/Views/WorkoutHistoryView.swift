import SwiftUI

/// Progress tab. Backend sync isn't wired yet, so this presents an honest,
/// premium "preview" of the upcoming progress dashboard — sample visuals are
/// clearly labeled so coaches understand what's coming without being misled.
struct WorkoutHistoryView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            ZStack {
                KScreenBackground()
                ScrollView {
                    VStack(spacing: KSpacing.lg) {
                        previewBanner
                        scoreTrendCard
                        consistencyCard
                        recentPlaceholder
                    }
                    .padding(.horizontal, KSpacing.screenH)
                    .padding(.top, KSpacing.xs)
                    .padding(.bottom, KSpacing.xxl)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var previewBanner: some View {
        InfoBanner(icon: "icloud.and.arrow.up",
                   title: "Progress sync is coming",
                   message: "Soon your analyses and assessments will save here automatically so you can track movement quality over time. The layout below is a preview.",
                   tint: KColor.accent)
        .padding(.top, KSpacing.xs)
    }

    private var scoreTrendCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Form score")
                        Text("Last 8 sessions")
                            .font(KFont.headline)
                            .foregroundStyle(KColor.textPrimary)
                    }
                    Spacer()
                    KPill(text: "Sample", tint: KColor.textTertiary)
                }
                Sparkline(values: [64, 70, 67, 73, 78, 75, 82, 86], tint: KColor.accent)
                    .frame(height: 80)
                    .opacity(0.9)
                HStack(spacing: KSpacing.sm) {
                    StatTile(icon: "arrow.up.right", value: "+22", label: "Trend", tint: KColor.success)
                    StatTile(icon: "rosette", value: "86", label: "Best", tint: KColor.accent)
                    StatTile(icon: "function", value: "74", label: "Average", tint: KColor.teal)
                }
            }
        }
    }

    private var consistencyCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack {
                    Eyebrow(text: "Consistency")
                    Spacer()
                    KPill(text: "Sample", tint: KColor.textTertiary)
                }
                HStack(spacing: 6) {
                    ForEach(0..<14, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barFilled(i) ? KColor.teal : KColor.separator.opacity(0.6))
                            .frame(height: barHeight(i))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 60, alignment: .bottom)
                Text("Sessions logged over the last two weeks.")
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
            }
        }
    }

    private func barFilled(_ i: Int) -> Bool { [1, 2, 4, 5, 6, 8, 9, 11, 12, 13].contains(i) }
    private func barHeight(_ i: Int) -> CGFloat {
        let heights: [CGFloat] = [16, 34, 40, 12, 46, 38, 52, 14, 30, 44, 18, 48, 36, 56]
        return heights[i % heights.count]
    }

    private var recentPlaceholder: some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            SectionHeader("Recent analyses", eyebrow: "History")
            KCard {
                VStack(spacing: KSpacing.md) {
                    KEmptyState(icon: "clock.arrow.circlepath",
                                title: "No saved analyses yet",
                                message: "Analyze a movement to start building your history. Until sync ships, export clips to keep your own records.")
                    Button {
                        router.goToWorkout(.savedVideo)
                    } label: {
                        Label("Analyze a movement", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(KPrimaryButtonStyle())
                }
            }
        }
    }
}
