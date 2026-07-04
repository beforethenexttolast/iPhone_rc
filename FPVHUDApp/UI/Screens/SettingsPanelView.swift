import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var viewModel: FPVHUDViewModel
    @Environment(\.dismiss) private var dismiss

    private let portRange = 1...65535

    var body: some View {
        NavigationStack {
            Form {
                Section("Windows ground station") {
                    TextField("Host IP", text: $viewModel.settings.windowsHost)
                        .fpvHostTextInput()

                    Stepper(
                        "Telemetry UDP: \(viewModel.settings.telemetryPort)",
                        value: $viewModel.settings.telemetryPort,
                        in: portRange
                    )

                    Stepper(
                        "Head tracking UDP: \(viewModel.settings.headTrackingPort)",
                        value: $viewModel.settings.headTrackingPort,
                        in: portRange
                    )
                }

                Section("Modes") {
                    Toggle("Demo telemetry", isOn: $viewModel.settings.demoModeEnabled)
                    Toggle("Head tracking input to Windows", isOn: $viewModel.settings.trackingEnabled)
                    Stepper(
                        "Motion rate: \(viewModel.settings.motionUpdateHz) Hz",
                        value: $viewModel.settings.motionUpdateHz,
                        in: 15...120,
                        step: 5
                    )
                    Stepper(
                        "Head send rate: \(viewModel.settings.headTrackingSendHz) Hz",
                        value: $viewModel.settings.headTrackingSendHz,
                        in: 30...60,
                        step: 5
                    )
                    Stepper(
                        "Head timeout: \(viewModel.settings.headTrackingTimeoutMs) ms",
                        value: $viewModel.settings.headTrackingTimeoutMs,
                        in: 100...1000,
                        step: 50
                    )

                    Button(role: .destructive) {
                        viewModel.resetSettingsToDefaults()
                    } label: {
                        Label("Reset settings to defaults", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("Telemetry receiver") {
                    HStack {
                        Text("UDP listener")
                        Spacer()
                        Text(receiverStateText)
                            .foregroundStyle(viewModel.telemetryStatus.isListening ? .green : .secondary)
                    }

                    HStack {
                        Text("Last packet age")
                        Spacer()
                        Text(lastPacketAgeText)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Malformed packets")
                        Spacer()
                        Text("\(viewModel.telemetryStatus.malformedPacketCount)")
                            .monospacedDigit()
                    }

                    if let warning = viewModel.telemetryStatus.warningText {
                        Text(warning)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Tracking") {
                    Button {
                        viewModel.centerTracking()
                    } label: {
                        Label("Center / calibrate", systemImage: "scope")
                    }

                    Button(role: .destructive) {
                        viewModel.resetTrackingCalibration()
                    } label: {
                        Label("Reset calibration", systemImage: "xmark.circle")
                    }

                    HStack {
                        Text("State")
                        Spacer()
                        Text(viewModel.motion.status.displayName)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("UDP configured")
                        Spacer()
                        Text(viewModel.headTrackingSenderStatus.isConfigured ? "Yes" : "No")
                            .foregroundStyle(viewModel.headTrackingSenderStatus.isConfigured ? .green : .secondary)
                    }

                    HStack {
                        Text("Packet rate")
                        Spacer()
                        Text(String(format: "%.0f Hz", viewModel.headTrackingSenderStatus.packetRateHz))
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Packets sent")
                        Spacer()
                        Text("\(viewModel.headTrackingSenderStatus.packetsSent)")
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Last send")
                        Spacer()
                        Text(lastHeadTrackingSendText)
                            .monospacedDigit()
                    }

                    if let error = viewModel.headTrackingSenderStatus.lastErrorText {
                        Text(error)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Text("Raw yaw")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.rawYawDeg))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Raw pitch")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.rawPitchDeg))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Raw roll")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.rawRollDeg))
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Centered yaw")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.yawDeg))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Centered pitch")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.pitchDeg))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Centered roll")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.rollDeg))
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Center yaw")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterYaw))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Center pitch")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterPitch))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Center roll")
                        Spacer()
                        Text(HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterRoll))
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("FPV HUD Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.applySettings()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.applySettings()
                    }
                }
            }
        }
    }

    private var receiverStateText: String {
        if viewModel.settings.demoModeEnabled {
            return "Demo"
        }
        return viewModel.telemetryStatus.isListening ? "Listening" : "Stopped"
    }

    private var lastPacketAgeText: String {
        guard !viewModel.settings.demoModeEnabled else { return "Demo" }
        guard let age = viewModel.telemetryStatus.lastPacketAge else { return "Waiting" }
        return String(format: "%.2fs", age)
    }

    private var lastHeadTrackingSendText: String {
        guard let date = viewModel.headTrackingSenderStatus.lastSendAt else { return "Never" }
        let age = Date().timeIntervalSince(date)
        return String(format: "%.2fs ago", age)
    }
}

private extension View {
    @ViewBuilder
    func fpvHostTextInput() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}
