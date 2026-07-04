#if os(iOS)
import CoreMotion
import Foundation

final class CoreMotionService: MotionService {
    var onMotion: ((RawMotionSample) -> Void)?

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    func start(updateRateHz: Double) {
        stop()
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / min(max(updateRateHz, 15), 120)
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] motion, _ in
            guard let motion else { return }
            let attitude = motion.attitude
            self?.onMotion?(
                RawMotionSample(
                    timestamp: Date(),
                    yawDeg: attitude.yaw.radiansToDegrees,
                    pitchDeg: attitude.pitch.radiansToDegrees,
                    rollDeg: attitude.roll.radiansToDegrees
                )
            )
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
#else
import Foundation

final class CoreMotionService: MotionService {
    var onMotion: ((RawMotionSample) -> Void)?

    func start(updateRateHz: Double) {}
    func stop() {}
}
#endif
