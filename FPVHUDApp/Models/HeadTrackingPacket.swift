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

struct HeadTrackingPacketFactory {
    private(set) var sequence: UInt32 = 0

    mutating func makePacket(
        yawDeg: Double,
        pitchDeg: Double,
        rollDeg: Double,
        trackingEnabled: Bool,
        centered: Bool,
        timeoutMs: UInt16,
        timestampMs: UInt64? = nil
    ) -> HeadTrackingPacket {
        sequence &+= 1
        return HeadTrackingPacket(
            seq: sequence,
            timestampMs: timestampMs ?? UInt64(Date().timeIntervalSince1970 * 1000),
            yawDeg: yawDeg,
            pitchDeg: pitchDeg,
            rollDeg: rollDeg,
            trackingEnabled: trackingEnabled,
            centered: centered,
            timeoutMs: timeoutMs
        )
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

struct HeadTrackingDisplayState: Equatable {
    var isUDPConfigured: Bool
    var udpConfiguredText: String
    var packetRateText: String
    var packetsSentText: String
    var lastSendText: String
    var warningText: String?
    var driveErrorText: String?
    var debugErrorText: String?
    var debugSuggestionText: String?

    var hasDriveError: Bool {
        driveErrorText != nil
    }

    init(
        isUDPConfigured: Bool,
        udpConfiguredText: String,
        packetRateText: String,
        packetsSentText: String,
        lastSendText: String,
        warningText: String?,
        driveErrorText: String?,
        debugErrorText: String?,
        debugSuggestionText: String?
    ) {
        self.isUDPConfigured = isUDPConfigured
        self.udpConfiguredText = udpConfiguredText
        self.packetRateText = packetRateText
        self.packetsSentText = packetsSentText
        self.lastSendText = lastSendText
        self.warningText = warningText
        self.driveErrorText = driveErrorText
        self.debugErrorText = debugErrorText
        self.debugSuggestionText = debugSuggestionText
    }

    static let idle = HeadTrackingDisplayState(
        isUDPConfigured: false,
        udpConfiguredText: "No",
        packetRateText: "0 Hz",
        packetsSentText: "0",
        lastSendText: "Never",
        warningText: nil,
        driveErrorText: nil,
        debugErrorText: nil,
        debugSuggestionText: nil
    )

    init(senderStatus: HeadTrackingSenderStatus, now: Date = Date()) {
        isUDPConfigured = senderStatus.isConfigured
        udpConfiguredText = senderStatus.isConfigured ? "Yes" : "No"
        packetRateText = String(format: "%.0f Hz", senderStatus.packetRateHz)
        packetsSentText = "\(senderStatus.packetsSent)"
        warningText = senderStatus.lastErrorText
        debugErrorText = senderStatus.lastErrorText
        driveErrorText = HeadTrackingErrorDisplay.driveLabel(for: senderStatus.lastErrorText)
        debugSuggestionText = HeadTrackingErrorDisplay.debugSuggestion(for: senderStatus.lastErrorText)

        if let lastSendAt = senderStatus.lastSendAt {
            lastSendText = String(format: "%.2fs ago", now.timeIntervalSince(lastSendAt))
        } else {
            lastSendText = "Never"
        }
    }

    func driveStatusText(motionStatus: HeadTrackingStatus) -> String {
        driveErrorText ?? motionStatus.driveDisplayName
    }
}

enum HeadTrackingErrorDisplay {
    static func driveLabel(for errorText: String?) -> String? {
        guard let normalized = normalized(errorText) else { return nil }

        if isNetworkAddressError(normalized) {
            return "HEAD TX NET ERROR"
        }

        if normalized.contains("invalid head tracking udp port") {
            return "SETTINGS INVALID"
        }

        if normalized.contains("not configured") {
            return "HEAD TX ERROR"
        }

        return "HEAD TX ERROR"
    }

    static func debugSuggestion(for errorText: String?) -> String? {
        guard let normalized = normalized(errorText) else { return nil }

        if isNetworkAddressError(normalized) || normalized.contains("invalid head tracking udp port") {
            return "Check Windows host/IP and head-tracking UDP port."
        }

        return nil
    }

    private static func normalized(_ errorText: String?) -> String? {
        guard let errorText else { return nil }
        let trimmed = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private static func isNetworkAddressError(_ normalized: String) -> Bool {
        normalized.contains("nwerror error 49")
            || normalized.contains("can't assign requested address")
            || normalized.contains("cannot assign requested address")
    }
}
