import SwiftUI

/// Credits for third-party content bundled in the app.
///
/// CC BY-SA 4.0 requires attribution that is reasonable to the medium, a statement of
/// whether the work was modified, and either a copy of the license or a link to it.
/// The per-image credit line appears wherever an illustration is shown; this screen
/// carries the full picture and the license text itself, which ships in the bundle
/// rather than relying on a network fetch.
struct AttributionView: View {

    private let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
    private let everkineticURL = URL(string: "http://db.everkinetic.com")!

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: KSpacing.lg) {
                    everkineticCard
                    imageListCard
                    licenseCard
                    ownWorkCard
                    Spacer(minLength: KSpacing.xl)
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.top, KSpacing.lg)
                .padding(.bottom, KSpacing.xl)
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var everkineticCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                Eyebrow(text: "Exercise illustrations")

                Text("Everkinetic")
                    .font(KFont.headline)
                    .foregroundStyle(KColor.textPrimary)

                Text("The exercise illustrations in Kinetriq come from the Everkinetic open data project, created by Greg Priday. They are used **unmodified**.")
                    .font(KFont.subheadline)
                    .foregroundStyle(KColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Licensed under Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0).")
                    .font(KFont.subheadline)
                    .foregroundStyle(KColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: everkineticURL) {
                    Label("db.everkinetic.com", systemImage: "arrow.up.right.square")
                        .font(KFont.subheadline)
                }
                Link(destination: licenseURL) {
                    Label("View the CC BY-SA 4.0 license", systemImage: "arrow.up.right.square")
                        .font(KFont.subheadline)
                }
            }
        }
    }

    private var imageListCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                Eyebrow(text: "Illustrations used")
                ForEach(ExerciseIllustration.all) { illustration in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(illustration.title)
                            .font(KFont.subheadline)
                            .foregroundStyle(KColor.textPrimary)
                        Text(illustration.sourceURL.absoluteString)
                            .font(.system(size: 10))
                            .foregroundStyle(KColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("All shown as published, with no changes.")
                    .font(KFont.micro)
                    .foregroundStyle(KColor.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var licenseCard: some View {
        if ExerciseIllustration.licenseText != nil {
            KCard {
                NavigationLink {
                    LicenseTextView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full license text")
                                .font(KFont.callout)
                                .foregroundStyle(KColor.textPrimary)
                            Text("CC BY-SA 4.0, included in the app")
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KColor.textTertiary)
                    }
                }
            }
        }
    }

    private var ownWorkCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                Eyebrow(text: "Analysis")
                Text("Pose estimation uses Google's MediaPipe Pose Landmarker, running entirely on this device. Joint angles, rep counting, tempo, scoring, and all coaching text are Kinetriq's own work.")
                    .font(KFont.subheadline)
                    .foregroundStyle(KColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The bundled CC BY-SA deed, rendered as plain text.
private struct LicenseTextView: View {
    var body: some View {
        ScrollView {
            Text(ExerciseIllustration.licenseText ?? "License text unavailable.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(KColor.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(KSpacing.md)
        }
        .background(KScreenBackground())
        .navigationTitle("CC BY-SA 4.0")
        .navigationBarTitleDisplayMode(.inline)
    }
}
