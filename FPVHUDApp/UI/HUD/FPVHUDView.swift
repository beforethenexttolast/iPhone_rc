import SwiftUI

struct FPVHUDView: View {
    var telemetry: TelemetryState
    var motion: MotionState
    var settings: AppSettings
    var headTrackingSenderStatus: HeadTrackingSenderStatus

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width >= proxy.size.height
            let sideWidth = min(max(proxy.size.width * 0.24, 210), 292)
            let horizontalInset: CGFloat = landscape ? 18 : 12
            let topInset: CGFloat = landscape ? 14 : 18

            ZStack {
                VideoSurface()
                HUDVignette()

                VStack(spacing: 0) {
                    TopTelemetryStrip(telemetry: telemetry, settings: settings)
                        .padding(.top, topInset)
                        .padding(.horizontal, horizontalInset)

                    Spacer(minLength: landscape ? 28 : 18)

                    HStack(alignment: .center, spacing: 16) {
                        Spacer(minLength: landscape ? sideWidth * 0.35 : 0)
                        CenterReticleBlock(telemetry: telemetry)
                        Spacer(minLength: landscape ? sideWidth : 0)
                    }
                    .padding(.horizontal, horizontalInset)

                    Spacer(minLength: landscape ? 22 : 14)

                    BottomControlCluster(telemetry: telemetry)
                        .padding(.horizontal, horizontalInset)
                        .padding(.bottom, landscape ? 16 : 12)
                }

                RightTrackingCluster(telemetry: telemetry, motion: motion)
                    .frame(width: sideWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, horizontalInset)
                    .padding(.top, landscape ? 96 : 112)
                    .padding(.bottom, landscape ? 126 : 170)

                if let warning = warningText(for: telemetry) {
                    WarningBanner(text: warning, linkState: telemetry.linkState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, landscape ? 78 : 92)
                        .padding(.horizontal, horizontalInset)
                }

                if settings.trackingEnabled, let error = headTrackingSenderStatus.lastErrorText {
                    WarningBanner(text: "HEAD TX: \(error)", linkState: .degraded)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, landscape ? 124 : 138)
                        .padding(.trailing, horizontalInset)
                }
            }
            .foregroundStyle(.white)
            .ignoresSafeArea()
        }
    }

    private func warningText(for telemetry: TelemetryState) -> String? {
        if let warning = telemetry.warningText, !warning.isEmpty {
            return warning
        }

        guard !telemetry.staleDataWarnings.isEmpty else { return nil }
        return telemetry.staleDataWarnings.map(\.displayName).joined(separator: " / ")
    }
}

private struct HUDVignette: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.78), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.22),
                    .init(color: .clear, location: 0.48),
                    .init(color: .black.opacity(0.7), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.72), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: 220)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: 260)
            }
        }
        .ignoresSafeArea()
    }
}

private struct TopTelemetryStrip: View {
    var telemetry: TelemetryState
    var settings: AppSettings

    var body: some View {
        HUDPanel(prominence: .strong) {
            HStack(spacing: 14) {
                StatusPill(text: telemetry.linkState.displayName, tint: linkColor)

                Divider()
                    .frame(height: 30)
                    .overlay(HUDPalette.edge)

                StatusMetric(title: "BATTERY", value: HUDFormatters.volts(telemetry.batteryVoltage), tint: batteryColor)
                StatusMetric(title: "LQ", value: "\(telemetry.linkQualityPercent)%", tint: linkQualityColor)
                StatusMetric(title: "RSSI", value: "\(telemetry.rssiDbm) dBm")
                StatusMetric(title: "SNR", value: HUDFormatters.db(telemetry.snrDb))

                Spacer(minLength: 10)

                StatusPill(
                    text: telemetry.videoLock ? "VIDEO LOCK" : "NO VIDEO",
                    tint: telemetry.videoLock ? HUDPalette.green : HUDPalette.amber
                )
                RecordingIndicator()
                StatusMetric(title: "HEAD", value: settings.trackingEnabled ? "TX ON" : "TX OFF", tint: settings.trackingEnabled ? HUDPalette.green : HUDPalette.muted)
                StatusMetric(title: "DRIVE", value: telemetry.driveMode.displayName, tint: telemetry.driveMode == .gearboxERS ? HUDPalette.tealBright : .white)
                StatusMetric(title: "SRC", value: telemetry.mode.rawValue.uppercased(), tint: telemetry.mode == .demo ? HUDPalette.tealBright : .white)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var linkColor: Color {
        switch telemetry.linkState {
        case .connected: return HUDPalette.green
        case .degraded: return HUDPalette.amber
        case .demo: return HUDPalette.tealBright
        case .connecting: return .yellow
        case .disconnected: return HUDPalette.red
        }
    }

    private var batteryColor: Color {
        telemetry.batteryVoltage < 7.2 ? HUDPalette.red : .white
    }

    private var linkQualityColor: Color {
        if telemetry.linkQualityPercent < 45 { return HUDPalette.red }
        if telemetry.linkQualityPercent < 70 { return HUDPalette.amber }
        return HUDPalette.green
    }
}

private struct CenterReticleBlock: View {
    var telemetry: TelemetryState

    var body: some View {
        ZStack {
            CrosshairView()
                .frame(width: 154, height: 154)

            VStack {
                StatusPill(
                    text: telemetry.videoLock ? "LIVE FPV" : "VIDEO PLACEHOLDER",
                    tint: telemetry.videoLock ? HUDPalette.green : HUDPalette.teal,
                    compact: true
                )
                Spacer()
            }
            .frame(width: 210, height: 176)
        }
    }
}

private struct BottomControlCluster: View {
    var telemetry: TelemetryState

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HUDPanel(prominence: .strong) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(telemetry.speedKmh.rounded()))")
                            .font(.system(size: 82, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.56)
                            .lineLimit(1)
                        Text("KM/H")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(HUDPalette.muted)
                    }
                    HStack(spacing: 8) {
                        StatusPill(text: "THIN CLIENT", tint: HUDPalette.teal, compact: true)
                        StatusPill(text: "WINDOWS AUTH", tint: HUDPalette.amber, compact: true)
                    }
                }
                .frame(width: 230, alignment: .leading)
            }

            HUDPanel {
                VStack(spacing: 10) {
                    MeterBar(title: "THR", value: telemetry.throttle, tint: HUDPalette.green)
                    MeterBar(title: "BRK", value: telemetry.brake, tint: HUDPalette.red)
                    SteeringBar(value: telemetry.steering)
                }
                .frame(width: 300)
            }

            HUDPanel {
                HStack(alignment: .bottom, spacing: 16) {
                    VerticalSignalBar(title: "THR", value: telemetry.throttle, tint: HUDPalette.green)
                    VerticalSignalBar(title: "BRK", value: telemetry.brake, tint: HUDPalette.red)
                    VStack(alignment: .leading, spacing: 8) {
                        StatusMetric(title: "GEAR", value: "\(telemetry.gear)", tint: HUDPalette.tealBright)
                        StatusMetric(title: "ERS", value: "\(telemetry.ersPercent)%", tint: ersColor)
                        StatusMetric(title: "STEER", value: String(format: "%+.0f%%", telemetry.steering * 100), tint: HUDPalette.tealBright)
                        StatusMetric(title: "DRIVE", value: telemetry.driveMode.displayName)
                    }
                }
                .frame(width: 232, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var ersColor: Color {
        telemetry.ersPercent < 20 ? HUDPalette.amber : HUDPalette.tealBright
    }
}

private struct RightTrackingCluster: View {
    var telemetry: TelemetryState
    var motion: MotionState

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HUDPanel(prominence: .strong) {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        Text("PAN / TILT")
                            .hudLabel()
                        Spacer()
                        StatusPill(text: telemetry.panTiltMode.displayName, tint: panTiltColor, compact: true)
                    }
                    AngleRow(title: "YAW", value: telemetry.cameraYawDeg, tint: HUDPalette.tealBright)
                    AngleRow(title: "PITCH", value: telemetry.cameraPitchDeg, tint: .white)
                    StatusMetric(title: "VIDEO", value: telemetry.videoLock ? "LOCK" : "STUB", alignment: .trailing, tint: telemetry.videoLock ? HUDPalette.green : HUDPalette.amber)
                }
            }

            HUDPanel(prominence: .strong) {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        Text("HEAD INPUT")
                            .hudLabel()
                        Spacer()
                        StatusPill(text: motion.status.displayName, tint: headTrackingColor, compact: true)
                    }
                    AngleRow(title: "YAW", value: motion.yawDeg, tint: HUDPalette.tealBright)
                    AngleRow(title: "PITCH", value: motion.pitchDeg, tint: .white)
                    AngleRow(title: "ROLL", value: motion.rollDeg, tint: .white)
                    Text("TO WINDOWS ONLY")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(HUDPalette.amber)
                }
            }

            HUDPanel {
                VStack(alignment: .trailing, spacing: 7) {
                    Text("PACKET STATE")
                        .hudLabel()
                    StatusMetric(title: "LAST TEL", value: shortTime(telemetry.timestamp), alignment: .trailing)
                    StatusMetric(title: "LAST MOT", value: shortTime(motion.timestamp), alignment: .trailing)
                    StatusMetric(title: "STALE", value: telemetry.staleDataWarnings.isEmpty ? "NONE" : "\(telemetry.staleDataWarnings.count)", alignment: .trailing, tint: telemetry.staleDataWarnings.isEmpty ? HUDPalette.green : HUDPalette.amber)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Spacer(minLength: 0)
        }
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SS"
        return formatter.string(from: date)
    }

    private var panTiltColor: Color {
        switch telemetry.panTiltMode {
        case .dualShock: return HUDPalette.teal
        case .headTracking: return HUDPalette.green
        case .mixed: return HUDPalette.tealBright
        case .disabled: return .gray
        case .unknown: return HUDPalette.amber
        }
    }

    private var headTrackingColor: Color {
        switch motion.status {
        case .off: return .gray
        case .ready: return HUDPalette.teal
        case .active: return HUDPalette.green
        case .stale: return HUDPalette.amber
        case .lost: return HUDPalette.red
        }
    }
}

private struct AngleRow: View {
    var title: String
    var value: Double
    var tint: Color

    var body: some View {
        HStack {
            Text(title)
                .hudLabel()
            Spacer()
            Text(HUDFormatters.signedDegrees(value))
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
    }
}

private struct WarningBanner: View {
    var text: String
    var linkState: LinkState

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .monospaced))
            .tracking(3)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background((linkState == .demo ? HUDPalette.tealBright : HUDPalette.amber).opacity(0.92))
            .foregroundStyle(.black)
            .clipShape(ChamferedRectangle(cut: 8))
            .shadow(color: .black.opacity(0.5), radius: 14)
    }
}
