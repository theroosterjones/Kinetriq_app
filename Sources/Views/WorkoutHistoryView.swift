import SwiftUI

struct WorkoutHistoryView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("Coming Soon")
                    .font(.title2.bold())

                Text("Your workout history will appear here in a future update.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle("History")
        }
    }
}
