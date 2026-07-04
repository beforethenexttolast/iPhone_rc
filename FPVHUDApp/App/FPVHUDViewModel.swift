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
    private let settingsStore: SettingsStore

    private var rawYawDeg: Double = 0
    private var rawPitchDeg: Double = 0
    private var rawRollDeg: Double = 0
    private var centerYawDeg: Double = 0
    private var centerPitchDeg: Double = 0
    private var centerRollDeg: Double = 0
    private var motionStatusTimer: DispatchSourceTimer?
    private var headTrackingSendTimer: DispatchSourceTimer?
    private let motionStatusQueue = DispatchQueue(label: "fpvhud.motion.status.timer")
    private let headTrackingSendQueue = DispatchQueue(label: "fpvhud.headtracking.send.timer")
    private var hasCenteredTracking = false

    init(
        motionService: MotionService = MotionServiceFactory.makeDefault(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.motionService = motionService
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        bindServices()
        applySettings()
    }

    func applySettings() {
        settingsStore.save(settings)
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

    func resetSettingsToDefaults() {
        settings = settingsStore.reset()
        resetTrackingCalibration()
        applySettings()
    }

    func centerTracking() {
        centerYawDeg = rawYawDeg
        centerPitchDeg = rawPitchDeg
        centerRollDeg = rawRollDeg
        hasCenteredTracking = true
        updateMotionState()
    }

    func resetTrackingCalibration() {
        centerYawDeg = 0
        centerPitchDeg = 0
        centerRollDeg = 0
        hasCenteredTracking = false
        updateMotionState()
    }

    func stopNetworking() {
        demoTelemetry.stop()
        udpTelemetry.stop()
        headTrackingSender.stop()
        motionStatusTimer?.cancel()
        motionStatusTimer = nil
        headTrackingSendTimer?.cancel()
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
        guard settings.trackingEnabled, HeadTrackingSafety.canSend(status: motion.status) else {
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
        motionStatusTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: motionStatusQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.updateMotionState()
            }
        }
        timer.resume()
        motionStatusTimer = timer
    }

    private func startHeadTrackingSendTimer() {
        headTrackingSendTimer?.cancel()
        let intervalMs = HeadTrackingTiming.sendIntervalMilliseconds(forRateHz: settings.headTrackingSendHz)
        let timer = DispatchSource.makeTimerSource(queue: headTrackingSendQueue)
        timer.schedule(deadline: .now() + .milliseconds(intervalMs), repeating: .milliseconds(intervalMs), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.sendHeadTrackingIfNeeded()
            }
        }
        timer.resume()
        headTrackingSendTimer = timer
    }

    private func headTrackingStatus(for timestamp: Date) -> HeadTrackingStatus {
        HeadTrackingSafety.status(
            trackingEnabled: settings.trackingEnabled,
            hasCentered: hasCenteredTracking,
            sampleTimestamp: timestamp
        )
    }
}
