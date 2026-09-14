import SwiftUI
import UIKit

// MARK: - Reusable presentation for a saved `AnalysisRecord`.
//
// Shared by the live post-session sheet and the Progress tab so a set looks the
// same however it was captured and wherever it is reviewed.

/// Score ring (exercises) or grade badge (assessments) plus the headline stats.
struct AnalysisRecordHeadline: View {
    let record: AnalysisRecord

    var body: some View {
        HStack(alignment: .center, spacing: KSpacing.md) {
            switch record.kind {
            case .exercise:
                if let score = record.finalScore {
                    ScoreRing(value: score, size: 104, lineWidth: 10)
                } else {
                    ScoreRing(value: 0, size: 104, lineWidth: 10, caption: "NO SCORE")
                        .opacity(0.45)
                }
            case .assessment:
                GradeBadge(grade: record.grade ?? .F, size: 72)
            }

            VStack(spacing: KSpacing.sm) {
                HStack(spacing: KSpacing.sm) {
                    switch record.kind {
                    case .exercise:
                        StatTile(icon: "number",
                                 value: "\(record.totalReps)",
                                 label: "Reps",
                                 tint: KColor.accent)
                    case .assessment:
                        StatTile(icon: "arrow.left.arrow.right",
                                 value: record.asymmetryDeg.map { "\(Int($0))°" } ?? "—",
                                 label: "Asymmetry",
                                 tint: record.asymmetryFlag ? KColor.warning : KColor.teal)
                    }
                    StatTile(icon: "timer",
                             value: String(format: "%.0fs", record.duration),
                             label: "Duration",
                             tint: KColor.teal)
                }
            }
        }
    }
}

/// Average tempo row. Hidden when the set produced no completed reps.
struct AverageTempoRow: View {
    let record: AnalysisRecord

    var body: some View {
        if let tempo = record.averageTempoString {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: KSpacing.xs) {
                    Image(systemName: "metronome")
                        .foregroundStyle(KColor.teal)
                        .imageScale(.small)
                    Text("Average tempo")
                        .font(KFont.caption)
                        .foregroundStyle(KColor.textSecondary)
                    Spacer()
                    Text(tempo)
                        .font(KFont.callout)
                        .foregroundStyle(KColor.textPrimary)
                        .monospacedDigit()
                }
                Text("Eccentric – pause – concentric – pause (seconds)")
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.textTertiary)
            }
        }
    }
}

/// Per-rep tempo and peak-angle breakdown.
struct PerRepTable: View {
    let reps: [RepMetric]

    var body: some View {
        if !reps.isEmpty {
            VStack(alignment: .leading, spacing: KSpacing.xs) {
                Eyebrow(text: "Per-rep breakdown")
                VStack(spacing: 0) {
                    HStack {
                        Text("Rep").frame(width: 44, alignment: .leading)
                        Text("Tempo").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Peak").frame(width: 56, alignment: .trailing)
                    }
                    .font(KFont.micro)
                    .foregroundStyle(KColor.textTertiary)
                    .padding(.vertical, KSpacing.xs)

                    ForEach(reps, id: \.repNumber) { rep in
                        HStack {
                            Text("\(rep.repNumber)")
                                .frame(width: 44, alignment: .leading)
                                .foregroundStyle(KColor.textSecondary)
                            Text(rep.tempoString)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(KColor.textPrimary)
                            Text(Self.peakText(rep.peakFlexionAngle))
                                .frame(width: 56, alignment: .trailing)
                                .foregroundStyle(KColor.textPrimary)
                        }
                        .font(KFont.callout)
                        .monospacedDigit()
                        .padding(.vertical, 7)
                        .background(rep.repNumber % 2 == 0
                                    ? Color.clear
                                    : KColor.surfaceSunken.opacity(0.6))
                    }
                }
            }
        }
    }

    static func peakText(_ angle: Float) -> String {
        guard angle.isFinite, angle < 1000 else { return "—" }
        return "\(Int(angle.rounded()))°"
    }
}

/// Renders coaching text that was generated at analysis time and stored on the
/// record, rather than regenerating it. A saved set should read the same next month
/// as it did the day it was filmed, even if the heuristics have since changed.
struct StoredInsightsSection: View {
    let title: String
    let insights: [String]
    let copyHeader: String
    var tint: Color = KColor.accent

    @State private var copied = false

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                HStack {
                    Eyebrow(text: title)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = ([copyHeader]
                            + insights.map { "• \($0)" }
                            + ["— via Kinetriq"]).joined(separator: "\n")
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(KFont.caption)
                            .foregroundStyle(copied ? KColor.success : tint)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(insights.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: KSpacing.xs) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(tint)
                            .padding(.top, 6)
                            .frame(width: 12)
                        Text(text)
                            .font(KFont.caption)
                            .foregroundStyle(KColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Compact row for the history list.
struct AnalysisRecordRow: View {
    let record: AnalysisRecord

    var body: some View {
        HStack(spacing: KSpacing.sm) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: KSpacing.xs) {
                    Text(record.movementName)
                        .font(KFont.callout)
                        .foregroundStyle(KColor.textPrimary)
                        .lineLimit(1)
                    if record.source == .liveCamera {
                        KPill(text: "Live", tint: KColor.teal)
                    }
                }
                Text(record.summaryLine)
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .lineLimit(1)
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.textTertiary)
            }

            Spacer(minLength: 0)

            trailingBadge
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous)
                .fill(KColor.surfaceSunken)
            if let url = record.thumbnailURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: record.kind == .assessment
                      ? "figure.flexibility"
                      : "figure.strengthtraining.traditional")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KColor.textTertiary)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
    }

    @ViewBuilder
    private var trailingBadge: some View {
        switch record.kind {
        case .exercise:
            if let score = record.finalScore {
                Text("\(score)")
                    .font(KFont.numeral(22))
                    .monospacedDigit()
                    .foregroundStyle(KColor.score(score))
            }
        case .assessment:
            if let grade = record.grade {
                Text(grade.rawValue)
                    .font(KFont.numeral(22))
                    .foregroundStyle(KColor.grade(grade))
            }
        }
    }
}

/// Tracking-quality caveat shared by every result surface.
struct TrackingQualityRow: View {
    let rate: Double

    var body: some View {
        let pct = Int((rate * 100).rounded())
        let color: Color = pct >= 70 ? KColor.success : pct >= 40 ? KColor.warning : KColor.danger
        HStack(spacing: KSpacing.xs) {
            Image(systemName: pct >= 70 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
                .imageScale(.small)
            Text("Pose tracked \(pct)% of frames")
                .font(KFont.caption)
                .foregroundStyle(pct >= 70 ? KColor.textSecondary : color)
            Spacer(minLength: 0)
        }
    }
}
