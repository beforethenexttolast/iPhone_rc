import Foundation

protocol MotionService: AnyObject {
    var onMotion: ((RawMotionSample) -> Void)? { get set }
    func start(updateRateHz: Double)
    func stop()
}

struct MockMotionControlState: Equatable {
    var isAvailable: Bool
    var yawDeg: Double
    var pitchDeg: Double
    var rollDeg: Double

    static let unavailable = MockMotionControlState(
        isAvailable: false,
        yawDeg: 0,
        pitchDeg: 0,
        rollDeg: 0
    )
}

protocol MockMotionControllable: AnyObject {
    var controlState: MockMotionControlState { get }
    var onControlStateChanged: ((MockMotionControlState) -> Void)? { get set }
    func setMockMotion(yawDeg: Double, pitchDeg: Double, rollDeg: Double)
    func resetMockMotion()
}

enum MotionServiceFactory {
    static func makeDefault() -> MotionService {
        #if targetEnvironment(simulator)
        return MockMotionService()
        #else
        return CoreMotionService()
        #endif
    }
}
