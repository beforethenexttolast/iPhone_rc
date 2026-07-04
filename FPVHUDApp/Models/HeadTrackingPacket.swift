import Foundation

struct HeadTrackingPacket: Codable, Equatable {
    var seq: UInt32
    var timestampMs: UInt64
    var yawDeg: Double
    var pitchDeg: Double
    var rollDeg: Double
    var trackingEnabled: Bool
    var centered: Bool
    var timeoutMs: UInt16

    enum CodingKeys: String, CodingKey {
        case seq
        case timestampMs = "timestamp_ms"
        case yawDeg = "yaw_deg"
        case pitchDeg = "pitch_deg"
        case rollDeg = "roll_deg"
        case trackingEnabled = "tracking_enabled"
        case centered
        case timeoutMs = "timeout_ms"
    }
}

struct HeadTrackingSenderStatus: Equatable {
    var isConfigured: Bool = false
    var packetsSent: UInt64 = 0
    var packetRateHz: Double = 0
    var lastSendAt: Date?
    var lastErrorText: String?

    static let idle = HeadTrackingSenderStatus()
}
