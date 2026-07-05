import Foundation

struct TelemetryState: Equatable {
    var timestamp: Date
    var batteryVoltage: Double
    var rssiDbm: Int
    var snrDb: Double
    var linkQualityPercent: Int
    var speedKmh: Double
    var gear: Int
    var driveMode: DriveMode
    var ersPercent: Int
    var throttle: Double
    var brake: Double
    var steering: Double
    var cameraYawDeg: Double
    var cameraPitchDeg: Double
    var panTiltMode: PanTiltMode
    var videoLock: Bool
    var linkState: LinkState
    var mode: TelemetryMode
    var warningText: String?
    var staleDataWarnings: [StaleDataWarning]

    static let demo = TelemetryState(
        timestamp: Date(),
        batteryVoltage: 8.12,
        rssiDbm: -48,
        snrDb: 21.4,
        linkQualityPercent: 96,
        speedKmh: 0,
        gear: 3,
        driveMode: .gearbox,
        ersPercent: 55,
        throttle: 0,
        brake: 0,
        steering: 0,
        cameraYawDeg: 0,
        cameraPitchDeg: 0,
        panTiltMode: .dualShock,
        videoLock: false,
        linkState: .demo,
        mode: .demo,
        warningText: "VIDEO PLACEHOLDER",
        staleDataWarnings: []
    )
}

struct TelemetryDisplayState: Equatable {
    var rawTelemetry: TelemetryState?
    var freshness: TelemetryFreshness
    var linkState: LinkState
    var linkText: String
    var sourceText: String
    var batteryText: String
    var linkQualityText: String
    var rssiText: String
    var snrText: String
    var speedValueText: String
    var speedText: String
    var gearText: String
    var driveModeText: String
    var ersText: String
    var throttle: Double
    var brake: Double
    var steering: Double
    var panTiltMode: PanTiltMode
    var panTiltModeText: String
    var cameraYawText: String
    var cameraPitchText: String
    var videoLock: Bool
    var videoText: String
    var warningText: String?
    var staleDataWarnings: [StaleDataWarning]
    var showsLiveValues: Bool

    static let unknown = placeholder(
        rawTelemetry: nil,
        linkState: .disconnected,
        warningText: nil
    )

    static func make(
        rawTelemetry: TelemetryState?,
        receiverStatus: TelemetryReceiverStatus,
        settings: AppSettings,
        now: Date = Date()
    ) -> TelemetryDisplayState {
        guard let rawTelemetry else {
            return placeholder(
                rawTelemetry: nil,
                linkState: settings.demoModeEnabled ? .demo : .connecting,
                warningText: settings.demoModeEnabled ? nil : "WAITING FOR TELEMETRY"
            )
        }

        if settings.demoModeEnabled && rawTelemetry.mode != .demo {
            return placeholder(
                rawTelemetry: rawTelemetry,
                linkState: .demo,
                warningText: nil,
                staleDataWarnings: []
            )
        }

        if !settings.demoModeEnabled && rawTelemetry.mode == .demo {
            return placeholder(
                rawTelemetry: rawTelemetry,
                linkState: .connecting,
                warningText: receiverStatus.warningText ?? "WAITING FOR TELEMETRY",
                staleDataWarnings: [.telemetry]
            )
        }

        if rawTelemetry.linkState == .connecting || rawTelemetry.warningText == "WAITING FOR TELEMETRY" {
            return placeholder(
                rawTelemetry: rawTelemetry,
                linkState: .connecting,
                warningText: rawTelemetry.warningText ?? receiverStatus.warningText ?? "WAITING FOR TELEMETRY",
                staleDataWarnings: mergedWarnings(rawTelemetry.staleDataWarnings, adding: .telemetry)
            )
        }

        if rawTelemetry.linkState == .disconnected || rawTelemetry.warningText == "TELEMETRY DATA LOST >3S" {
            return placeholder(
                rawTelemetry: rawTelemetry,
                linkState: .disconnected,
                warningText: rawTelemetry.warningText ?? "TELEMETRY DATA LOST >3S",
                staleDataWarnings: mergedWarnings(rawTelemetry.staleDataWarnings, adding: .telemetry)
            )
        }

        let freshness = displayFreshness(
            for: rawTelemetry,
            receiverStatus: receiverStatus,
            settings: settings,
            now: now
        )

        switch freshness {
        case .live:
            var display = live(from: rawTelemetry, freshness: .live)
            display.warningText = rawTelemetry.warningText
            display.staleDataWarnings = rawTelemetry.staleDataWarnings
            return display
        case .staleWarning:
            var display = live(from: rawTelemetry, freshness: .staleWarning)
            display.linkState = .degraded
            display.linkText = LinkState.degraded.displayName
            display.warningText = rawTelemetry.warningText ?? "TELEMETRY STALE >1S"
            display.staleDataWarnings = mergedWarnings(rawTelemetry.staleDataWarnings, adding: .telemetry)
            return display
        case .dataLost:
            return placeholder(
                rawTelemetry: rawTelemetry,
                linkState: .disconnected,
                warningText: "TELEMETRY DATA LOST >3S",
                staleDataWarnings: mergedWarnings(rawTelemetry.staleDataWarnings, adding: .telemetry)
            )
        }
    }

    private static func live(
        from telemetry: TelemetryState,
        freshness: TelemetryFreshness
    ) -> TelemetryDisplayState {
        TelemetryDisplayState(
            rawTelemetry: telemetry,
            freshness: freshness,
            linkState: telemetry.linkState,
            linkText: telemetry.linkState.displayName,
            sourceText: telemetry.mode.rawValue.uppercased(),
            batteryText: String(format: "%.1f V", telemetry.batteryVoltage),
            linkQualityText: "\(telemetry.linkQualityPercent)%",
            rssiText: "\(telemetry.rssiDbm)",
            snrText: String(format: "%.0f", telemetry.snrDb),
            speedValueText: "\(Int(telemetry.speedKmh.rounded()))",
            speedText: "\(Int(telemetry.speedKmh.rounded())) km/h",
            gearText: "G\(telemetry.gear)",
            driveModeText: telemetry.driveMode.displayName,
            ersText: "\(telemetry.ersPercent)%",
            throttle: telemetry.throttle,
            brake: telemetry.brake,
            steering: telemetry.steering,
            panTiltMode: telemetry.panTiltMode,
            panTiltModeText: telemetry.panTiltMode.displayName,
            cameraYawText: String(format: "%+.1f deg", telemetry.cameraYawDeg),
            cameraPitchText: String(format: "%+.1f deg", telemetry.cameraPitchDeg),
            videoLock: telemetry.videoLock,
            videoText: telemetry.videoLock ? "VIDEO LOCK" : "NO VIDEO",
            warningText: telemetry.warningText,
            staleDataWarnings: telemetry.staleDataWarnings,
            showsLiveValues: true
        )
    }

    private static func placeholder(
        rawTelemetry: TelemetryState?,
        linkState: LinkState,
        warningText: String?,
        staleDataWarnings: [StaleDataWarning] = [.telemetry]
    ) -> TelemetryDisplayState {
        TelemetryDisplayState(
            rawTelemetry: rawTelemetry,
            freshness: .dataLost,
            linkState: linkState,
            linkText: linkState.displayName,
            sourceText: "--",
            batteryText: "--.- V",
            linkQualityText: "--",
            rssiText: "--",
            snrText: "--",
            speedValueText: "--",
            speedText: "-- km/h",
            gearText: "--",
            driveModeText: "UNKNOWN",
            ersText: "--",
            throttle: 0,
            brake: 0,
            steering: 0,
            panTiltMode: .unknown,
            panTiltModeText: "--",
            cameraYawText: "--",
            cameraPitchText: "--",
            videoLock: false,
            videoText: "NO VIDEO",
            warningText: warningText,
            staleDataWarnings: staleDataWarnings,
            showsLiveValues: false
        )
    }

    private static func displayFreshness(
        for telemetry: TelemetryState,
        receiverStatus: TelemetryReceiverStatus,
        settings: AppSettings,
        now: Date
    ) -> TelemetryFreshness {
        if settings.demoModeEnabled || telemetry.mode == .demo {
            return .live
        }

        if let lastPacketReceivedAt = receiverStatus.lastPacketReceivedAt {
            return TelemetryFreshness.evaluate(age: max(0, now.timeIntervalSince(lastPacketReceivedAt)))
        }

        if let lastPacketAge = receiverStatus.lastPacketAge {
            return TelemetryFreshness.evaluate(age: lastPacketAge)
        }

        return TelemetryFreshness.evaluate(age: max(0, now.timeIntervalSince(telemetry.timestamp)))
    }

    private static func mergedWarnings(
        _ warnings: [StaleDataWarning],
        adding warning: StaleDataWarning
    ) -> [StaleDataWarning] {
        warnings.contains(warning) ? warnings : warnings + [warning]
    }
}

enum LinkState: String, Codable, CaseIterable {
    case disconnected
    case connecting
    case connected
    case degraded
    case demo

    var displayName: String {
        switch self {
        case .disconnected: return "DISCONNECTED"
        case .connecting: return "CONNECTING"
        case .connected: return "LINK OK"
        case .degraded: return "LINK DEGRADED"
        case .demo: return "SIM / DEMO"
        }
    }
}

enum TelemetryMode: String, Codable {
    case demo
    case udp
    case replay
}

enum DriveMode: String, Codable, CaseIterable {
    case training
    case gearbox
    case gearboxERS
    case unknown

    var displayName: String {
        switch self {
        case .training: return "TRAIN"
        case .gearbox: return "GEAR"
        case .gearboxERS: return "ERS"
        case .unknown: return "UNK"
        }
    }
}

enum PanTiltMode: String, Codable, CaseIterable {
    case dualShock
    case headTracking
    case mixed
    case disabled
    case unknown

    var displayName: String {
        switch self {
        case .dualShock: return "DS4"
        case .headTracking: return "HEAD"
        case .mixed: return "MIX"
        case .disabled: return "OFF"
        case .unknown: return "UNK"
        }
    }
}

enum StaleDataWarning: String, Codable, CaseIterable {
    case telemetry
    case battery
    case linkQuality
    case speed
    case flightMode
    case camera
    case video

    var displayName: String {
        switch self {
        case .telemetry: return "TEL STALE"
        case .battery: return "BAT STALE"
        case .linkQuality: return "LQ STALE"
        case .speed: return "SPD STALE"
        case .flightMode: return "MODE STALE"
        case .camera: return "CAM STALE"
        case .video: return "VID STALE"
        }
    }
}
