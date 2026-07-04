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
