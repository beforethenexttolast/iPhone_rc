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

enum AppSettingsField: String, CaseIterable {
    case windowsHost
    case telemetryPort
    case headTrackingPort
    case motionUpdateHz
    case headTrackingSendHz
    case headTrackingTimeoutMs

    var displayName: String {
        switch self {
        case .windowsHost: return "Windows host"
        case .telemetryPort: return "Telemetry UDP port"
        case .headTrackingPort: return "Head tracking UDP port"
        case .motionUpdateHz: return "Motion rate"
        case .headTrackingSendHz: return "Head send rate"
        case .headTrackingTimeoutMs: return "Head timeout"
        }
    }
}

struct AppSettingsValidationIssue: Equatable, Identifiable {
    var field: AppSettingsField
    var message: String

    var id: String {
        "\(field.rawValue):\(message)"
    }
}

struct AppSettingsValidationResult: Equatable {
    var sanitizedSettings: AppSettings?
    var issues: [AppSettingsValidationIssue]

    var isValid: Bool {
        sanitizedSettings != nil && issues.isEmpty
    }

    func messages(for field: AppSettingsField) -> [AppSettingsValidationIssue] {
        issues.filter { $0.field == field }
    }
}

enum AppSettingsValidator {
    static let portRange = 1...65535
    static let motionRateRange = 1...60
    static let sendRateRange = 1...60
    static let timeoutMsRange = 100...5000

    static func validate(_ settings: AppSettings) -> AppSettingsValidationResult {
        var sanitized = settings
        var issues: [AppSettingsValidationIssue] = []

        if let host = validateHost(settings.windowsHost) {
            sanitized.windowsHost = host
        } else {
            issues.append(
                AppSettingsValidationIssue(
                    field: .windowsHost,
                    message: "Enter a valid IPv4 address or hostname."
                )
            )
        }

        if !portRange.contains(settings.telemetryPort) {
            issues.append(
                AppSettingsValidationIssue(
                    field: .telemetryPort,
                    message: "Port must be an integer from 1 to 65535."
                )
            )
        }

        if !portRange.contains(settings.headTrackingPort) {
            issues.append(
                AppSettingsValidationIssue(
                    field: .headTrackingPort,
                    message: "Port must be an integer from 1 to 65535."
                )
            )
        }

        if !motionRateRange.contains(settings.motionUpdateHz) {
            issues.append(
                AppSettingsValidationIssue(
                    field: .motionUpdateHz,
                    message: "Motion rate must be from 1 to 60 Hz."
                )
            )
        }

        if !sendRateRange.contains(settings.headTrackingSendHz) {
            issues.append(
                AppSettingsValidationIssue(
                    field: .headTrackingSendHz,
                    message: "Head send rate must be from 1 to 60 Hz."
                )
            )
        }

        if !timeoutMsRange.contains(settings.headTrackingTimeoutMs) {
            issues.append(
                AppSettingsValidationIssue(
                    field: .headTrackingTimeoutMs,
                    message: "Timeout must be from 100 to 5000 ms."
                )
            )
        }

        return AppSettingsValidationResult(
            sanitizedSettings: issues.isEmpty ? sanitized : nil,
            issues: issues
        )
    }

    static func validateHost(_ host: String) -> String? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if looksLikeIPv4(trimmed) {
            return isValidIPv4(trimmed) ? trimmed : nil
        }
        if looksLikeMalformedNumericIPv4(trimmed) {
            return nil
        }
        guard isValidIPv4(trimmed) || isValidHostname(trimmed) else { return nil }
        return trimmed
    }

    static func parsePort(_ text: String) -> Int? {
        parseInteger(text, in: portRange)
    }

    static func parseSendRateHz(_ text: String) -> Int? {
        parseInteger(text, in: sendRateRange)
    }

    static func parseMotionRateHz(_ text: String) -> Int? {
        parseInteger(text, in: motionRateRange)
    }

    static func parseTimeoutMs(_ text: String) -> Int? {
        parseInteger(text, in: timeoutMsRange)
    }

    private static func parseInteger(_ text: String, in range: ClosedRange<Int>) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return nil }
        guard let value = Int(trimmed), range.contains(value) else { return nil }
        return value
    }

    private static func isValidIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }

        return parts.allSatisfy { part in
            guard !part.isEmpty else { return false }
            guard part.allSatisfy(\.isNumber) else { return false }
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return true
        }
    }

    private static func looksLikeIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }

    private static func looksLikeMalformedNumericIPv4(_ host: String) -> Bool {
        guard host.contains(".") else { return false }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }

    private static func isValidHostname(_ host: String) -> Bool {
        let pattern = #"^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"#
        return host.range(of: pattern, options: .regularExpression) != nil
    }
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
