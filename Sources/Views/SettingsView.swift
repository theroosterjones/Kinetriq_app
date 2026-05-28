import SwiftUI

struct SettingsView: View {
    @State private var config = AnalysisConfig.default
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Advanced Settings") {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        Section("Pose Detection") {
                            HStack {
                                Text("Detection Confidence")
                                Spacer()
                                Text(String(format: "%.1f", config.minDetectionConfidence))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.minDetectionConfidence, in: 0.1...1.0, step: 0.1)

                            HStack {
                                Text("Tracking Confidence")
                                Spacer()
                                Text(String(format: "%.1f", config.minTrackingConfidence))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.minTrackingConfidence, in: 0.1...1.0, step: 0.1)
                        }

                        Section("Smoothing") {
                            HStack {
                                Text("Landmark Smoothing")
                                Spacer()
                                Text(String(format: "%.1f", config.smoothingAlpha))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.smoothingAlpha, in: 0.1...1.0, step: 0.1)
                        }

                        Section("Tempo Tracking") {
                            HStack {
                                Text("Velocity Threshold")
                                Spacer()
                                Text(String(format: "%.0f°/s", config.tempoVelocityThreshold))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $config.tempoVelocityThreshold, in: 5...50, step: 5)
                        }
                    } label: {
                        Label("Advanced Settings", systemImage: "slider.horizontal.3")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("3.4.1")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Processing")
                        Spacer()
                        Text("100% On-Device")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Kinetriq is made and used by fitness professionals such as yourself. If you have any feedback, INCLUDING features you would like to have added, please reach out to me and let me know. I'd be happy to add the feature if it improves the functionality.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
