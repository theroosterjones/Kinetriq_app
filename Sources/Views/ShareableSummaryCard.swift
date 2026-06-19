import SwiftUI

/// Data needed to render a shareable summary image. Built from an existing
/// `AnalysisSummary` or `AssessmentMetrics` — no new analysis required.
struct SummaryShareCardModel {
    enum Headline {
        case score(Int)        // 0–100 consistency score
        case grade(LetterGrade) // assessment letter grade
        case reps(Int)          // fallback when no score is available
    }

    let categoryLabel: String   // e.g. "Form Analysis" / "Assessment"
    let title: String           // exercise / assessment name
    let headline: Headline
    let stats: [Stat]
    let insights: [String]
    let dateText: String

    struct Stat: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }
}

/// A branded, self-contained card designed to be rendered to a PNG and shared to
/// iMessage / email / Stories. Uses explicit colors (not adaptive tokens) so the
/// offscreen `ImageRenderer` output looks identical regardless of device theme.
struct ShareableSummaryCard: View {
    let model: SummaryShareCardModel

    private let cardWidth: CGFloat = 360

    private static let bg1 = Color(red: 0.043, green: 0.055, blue: 0.078)   // #0B0E14
    private static let bg2 = Color(red: 0.086, green: 0.114, blue: 0.18)    // deep navy
    private static let accent = Color(red: 0.239, green: 0.482, blue: 1.0)  // #3D7BFF
    private static let teal = Color(red: 0.129, green: 0.816, blue: 0.698)  // #21D0B2

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandRow
            headlineRow
            if !model.stats.isEmpty { statsRow }
            if !model.insights.isEmpty { insightList }
            footer
        }
        .padding(28)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            LinearGradient(colors: [Self.bg2, Self.bg1],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    // MARK: - Sections

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [Self.accent, Color(red: 0.43, green: 0.36, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("Kinetriq")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(model.categoryLabel.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(Self.teal)
        }
    }

    private var headlineRow: some View {
        HStack(alignment: .center, spacing: 18) {
            headlineBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(headlineCaption)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var headlineBadge: some View {
        switch model.headline {
        case .score(let value):
            scoreRing(value: value)
        case .grade(let grade):
            gradeBadge(grade)
        case .reps(let reps):
            VStack(spacing: 0) {
                Text("\(reps)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("REPS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 96, height: 96)
            .background(Color.white.opacity(0.06), in: Circle())
        }
    }

    private func scoreRing(value: Int) -> some View {
        let fraction = CGFloat(max(0, min(100, value))) / 100
        let color = scoreColor(value)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("SCORE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 96, height: 96)
    }

    private func gradeBadge(_ grade: LetterGrade) -> some View {
        Text(grade.rawValue)
            .font(.system(size: 46, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(
                LinearGradient(colors: [gradeColor(grade).opacity(0.85), gradeColor(grade)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ForEach(model.stats.prefix(3)) { stat in
                VStack(spacing: 4) {
                    Text(stat.value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var insightList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(model.insights.prefix(3).enumerated()), id: \.offset) { _, insight in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Self.teal)
                        .padding(.top, 2)
                    Text(insight)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.dateText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text("On-device movement analysis")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Helpers

    private var headlineCaption: String {
        switch model.headline {
        case .score: return "Form consistency"
        case .grade(let grade):
            switch grade {
            case .A: return "Excellent movement quality"
            case .B: return "Good movement quality"
            case .C: return "Fair — room to improve"
            case .D: return "Limited — needs work"
            case .F: return "Needs work"
            }
        case .reps: return "Reps analyzed"
        }
    }

    private func scoreColor(_ value: Int) -> Color {
        switch value {
        case 80...: return Color(red: 0.184, green: 0.796, blue: 0.431) // success
        case 60..<80: return Color(red: 0.965, green: 0.718, blue: 0.235) // amber
        default: return Color(red: 0.984, green: 0.302, blue: 0.388) // danger
        }
    }

    private func gradeColor(_ grade: LetterGrade) -> Color {
        switch grade {
        case .A: return Color(red: 0.184, green: 0.796, blue: 0.431)
        case .B: return Self.teal
        case .C: return Color(red: 0.965, green: 0.718, blue: 0.235)
        case .D: return Color(red: 0.965, green: 0.718, blue: 0.235)
        case .F: return Color(red: 0.984, green: 0.302, blue: 0.388)
        }
    }
}

/// Renders a `ShareableSummaryCard` to a PNG file in the temporary directory.
enum SummaryImageRenderer {
    @MainActor
    static func renderPNG(_ model: SummaryShareCardModel) -> URL? {
        let renderer = ImageRenderer(content: ShareableSummaryCard(model: model))
        renderer.scale = 3.0
        guard let uiImage = renderer.uiImage,
              let data = uiImage.pngData() else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinetriq_summary_\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
