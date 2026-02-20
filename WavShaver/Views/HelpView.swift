import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section("Design Philosophy") {
                    text("""
                    WavShaver is intentionally minimal. It does one thing — applies \
                    brick-wall peak limiting — and gets out of the way. Set your ceiling, \
                    drop your files, done.
                    """)
                }
                section("Getting Started") {
                    text("""
                    WavShaver applies a brick-wall limiter to audio files, shaving peaks \
                    above your chosen ceiling. It preserves the original channel layout \
                    and outputs clean 24-bit WAV files.
                    """)
                    steps([
                        "Choose your sample rate (44.1 kHz or 48 kHz).",
                        "Set the ceiling to control maximum peak level (e.g., -1 dB).",
                        "Drag and drop audio files onto the window.",
                        "Click Process.",
                        "Output files are saved alongside the originals with a -shaved suffix."
                    ])
                }
                section("Output Naming") {
                    code("{original-name}-{samplerate}shaved-{limit}dB.wav")
                    text("Example: episode-01-44kshaved-1dB.wav")
                }
                section("Processing Pipeline") {
                    text("WavShaver uses FFmpeg with a simple two-step pipeline:")
                    numberedList([
                        "Resampling to the target sample rate.",
                        "Brick-wall limiting with 2x oversampled true peak control."
                    ])
                    text("Output format: 24-bit WAV")
                }
                section("Settings") {
                    definition("Sample Rate", "Output sample rate — 44.1 kHz or 48 kHz.")
                    definition("Ceiling", "Brick-wall limiter ceiling, from -6 dB to -1 dB. Controls the maximum peak level of the output.")
                    definition("Output Directory", "Custom output folder for processed files. Defaults to the same directory as the source file.")
                }
                Spacer()
            }
            .padding(30)
        }
        .frame(width: 540, height: 520)
    }

    // MARK: - Components

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WavShaver Help")
                .font(.largeTitle.bold())
            Text("Brick-Wall Limiter for macOS")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    private func text(_ string: String) -> some View {
        Text(string)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func code(_ string: String) -> some View {
        Text(string)
            .font(.system(.body, design: .monospaced))
            .padding(8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.body.bold())
                        .frame(width: 20, alignment: .trailing)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func numberedList(_ items: [String]) -> some View {
        steps(items)
    }

    private func definition(_ term: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term)
                .font(.body.bold())
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    HelpView()
}
