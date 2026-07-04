import Foundation

protocol MotionService: AnyObject {
    var onMotion: ((RawMotionSample) -> Void)? { get set }
    func start(updateRateHz: Double)
    func stop()
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
