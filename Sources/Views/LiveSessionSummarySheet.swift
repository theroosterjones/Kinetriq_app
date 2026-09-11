import SwiftUI

/// Shown after a live take is stopped and saved.
///
/// Until this existed, stopping a live recording went straight to the iOS share
/// sheet: the reps, tempo, and score that had been on the HUD a second earlier were
/// gone, and nothing about the set was kept. Now the take is already in history by
/// the time this appears, and the sheet is a confirmation of what was saved rather
/// than the last chance to see it.
struct LiveSessionSummarySheet: View {
    let record: AnalysisRecord
    let videoURL: URL
    let onShare: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                KScreenBackground()
                ScrollView {
                    VStack(spacing: KSpacing.lg) {
                        savedBanner

                        KCard {
                            VStack(alignment: .leading, spacing: KSpacing.md) {
                                SectionHeader(record.movementName, eyebrow: "Set complete")

                                AnalysisRecordHeadline(record: record)

                                if record.kind == .exercise {
                                    Divider().overlay(KColor.separator)
                                    AverageTempoRow(record: record)
                                    if !record.perRepMetrics.isEmpty {
                                        Divider().overlay(KColor.separator)
                                        PerRepTable(reps: record.perRepMetrics)
                                    }
                                } else if !record.payload.subGrades.isEmpty {
                                    Divider().overlay(KColor.separator)
                                    Eyebrow(text: "Breakdown")
                                    ForEach(record.payload.subGrades, id: \.label) { sub in
                                        HStack {
                                            Text(sub.label)
                                                .font(KFont.subheadline)
                                                .foregroundStyle(KColor.textPrimary)
                                            Spacer()
                                            KPill(text: sub.grade.rawValue,
                                                  tint: KColor.grade(sub.grade),
                                                  filled: true)
                                        }
                                    }
                                }

                                if !record.payload.insights.isEmpty {
                                    Divider().overlay(KColor.separator)
                                    StoredInsightsSection(
                                        title: "Coaching",
                                        insights: record.payload.insights,
                                        copyHeader: "Kinetriq — \(record.movementName)"
                                    )
                                }

                                Divider().overlay(KColor.separator)
                                TrackingQualityRow(rate: record.poseDetectionRate)
                            }
                        }

                        Button {
                            onShare()
                        } label: {
                            Label("Share recording", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(KSecondaryButtonStyle(tint: KColor.amber))

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                        }
                        .buttonStyle(KPrimaryButtonStyle())
                    }
                    .padding(.horizontal, KSpacing.screenH)
                    .padding(.vertical, KSpacing.lg)
                }
            }
            .navigationTitle("Session saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var savedBanner: some View {
        InfoBanner(
            icon: "checkmark.icloud",
            title: "Saved to Progress",
            message: record.videoFileName == nil
                ? "The measurements from this set are in your history. The video could not be moved into the app's storage — share it now if you want to keep it."
                : "This set and its video are in your history. Open Progress to see how it compares to previous sessions.",
            tint: record.videoFileName == nil ? KColor.warning : KColor.teal
        )
    }
}
