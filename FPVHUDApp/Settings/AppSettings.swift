import Foundation

struct AppSettings: Codable, Equatable {
    var windowsHost: String = "192.168.4.2"
    var telemetryPort: Int = 5601
    var headTrackingPort: Int = 5602
    var motionUpdateHz: Int = 60
    var headTrackingSendHz: Int = 60
    var headTrackingTimeoutMs: Int = 250
    var trackingEnabled: Bool = false
    var demoModeEnabled: Bool = true

    static let defaults = AppSettings()
}

enum HeadTrackingTiming {
    static func clampedSendRateHz(_ rate: Int) -> Int {
        min(max(rate, 30), 60)
    }

    static func sendIntervalMilliseconds(forRateHz rate: Int) -> Int {
        let clampedRate = clampedSendRateHz(rate)
        return max(1, Int((1000.0 / Double(clampedRate)).rounded()))
    }
}

struct SettingsStore {
    static let storageKey = "fpvhud.appSettings.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return .defaults
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return .defaults
        }
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func reset() -> AppSettings {
        defaults.removeObject(forKey: Self.storageKey)
        return .defaults
    }
}
