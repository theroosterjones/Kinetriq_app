import SwiftUI
import SwiftData
import AVKit

/// Full read-back of one saved analysis, including its video if the file is still
/// present.
struct AnalysisRecordDetailView: View {
    let record: AnalysisRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var sharePayload: SharePayload?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(spacing: KSpacing.lg) {
                    videoSection
                    resultCard
                    TechniqueLessonSection(lessons: lessons)
                    shareActions
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.top, KSpacing.xs)
                .padding(.bottom, KSpacing.xxl)
            }
        }
        .navigationTitle(record.movementName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this analysis?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                AnalysisLibrary.delete(record, from: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved measurements and the video for this session will be removed from this device.")
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .onAppear {
            if let url = record.videoURL { player = AVPlayer(url: url) }
        }
        .onDisappear { player?.pause() }
    }

    /// Prior sessions for the same movement establish this user's own best range,
    /// which is what `rangeBelowPersonalBest` compares against. The record itself is
    /// excluded so a set is never measured against its own result.
    private var lessons: [TechniqueLesson] {
        let history = AnalysisLibrary
            .fetchHistory(movementKey: record.movementKey, from: modelContext)
            .filter { $0.date < record.date }
            .map(TrendSample.init(record:))
        return TechniqueLibrary.lessons(for: record, history: history)
    }

    @ViewBuilder
    private var videoSection: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
        } else {
            InfoBanner(
                icon: "video.slash",
                title: "Video no longer available",
                message: "The measurements below are intact. The clip was removed from this device, or could not be saved when the session ended.",
                tint: KColor.textTertiary
            )
        }
    }

    private var resultCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: record.kind == .assessment ? "Assessment" : "Form analysis")
                        Text(record.date.formatted(date: .complete, time: .shortened))
                            .font(KFont.caption)
                            .foregroundStyle(KColor.textSecondary)
                    }
                    Spacer()
                    KPill(text: record.source.displayName, tint: KColor.teal)
                }

                AnalysisRecordHeadline(record: record)

                if record.kind == .exercise {
                    if !record.payload.averageAngles.isEmpty {
                        Divider().overlay(KColor.separator)
                        Eyebrow(text: "Average joint angles")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: KSpacing.xs) {
                                ForEach(record.payload.averageAngles, id: \.joint) { angle in
                                    MetricChip(label: angle.joint.rawValue.capitalized,
                                               value: "\(Int(angle.degrees))°",
                                               tint: KColor.textPrimary)
                                }
                            }
                        }
                    }
                    Divider().overlay(KColor.separator)
                    AverageTempoRow(record: record)
                    if !record.perRepMetrics.isEmpty {
                        Divider().overlay(KColor.separator)
                        PerRepTable(reps: record.perRepMetrics)
                    }
                } else {
                    assessmentSections
                }

                if !record.payload.insights.isEmpty {
                    Divider().overlay(KColor.separator)
                    StoredInsightsSection(
                        title: "Coaching",
                        insights: record.payload.insights,
                        copyHeader: "Kinetriq — \(record.movementName), \(record.date.formatted(date: .abbreviated, time: .omitted))"
                    )
                }

                Divider().overlay(KColor.separator)
                TrackingQualityRow(rate: record.poseDetectionRate)

                if record.kind == .assessment {
                    Text("For general fitness and educational purposes only — not medical advice. Consult a qualified professional for diagnosis or treatment.")
                        .font(.system(size: 11))
                        .foregroundStyle(KColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var assessmentSections: some View {
        if !record.payload.subGrades.isEmpty {
            Divider().overlay(KColor.separator)
            Eyebrow(text: "Breakdown")
            ForEach(record.payload.subGrades, id: \.label) { sub in
                HStack {
                    Image(systemName: sub.grade <= .B ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(KColor.grade(sub.grade))
                        .imageScale(.small)
                    Text(sub.label)
                        .font(KFont.subheadline)
                        .foregroundStyle(KColor.textPrimary)
                    Spacer()
                    KPill(text: sub.grade.rawValue, tint: KColor.grade(sub.grade), filled: true)
                }
            }
        }

        if let left = record.leftROM, let right = record.rightROM {
            Divider().overlay(KColor.separator)
            Eyebrow(text: "Range of motion")
            let maxV = max(left, right, 1)
            romRow(label: "Left", value: left, fraction: left / maxV, tint: KColor.accent)
            romRow(label: "Right", value: right, fraction: right / maxV, tint: KColor.teal)
        }

        if !record.payload.details.isEmpty {
            Divider().overlay(KColor.separator)
            StoredInsightsSection(
                title: "Recommendations",
                insights: record.payload.details,
                copyHeader: "Kinetriq — \(record.movementName) recommendations",
                tint: KColor.violet
            )
        }
    }

    private func romRow(label: String, value: Double, fraction: Double, tint: Color) -> some View {
        HStack(spacing: KSpacing.sm) {
            Text(label)
                .font(KFont.caption)
                .foregroundStyle(KColor.textSecondary)
                .frame(width: 42, alignment: .leading)
            ProgressTrack(value: fraction, tint: tint)
            Text("\(Int(value))°")
                .font(KFont.callout)
                .foregroundStyle(KColor.textPrimary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var shareActions: some View {
        VStack(spacing: KSpacing.sm) {
            if let url = record.videoURL {
                Button {
                    sharePayload = SharePayload(items: [url])
                } label: {
                    Label("Share analyzed video", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(KSecondaryButtonStyle(tint: KColor.amber))
            }
            Button {
                switch CSVExporter.writeSessions([record], fileNameHint: "kinetriq-\(record.movementName)") {
                case .success(let url): sharePayload = SharePayload(items: [url])
                case .failure: break
                }
            } label: {
                Label("Export this session as CSV", systemImage: "tablecells")
            }
            .buttonStyle(KSecondaryButtonStyle(tint: KColor.accent))
        }
    }
}
