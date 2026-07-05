import SwiftUI

struct FPVHUDView: View {
    var telemetry: TelemetryDisplayState
    var motion: MotionState
    var settings: AppSettings
    var headTrackingDisplay: HeadTrackingDisplayState
    var onOpenDebug: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            DriveHUDView(
                telemetry: telemetry,
                motion: motion,
                settings: settings,
                headTrackingDisplay: headTrackingDisplay,
                safeArea: proxy.safeAreaInsets,
                onOpenDebug: onOpenDebug
            )
        }
        .foregroundStyle(.white)
        .background(Color.black)
    }
}

struct DebugHUDView: View {
    @ObservedObject var viewModel: FPVHUDViewModel
    var onOpenSettings: () -> Void
    var onExit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding = debugHorizontalPadding(for: proxy)
            let contentWidth = max(proxy.size.width - (horizontalPadding * 2), 0)

            ZStack {
                VideoSurface()
                HUDVignette()

                VStack(alignment: .leading, spacing: 12) {
                    DebugHeaderView(
                        isDemo: viewModel.settings.demoModeEnabled,
                        onOpenSettings: onOpenSettings,
                        onExit: onExit
                    )
                    .padding(.top, max(proxy.safeAreaInsets.top + 10, 14))
                    .padding(.horizontal, horizontalPadding)

                    ScrollView {
                        LazyVGrid(columns: debugColumns(for: contentWidth), alignment: .leading, spacing: 12) {
                            DebugPanel(title: "Motion") {
                                DebugRow("State", viewModel.motion.status.displayName)
                                DebugRow("Raw yaw", HUDFormatters.signedDegrees(viewModel.motion.rawYawDeg))
                                DebugRow("Raw pitch", HUDFormatters.signedDegrees(viewModel.motion.rawPitchDeg))
                                DebugRow("Raw roll", HUDFormatters.signedDegrees(viewModel.motion.rawRollDeg))
                                DebugRow("Centered yaw", HUDFormatters.signedDegrees(viewModel.motion.yawDeg))
                                DebugRow("Centered pitch", HUDFormatters.signedDegrees(viewModel.motion.pitchDeg))
                                DebugRow("Centered roll", HUDFormatters.signedDegrees(viewModel.motion.rollDeg))
                                DebugRow("Center yaw", HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterYaw))
                                DebugRow("Center pitch", HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterPitch))
                                DebugRow("Center roll", HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterRoll))
                                DebugMotionActions(
                                    onCenter: {
                                        viewModel.centerTracking()
                                    },
                                    onReset: {
                                        viewModel.resetTrackingCalibration()
                                    }
                                )
                            }

                            DebugPanel(title: "Telemetry") {
                                DebugRow("Source", viewModel.telemetryDisplay.sourceText)
                                DebugRow("Link", viewModel.telemetryDisplay.linkText)
                                DebugRow("Age", lastPacketAgeText)
                                DebugRow("Malformed", "\(viewModel.telemetryStatus.malformedPacketCount)")
                                DebugRow("Battery", viewModel.telemetryDisplay.batteryText)
                                DebugRow("LQ", viewModel.telemetryDisplay.linkQualityText)
                                DebugRow("RSSI", viewModel.telemetryDisplay.rssiText)
                                DebugRow("SNR", viewModel.telemetryDisplay.snrText)
                                DebugRow("Speed", viewModel.telemetryDisplay.speedText)
                                if let warning = viewModel.telemetryDisplay.warningText ?? viewModel.telemetryStatus.warningText {
                                    DebugWarning(text: warning)
                                }
                            }

                            DebugPanel(title: "Head Sender") {
                                DebugRow("Configured", viewModel.headTrackingDisplay.udpConfiguredText)
                                DebugRow("Packet rate", viewModel.headTrackingDisplay.packetRateText)
                                DebugRow("Packets sent", viewModel.headTrackingDisplay.packetsSentText)
                                DebugRow("Last send", viewModel.headTrackingDisplay.lastSendText)
                                DebugRow("Tracking", viewModel.settings.trackingEnabled ? "Enabled" : "Disabled")
                                DebugRow("Send rate", "\(viewModel.settings.headTrackingSendHz) Hz")
                                DebugRow("Timeout", "\(viewModel.settings.headTrackingTimeoutMs) ms")
                                if let warning = viewModel.headTrackingDisplay.warningText {
                                    DebugWarning(text: warning)
                                }
                            }

                            DebugPanel(title: "Car Snapshot") {
                                DebugRow("Gear", viewModel.telemetryDisplay.gearText)
                                DebugRow("Drive mode", viewModel.telemetryDisplay.driveModeText)
                                DebugRow("ERS", viewModel.telemetryDisplay.ersText)
                                DebugRow("Throttle", "\(Int(viewModel.telemetryDisplay.throttle * 100))%")
                                DebugRow("Brake", "\(Int(viewModel.telemetryDisplay.brake * 100))%")
                                DebugRow("Steer", String(format: "%+.0f%%", viewModel.telemetryDisplay.steering * 100))
                                DebugRow("Pan/tilt", viewModel.telemetryDisplay.panTiltModeText)
                                DebugRow("Camera yaw", viewModel.telemetryDisplay.cameraYawText)
                                DebugRow("Camera pitch", viewModel.telemetryDisplay.cameraPitchText)
                                DebugRow("Video", viewModel.telemetryDisplay.videoText)
                            }

                            DebugPanel(title: "Network Settings") {
                                DebugRow("Windows host", viewModel.settings.windowsHost)
                                DebugRow("Telemetry UDP", "\(viewModel.settings.telemetryPort)")
                                DebugRow("Head UDP", "\(viewModel.settings.headTrackingPort)")
                                DebugRow("Motion rate", "\(viewModel.settings.motionUpdateHz) Hz")
                                DebugRow("Demo mode", viewModel.settings.demoModeEnabled ? "On" : "Off")
                                Button {
                                    onOpenSettings()
                                } label: {
                                    Label("Open Settings", systemImage: "gearshape")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 16, 24))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .foregroundStyle(.white)
            .ignoresSafeArea(edges: .all)
        }
    }

    private var lastPacketAgeText: String {
        guard !viewModel.settings.demoModeEnabled else { return "Demo" }
        guard let age = viewModel.telemetryStatus.lastPacketAge else { return "Waiting" }
        return String(format: "%.2fs", age)
    }

    private func debugHorizontalPadding(for proxy: GeometryProxy) -> CGFloat {
        max(max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing) + 12, 16)
    }

    private func debugColumns(for width: CGFloat) -> [GridItem] {
        if width < 620 {
            return [
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top)
            ]
        }

        return [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top)
        ]
    }
}

private struct DebugHeaderView: View {
    var isDemo: Bool
    var onOpenSettings: () -> Void
    var onExit: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                titlePills(compact: false)
                Spacer(minLength: 12)
                headerActions(compact: false)
            }

            HStack(spacing: 8) {
                titlePills(compact: true)
                Spacer(minLength: 8)
                headerActions(compact: true)
            }

            VStack(alignment: .leading, spacing: 9) {
                titlePills(compact: true)
                headerActions(compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func titlePills(compact: Bool) -> some View {
        HStack(spacing: 8) {
            StatusPill(text: "DEBUG / SETUP", tint: HUDPalette.tealBright, compact: compact)
            StatusPill(text: isDemo ? "DEMO" : "UDP", tint: isDemo ? HUDPalette.teal : HUDPalette.green, compact: compact)
        }
    }

    private func headerActions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            DebugHeaderButton(
                title: "Settings",
                systemImage: "slider.horizontal.3",
                compact: compact,
                prominent: true,
                action: onOpenSettings
            )
            DebugHeaderButton(
                title: "Drive",
                systemImage: "viewfinder",
                compact: compact,
                prominent: false,
                action: onExit
            )
        }
    }
}

private struct DebugHeaderButton: View {
    var title: String
    var systemImage: String
    var compact: Bool
    var prominent: Bool
    var action: () -> Void

    var body: some View {
        if prominent {
            buttonLabel
                .buttonStyle(.borderedProminent)
                .controlSize(compact ? .small : .regular)
                .accessibilityLabel(title)
        } else {
            buttonLabel
                .buttonStyle(.bordered)
                .controlSize(compact ? .small : .regular)
                .accessibilityLabel(title)
        }
    }

    private var buttonLabel: some View {
        Button(action: action) {
            if compact {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 32)
            } else {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

private struct DebugMotionActions: View {
    var onCenter: () -> Void
    var onReset: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                centerButton
                resetButton
            }

            VStack(alignment: .leading, spacing: 8) {
                centerButton
                resetButton
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var centerButton: some View {
        Button(action: onCenter) {
            Label("Center", systemImage: "scope")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var resetButton: some View {
        Button(role: .destructive, action: onReset) {
            Label("Reset", systemImage: "xmark.circle")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct DriveHUDView: View {
    var telemetry: TelemetryDisplayState
    var motion: MotionState
    var settings: AppSettings
    var headTrackingDisplay: HeadTrackingDisplayState
    var safeArea: EdgeInsets
    var onOpenDebug: (() -> Void)?

    var body: some View {
        ZStack {
            VideoSurface()
            DriveVignette()

            VStack(spacing: 0) {
                TopTelemetryStrip(telemetry: telemetry, onOpenDebug: onOpenDebug)
                    .padding(.top, max(safeArea.top + 12, 16))
                    .padding(.horizontal, horizontalInset)

                Spacer()

                HStack(alignment: .bottom) {
                    SpeedWidget(telemetry: telemetry)
                    Spacer(minLength: 24)
                    ControlWidget(telemetry: telemetry)
                }
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, max(safeArea.bottom + 14, 18))
            }

            VStack(alignment: .trailing, spacing: 8) {
                HeadTrackingStatusChip(motion: motion)
                if settings.trackingEnabled, let error = headTrackingDisplay.warningText {
                    CompactWarningChip(text: "HEAD TX \(error)", tint: HUDPalette.amber)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.top, max(safeArea.top + 62, 72))
            .padding(.trailing, horizontalInset)

            if let warning = warningText {
                WarningBanner(text: warning, linkState: telemetry.linkState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, max(safeArea.top + 58, 70))
                    .padding(.horizontal, horizontalInset)
            }
        }
        .ignoresSafeArea(edges: .all)
    }

    private var horizontalInset: CGFloat {
        max(max(safeArea.leading, safeArea.trailing) + 14, 18)
    }

    private var warningText: String? {
        if let warning = telemetry.warningText, !warning.isEmpty, warning != "VIDEO PLACEHOLDER" {
            return warning
        }

        guard !telemetry.staleDataWarnings.isEmpty else { return nil }
        return telemetry.staleDataWarnings.map(\.displayName).joined(separator: " / ")
    }
}

private struct DriveVignette: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.46), location: 0),
                    .init(color: .black.opacity(0.14), location: 0.18),
                    .init(color: .clear, location: 0.46),
                    .init(color: .black.opacity(0.48), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.34), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: 140)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.34)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: 140)
            }
        }
        .ignoresSafeArea()
    }
}

private struct HUDVignette: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.68), location: 0),
                    .init(color: .black.opacity(0.14), location: 0.22),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.66), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.56), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: 160)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.58)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: 170)
            }
        }
        .ignoresSafeArea()
    }
}

private struct TopTelemetryStrip: View {
    var telemetry: TelemetryDisplayState
    var onOpenDebug: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                ARStatusChip(text: telemetry.linkText, tint: linkColor)
                ARMetric(title: "BAT", value: telemetry.batteryText, tint: batteryColor)
                ARMetric(title: "LQ", value: telemetry.linkQualityText, tint: linkQualityColor)
                ARMetric(title: "RSSI", value: telemetry.rssiText, tint: valueColor)
                ARMetric(title: "SNR", value: telemetry.snrText, tint: valueColor)
                Spacer(minLength: 8)
                TopRightVideoControls(
                    videoText: telemetry.videoText,
                    videoLock: telemetry.videoLock,
                    onOpenDebug: onOpenDebug
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.18))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, HUDPalette.tealBright.opacity(0.7), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }

            HStack(spacing: 0) {
                ARCornerLine()
                Spacer()
                ARCornerLine()
                    .scaleEffect(x: -1, y: 1)
            }
            .frame(height: 8)
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
        guard telemetry.showsLiveValues, let voltage = telemetry.rawTelemetry?.batteryVoltage else {
            return HUDPalette.muted
        }

        return voltage < 7.2 ? HUDPalette.red : .white
    }

    private var linkQualityColor: Color {
        guard telemetry.showsLiveValues, let linkQuality = telemetry.rawTelemetry?.linkQualityPercent else {
            return HUDPalette.muted
        }

        if linkQuality < 45 { return HUDPalette.red }
        if linkQuality < 70 { return HUDPalette.amber }
        return HUDPalette.green
    }

    private var valueColor: Color {
        telemetry.showsLiveValues ? .white : HUDPalette.muted
    }
}

private struct SpeedWidget: View {
    var telemetry: TelemetryDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SPEED")
                .hudLabel()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(telemetry.speedValueText)
                    .font(.system(size: 84, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.95), radius: 6)
                    .shadow(color: HUDPalette.tealBright.opacity(0.22), radius: 10)
                Text("KM/H")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.76))
                    .shadow(color: .black.opacity(0.8), radius: 4)
            }

            HStack(spacing: 7) {
                ARStatusChip(text: telemetry.gearText, tint: telemetry.showsLiveValues ? HUDPalette.tealBright : HUDPalette.muted)
                ARStatusChip(text: telemetry.driveModeText, tint: telemetry.showsLiveValues ? HUDPalette.teal : HUDPalette.muted)
                ARStatusChip(text: "ERS \(telemetry.ersText)", tint: ersColor)
                if telemetry.sourceText != "--" {
                    ARStatusChip(text: telemetry.sourceText, tint: HUDPalette.tealBright)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .padding(.top, 8)
        .padding(.trailing, 10)
        .padding(.bottom, 10)
        .frame(width: 292, alignment: .leading)
        .overlay(AROpenCorners(length: 24, edges: [.topLeading, .bottomLeading]))
    }

    private var ersColor: Color {
        guard telemetry.showsLiveValues, let ersPercent = telemetry.rawTelemetry?.ersPercent else {
            return HUDPalette.muted
        }

        return ersPercent < 20 ? HUDPalette.amber : HUDPalette.teal
    }
}

private struct ControlWidget: View {
    var telemetry: TelemetryDisplayState

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 8) {
                Text("INPUT")
                    .hudLabel()
                Text(telemetry.panTiltModeText)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(panTiltColor)
                    .shadow(color: .black.opacity(0.8), radius: 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                AREdgeMeter(title: "THR", value: telemetry.throttle, tint: HUDPalette.green)
                AREdgeMeter(title: "BRK", value: telemetry.brake, tint: HUDPalette.red)
                AREdgeSteering(value: telemetry.steering)
            }
        }
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(HUDPalette.tealBright.opacity(0.7))
                .frame(width: 1)
        }
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
}

private struct HeadTrackingStatusChip: View {
    var motion: MotionState

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.5), radius: 4)

            Text(motion.status.driveDisplayName)
                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                .tracking(0.35)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .foregroundStyle(tint)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.black.opacity(0.26))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.5), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
        .shadow(color: .black.opacity(0.55), radius: 10)
    }

    private var tint: Color {
        switch motion.status {
        case .off: return .gray
        case .readyNotCentered: return HUDPalette.amber
        case .active: return HUDPalette.green
        case .stale: return HUDPalette.amber
        case .error: return HUDPalette.red
        }
    }
}

private struct WarningBanner: View {
    var text: String
    var linkState: LinkState

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .monospaced))
            .tracking(2)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.black.opacity(0.42))
            .foregroundStyle(warningColor)
            .overlay(
                Capsule()
                    .stroke(warningColor.opacity(0.78), lineWidth: 1)
            )
            .clipShape(Capsule())
            .shadow(color: warningColor.opacity(0.26), radius: 10)
    }

    private var warningColor: Color {
        switch linkState {
        case .disconnected, .degraded: return HUDPalette.red
        case .demo, .connecting, .connected: return HUDPalette.amber
        }
    }
}

private struct CompactWarningChip: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.34))
            .foregroundStyle(tint)
            .overlay(Capsule().stroke(tint.opacity(0.62), lineWidth: 1))
            .clipShape(Capsule())
    }
}

private struct CompactMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .hudLabel()
            Text(value)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

private struct ARFrame<Content: View>: View {
    var cornerLength: CGFloat
    private let content: Content

    init(cornerLength: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerLength = cornerLength
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(0.16))
                    .blur(radius: 0.2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .overlay(ARFrameCorners(length: cornerLength))
            .shadow(color: .black.opacity(0.55), radius: 10)
    }
}

private struct ARFrameCorners: View {
    var length: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let l = min(length, min(w, h) * 0.35)

                var path = Path()
                path.move(to: CGPoint(x: 0, y: l))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: l, y: 0))

                path.move(to: CGPoint(x: w - l, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: l))

                path.move(to: CGPoint(x: w, y: h - l))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w - l, y: h))

                path.move(to: CGPoint(x: l, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h - l))

                context.stroke(path, with: .color(HUDPalette.tealBright.opacity(0.72)), lineWidth: 1.2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

private enum ARCorner {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

private struct AROpenCorners: View {
    var length: CGFloat
    var edges: [ARCorner]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let l = min(length, min(w, h) * 0.45)

                var path = Path()
                if edges.contains(.topLeading) {
                    path.move(to: CGPoint(x: 0, y: l))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: l, y: 0))
                }
                if edges.contains(.topTrailing) {
                    path.move(to: CGPoint(x: w - l, y: 0))
                    path.addLine(to: CGPoint(x: w, y: 0))
                    path.addLine(to: CGPoint(x: w, y: l))
                }
                if edges.contains(.bottomTrailing) {
                    path.move(to: CGPoint(x: w, y: h - l))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: w - l, y: h))
                }
                if edges.contains(.bottomLeading) {
                    path.move(to: CGPoint(x: l, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h - l))
                }

                context.stroke(path, with: .color(HUDPalette.tealBright.opacity(0.76)), lineWidth: 1.1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct ARCornerLine: View {
    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 8))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 38, y: 0))
            context.stroke(path, with: .color(HUDPalette.tealBright.opacity(0.7)), lineWidth: 1)
        }
        .frame(width: 38, height: 8)
    }
}

private struct ARStatusChip: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(1.1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(.black.opacity(0.28))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.56), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct TopRightVideoControls: View {
    var videoText: String
    var videoLock: Bool
    var onOpenDebug: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ARStatusChip(
                text: videoText,
                tint: videoLock ? HUDPalette.green : HUDPalette.amber
            )
            .frame(height: 26)

            if let onOpenDebug {
                DriveDebugButton(action: onOpenDebug)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct DriveDebugButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .black))
                .frame(width: 30, height: 26)
                .foregroundStyle(.white.opacity(0.92))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Debug setup")
    }
}

private struct ARMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .hudLabel()
            Text(value)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.82), radius: 3)
        }
    }
}

private struct ARMeterBar: View {
    var title: String
    var value: Double
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .hudLabel()
                .frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                let clamped = min(max(value, 0), 1)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(height: 1)
                    Rectangle()
                        .fill(tint)
                        .frame(width: max(3, proxy.size.width * clamped), height: 3)
                        .shadow(color: tint.opacity(0.8), radius: 5)
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .position(x: max(3, proxy.size.width * clamped), y: proxy.size.height / 2)
                }
            }
            .frame(height: 12)
        }
    }
}

private struct ARSteeringBar: View {
    var value: Double

    var body: some View {
        HStack(spacing: 9) {
            Text("STR")
                .hudLabel()
                .frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                let clamped = min(max(value, -1), 1)
                let x = proxy.size.width * CGFloat((clamped + 1) / 2)

                ZStack {
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(height: 1)
                    Rectangle()
                        .fill(.white.opacity(0.4))
                        .frame(width: 1, height: 10)
                    Capsule()
                        .fill(HUDPalette.tealBright)
                        .frame(width: 18, height: 5)
                        .position(x: x, y: proxy.size.height / 2)
                        .shadow(color: HUDPalette.tealBright.opacity(0.8), radius: 5)
                }
            }
            .frame(height: 14)
        }
    }
}

private struct AREdgeMeter: View {
    var title: String
    var value: Double
    var tint: Color

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let clamped = min(max(value, 0), 1)

                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 1)
                    Rectangle()
                        .fill(tint)
                        .frame(width: 3, height: max(3, proxy.size.height * clamped))
                        .shadow(color: tint.opacity(0.74), radius: 5)
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * CGFloat(1 - clamped))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 18, height: 54)

            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
        }
    }
}

private struct AREdgeSteering: View {
    var value: Double

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let clamped = min(max(value, -1), 1)
                let y = proxy.size.height * CGFloat((1 - clamped) / 2)

                ZStack {
                    Rectangle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 1)
                    Rectangle()
                        .fill(.white.opacity(0.34))
                        .frame(width: 12, height: 1)
                    Capsule()
                        .fill(HUDPalette.tealBright)
                        .frame(width: 14, height: 5)
                        .position(x: proxy.size.width / 2, y: y)
                        .shadow(color: HUDPalette.tealBright.opacity(0.8), radius: 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 22, height: 54)

            Text("STR")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
        }
    }
}

private struct DebugPanel<Content: View>: View {
    var title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HUDPanel(prominence: .strong) {
            VStack(alignment: .leading, spacing: 9) {
                Text(title.uppercased())
                    .hudLabel()
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DebugRow: View {
    var title: String
    var value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                titleText
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 3) {
                titleText
                valueText
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleText: some View {
        Text(title)
            .hudLabel()
    }

    private var valueText: some View {
        Text(value)
            .font(.system(size: 14, weight: .black, design: .monospaced))
            .monospacedDigit()
            .lineLimit(2)
            .minimumScaleFactor(0.72)
    }
}

private struct DebugWarning: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .monospaced))
            .lineLimit(3)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HUDPalette.amber.opacity(0.9))
            .foregroundStyle(.black)
            .clipShape(ChamferedRectangle(cut: 6))
    }
}
