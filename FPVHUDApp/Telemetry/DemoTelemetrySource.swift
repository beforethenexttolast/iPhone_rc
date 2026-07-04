import Foundation

final class DemoTelemetrySource: TelemetrySource {
    var onTelemetry: ((TelemetryState) -> Void)?

    private var timer: Timer?
    private let startDate = Date()

    func start(settings: AppSettings) {
        stop()
        emitSample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.emitSample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func emitSample() {
        let t = Date().timeIntervalSince(startDate)
        let throttle = max(0, sin(t * 0.82) * 0.55 + 0.35)
        let brake = max(0, sin(t * 0.47 + 2.2) * 0.32)
        let steering = sin(t * 1.35) * 0.82
        let speed = max(0, 8 + throttle * 58 + sin(t * 1.9) * 5 - brake * 18)
        let rssi = -47 - Int((sin(t * 0.55) + 1) * 10)
        let snr = 20 + sin(t * 0.7 + 0.4) * 4
        let linkQuality = 82 + Int((sin(t * 0.42) + 1) * 8)
        let gear = min(max(Int(speed / 20) + 1, 1), 4)
        let ersPercent = min(max(55 + Int(sin(t * 0.31) * 33) - Int(throttle * 12), 0), 100)
        let driveMode: DriveMode = ersPercent > 24 ? .gearboxERS : .gearbox
        let panTiltMode: PanTiltMode = Int(t / 12).isMultiple(of: 2) ? .dualShock : .headTracking

        let state = TelemetryState(
            timestamp: Date(),
            batteryVoltage: 8.18 - min(t * 0.001, 0.5) + sin(t * 0.33) * 0.04,
            rssiDbm: rssi,
            snrDb: snr,
            linkQualityPercent: linkQuality,
            speedKmh: speed,
            gear: gear,
            driveMode: driveMode,
            ersPercent: ersPercent,
            throttle: min(max(throttle, 0), 1),
            brake: min(max(brake, 0), 1),
            steering: steering,
            cameraYawDeg: sin(t * 0.5) * 28,
            cameraPitchDeg: sin(t * 0.37 + 1.0) * 9,
            panTiltMode: panTiltMode,
            videoLock: false,
            linkState: .demo,
            mode: .demo,
            warningText: "VIDEO PLACEHOLDER",
            staleDataWarnings: Int(t / 9).isMultiple(of: 5) ? [.video] : []
        )

        onTelemetry?(state)
    }
}
