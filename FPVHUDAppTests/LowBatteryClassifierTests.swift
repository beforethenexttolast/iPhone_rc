import XCTest
@testable import FPVHUDApp

final class LowBatteryClassifierTests: XCTestCase {

    // MARK: - Ground-station parity: thresholds and wording

    func testDefaultThresholdsMatchGroundStation() {
        XCTAssertEqual(LowBatteryThresholds.defaults.warnVolts, 7.0)
        XCTAssertEqual(LowBatteryThresholds.defaults.criticalVolts, 6.6)
        XCTAssertEqual(LowBatteryThresholds.hysteresisVolts, 0.15)
    }

    func testBannerWordingMatchesGroundStation() {
        XCTAssertNil(LowBatteryLevel.ok.bannerText)
        XCTAssertEqual(LowBatteryLevel.warn.bannerText, "BATTERY LOW — finish your lap and park")
        XCTAssertEqual(LowBatteryLevel.critical.bannerText, "BATTERY CRITICAL — park the car now")
    }

    func testThresholdSanitizationRepairsInvalidValuesToDefaults() {
        XCTAssertEqual(LowBatteryThresholds(warnVolts: .nan, criticalVolts: .infinity), .defaults)
        XCTAssertEqual(LowBatteryThresholds(warnVolts: 0, criticalVolts: -3), .defaults)
        XCTAssertEqual(LowBatteryThresholds(warnVolts: 7000, criticalVolts: 6600), .defaults)

        // Inverted pair repairs conservatively: critical is lowered to warn,
        // never warn raised to critical.
        let inverted = LowBatteryThresholds(warnVolts: 6.0, criticalVolts: 7.0)
        XCTAssertEqual(inverted.warnVolts, 6.0)
        XCTAssertEqual(inverted.criticalVolts, 6.0)

        let custom = LowBatteryThresholds(warnVolts: 14.0, criticalVolts: 13.2)
        XCTAssertEqual(custom.warnVolts, 14.0)
        XCTAssertEqual(custom.criticalVolts, 13.2)
    }

    // MARK: - Entry is immediate, at the threshold

    func testEntersWarnImmediatelyAtThreshold() {
        var classifier = LowBatteryClassifier()
        XCTAssertEqual(classifier.classify(packVoltage: 7.01), .ok)
        XCTAssertEqual(classifier.classify(packVoltage: 7.0), .warn)
    }

    func testEntersCriticalImmediatelyEvenStraightFromOk() {
        var classifier = LowBatteryClassifier()
        XCTAssertEqual(classifier.classify(packVoltage: 8.2), .ok)
        XCTAssertEqual(classifier.classify(packVoltage: 6.6), .critical)
    }

    // MARK: - Hysteresis: no flicker at the boundary

    func testWarnExitRequiresHysteresisAboveWarnThreshold() {
        var classifier = LowBatteryClassifier()
        classifier.classify(packVoltage: 7.0)
        XCTAssertEqual(classifier.level, .warn)

        XCTAssertEqual(classifier.classify(packVoltage: 7.05), .warn)
        XCTAssertEqual(classifier.classify(packVoltage: 7.14), .warn)
        XCTAssertEqual(classifier.classify(packVoltage: 7.15), .ok)
    }

    func testNoFlapWhenVoltageSagsAndRecoversAroundThreshold() {
        // A LiPo sags under throttle and recovers at idle; hovering around the
        // warn line must not blink the banner.
        var classifier = LowBatteryClassifier()
        classifier.classify(packVoltage: 6.99)
        XCTAssertEqual(classifier.level, .warn)

        for _ in 0..<5 {
            XCTAssertEqual(classifier.classify(packVoltage: 7.05), .warn)
            XCTAssertEqual(classifier.classify(packVoltage: 6.98), .warn)
        }
        XCTAssertEqual(classifier.classify(packVoltage: 7.2), .ok)
    }

    func testCriticalExitRequiresHysteresisAndStepsDownToWarn() {
        var classifier = LowBatteryClassifier()
        classifier.classify(packVoltage: 6.5)
        XCTAssertEqual(classifier.level, .critical)

        XCTAssertEqual(classifier.classify(packVoltage: 6.74), .critical)
        XCTAssertEqual(classifier.classify(packVoltage: 6.75), .warn)
    }

    func testFullStaircaseCriticalToWarnToOk() {
        var classifier = LowBatteryClassifier()
        XCTAssertEqual(classifier.classify(packVoltage: 6.5), .critical)
        XCTAssertEqual(classifier.classify(packVoltage: 6.9), .warn)
        XCTAssertEqual(classifier.classify(packVoltage: 7.1), .warn)
        XCTAssertEqual(classifier.classify(packVoltage: 7.2), .ok)
    }

    func testCriticalRecoveryJumpStillStepsThroughWarn() {
        // The ratchet: even a single reading that recovers far past
        // warn + hysteresis exits critical one level at a time.
        var classifier = LowBatteryClassifier()
        classifier.classify(packVoltage: 6.4)
        XCTAssertEqual(classifier.level, .critical)

        XCTAssertEqual(classifier.classify(packVoltage: 8.2), .warn)
        XCTAssertEqual(classifier.classify(packVoltage: 8.2), .ok)
    }

    // MARK: - Non-finite readings: no reading, no claim

    func testNonFiniteReadingClearsToOk() {
        var classifier = LowBatteryClassifier()
        classifier.classify(packVoltage: 6.5)
        XCTAssertEqual(classifier.level, .critical)

        XCTAssertEqual(classifier.classify(packVoltage: .nan), .ok)

        classifier.classify(packVoltage: 6.9)
        XCTAssertEqual(classifier.level, .warn)
        XCTAssertEqual(classifier.classify(packVoltage: .infinity), .ok)
        XCTAssertEqual(classifier.classify(packVoltage: -.infinity), .ok)
    }

    // MARK: - Freshness gating (stale/lost telemetry never classifies)

    func testUpdateClassifiesLiveValues() {
        var classifier = LowBatteryClassifier()
        let level = classifier.update(
            packVoltage: 6.5,
            showsLiveValues: true,
            freshness: .live,
            batteryFlaggedStale: false
        )
        XCTAssertEqual(level, .critical)
    }

    func testUpdateHoldsDuringStaleTelemetryInBothDirections() {
        var classifier = LowBatteryClassifier()
        classifier.update(packVoltage: 6.9, showsLiveValues: true, freshness: .live, batteryFlaggedStale: false)
        XCTAssertEqual(classifier.level, .warn)

        // A recovering value seen through a stale tier must not clear the level...
        XCTAssertEqual(
            classifier.update(packVoltage: 8.4, showsLiveValues: true, freshness: .staleWarning, batteryFlaggedStale: false),
            .warn
        )

        // ...and a sagging value seen through a stale tier must not raise it.
        var fresh = LowBatteryClassifier()
        XCTAssertEqual(
            fresh.update(packVoltage: 6.0, showsLiveValues: true, freshness: .staleWarning, batteryFlaggedStale: false),
            .ok
        )
    }

    func testUpdateHoldsWhenWindowsFlagsBatteryStale() {
        var classifier = LowBatteryClassifier()
        classifier.update(packVoltage: 6.9, showsLiveValues: true, freshness: .live, batteryFlaggedStale: false)
        XCTAssertEqual(classifier.level, .warn)

        XCTAssertEqual(
            classifier.update(packVoltage: 8.4, showsLiveValues: true, freshness: .live, batteryFlaggedStale: true),
            .warn
        )
    }

    func testUpdateClearsWhenTelemetryIsLost() {
        var classifier = LowBatteryClassifier()
        classifier.update(packVoltage: 6.4, showsLiveValues: true, freshness: .live, batteryFlaggedStale: false)
        XCTAssertEqual(classifier.level, .critical)

        XCTAssertEqual(
            classifier.update(packVoltage: 6.4, showsLiveValues: false, freshness: .dataLost, batteryFlaggedStale: false),
            .ok
        )

        // Recovery after a gap re-enters immediately at the true level — no
        // fake staircase through warn from a cleared state.
        XCTAssertEqual(
            classifier.update(packVoltage: 6.4, showsLiveValues: true, freshness: .live, batteryFlaggedStale: false),
            .critical
        )
    }

    func testUpdateClearsForPlaceholderDisplaysEvenIfFreshnessReadsLive() {
        var classifier = LowBatteryClassifier()
        classifier.update(packVoltage: 6.9, showsLiveValues: true, freshness: .live, batteryFlaggedStale: false)
        XCTAssertEqual(classifier.level, .warn)

        XCTAssertEqual(
            classifier.update(packVoltage: 6.9, showsLiveValues: false, freshness: .live, batteryFlaggedStale: false),
            .ok
        )
    }

    // MARK: - BAT metric color alignment (legacy 7.2 V cutoff retired)

    func testBatteryTintAlignmentRetiresLegacySevenPointTwoCutoff() {
        // The old BAT tint turned red below a one-off 7.2 V line with no
        // hysteresis. The tint now follows the classifier level 1:1, so 7.1 V
        // is plain ok (white), warn starts amber at 7.0 V, critical red at 6.6 V.
        var classifier = LowBatteryClassifier()
        XCTAssertEqual(classifier.classify(packVoltage: 7.1), .ok)
        XCTAssertEqual(classifier.classify(packVoltage: 6.95), .warn)
        XCTAssertEqual(classifier.classify(packVoltage: 6.55), .critical)
    }

    func testDisplayStateDefaultsToOkAndMarksStaleBatteryValues() {
        XCTAssertEqual(TelemetryDisplayState.unknown.lowBattery, .ok)

        let now = Date()
        var settings = AppSettings.defaults
        settings.demoModeEnabled = false

        let staleDisplay = TelemetryDisplayState.make(
            rawTelemetry: makeTelemetry(batteryVoltage: 6.9, timestamp: now.addingTimeInterval(-1.5)),
            receiverStatus: makeTelemetryStatus(age: 1.5, now: now),
            settings: settings,
            now: now
        )
        XCTAssertEqual(staleDisplay.freshness, .staleWarning)
        XCTAssertTrue(staleDisplay.lowBatteryValueIsStale)

        var liveFlagged = makeTelemetry(batteryVoltage: 6.9, timestamp: now)
        liveFlagged.staleDataWarnings = [.battery]
        let liveFlaggedDisplay = TelemetryDisplayState.make(
            rawTelemetry: liveFlagged,
            receiverStatus: makeTelemetryStatus(age: 0.1, now: now),
            settings: settings,
            now: now
        )
        XCTAssertEqual(liveFlaggedDisplay.freshness, .live)
        XCTAssertTrue(liveFlaggedDisplay.lowBatteryValueIsStale)

        let liveDisplay = TelemetryDisplayState.make(
            rawTelemetry: makeTelemetry(batteryVoltage: 6.9, timestamp: now),
            receiverStatus: makeTelemetryStatus(age: 0.1, now: now),
            settings: settings,
            now: now
        )
        XCTAssertFalse(liveDisplay.lowBatteryValueIsStale)
    }

    // MARK: - View model integration: stamped level follows the freshness tiers

    @MainActor
    func testViewModelStampsAndGatesLowBatteryAcrossFreshnessTiers() async {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings.defaults
        settings.demoModeEnabled = false
        store.save(settings)

        let receiver = TelemetryReceiverSpy()
        let viewModel = FPVHUDViewModel(
            motionService: MockMotionService(),
            settingsStore: store,
            udpTelemetry: receiver
        )

        XCTAssertEqual(viewModel.telemetryDisplay.lowBattery, .ok)

        // Live critical packet -> banner level stamped on the display state.
        receiver.onTelemetry?(makeTelemetry(batteryVoltage: 6.5, timestamp: Date()))
        receiver.onStatus?(makeTelemetryStatus(age: 0.05, now: Date()))
        await waitForMainActor { viewModel.telemetryDisplay.lowBattery == .critical }

        XCTAssertEqual(viewModel.telemetryDisplay.lowBattery, .critical)
        XCTAssertEqual(viewModel.telemetryDisplay.freshness, .live)
        XCTAssertFalse(viewModel.telemetryDisplay.lowBatteryValueIsStale)

        // Stale tier: the level holds and the display marks the value stale.
        receiver.onStatus?(makeTelemetryStatus(age: 2.0, now: Date()))
        await waitForMainActor { viewModel.telemetryDisplay.freshness == .staleWarning }

        XCTAssertEqual(viewModel.telemetryDisplay.freshness, .staleWarning)
        XCTAssertEqual(viewModel.telemetryDisplay.lowBattery, .critical)
        XCTAssertTrue(viewModel.telemetryDisplay.lowBatteryValueIsStale)

        // Lost tier: values clear to placeholders and the level clears with them.
        receiver.onStatus?(makeTelemetryStatus(age: 4.0, now: Date()))
        await waitForMainActor { viewModel.telemetryDisplay.freshness == .dataLost }

        XCTAssertEqual(viewModel.telemetryDisplay.freshness, .dataLost)
        XCTAssertFalse(viewModel.telemetryDisplay.showsLiveValues)
        XCTAssertEqual(viewModel.telemetryDisplay.lowBattery, .ok)
    }

    // MARK: - Helpers

    @MainActor
    private func waitForMainActor(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() {
            await Task.yield()
        }
    }

    private func makeTelemetry(batteryVoltage: Double, timestamp: Date) -> TelemetryState {
        TelemetryState(
            timestamp: timestamp,
            batteryVoltage: batteryVoltage,
            rssiDbm: -62,
            snrDb: 18,
            linkQualityPercent: 92,
            speedKmh: 12.4,
            gear: 3,
            driveMode: .gearboxERS,
            ersPercent: 55,
            throttle: 0.43,
            brake: 0,
            steering: -0.15,
            cameraYawDeg: -12,
            cameraPitchDeg: 5,
            panTiltMode: .dualShock,
            videoLock: true,
            linkState: .connected,
            mode: .udp,
            warningText: nil,
            staleDataWarnings: []
        )
    }

    private func makeTelemetryStatus(age: TimeInterval, now: Date) -> TelemetryReceiverStatus {
        TelemetryReceiverStatus(
            isListening: true,
            lastPacketReceivedAt: now.addingTimeInterval(-age),
            lastPacketAge: age,
            malformedPacketCount: 0,
            warningText: nil
        )
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "FPVHUDAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private final class TelemetryReceiverSpy: TelemetryReceiver {
        var onTelemetry: ((TelemetryState) -> Void)?
        var onStatus: ((TelemetryReceiverStatus) -> Void)?

        func start(settings: AppSettings) {}
        func stop() {}
    }
}
