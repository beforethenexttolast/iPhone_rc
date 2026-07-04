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
