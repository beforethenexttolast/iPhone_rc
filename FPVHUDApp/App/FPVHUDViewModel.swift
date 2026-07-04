import Foundation

@MainActor
final class FPVHUDViewModel: ObservableObject {
    @Published var telemetry: TelemetryState = .demo
    @Published var motion: MotionState = .zero
    @Published var settings = AppSettings()
    @Published var telemetryStatus: TelemetryReceiverStatus = .idle
    @Published var headTrackingSenderStatus: HeadTrackingSenderStatus = .idle
    @Published var isSettingsPresented = false

    private let demoTelemetry = DemoTelemetrySource()
    private let udpTelemetry = UDPTelemetryReceiver()
    private let motionService: MotionService
    private let headTrackingSender = HeadTrackingSender()

    private var rawYawDeg: Double = 0
    private var rawPitchDeg: Double = 0
    private var rawRollDeg: Double = 0
    private var centerYawDeg: Double = 0
    private var centerPitchDeg: Double = 0
    private var centerRollDeg: Double = 0
    private var motionStatusTimer: Timer?
    private var headTrackingSendTimer: Timer?
    private var hasCenteredTracking = false

    init(
        motionService: MotionService = MotionServiceFactory.makeDefault()
    ) {
        self.motionService = motionService
        bindServices()
        applySettings()
    }

    func applySettings() {
        headTrackingSender.configure(
            host: settings.windowsHost,
            port: UInt16(clamping: settings.headTrackingPort)
        )
        startHeadTrackingSendTimer()

        if settings.demoModeEnabled {
            udpTelemetry.stop()
            telemetryStatus = .idle
            demoTelemetry.start(settings: settings)
        } else {
            demoTelemetry.stop()
            udpTelemetry.start(settings: settings)
        }

        motionService.start(updateRateHz: Double(settings.motionUpdateHz))
        startMotionStatusTimer()
        updateMotionState()
    }

    func centerTracking() {
        centerYawDeg = rawYawDeg
        centerPitchDeg = rawPitchDeg
        centerRollDeg = rawRollDeg
        hasCenteredTracking = true
        updateMotionState()
    }

    func stopNetworking() {
        demoTelemetry.stop()
        udpTelemetry.stop()
        headTrackingSender.stop()
        motionStatusTimer?.invalidate()
        motionStatusTimer = nil
        headTrackingSendTimer?.invalidate()
        headTrackingSendTimer = nil
    }

    private func bindServices() {
        demoTelemetry.onTelemetry = { [weak self] state in
            Task { @MainActor in
                self?.telemetry = state
            }
        }

        udpTelemetry.onTelemetry = { [weak self] state in
            Task { @MainActor in
                self?.telemetry = state
            }
        }

        udpTelemetry.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.telemetryStatus = status
            }
        }

        headTrackingSender.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.headTrackingSenderStatus = status
            }
        }

        motionService.onMotion = { [weak self] sample in
            Task { @MainActor in
                self?.rawYawDeg = sample.yawDeg
                self?.rawPitchDeg = sample.pitchDeg
                self?.rawRollDeg = sample.rollDeg
                self?.updateMotionState(sampleTimestamp: sample.timestamp)
            }
        }
    }

    private func updateMotionState(sampleTimestamp: Date? = nil) {
        let timestamp = sampleTimestamp ?? motion.timestamp
        let centeredYaw = normalizedAngle(rawYawDeg - centerYawDeg)
        let centeredPitch = rawPitchDeg - centerPitchDeg
        let centeredRoll = rawRollDeg - centerRollDeg

        motion = MotionState(
            timestamp: timestamp,
            rawYawDeg: rawYawDeg,
            rawPitchDeg: rawPitchDeg,
            rawRollDeg: rawRollDeg,
            yawDeg: centeredYaw,
            pitchDeg: centeredPitch,
            rollDeg: centeredRoll,
            trackingEnabled: settings.trackingEnabled,
            status: headTrackingStatus(for: timestamp),
            calibratedCenterYaw: centerYawDeg,
            calibratedCenterPitch: centerPitchDeg,
            calibratedCenterRoll: centerRollDeg
        )
    }

    private func sendHeadTrackingIfNeeded() {
        guard settings.trackingEnabled, motion.status == .active else {
            headTrackingSender.refreshStatus()
            return
        }
        headTrackingSender.send(
            yawDeg: motion.yawDeg,
            pitchDeg: motion.pitchDeg,
            rollDeg: motion.rollDeg,
            trackingEnabled: settings.trackingEnabled,
            centered: hasCenteredTracking,
            timeoutMs: UInt16(clamping: settings.headTrackingTimeoutMs)
        )
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        var value = angle
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }

    private func startMotionStatusTimer() {
        motionStatusTimer?.invalidate()
        motionStatusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMotionState()
            }
        }
    }

    private func startHeadTrackingSendTimer() {
        headTrackingSendTimer?.invalidate()
        let clampedRate = min(max(settings.headTrackingSendHz, 30), 60)
        headTrackingSendTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(clampedRate), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeadTrackingIfNeeded()
            }
        }
    }

    private func headTrackingStatus(for timestamp: Date) -> HeadTrackingStatus {
        let age = Date().timeIntervalSince(timestamp)

        if timestamp == .distantPast || age > 2.0 {
            return settings.trackingEnabled ? .lost : .off
        }

        if age > 0.5 {
            return .stale
        }

        return settings.trackingEnabled ? .active : .ready
    }
}
