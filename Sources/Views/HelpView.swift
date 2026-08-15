import SwiftUI

/// Tips, camera setup, and FAQ — moved out of the Home dashboard to reduce
/// clutter and keep Home focused on a single primary action.
struct HelpView: View {
    private let faqs: [(q: String, a: String)] = [
        ("How can I use this to help my clients or patients?",
         "Kinetriq gives fitness and rehab professionals a simple way to show movement quality, joint angles, tempo, and visible progress. Use it to give clients clearer feedback, compare movement over time, and explain technique changes with video instead of relying only on verbal cues."),
        ("How can I use this to create better content?",
         "Use Kinetriq overlays to make exercise videos more educational. Angles, reps, tempo, and reference lines can help viewers understand what you are coaching, why a setup matters, and how movement changes from rep to rep."),
        ("Where should I start?",
         "Tap Record or Upload on the Home dashboard. Choose the exercise or assessment that best matches the movement, select the correct side or camera plane when prompted, then analyze the video."),
        ("How should I position the camera?",
         "Keep your full body visible from head to feet when possible. For side-view exercises, film from the side. For front or back exercises, film straight on. For deadlifts or movements where the bar blocks the hips, film 15–30 degrees off true side view."),
        ("Why isn’t the app tracking my movement correctly?",
         "Tracking can fail if the camera angle is wrong, the body is too small in the frame, lighting is poor, or key landmarks are blocked by equipment, arms, plates, benches, or another person."),
        ("Can Kinetriq track more than one person?",
         "No. Kinetriq is designed to analyze one person at a time. If multiple people are visible, the app may track the wrong person or lose tracking."),
        ("What does the tempo counter mean?",
         "Tempo is shown as four numbers: eccentric – pause bottom – concentric – pause top. For example, 3-0-1-1 means 3 seconds lowering or lengthening, no pause at the bottom, 1 second lifting or contracting, and 1 second pause at the top."),
        ("Why do some exercises have different eccentric and concentric directions?",
         "Different exercises move differently. In a squat, the knee and hip angle close during the eccentric. In a curl or pulldown, the working concentric phase often happens as the joint angle closes. Kinetriq adjusts this by exercise."),
        ("What is the difference between Simple and Full HUD?",
         "Simple shows a cleaner overlay with less text. Full HUD shows more details like angles, reps, tempo, and additional reference lines. Full HUD is best for analysis; Simple is best for cleaner video review."),
        ("Why are reps not counting even when landmarks appear?",
         "Rep counting depends on the movement reaching expected start and end ranges. If range of motion is partial, the camera angle changes the measured angle, or landmarks are blocked at key moments, reps may not register."),
        ("Why does the analyzed video sometimes show low pose tracking percentage?",
         "That means Kinetriq could not reliably detect the body in many frames. Improve lighting, move closer, keep the whole body visible, avoid cluttered backgrounds, and make sure the selected exercise matches the filming angle."),
        ("Are videos uploaded to a server?",
         "No. Kinetriq performs analysis on-device. Videos are selected from your device and processed locally. I am working on a cloud backup system so users can save workout histories to better analyze progress. If you are a coach, physical therapist, or related fitness professional, I recommend saving your client videos on your own drive in the meantime.")
    ]

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(spacing: KSpacing.sm) {
                    InfoBanner(icon: "iphone.gen3",
                               title: "100% on-device",
                               message: "Your videos never leave the phone. Analysis runs locally for privacy and speed.",
                               tint: KColor.teal)
                        .padding(.bottom, KSpacing.xs)

                    ForEach(faqs.indices, id: \.self) { i in
                        FAQRow(question: faqs[i].q, answer: faqs[i].a)
                    }
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.vertical, KSpacing.md)
            }
        }
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: expanded ? KSpacing.xs : 0) {
                HStack(alignment: .top, spacing: KSpacing.sm) {
                    Text(question)
                        .font(KFont.callout)
                        .foregroundStyle(KColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KColor.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                if expanded {
                    Text(answer)
                        .font(KFont.subheadline)
                        .foregroundStyle(KColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
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
