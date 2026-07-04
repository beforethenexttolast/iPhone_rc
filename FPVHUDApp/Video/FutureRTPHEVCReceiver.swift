import Foundation

// TODO: Replace this marker with the native APFPV RTP/H.265 receiver milestone.
// Planned shape: APFPV RTP/UDP H.265 -> iPhone UDP receiver -> RTP/H.265 depacketizer
// -> VideoToolbox decode -> video surface -> SwiftUI/UIKit HUD overlay.
// Keep this path independent from Windows telemetry forwarding and head-tracking intent output.
enum FutureRTPHEVCReceiver {
    static let plannedDefaultPort = 5600
}
