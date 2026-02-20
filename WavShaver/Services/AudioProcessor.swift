import Foundation

struct JobInput: Sendable {
    let id: UUID
    let url: URL
}

actor AudioProcessor {
    let settings: WavShaverSettings
    let onFileStarted: (@Sendable (UUID) -> Void)?

    init(settings: WavShaverSettings, onFileStarted: (@Sendable (UUID) -> Void)? = nil) {
        self.settings = settings
        self.onFileStarted = onFileStarted
    }

    func run(inputs: [JobInput]) async throws -> [JobResult] {
        guard !inputs.isEmpty else { return [] }

        let tools = try await FFmpegManager.shared.ensureTools()
        let maxConcurrent = 3

        return try await withThrowingTaskGroup(of: JobResult?.self) { group in
            var results: [JobResult] = []
            var index = 0

            func addNext() {
                guard index < inputs.count else { return }
                let input = inputs[index]
                index += 1
                group.addTask {
                    try Task.checkCancellation()
                    await self.onFileStarted?(input.id)
                    return try await self.processOne(input.url, id: input.id, tools: tools)
                }
            }

            for _ in 0..<min(maxConcurrent, inputs.count) {
                addNext()
            }

            for try await result in group {
                if let result {
                    results.append(result)
                }
                addNext()
            }

            return results
        }
    }

    private func processOne(_ input: URL, id: UUID, tools: FFmpegManager.Paths) async throws -> JobResult? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: input.path) else {
            throw ProcessingError.invalidInput
        }

        let sr = settings.sampleRate.rawValue
        let rateTag = sr == 44100 ? "44k" : "48k"
        let stem = input.deletingPathExtension().lastPathComponent
        let limitAmp = pow(10.0, settings.limitDb / 20.0)
        let limitTag = formatDbTag(settings.limitDb)
        let outDir = bestOutputDir(for: input)
        let outName = "\(stem)-\(rateTag)shaved-\(limitTag).wav"
        let finalURL = outDir.appendingPathComponent(outName)
        let tmpURL = outDir.appendingPathComponent(".\(outName).tmp")

        let work = try makeTemp(prefix: "wavshaver_\(rateTag)_")
        defer { try? fm.removeItem(at: work) }

        // Detect input channel count
        let probeArgs = [
            "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=channels",
            "-of", "csv=p=0", input.path
        ]
        let channelStr = try await runFFmpegCapture(exe: tools.ffprobe, args: probeArgs).trimmingCharacters(in: .whitespacesAndNewlines)
        let channels = Int(channelStr) ?? 2

        // Step 1: Resample to target sample rate
        let midURL = work.appendingPathComponent("\(stem)_\(rateTag)24.wav")
        try await runFFmpeg(exe: tools.ffmpeg, args: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", input.path, "-af", "aresample=\(sr)",
            "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(channels)", midURL.path
        ])

        try Task.checkCancellation()

        // Step 2: Brick-wall limiter with 2x oversampling
        let oversampleSr = sr * 2
        let limiterAf = [
            "aresample=\(oversampleSr)",
            "alimiter=limit=\(limitAmp):attack=5:release=50:level=disabled",
            "aresample=\(sr)"
        ].joined(separator: ",")

        if fm.fileExists(atPath: tmpURL.path) {
            try? fm.removeItem(at: tmpURL)
        }

        try await runFFmpeg(exe: tools.ffmpeg, args: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", midURL.path, "-af", limiterAf,
            "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(channels)", "-f", "wav", tmpURL.path
        ])

        guard let attrs = try? fm.attributesOfItem(atPath: tmpURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 0 else {
            throw ProcessingError.outputMissing
        }

        if fm.fileExists(atPath: finalURL.path) {
            try? fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: tmpURL, to: finalURL)

        return JobResult(id: id, input: input, output: finalURL)
    }

    private nonisolated func runFFmpeg(exe: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let fm = FileManager.default
            guard fm.fileExists(atPath: exe) else {
                continuation.resume(throwing: ProcessingError.ffmpegNotFound)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = args

            let stderrPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrPipe

            var stderrData = Data()
            let readGroup = DispatchGroup()
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }

            process.terminationHandler = { proc in
                readGroup.wait()
                let exitCode = proc.terminationStatus
                let msg = String(data: stderrData, encoding: .utf8) ?? ""
                if exitCode != 0 {
                    continuation.resume(throwing: ProcessingError.ffmpegFailed(code: exitCode, message: msg.isEmpty ? "Exit code \(exitCode)" : msg))
                } else {
                    continuation.resume(returning: ())
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessingError.ffmpegFailed(code: -1, message: "Failed to launch: \(error.localizedDescription)"))
            }
        }
    }

    private nonisolated func runFFmpegCapture(exe: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let fm = FileManager.default
            guard fm.fileExists(atPath: exe) else {
                continuation.resume(throwing: ProcessingError.ffmpegNotFound)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var stdoutData = Data()
            var stderrData = Data()
            let readGroup = DispatchGroup()

            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }

            process.terminationHandler = { proc in
                readGroup.wait()
                let exitCode = proc.terminationStatus
                if exitCode != 0 {
                    let msg = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: ProcessingError.ffmpegFailed(code: exitCode, message: msg.isEmpty ? "Exit code \(exitCode)" : msg))
                } else {
                    let output = String(data: stdoutData, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessingError.ffmpegFailed(code: -1, message: "Failed to launch: \(error.localizedDescription)"))
            }
        }
    }

    private func makeTemp(prefix: String) throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ProcessingError.tempDirectoryFailed
        }
        return dir
    }

    private func formatDbTag(_ db: Double) -> String {
        var s = String(format: "%.2f", db)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            s.removeLast()
        }
        return "\(s)dB"
    }

    private func bestOutputDir(for input: URL) -> URL {
        let fm = FileManager.default

        if let customPath = settings.outputDirectoryPath {
            let customURL = URL(fileURLWithPath: customPath, isDirectory: true)
            if fm.isWritableFile(atPath: customURL.path) { return customURL }
        }

        let here = input.deletingLastPathComponent()
        if fm.isWritableFile(atPath: here.path) { return here }

        let music = fm.homeDirectoryForCurrentUser.appendingPathComponent("Music/WavShaver", isDirectory: true)
        if (try? fm.createDirectory(at: music, withIntermediateDirectories: true)) != nil {
            return music
        }

        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}
