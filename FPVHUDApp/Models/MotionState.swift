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
    case ready
    case active
    case stale
    case lost

    var displayName: String {
        switch self {
        case .off: return "HEAD TRACK OFF"
        case .ready: return "HEAD TRACK READY"
        case .active: return "HEAD TRACK ACTIVE"
        case .stale: return "HEAD TRACK STALE"
        case .lost: return "HEAD TRACK LOST"
        }
    }
}

struct RawMotionSample {
    var timestamp: Date
    var yawDeg: Double
    var pitchDeg: Double
    var rollDeg: Double
}
