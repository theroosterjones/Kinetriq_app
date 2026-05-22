import SwiftUI

struct SettingsView: View {
    @State private var config = AnalysisConfig.default

    var body: some View {
        NavigationStack {
            Form {
                Section("Pose Detection") {
                    HStack {
                        Text("Detection Confidence")
                        Spacer()
                        Text(String(format: "%.1f", config.minDetectionConfidence))
                    }
                    Slider(value: $config.minDetectionConfidence, in: 0.1...1.0, step: 0.1)

                    HStack {
                        Text("Tracking Confidence")
                        Spacer()
                        Text(String(format: "%.1f", config.minTrackingConfidence))
                    }
                    Slider(value: $config.minTrackingConfidence, in: 0.1...1.0, step: 0.1)
                }

                Section("Smoothing") {
                    HStack {
                        Text("Landmark Smoothing")
                        Spacer()
                        Text(String(format: "%.1f", config.smoothingAlpha))
                    }
                    Slider(value: $config.smoothingAlpha, in: 0.1...1.0, step: 0.1)
                }

                Section("Tempo Tracking") {
                    HStack {
                        Text("Velocity Threshold")
                        Spacer()
                        Text(String(format: "%.0f°/s", config.tempoVelocityThreshold))
                    }
                    Slider(value: $config.tempoVelocityThreshold, in: 5...50, step: 5)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Processing")
                        Spacer()
                        Text("100% On-Device")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
