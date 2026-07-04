import Foundation

final class MockMotionService: MotionService {
    var onMotion: ((RawMotionSample) -> Void)?

    private var timer: Timer?
    private let startDate = Date()

    func start(updateRateHz: Double) {
        stop()
        let interval = 1.0 / min(max(updateRateHz, 15), 120)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.emit()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func emit() {
        let t = Date().timeIntervalSince(startDate)
        onMotion?(
            RawMotionSample(
                timestamp: Date(),
                yawDeg: sin(t * 0.45) * 32,
                pitchDeg: sin(t * 0.62 + 0.5) * 11,
                rollDeg: sin(t * 0.78 + 1.7) * 8
            )
        )
    }
}
