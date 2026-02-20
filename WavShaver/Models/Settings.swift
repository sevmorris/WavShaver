import Foundation

struct WavShaverSettings: Codable, Equatable, Sendable {
    enum SampleRate: Int, CaseIterable, Codable, Sendable {
        case s44100 = 44100
        case s48000 = 48000
    }

    var sampleRate: SampleRate = .s44100
    var limitDb: Double = -1.0
    var outputDirectoryPath: String? = nil

    private static let storageKey = "WavShaverSettings"

    static func load() -> WavShaverSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(WavShaverSettings.self, from: data)
        else {
            return WavShaverSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
