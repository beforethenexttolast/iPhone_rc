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
        case .off: return "HEAD TRACK OFF"
        case .readyNotCentered: return "HEAD TRACK READY - NOT CENTERED"
        case .active: return "HEAD TRACK ACTIVE"
        case .stale: return "HEAD TRACK STALE"
        case .error: return "HEAD TRACK ERROR"
        }
    }
}

enum HeadTrackingSafety {
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
