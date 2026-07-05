import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var viewModel: FPVHUDViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftSettings: AppSettings

    init(viewModel: FPVHUDViewModel) {
        self.viewModel = viewModel
        _draftSettings = State(initialValue: viewModel.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Windows ground station") {
                    TextField("Host IP", text: $draftSettings.windowsHost)
                        .fpvHostTextInput()

                    SettingsValidationMessages(messages: validation.messages(for: .windowsHost))

                    Stepper(
                        "Telemetry UDP: \(draftSettings.telemetryPort)",
                        value: $draftSettings.telemetryPort,
                        in: AppSettingsValidator.portRange
                    )
                    SettingsValidationMessages(messages: validation.messages(for: .telemetryPort))

                    Stepper(
                        "Head tracking UDP: \(draftSettings.headTrackingPort)",
                        value: $draftSettings.headTrackingPort,
                        in: AppSettingsValidator.portRange
                    )
                    SettingsValidationMessages(messages: validation.messages(for: .headTrackingPort))
                }

                Section("Modes") {
                    Toggle("Demo telemetry", isOn: $draftSettings.demoModeEnabled)
                    Toggle("Head tracking input to Windows", isOn: $draftSettings.trackingEnabled)
                    Stepper(
                        "Motion rate: \(draftSettings.motionUpdateHz) Hz",
                        value: $draftSettings.motionUpdateHz,
                        in: 15...120,
                        step: 5
                    )
                    SettingsValidationMessages(messages: validation.messages(for: .motionUpdateHz))
                    Stepper(
                        "Head send rate: \(draftSettings.headTrackingSendHz) Hz",
                        value: $draftSettings.headTrackingSendHz,
                        in: 30...60,
                        step: 5
                    )
                    SettingsValidationMessages(messages: validation.messages(for: .headTrackingSendHz))
                    Stepper(
                        "Head timeout: \(draftSettings.headTrackingTimeoutMs) ms",
                        value: $draftSettings.headTrackingTimeoutMs,
                        in: AppSettingsValidator.timeoutMsRange,
                        step: 50
                    )
                    SettingsValidationMessages(messages: validation.messages(for: .headTrackingTimeoutMs))

                    Button(role: .destructive) {
                        draftSettings = viewModel.resetSettingsToDefaults()
                    } label: {
                        Label("Reset settings to defaults", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("Telemetry receiver") {
                    SettingsValueRow(
                        title: "UDP listener",
                        value: receiverStateText,
                        tint: viewModel.telemetryStatus.isListening ? .green : .secondary
                    )

                    SettingsValueRow(title: "Last packet age", value: lastPacketAgeText)

                    SettingsValueRow(title: "Malformed packets", value: "\(viewModel.telemetryStatus.malformedPacketCount)")

                    if let warning = viewModel.telemetryStatus.warningText {
                        Text(warning)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Tracking") {
                    SettingsTrackingActions(
                        onCenter: {
                            viewModel.centerTracking()
                        },
                        onReset: {
                            viewModel.resetTrackingCalibration()
                        }
                    )

                    SettingsValueRow(title: "State", value: viewModel.motion.status.displayName)

                    SettingsValueRow(
                        title: "UDP configured",
                        value: viewModel.headTrackingDisplay.udpConfiguredText,
                        tint: viewModel.headTrackingDisplay.isUDPConfigured ? .green : .secondary
                    )

                    SettingsValueRow(title: "Packet rate", value: viewModel.headTrackingDisplay.packetRateText)

                    SettingsValueRow(title: "Packets sent", value: viewModel.headTrackingDisplay.packetsSentText)

                    SettingsValueRow(title: "Last send", value: viewModel.headTrackingDisplay.lastSendText)

                    if let error = viewModel.headTrackingDisplay.warningText {
                        Text(error)
                            .foregroundStyle(.orange)
                    }

                    SettingsValueRow(title: "Raw yaw", value: HUDFormatters.signedDegrees(viewModel.motion.rawYawDeg))
                    SettingsValueRow(title: "Raw pitch", value: HUDFormatters.signedDegrees(viewModel.motion.rawPitchDeg))
                    SettingsValueRow(title: "Raw roll", value: HUDFormatters.signedDegrees(viewModel.motion.rawRollDeg))

                    SettingsValueRow(title: "Centered yaw", value: HUDFormatters.signedDegrees(viewModel.motion.yawDeg))
                    SettingsValueRow(title: "Centered pitch", value: HUDFormatters.signedDegrees(viewModel.motion.pitchDeg))
                    SettingsValueRow(title: "Centered roll", value: HUDFormatters.signedDegrees(viewModel.motion.rollDeg))

                    SettingsValueRow(title: "Center yaw", value: HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterYaw))
                    SettingsValueRow(title: "Center pitch", value: HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterPitch))
                    SettingsValueRow(title: "Center roll", value: HUDFormatters.signedDegrees(viewModel.motion.calibratedCenterRoll))
                }
            }
            .navigationTitle("FPV HUD Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyDraftSettings()
                    }
                    .disabled(!validation.isValid)
                }
            }
        }
    }

    private var validation: AppSettingsValidationResult {
        AppSettingsValidator.validate(draftSettings)
    }

    private func applyDraftSettings() {
        if viewModel.applySettings(draftSettings) {
            draftSettings = viewModel.settings
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

}

private struct SettingsTrackingActions: View {
    var onCenter: () -> Void
    var onReset: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                centerButton
                resetButton
            }

            VStack(alignment: .leading, spacing: 8) {
                centerButton
                resetButton
            }
        }
    }

    private var centerButton: some View {
        Button(action: onCenter) {
            Label("Center / calibrate", systemImage: "scope")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var resetButton: some View {
        Button(role: .destructive, action: onReset) {
            Label("Reset calibration", systemImage: "xmark.circle")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct SettingsValueRow: View {
    var title: String
    var value: String
    var tint: Color = .primary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                valueText
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var valueText: some View {
        Text(value)
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
    }
}

private struct SettingsValidationMessages: View {
    var messages: [AppSettingsValidationIssue]

    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages) { issue in
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
