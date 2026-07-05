import Foundation

struct MotionState: Equatable {
    var timestamp: Date
    var rawYawDeg: Double
    var rawPitchDeg: Double
    var rawRollDeg: Double
    var yawDeg: Double
    var pitchDeg: Double
    var rollDeg: Double
    var trackingEnabled: Bool
    var status: HeadTrackingStatus
    var calibratedCenterYaw: Double
    var calibratedCenterPitch: Double
    var calibratedCenterRoll: Double

    static let zero = MotionState(
        timestamp: .distantPast,
        rawYawDeg: 0,
        rawPitchDeg: 0,
        rawRollDeg: 0,
        yawDeg: 0,
        pitchDeg: 0,
        rollDeg: 0,
        trackingEnabled: false,
        status: .off,
        calibratedCenterYaw: 0,
        calibratedCenterPitch: 0,
        calibratedCenterRoll: 0
    )
}

enum HeadTrackingStatus: String, Equatable {
    case off
    case readyNotCentered
    case active
    case stale
    case error

    var displayName: String {
        switch self {
        case .off: return "HEAD TX OFF"
        case .readyNotCentered: return "HEAD TX READY - NOT CENTERED"
        case .active: return "HEAD TX ACTIVE"
        case .stale: return "HEAD TX STALE"
        case .error: return "HEAD TX ERROR"
        }
    }

    var driveDisplayName: String {
        switch self {
        case .off: return "HEAD OFF"
        case .readyNotCentered: return "HEAD NOT CENTERED"
        case .active: return "HEAD ACTIVE"
        case .stale: return "HEAD STALE"
        case .error: return "HEAD STALE"
        }
    }
}

enum HeadTrackingSafety {
    static func canConfigureSender(settings: AppSettings, hasCentered: Bool) -> Bool {
        AppSettingsValidator.validate(settings).isValid
            && settings.trackingEnabled
            && hasCentered
    }

    static func canSend(
        settings: AppSettings,
        status: HeadTrackingStatus,
        hasCentered: Bool
    ) -> Bool {
        canConfigureSender(settings: settings, hasCentered: hasCentered)
            && canSend(status: status)
    }

    static func status(
        trackingEnabled: Bool,
        hasCentered: Bool,
        sampleTimestamp: Date,
        now: Date = Date(),
        staleAfter: TimeInterval = 0.5,
        errorAfter: TimeInterval = 2.0
    ) -> HeadTrackingStatus {
        guard trackingEnabled else { return .off }

        let age = now.timeIntervalSince(sampleTimestamp)
        if sampleTimestamp == .distantPast || age > errorAfter {
            return .error
        }

        if age > staleAfter {
            return .stale
        }

        return hasCentered ? .active : .readyNotCentered
    }

    static func canSend(status: HeadTrackingStatus) -> Bool {
        status == .active
    }
}

struct RawMotionSample {
    var timestamp: Date
    var yawDeg: Double
    var pitchDeg: Double
    var rollDeg: Double
}
