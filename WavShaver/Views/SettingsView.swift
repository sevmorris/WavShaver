import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Sample Rate")
                    Picker("", selection: $viewModel.settings.sampleRate) {
                        Text("44.1 kHz").tag(WavShaverSettings.SampleRate.s44100)
                        Text("48 kHz").tag(WavShaverSettings.SampleRate.s48000)
                    }
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Ceiling")
                    HStack {
                        Slider(value: $viewModel.settings.limitDb, in: -6 ... -1, step: 1)
                        Text(String(format: "%.0f dB", viewModel.settings.limitDb))
                            .frame(width: 80, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("Output Dir")
                    HStack {
                        if let path = viewModel.settings.outputDirectoryPath {
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption)
                            Button("Reset") {
                                viewModel.settings.outputDirectoryPath = nil
                            }
                            .controlSize(.small)
                        } else {
                            Text("Same as source")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                viewModel.settings.outputDirectoryPath = url.path
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
    }
}
