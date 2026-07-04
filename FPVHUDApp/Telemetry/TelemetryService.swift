import Foundation

protocol TelemetrySource: AnyObject {
    var onTelemetry: ((TelemetryState) -> Void)? { get set }
    func start(settings: AppSettings)
    func stop()
}

struct TelemetryReceiverStatus: Equatable {
    var isListening: Bool = false
    var lastPacketReceivedAt: Date?
    var lastPacketAge: TimeInterval?
    var malformedPacketCount: Int = 0
    var warningText: String?

    static let idle = TelemetryReceiverStatus()
}

enum TelemetryFreshness: Equatable {
    case live
    case staleWarning
    case dataLost

    static func evaluate(age: TimeInterval) -> TelemetryFreshness {
        if age > 3 {
            return .dataLost
        }

        if age > 1 {
            return .staleWarning
        }

        return .live
    }
}

struct IncomingTelemetryPacket: Decodable {
    var timestampMs: UInt64?
    var batteryVoltage: Double?
    var rssiDbm: Int?
    var snrDb: Double?
    var linkQualityPercent: Int?
    var speedKmh: Double?
    var gear: Int?
    var driveMode: DriveMode?
    var ersPercent: Int?
    var throttle: Double?
    var brake: Double?
    var steering: Double?
    var cameraYawDeg: Double?
    var cameraPitchDeg: Double?
    var panTiltMode: PanTiltMode?
    var videoLock: Bool?
    var linkState: LinkState?
    var mode: TelemetryMode?
    var warningText: String?
    var staleDataWarnings: [StaleDataWarning]?

    enum CodingKeys: String, CodingKey {
        case timestampMs = "timestamp_ms"
        case batteryVoltage = "battery_v"
        case rssiDbm = "rssi_dbm"
        case snrDb = "snr_db"
        case linkQualityPercent = "link_quality"
        case speedKmh = "speed_kmh"
        case gear
        case driveMode = "drive_mode"
        case ersPercent = "ers_percent"
        case throttle
        case brake
        case steering
        case cameraYawDeg = "camera_yaw_deg"
        case cameraPitchDeg = "camera_pitch_deg"
        case panTiltMode = "head_tracking_mode"
        case videoLock = "video_lock"
        case linkState = "link_state"
        case mode
        case warningText = "warning"
        case staleDataWarnings = "stale_data_warnings"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestampMs = try container.decodeIfPresent(UInt64.self, forKey: .timestampMs)
        batteryVoltage = try container.decodeIfPresent(Double.self, forKey: .batteryVoltage)
        rssiDbm = try container.decodeIfPresent(Int.self, forKey: .rssiDbm)
        snrDb = try container.decodeIfPresent(Double.self, forKey: .snrDb)
        linkQualityPercent = try container.decodeIfPresent(Int.self, forKey: .linkQualityPercent)
        speedKmh = try container.decodeIfPresent(Double.self, forKey: .speedKmh)
        gear = try container.decodeIfPresent(Int.self, forKey: .gear)
        driveMode = try Self.decodeDriveMode(from: container, forKey: .driveMode)
        ersPercent = try container.decodeIfPresent(Int.self, forKey: .ersPercent)
        throttle = try container.decodeIfPresent(Double.self, forKey: .throttle)
        brake = try container.decodeIfPresent(Double.self, forKey: .brake)
        steering = try container.decodeIfPresent(Double.self, forKey: .steering)
        cameraYawDeg = try container.decodeIfPresent(Double.self, forKey: .cameraYawDeg)
        cameraPitchDeg = try container.decodeIfPresent(Double.self, forKey: .cameraPitchDeg)
        panTiltMode = try Self.decodePanTiltMode(from: container, forKey: .panTiltMode)
        videoLock = try container.decodeIfPresent(Bool.self, forKey: .videoLock)
        linkState = try container.decodeIfPresent(LinkState.self, forKey: .linkState)
        mode = try container.decodeIfPresent(TelemetryMode.self, forKey: .mode)
        warningText = try container.decodeIfPresent(String.self, forKey: .warningText)
        staleDataWarnings = try container.decodeIfPresent([StaleDataWarning].self, forKey: .staleDataWarnings)
    }

    func merged(with previous: TelemetryState) -> TelemetryState {
        TelemetryState(
            timestamp: Date(),
            batteryVoltage: batteryVoltage ?? previous.batteryVoltage,
            rssiDbm: rssiDbm ?? previous.rssiDbm,
            snrDb: snrDb ?? previous.snrDb,
            linkQualityPercent: clampPercent(linkQualityPercent ?? previous.linkQualityPercent),
            speedKmh: speedKmh ?? previous.speedKmh,
            gear: max(0, gear ?? previous.gear),
            driveMode: driveMode ?? previous.driveMode,
            ersPercent: clampPercent(ersPercent ?? previous.ersPercent),
            throttle: clampUnit(throttle ?? previous.throttle),
            brake: clampUnit(brake ?? previous.brake),
            steering: clampSignedUnit(steering ?? previous.steering),
            cameraYawDeg: cameraYawDeg ?? previous.cameraYawDeg,
            cameraPitchDeg: cameraPitchDeg ?? previous.cameraPitchDeg,
            panTiltMode: panTiltMode ?? previous.panTiltMode,
            videoLock: videoLock ?? previous.videoLock,
            linkState: linkState ?? .connected,
            mode: mode ?? .udp,
            warningText: normalizedWarning,
            staleDataWarnings: staleDataWarnings ?? []
        )
    }

    private var normalizedWarning: String? {
        guard let warningText else { return nil }
        let trimmed = warningText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func clampSignedUnit(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    private func clampPercent(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }

    private static func decodeDriveMode(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> DriveMode? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        switch normalizedToken(raw) {
        case "TRAINING", "TRAIN": return .training
        case "GEARBOX", "GEAR": return .gearbox
        case "GEARBOXERS", "GEARBOX_ERS", "ERS", "GEARERS": return .gearboxERS
        default: return .unknown
        }
    }

    private static func decodePanTiltMode(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> PanTiltMode? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        switch normalizedToken(raw) {
        case "OFF", "DISABLED": return .disabled
        case "DS4", "DUALSHOCK", "DUALSHOCK4": return .dualShock
        case "HEAD", "HEADTRACKING", "HEAD_TRACKING": return .headTracking
        case "MIX", "MIXED": return .mixed
        default: return .unknown
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
