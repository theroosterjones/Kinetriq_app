import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                        .padding(.top, 32)

                    quickActionCards

                    faqSection
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        // Logo placeholder — replace with asset once branding is finalised
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.blue)

            Text("Kinetriq")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Movement Intelligence")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var quickActionCards: some View {
        VStack(spacing: 14) {
            QuickActionCard(
                title: "Analyze a workout",
                subtitle: "Pick a saved video or use your camera",
                icon: "play.circle.fill",
                color: .blue
            )
            QuickActionCard(
                title: "Movement assessment",
                subtitle: "Squat, shoulder flexion, hip hinge",
                icon: "waveform.path.ecg",
                color: .green
            )
        }
        .padding(.horizontal)
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FAQ")
                .font(.title3.bold())
                .padding(.horizontal)

            VStack(spacing: 10) {
                FAQItem(
                    question: "How can I use this to help my clients or patients?",
                    answer: "Kinetriq gives fitness and rehab professionals a simple way to show movement quality, joint angles, tempo, and visible progress. Use it to give clients clearer feedback, compare movement over time, and explain technique changes with video instead of relying only on verbal cues."
                )
                FAQItem(
                    question: "How can I use this to create better content?",
                    answer: "Use Kinetriq overlays to make exercise videos more educational. Angles, reps, tempo, and reference lines can help viewers understand what you are coaching, why a setup matters, and how movement changes from rep to rep."
                )
                FAQItem(
                    question: "Where should I start?",
                    answer: "Start with a saved video in the Workout tab. Choose the exercise or assessment that best matches the movement, select the correct side or camera plane when prompted, then analyze the video."
                )
                FAQItem(
                    question: "How should I position the camera?",
                    answer: "Keep your full body visible from head to feet when possible. For side-view exercises, film from the side. For front or back exercises, film straight on. For deadlifts or movements where the bar blocks the hips, film 15–30 degrees off true side view."
                )
                FAQItem(
                    question: "Why isn’t the app tracking my movement correctly?",
                    answer: "Tracking can fail if the camera angle is wrong, the body is too small in the frame, lighting is poor, or key landmarks are blocked by equipment, arms, plates, benches, or another person."
                )
                FAQItem(
                    question: "Can Kinetriq track more than one person?",
                    answer: "No. Kinetriq is designed to analyze one person at a time. If multiple people are visible, the app may track the wrong person or lose tracking."
                )
                FAQItem(
                    question: "What does the tempo counter mean?",
                    answer: "Tempo is shown as four numbers: eccentric – pause bottom – concentric – pause top. For example, 3-0-1-1 means 3 seconds lowering or lengthening, no pause at the bottom, 1 second lifting or contracting, and 1 second pause at the top."
                )
                FAQItem(
                    question: "Why do some exercises have different eccentric and concentric directions?",
                    answer: "Different exercises move differently. In a squat, the knee and hip angle close during the eccentric. In a curl or pulldown, the working concentric phase often happens as the joint angle closes. Kinetriq adjusts this by exercise."
                )
                FAQItem(
                    question: "What is the difference between Simple and Full HUD?",
                    answer: "Simple shows a cleaner overlay with less text. Full HUD shows more details like angles, reps, tempo, and additional reference lines. Full HUD is best for analysis; Simple is best for cleaner video review."
                )
                FAQItem(
                    question: "Why are reps not counting even when landmarks appear?",
                    answer: "Rep counting depends on the movement reaching expected start and end ranges. If range of motion is partial, the camera angle changes the measured angle, or landmarks are blocked at key moments, reps may not register."
                )
                FAQItem(
                    question: "Why does the analyzed video sometimes show low pose tracking percentage?",
                    answer: "That means Kinetriq could not reliably detect the body in many frames. Improve lighting, move closer, keep the whole body visible, avoid cluttered backgrounds, and make sure the selected exercise matches the filming angle."
                )
                FAQItem(
                    question: "Are videos uploaded to a server?",
                    answer: "No. Kinetriq performs analysis on-device. Videos are selected from your device and processed locally. I am working on a cloud backup system so users can save workout histories to better analyze progress. If you are a coach, physical therapist, or related fitness professional, I recommend saving your client videos on your own drive in the meantime."
                )
            }
            .padding(.horizontal)
        }
    }
}

private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct FAQItem: View {
    let question: String
    let answer: String

    var body: some View {
        DisclosureGroup {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            Text(question)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
