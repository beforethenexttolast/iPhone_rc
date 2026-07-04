import Foundation

struct AppSettings: Equatable {
    var windowsHost: String = "192.168.4.2"
    var telemetryPort: Int = 5601
    var headTrackingPort: Int = 5602
    var motionUpdateHz: Int = 60
    var headTrackingSendHz: Int = 60
    var headTrackingTimeoutMs: Int = 250
    var trackingEnabled: Bool = false
    var demoModeEnabled: Bool = true
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
