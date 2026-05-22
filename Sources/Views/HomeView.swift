import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

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

                    Text("Movement intelligence, on-device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Quick-action cards
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

                Spacer()
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
