import Foundation

final class MockMotionService: MotionService, MockMotionControllable {
    var onMotion: ((RawMotionSample) -> Void)?
    var onControlStateChanged: ((MockMotionControlState) -> Void)?

    private var timer: Timer?
    private var yawDeg: Double = 0
    private var pitchDeg: Double = 0
    private var rollDeg: Double = 0

    var controlState: MockMotionControlState {
        MockMotionControlState(
            isAvailable: true,
            yawDeg: yawDeg,
            pitchDeg: pitchDeg,
            rollDeg: rollDeg
        )
    }

    func start(updateRateHz: Double) {
        stop()
        let interval = 1.0 / min(max(updateRateHz, 15), 120)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.emit()
        }
        emit()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setMockMotion(yawDeg: Double, pitchDeg: Double, rollDeg: Double) {
        self.yawDeg = normalizedAngle(yawDeg)
        self.pitchDeg = min(max(pitchDeg, -90), 90)
        self.rollDeg = min(max(rollDeg, -90), 90)
        onControlStateChanged?(controlState)
        emit()
    }

    func resetMockMotion() {
        setMockMotion(yawDeg: 0, pitchDeg: 0, rollDeg: 0)
    }

    private func emit() {
        onMotion?(
            RawMotionSample(
                timestamp: Date(),
                yawDeg: yawDeg,
                pitchDeg: pitchDeg,
                rollDeg: rollDeg
            )
        )
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        var value = angle
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}
