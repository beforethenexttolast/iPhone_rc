import XCTest
@testable import FPVHUDApp

final class TelemetryParsingTests: XCTestCase {
    func testSettingsStoreReturnsSafeDefaultsWhenEmpty() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)

        let settings = store.load()

        XCTAssertEqual(settings, .defaults)
        XCTAssertTrue(settings.demoModeEnabled)
        XCTAssertFalse(settings.trackingEnabled)
    }

    func testSettingsStoreSavesAndLoadsExposedSettings() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        let settings = AppSettings(
            windowsHost: "10.0.0.42",
            telemetryPort: 6001,
            headTrackingPort: 6002,
            motionUpdateHz: 90,
            headTrackingSendHz: 45,
            headTrackingTimeoutMs: 350,
            trackingEnabled: true,
            demoModeEnabled: false
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testSettingsStoreDoesNotPersistAPFPVDiagnosticEnabled() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings.defaults
        settings.apfpvDiagnosticPort = 5700
        settings.apfpvDiagnosticEnabled = true

        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded.apfpvDiagnosticPort, 5700)
        XCTAssertFalse(loaded.apfpvDiagnosticEnabled)
    }

    func testSettingsStoreResetRestoresDefaults() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings.defaults
        settings.windowsHost = "10.0.0.99"
        settings.demoModeEnabled = false
        settings.trackingEnabled = true
        store.save(settings)

        let reset = store.reset()

        XCTAssertEqual(reset, .defaults)
        XCTAssertEqual(store.load(), .defaults)
        XCTAssertTrue(store.load().demoModeEnabled)
        XCTAssertFalse(store.load().trackingEnabled)
    }

    func testSettingsStoreFallsBackToDefaultsForCorruptData() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: SettingsStore.storageKey)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .defaults)
    }

    func testHeadTrackingTimingClampsSendRate() {
        XCTAssertEqual(HeadTrackingTiming.clampedSendRateHz(10), 30)
        XCTAssertEqual(HeadTrackingTiming.clampedSendRateHz(45), 45)
        XCTAssertEqual(HeadTrackingTiming.clampedSendRateHz(90), 60)
    }

    func testHeadTrackingTimingCalculatesIntervalMilliseconds() {
        XCTAssertEqual(HeadTrackingTiming.sendIntervalMilliseconds(forRateHz: 30), 33)
        XCTAssertEqual(HeadTrackingTiming.sendIntervalMilliseconds(forRateHz: 60), 17)
    }

    func testHeadTrackingSafetyRequiresCenteringBeforeSend() {
        let now = Date()
        let status = HeadTrackingSafety.status(
            trackingEnabled: true,
            hasCentered: false,
            sampleTimestamp: now,
            now: now
        )

        XCTAssertEqual(status, .readyNotCentered)
        XCTAssertFalse(HeadTrackingSafety.canSend(status: status))
    }

    func testHeadTrackingSafetyAllowsSendOnlyWhenActive() {
        let now = Date()
        let status = HeadTrackingSafety.status(
            trackingEnabled: true,
            hasCentered: true,
            sampleTimestamp: now,
            now: now
        )

        XCTAssertEqual(status, .active)
        XCTAssertTrue(HeadTrackingSafety.canSend(status: status))
    }

    func testHeadTrackingSafetyStopsSendWhenDisabledOrStaleOrError() {
        let now = Date()

        let disabled = HeadTrackingSafety.status(
            trackingEnabled: false,
            hasCentered: true,
            sampleTimestamp: now,
            now: now
        )
        let stale = HeadTrackingSafety.status(
            trackingEnabled: true,
            hasCentered: true,
            sampleTimestamp: now.addingTimeInterval(-0.75),
            now: now
        )
        let error = HeadTrackingSafety.status(
            trackingEnabled: true,
            hasCentered: true,
            sampleTimestamp: now.addingTimeInterval(-2.5),
            now: now
        )

        XCTAssertEqual(disabled, .off)
        XCTAssertEqual(stale, .stale)
        XCTAssertEqual(error, .error)
        XCTAssertFalse(HeadTrackingSafety.canSend(status: disabled))
        XCTAssertFalse(HeadTrackingSafety.canSend(status: stale))
        XCTAssertFalse(HeadTrackingSafety.canSend(status: error))
    }

    func testHeadTrackingSafetyBlocksAgainAfterCalibrationReset() {
        let now = Date()
        let active = HeadTrackingSafety.status(
            trackingEnabled: true,
            hasCentered: true,
            sampleTimestamp: now,
            now: now
        )
        let afterReset = HeadTrackingSafety.status(
            trackingEnabled: true,
            hasCentered: false,
            sampleTimestamp: now,
            now: now
        )

        XCTAssertTrue(HeadTrackingSafety.canSend(status: active))
        XCTAssertEqual(afterReset, .readyNotCentered)
        XCTAssertFalse(HeadTrackingSafety.canSend(status: afterReset))
    }

    func testHeadTrackingDriveLabelsStayCompact() {
        XCTAssertEqual(HeadTrackingStatus.off.driveDisplayName, "HEAD OFF")
        XCTAssertEqual(HeadTrackingStatus.readyNotCentered.driveDisplayName, "HEAD NOT CENTERED")
        XCTAssertEqual(HeadTrackingStatus.active.driveDisplayName, "HEAD ACTIVE")
        XCTAssertEqual(HeadTrackingStatus.stale.driveDisplayName, "HEAD STALE")
        XCTAssertEqual(HeadTrackingStatus.error.driveDisplayName, "HEAD STALE")
    }

    func testMockMotionServiceControlsClampAndReset() {
        let service = MockMotionService()
        service.setMockMotion(yawDeg: 220, pitchDeg: 120, rollDeg: -120)

        XCTAssertTrue(service.controlState.isAvailable)
        XCTAssertEqual(service.controlState.yawDeg, -140, accuracy: 0.001)
        XCTAssertEqual(service.controlState.pitchDeg, 90, accuracy: 0.001)
        XCTAssertEqual(service.controlState.rollDeg, -90, accuracy: 0.001)

        service.resetMockMotion()

        XCTAssertEqual(service.controlState.yawDeg, 0, accuracy: 0.001)
        XCTAssertEqual(service.controlState.pitchDeg, 0, accuracy: 0.001)
        XCTAssertEqual(service.controlState.rollDeg, 0, accuracy: 0.001)
    }

    func testMockMotionServiceEmitsThroughRawMotionPipeline() {
        let service = MockMotionService()
        var sample: RawMotionSample?
        service.onMotion = { sample = $0 }

        service.setMockMotion(yawDeg: 12.5, pitchDeg: -4.5, rollDeg: 2.25)

        XCTAssertEqual(sample?.yawDeg, 12.5)
        XCTAssertEqual(sample?.pitchDeg, -4.5)
        XCTAssertEqual(sample?.rollDeg, 2.25)
    }

    func testRTPHeaderParserMapsSyntheticPacketFields() throws {
        let packet = makeRTPPacket(
            payloadType: 96,
            sequenceNumber: 0x1234,
            timestamp: 0x01020304,
            ssrc: 0xAABBCCDD,
            payload: makeH265NALHeader(type: 32) + [0x01, 0x02]
        )

        let header = try RTPDiagnosticParser.parseHeader(packet)

        XCTAssertEqual(header.version, 2)
        XCTAssertFalse(header.padding)
        XCTAssertFalse(header.extensionHeader)
        XCTAssertFalse(header.marker)
        XCTAssertEqual(header.payloadType, 96)
        XCTAssertEqual(header.sequenceNumber, 0x1234)
        XCTAssertEqual(header.timestamp, 0x01020304)
        XCTAssertEqual(header.ssrc, 0xAABBCCDD)
        XCTAssertEqual(header.headerLength, 12)
    }

    func testH265PayloadInspectionIdentifiesVpsSpsPps() throws {
        let vps = try inspectNAL(type: 32)
        let sps = try inspectNAL(type: 33)
        let pps = try inspectNAL(type: 34)

        XCTAssertTrue(vps.isVPS)
        XCTAssertEqual(vps.displayName, "VPS (32)")
        XCTAssertTrue(sps.isSPS)
        XCTAssertEqual(sps.displayName, "SPS (33)")
        XCTAssertTrue(pps.isPPS)
        XCTAssertEqual(pps.displayName, "PPS (34)")
    }

    func testH265PayloadInspectionIdentifiesFragmentedOriginalNalType() throws {
        let payload = makeH265NALHeader(type: 49) + [0x80 | 32, 0xAA, 0xBB]
        let packet = makeRTPPacket(payloadType: 96, sequenceNumber: 7, timestamp: 99, ssrc: 42, payload: payload)
        let header = try RTPDiagnosticParser.parseHeader(packet)

        let inspection = try RTPDiagnosticParser.inspectH265Payload(packet, header: header)

        XCTAssertTrue(inspection.isFragmentationUnit)
        XCTAssertEqual(inspection.packetType, 49)
        XCTAssertEqual(inspection.nalUnitType, 32)
        XCTAssertTrue(inspection.isVPS)
    }

    func testRTPHeaderParserRejectsInvalidVersionAndShortPackets() {
        XCTAssertThrowsError(try RTPDiagnosticParser.parseHeader(Data([0x80, 0x60])))

        var invalidVersion = makeRTPPacket(
            payloadType: 96,
            sequenceNumber: 1,
            timestamp: 2,
            ssrc: 3,
            payload: makeH265NALHeader(type: 32)
        )
        invalidVersion[0] = 0x40

        XCTAssertThrowsError(try RTPDiagnosticParser.parseHeader(invalidVersion)) { error in
            XCTAssertEqual(error as? RTPParseError, .invalidVersion(1))
        }
    }

    func testTelemetryFreshnessThresholds() {
        XCTAssertEqual(TelemetryFreshness.evaluate(age: 0.25), .live)
        XCTAssertEqual(TelemetryFreshness.evaluate(age: 1.01), .staleWarning)
        XCTAssertEqual(TelemetryFreshness.evaluate(age: 3.01), .dataLost)
    }

    func testHeadTrackingPacketFactoryIncrementsSequenceAndAddsTimestamp() {
        var factory = HeadTrackingPacketFactory()

        let first = factory.makePacket(
            yawDeg: -12.5,
            pitchDeg: 6.8,
            rollDeg: 1.2,
            trackingEnabled: true,
            centered: true,
            timeoutMs: 250
        )
        let second = factory.makePacket(
            yawDeg: -1,
            pitchDeg: 2,
            rollDeg: 3,
            trackingEnabled: false,
            centered: false,
            timeoutMs: 250
        )

        XCTAssertEqual(first.seq, 1)
        XCTAssertEqual(second.seq, 2)
        XCTAssertGreaterThan(first.timestampMs, 0)
        XCTAssertGreaterThanOrEqual(second.timestampMs, first.timestampMs)
        XCTAssertEqual(first.yawDeg, -12.5)
        XCTAssertEqual(first.pitchDeg, 6.8)
        XCTAssertEqual(first.rollDeg, 1.2)
        XCTAssertTrue(first.trackingEnabled)
        XCTAssertFalse(second.trackingEnabled)
    }

    func testHeadTrackingDisplayStateMapsSenderStatusForUI() {
        let now = Date()
        let status = HeadTrackingSenderStatus(
            isConfigured: true,
            packetsSent: 12,
            packetRateHz: 45,
            lastSendAt: now.addingTimeInterval(-0.5),
            lastErrorText: "send failed"
        )

        let display = HeadTrackingDisplayState(senderStatus: status, now: now)

        XCTAssertTrue(display.isUDPConfigured)
        XCTAssertEqual(display.udpConfiguredText, "Yes")
        XCTAssertEqual(display.packetRateText, "45 Hz")
        XCTAssertEqual(display.packetsSentText, "12")
        XCTAssertEqual(display.lastSendText, "0.50s ago")
        XCTAssertEqual(display.warningText, "send failed")
    }

    func testHeadTrackingPacketEncodesDebugJSONShape() throws {
        let packet = HeadTrackingPacket(
            seq: 7,
            timestampMs: 12345678,
            yawDeg: -12.5,
            pitchDeg: 6.8,
            rollDeg: 1.2,
            trackingEnabled: true,
            centered: true,
            timeoutMs: 250
        )

        let data = try JSONEncoder().encode(packet)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["seq"] as? Int, 7)
        XCTAssertEqual(object["timestamp_ms"] as? Int, 12345678)
        XCTAssertEqual(object["yaw_deg"] as? Double, -12.5)
        XCTAssertEqual(object["pitch_deg"] as? Double, 6.8)
        XCTAssertEqual(object["roll_deg"] as? Double, 1.2)
        XCTAssertEqual(object["tracking_enabled"] as? Bool, true)
        XCTAssertEqual(object["centered"] as? Bool, true)
        XCTAssertEqual(object["timeout_ms"] as? Int, 250)
    }

    func testGoldenTelemetryFixturesDecodeIntoIOSState() throws {
        let fresh = try TelemetryJSONDecoder.decodeState(
            from: fixtureData("telemetry_fresh.json"),
            previous: .demo
        )

        XCTAssertEqual(fresh.batteryVoltage, 14.8)
        XCTAssertEqual(fresh.linkQualityPercent, 92)
        XCTAssertEqual(fresh.rssiDbm, -62)
        XCTAssertEqual(fresh.snrDb, 18)
        XCTAssertEqual(fresh.speedKmh, 12.4)
        XCTAssertEqual(fresh.gear, 3)
        XCTAssertEqual(fresh.driveMode, .gearboxERS)
        XCTAssertEqual(fresh.ersPercent, 55)
        XCTAssertEqual(fresh.panTiltMode, .disabled)
        XCTAssertTrue(fresh.videoLock)
        XCTAssertEqual(fresh.mode, .udp)

        let staleLike = try TelemetryJSONDecoder.decodeState(
            from: fixtureData("telemetry_stale_like.json"),
            previous: .demo
        )

        XCTAssertEqual(staleLike.linkQualityPercent, 68)
        XCTAssertEqual(staleLike.driveMode, .gearbox)
        XCTAssertEqual(staleLike.panTiltMode, .dualShock)
        XCTAssertEqual(staleLike.warningText, "SIMULATED STALE SOURCE")
        XCTAssertEqual(staleLike.staleDataWarnings, [.speed, .flightMode])
    }

    func testGoldenTelemetryMinimalFixtureMergesWithPreviousState() throws {
        let previous = makeLiveTelemetry(timestamp: Date())

        let minimal = try TelemetryJSONDecoder.decodeState(
            from: fixtureData("telemetry_minimal.json"),
            previous: previous
        )

        XCTAssertEqual(minimal.batteryVoltage, 12.6)
        XCTAssertEqual(minimal.linkQualityPercent, previous.linkQualityPercent)
        XCTAssertEqual(minimal.rssiDbm, previous.rssiDbm)
        XCTAssertEqual(minimal.snrDb, previous.snrDb)
        XCTAssertEqual(minimal.speedKmh, previous.speedKmh)
        XCTAssertEqual(minimal.gear, previous.gear)
        XCTAssertEqual(minimal.ersPercent, previous.ersPercent)
        XCTAssertEqual(minimal.mode, .udp)
    }

    func testGoldenTelemetryMalformedFixtureIsRejectedSafely() throws {
        let previous = makeLiveTelemetry(timestamp: Date())

        XCTAssertThrowsError(
            try TelemetryJSONDecoder.decodeState(
                from: fixtureData("telemetry_malformed.json"),
                previous: previous
            )
        )

        let display = TelemetryDisplayState.make(
            rawTelemetry: previous,
            receiverStatus: TelemetryReceiverStatus(
                isListening: true,
                lastPacketReceivedAt: Date(),
                lastPacketAge: 0,
                malformedPacketCount: 1,
                warningText: "Malformed telemetry JSON"
            ),
            settings: realTelemetrySettings()
        )

        XCTAssertTrue(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "14.8 V")
        XCTAssertEqual(display.linkQualityText, "92%")
        XCTAssertEqual(display.speedText, "12 km/h")
        XCTAssertEqual(display.gearText, "G3")
    }

    func testGoldenTelemetryFixtureClearsUnsafeValuesWhenLost() throws {
        let fresh = try TelemetryJSONDecoder.decodeState(
            from: fixtureData("telemetry_fresh.json"),
            previous: .demo
        )
        let now = Date()

        let display = TelemetryDisplayState.make(
            rawTelemetry: fresh,
            receiverStatus: makeTelemetryStatus(age: 3.2, now: now),
            settings: realTelemetrySettings(),
            now: now
        )

        XCTAssertFalse(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "--.- V")
        XCTAssertEqual(display.linkQualityText, "--")
        XCTAssertEqual(display.rssiText, "--")
        XCTAssertEqual(display.snrText, "--")
        XCTAssertEqual(display.speedText, "-- km/h")
        XCTAssertEqual(display.gearText, "--")
        XCTAssertEqual(display.ersText, "--")
        XCTAssertEqual(display.warningText, "TELEMETRY DATA LOST >3S")
    }

    func testGoldenHeadTrackingFixturesMatchSchemaShape() throws {
        try assertHeadTrackingFixtureSchema("head_tracking_ready.json", enabled: false, centered: true)
        try assertHeadTrackingFixtureSchema("head_tracking_active.json", enabled: true, centered: true)
        try assertHeadTrackingFixtureSchema("head_tracking_uncentered.json", enabled: true, centered: false)
    }

    func testGoldenHeadTrackingMalformedFixtureIsRejected() throws {
        XCTAssertThrowsError(
            try JSONSerialization.jsonObject(with: fixtureData("head_tracking_malformed.json"))
        )
    }

    func testHeadTrackingEncoderOutputMatchesContractSchemaShape() throws {
        let packet = HeadTrackingPacket(
            seq: 42,
            timestampMs: 1783184400000,
            yawDeg: -12.5,
            pitchDeg: 6.8,
            rollDeg: 1.2,
            trackingEnabled: true,
            centered: true,
            timeoutMs: 250
        )

        let data = try JSONEncoder().encode(packet)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["seq"] as? Int, 42)
        XCTAssertEqual(object["timestamp_ms"] as? Int, 1783184400000)
        XCTAssertEqual(object["yaw_deg"] as? Double, -12.5)
        XCTAssertEqual(object["pitch_deg"] as? Double, 6.8)
        XCTAssertEqual(object["roll_deg"] as? Double, 1.2)
        XCTAssertEqual(object["tracking_enabled"] as? Bool, true)
        XCTAssertEqual(object["centered"] as? Bool, true)
        XCTAssertEqual(object["timeout_ms"] as? Int, 250)
        XCTAssertNil(object["protocol_version"])
    }

    func testIncomingTelemetryPacketMergesPartialJSON() throws {
        let json = """
        {
          "timestamp_ms": 12345678,
          "battery_v": 7.86,
          "rssi_dbm": -61,
          "snr_db": 18.5,
          "link_quality": 74,
          "speed_kmh": 42.0,
          "gear": 3,
          "drive_mode": "GEARBOX_ERS",
          "ers_percent": 64,
          "throttle": 0.7,
          "steering": -0.25,
          "camera_yaw_deg": 12.0,
          "camera_pitch_deg": -4.0,
          "head_tracking_mode": "OFF",
          "video_lock": true,
          "link_state": "connected",
          "mode": "udp",
          "warning": "",
          "stale_data_warnings": ["speed", "flightMode"]
        }
        """.data(using: .utf8)!

        let packet = try JSONDecoder().decode(IncomingTelemetryPacket.self, from: json)
        let state = packet.merged(with: .demo)

        XCTAssertEqual(state.batteryVoltage, 7.86)
        XCTAssertEqual(state.rssiDbm, -61)
        XCTAssertEqual(state.snrDb, 18.5)
        XCTAssertEqual(state.linkQualityPercent, 74)
        XCTAssertEqual(state.speedKmh, 42.0)
        XCTAssertEqual(state.gear, 3)
        XCTAssertEqual(state.driveMode, .gearboxERS)
        XCTAssertEqual(state.ersPercent, 64)
        XCTAssertEqual(state.throttle, 0.7)
        XCTAssertEqual(state.brake, TelemetryState.demo.brake)
        XCTAssertEqual(state.steering, -0.25)
        XCTAssertEqual(state.cameraYawDeg, 12.0)
        XCTAssertEqual(state.cameraPitchDeg, -4.0)
        XCTAssertEqual(state.panTiltMode, .disabled)
        XCTAssertTrue(state.videoLock)
        XCTAssertEqual(state.linkState, .connected)
        XCTAssertEqual(state.mode, .udp)
        XCTAssertNil(state.warningText)
        XCTAssertEqual(state.staleDataWarnings, [.speed, .flightMode])
    }

    func testIncomingTelemetryMissingOptionalFieldsDoesNotCrashAndKeepsPreviousValues() throws {
        let json = """
        {
          "battery_v": 7.5
        }
        """.data(using: .utf8)!

        let packet = try JSONDecoder().decode(IncomingTelemetryPacket.self, from: json)
        let state = packet.merged(with: .demo)

        XCTAssertEqual(state.batteryVoltage, 7.5)
        XCTAssertEqual(state.rssiDbm, TelemetryState.demo.rssiDbm)
        XCTAssertEqual(state.snrDb, TelemetryState.demo.snrDb)
        XCTAssertEqual(state.linkQualityPercent, TelemetryState.demo.linkQualityPercent)
        XCTAssertEqual(state.speedKmh, TelemetryState.demo.speedKmh)
        XCTAssertEqual(state.driveMode, TelemetryState.demo.driveMode)
        XCTAssertEqual(state.mode, .udp)
    }

    func testIncomingTelemetryMalformedJSONIsRejected() {
        let json = """
        {
          "battery_v": "not-a-number",
          "link_quality": 80
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(IncomingTelemetryPacket.self, from: json))
    }

    func testMalformedTelemetryDoesNotCorruptLastKnownSafeDisplayState() throws {
        let now = Date()
        let previous = makeLiveTelemetry(timestamp: now)
        let malformed = """
        {
          "battery_v": "not-a-number",
          "speed_kmh": 88.0
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(
            try TelemetryJSONDecoder.decodeState(from: malformed, previous: previous)
        )

        let display = TelemetryDisplayState.make(
            rawTelemetry: previous,
            receiverStatus: TelemetryReceiverStatus(
                isListening: true,
                lastPacketReceivedAt: now,
                lastPacketAge: 0,
                malformedPacketCount: 1,
                warningText: "Malformed telemetry JSON"
            ),
            settings: realTelemetrySettings(),
            now: now
        )

        XCTAssertTrue(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "14.8 V")
        XCTAssertEqual(display.linkQualityText, "92%")
        XCTAssertEqual(display.rssiText, "-62")
        XCTAssertEqual(display.snrText, "18")
        XCTAssertEqual(display.speedText, "12 km/h")
        XCTAssertEqual(display.gearText, "G3")
        XCTAssertEqual(display.ersText, "55%")
        XCTAssertNil(display.warningText)
    }

    func testIncomingTelemetryClampsControlValues() throws {
        let json = """
        {
          "throttle": 2.0,
          "brake": -1.0,
          "steering": -4.0,
          "link_quality": 150,
          "ers_percent": -10
        }
        """.data(using: .utf8)!

        let packet = try JSONDecoder().decode(IncomingTelemetryPacket.self, from: json)
        let state = packet.merged(with: .demo)

        XCTAssertEqual(state.throttle, 1.0)
        XCTAssertEqual(state.brake, 0.0)
        XCTAssertEqual(state.steering, -1.0)
        XCTAssertEqual(state.linkQualityPercent, 100)
        XCTAssertEqual(state.ersPercent, 0)
    }

    func testIncomingTelemetryMapsHeadTrackingModeTokens() throws {
        let json = """
        {
          "head_tracking_mode": "HEAD_TRACKING",
          "drive_mode": "GEARBOX"
        }
        """.data(using: .utf8)!

        let packet = try JSONDecoder().decode(IncomingTelemetryPacket.self, from: json)
        let state = packet.merged(with: .demo)

        XCTAssertEqual(state.panTiltMode, .headTracking)
        XCTAssertEqual(state.driveMode, .gearbox)
    }

    func testTelemetryDisplayShowsFreshValues() {
        let now = Date()
        let state = makeLiveTelemetry(timestamp: now.addingTimeInterval(-0.2))
        let display = TelemetryDisplayState.make(
            rawTelemetry: state,
            receiverStatus: makeTelemetryStatus(age: 0.2, now: now),
            settings: realTelemetrySettings(),
            now: now
        )

        XCTAssertEqual(display.freshness, .live)
        XCTAssertTrue(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "14.8 V")
        XCTAssertEqual(display.linkQualityText, "92%")
        XCTAssertEqual(display.rssiText, "-62")
        XCTAssertEqual(display.snrText, "18")
        XCTAssertEqual(display.gearText, "G3")
        XCTAssertEqual(display.driveModeText, "ERS")
        XCTAssertEqual(display.ersText, "55%")
        XCTAssertEqual(display.speedText, "12 km/h")
        XCTAssertNil(display.warningText)
    }

    func testTelemetryDisplayShowsStaleWarningAfterOneSecond() {
        let now = Date()
        let state = makeLiveTelemetry(timestamp: now.addingTimeInterval(-1.4))
        let display = TelemetryDisplayState.make(
            rawTelemetry: state,
            receiverStatus: makeTelemetryStatus(age: 1.4, now: now),
            settings: realTelemetrySettings(),
            now: now
        )

        XCTAssertEqual(display.freshness, .staleWarning)
        XCTAssertTrue(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "14.8 V")
        XCTAssertEqual(display.gearText, "G3")
        XCTAssertEqual(display.warningText, "TELEMETRY STALE >1S")
        XCTAssertTrue(display.staleDataWarnings.contains(.telemetry))
    }

    func testTelemetryDisplayClearsValuesAfterDataLost() {
        let now = Date()
        let state = makeLiveTelemetry(timestamp: now.addingTimeInterval(-3.4))
        let display = TelemetryDisplayState.make(
            rawTelemetry: state,
            receiverStatus: makeTelemetryStatus(age: 3.4, now: now),
            settings: realTelemetrySettings(),
            now: now
        )

        XCTAssertEqual(display.freshness, .dataLost)
        XCTAssertFalse(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "--.- V")
        XCTAssertEqual(display.linkQualityText, "--")
        XCTAssertEqual(display.rssiText, "--")
        XCTAssertEqual(display.snrText, "--")
        XCTAssertEqual(display.speedText, "-- km/h")
        XCTAssertEqual(display.gearText, "--")
        XCTAssertEqual(display.driveModeText, "UNKNOWN")
        XCTAssertEqual(display.ersText, "--")
        XCTAssertEqual(display.warningText, "TELEMETRY DATA LOST >3S")
    }

    func testTelemetryDisplayAgesFromLastPacketTimestamp() {
        let receivedAt = Date()
        let now = receivedAt.addingTimeInterval(3.2)
        let state = makeLiveTelemetry(timestamp: receivedAt)
        let status = TelemetryReceiverStatus(
            isListening: true,
            lastPacketReceivedAt: receivedAt,
            lastPacketAge: 0.1,
            malformedPacketCount: 0,
            warningText: nil
        )

        let display = TelemetryDisplayState.make(
            rawTelemetry: state,
            receiverStatus: status,
            settings: realTelemetrySettings(),
            now: now
        )

        XCTAssertEqual(display.freshness, .dataLost)
        XCTAssertFalse(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "--.- V")
        XCTAssertEqual(display.linkQualityText, "--")
        XCTAssertEqual(display.rssiText, "--")
        XCTAssertEqual(display.snrText, "--")
        XCTAssertEqual(display.speedValueText, "--")
        XCTAssertEqual(display.gearText, "--")
        XCTAssertEqual(display.ersText, "--")
    }

    func testTelemetryDisplayClearsDemoValuesWhenDemoIsOff() {
        let display = TelemetryDisplayState.make(
            rawTelemetry: .demo,
            receiverStatus: .idle,
            settings: realTelemetrySettings()
        )

        XCTAssertFalse(display.showsLiveValues)
        XCTAssertEqual(display.batteryText, "--.- V")
        XCTAssertEqual(display.speedText, "-- km/h")
        XCTAssertEqual(display.gearText, "--")
        XCTAssertEqual(display.ersText, "--")
        XCTAssertEqual(display.sourceText, "--")
        XCTAssertEqual(display.warningText, "WAITING FOR TELEMETRY")
    }

    func testTelemetryDisplayDoesNotKeepGearOrERSAfterTelemetryLost() {
        var state = makeLiveTelemetry(timestamp: Date().addingTimeInterval(-4))
        state.gear = 6
        state.ersPercent = 99

        let display = TelemetryDisplayState.make(
            rawTelemetry: state,
            receiverStatus: makeTelemetryStatus(age: 4, now: Date()),
            settings: realTelemetrySettings()
        )

        XCTAssertEqual(display.gearText, "--")
        XCTAssertEqual(display.ersText, "--")
        XCTAssertEqual(display.speedValueText, "--")
    }

    func testSettingsValidatorAcceptsTrimmedIPv4AndHostnames() throws {
        XCTAssertEqual(AppSettingsValidator.validateHost(" 192.168.4.2 "), "192.168.4.2")
        XCTAssertEqual(AppSettingsValidator.validateHost("windows-ground.local"), "windows-ground.local")
        XCTAssertEqual(AppSettingsValidator.validateHost("groundstation"), "groundstation")
        XCTAssertNil(AppSettingsValidator.validateHost(""))
        XCTAssertNil(AppSettingsValidator.validateHost("300.168.4.2"))
        XCTAssertNil(AppSettingsValidator.validateHost("bad_host_name"))
    }

    func testSettingsValidatorHostRules() {
        XCTAssertNil(AppSettingsValidator.validateHost(""))
        XCTAssertNil(AppSettingsValidator.validateHost("   "))
        XCTAssertEqual(AppSettingsValidator.validateHost(" 10.0.0.42 "), "10.0.0.42")
        XCTAssertEqual(AppSettingsValidator.validateHost("127.0.0.1"), "127.0.0.1")
        XCTAssertNil(AppSettingsValidator.validateHost("256.0.0.1"))
        XCTAssertNil(AppSettingsValidator.validateHost("192.168.1"))
        XCTAssertNil(AppSettingsValidator.validateHost("192.168.1.1.1"))
        XCTAssertEqual(AppSettingsValidator.validateHost("groundstation"), "groundstation")
        XCTAssertEqual(AppSettingsValidator.validateHost("groundstation.local"), "groundstation.local")
        XCTAssertNil(AppSettingsValidator.validateHost("-bad-host"))
        XCTAssertNil(AppSettingsValidator.validateHost("bad_host"))
    }

    func testSettingsValidatorParsesPortsRatesAndTimeoutsSafely() {
        XCTAssertEqual(AppSettingsValidator.parsePort("1"), 1)
        XCTAssertEqual(AppSettingsValidator.parsePort("5601"), 5601)
        XCTAssertEqual(AppSettingsValidator.parsePort(" 65535 "), 65535)
        XCTAssertNil(AppSettingsValidator.parsePort("0"))
        XCTAssertNil(AppSettingsValidator.parsePort("65536"))
        XCTAssertNil(AppSettingsValidator.parsePort("-1"))
        XCTAssertNil(AppSettingsValidator.parsePort("12.5"))
        XCTAssertNil(AppSettingsValidator.parsePort("abc"))

        XCTAssertEqual(AppSettingsValidator.parseSendRateHz("60"), 60)
        XCTAssertEqual(AppSettingsValidator.parseSendRateHz("1"), 1)
        XCTAssertNil(AppSettingsValidator.parseSendRateHz("0"))
        XCTAssertNil(AppSettingsValidator.parseSendRateHz("61"))

        XCTAssertEqual(AppSettingsValidator.parseMotionRateHz("60"), 60)
        XCTAssertNil(AppSettingsValidator.parseMotionRateHz("0"))
        XCTAssertNil(AppSettingsValidator.parseMotionRateHz("61"))

        XCTAssertEqual(AppSettingsValidator.parseTimeoutMs("250"), 250)
        XCTAssertEqual(AppSettingsValidator.parseTimeoutMs("100"), 100)
        XCTAssertEqual(AppSettingsValidator.parseTimeoutMs("5000"), 5000)
        XCTAssertNil(AppSettingsValidator.parseTimeoutMs("99"))
        XCTAssertNil(AppSettingsValidator.parseTimeoutMs("5001"))
    }

    func testSettingsValidatorRejectsUnsafePortRateAndTimeoutValues() {
        XCTAssertNil(AppSettingsValidator.parsePort("-1"))
        XCTAssertNil(AppSettingsValidator.parsePort("abc"))
        XCTAssertNil(AppSettingsValidator.parsePort("12.5"))
        XCTAssertNil(AppSettingsValidator.parseSendRateHz("-1"))
        XCTAssertNil(AppSettingsValidator.parseSendRateHz("abc"))
        XCTAssertNil(AppSettingsValidator.parseSendRateHz("30.5"))
        XCTAssertNil(AppSettingsValidator.parseSendRateHz("0"))
        XCTAssertNil(AppSettingsValidator.parseSendRateHz("61"))
        XCTAssertNil(AppSettingsValidator.parseTimeoutMs("-1"))
        XCTAssertNil(AppSettingsValidator.parseTimeoutMs("abc"))
        XCTAssertNil(AppSettingsValidator.parseTimeoutMs("250.5"))
        XCTAssertNil(AppSettingsValidator.parseTimeoutMs("99"))
        XCTAssertNil(AppSettingsValidator.parseTimeoutMs("5001"))
    }

    func testSettingsValidatorRejectsInvalidSettingsAndSanitizesValidSettings() throws {
        var invalid = AppSettings.defaults
        invalid.windowsHost = " "
        invalid.telemetryPort = 0
        invalid.headTrackingPort = 70000
        invalid.motionUpdateHz = 90
        invalid.headTrackingSendHz = 80
        invalid.headTrackingTimeoutMs = 50

        let invalidResult = AppSettingsValidator.validate(invalid)

        XCTAssertFalse(invalidResult.isValid)
        XCTAssertNil(invalidResult.sanitizedSettings)
        XCTAssertFalse(invalidResult.messages(for: .windowsHost).isEmpty)
        XCTAssertFalse(invalidResult.messages(for: .telemetryPort).isEmpty)
        XCTAssertFalse(invalidResult.messages(for: .headTrackingPort).isEmpty)
        XCTAssertFalse(invalidResult.messages(for: .motionUpdateHz).isEmpty)
        XCTAssertFalse(invalidResult.messages(for: .headTrackingSendHz).isEmpty)
        XCTAssertFalse(invalidResult.messages(for: .headTrackingTimeoutMs).isEmpty)

        var valid = AppSettings.defaults
        valid.windowsHost = " 10.0.0.5 "
        valid.demoModeEnabled = false

        let validResult = AppSettingsValidator.validate(valid)
        let sanitized = try XCTUnwrap(validResult.sanitizedSettings)

        XCTAssertTrue(validResult.isValid)
        XCTAssertEqual(sanitized.windowsHost, "10.0.0.5")
        XCTAssertFalse(sanitized.demoModeEnabled)
    }

    @MainActor
    func testViewModelDoesNotPersistInvalidSettings() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        var saved = AppSettings.defaults
        saved.windowsHost = "10.0.0.9"
        store.save(saved)

        let viewModel = FPVHUDViewModel(
            motionService: MockMotionService(),
            settingsStore: store
        )
        var invalid = saved
        invalid.windowsHost = ""
        invalid.telemetryPort = 0

        let didApply = viewModel.applySettings(invalid)

        XCTAssertFalse(didApply)
        XCTAssertEqual(store.load(), saved)
        XCTAssertEqual(viewModel.settings.windowsHost, saved.windowsHost)
    }

    func testHeadTrackingSendGateRequiresEnabledCenteredActiveAndValidSettings() {
        let now = Date()
        var settings = AppSettings.defaults
        settings.trackingEnabled = false
        let active = HeadTrackingSafety.status(
            trackingEnabled: true,
            hasCentered: true,
            sampleTimestamp: now,
            now: now
        )

        XCTAssertFalse(
            HeadTrackingSafety.canSend(settings: settings, status: active, hasCentered: true)
        )

        settings.trackingEnabled = true

        XCTAssertFalse(
            HeadTrackingSafety.canSend(settings: settings, status: active, hasCentered: false)
        )
        XCTAssertTrue(
            HeadTrackingSafety.canSend(settings: settings, status: active, hasCentered: true)
        )
        XCTAssertFalse(
            HeadTrackingSafety.canSend(settings: settings, status: .readyNotCentered, hasCentered: false)
        )
        XCTAssertFalse(
            HeadTrackingSafety.canSend(settings: settings, status: .stale, hasCentered: true)
        )
        XCTAssertFalse(
            HeadTrackingSafety.canSend(settings: settings, status: .error, hasCentered: true)
        )
    }

    func testHeadTrackingSendGateBlocksAgainAfterCalibrationReset() {
        var settings = AppSettings.defaults
        settings.trackingEnabled = true

        XCTAssertTrue(
            HeadTrackingSafety.canConfigureSender(settings: settings, hasCentered: true)
        )
        XCTAssertFalse(
            HeadTrackingSafety.canConfigureSender(settings: settings, hasCentered: false)
        )
    }

    func testHeadTrackingSendGateRejectsInvalidSettingsBeforeSenderStart() {
        var settings = AppSettings.defaults
        settings.trackingEnabled = true
        settings.windowsHost = ""

        XCTAssertFalse(
            HeadTrackingSafety.canConfigureSender(settings: settings, hasCentered: true)
        )
        XCTAssertFalse(
            HeadTrackingSafety.canSend(settings: settings, status: .active, hasCentered: true)
        )
    }

    @MainActor
    func testAppRestartDoesNotPersistCalibrationAsValid() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings.defaults
        settings.trackingEnabled = true
        store.save(settings)

        let firstLaunch = FPVHUDViewModel(
            motionService: MockMotionService(),
            settingsStore: store
        )
        firstLaunch.centerTracking()
        XCTAssertEqual(store.load(), settings)

        let restarted = FPVHUDViewModel(
            motionService: MockMotionService(),
            settingsStore: store
        )

        XCTAssertTrue(restarted.settings.trackingEnabled)
        XCTAssertFalse(
            HeadTrackingSafety.canConfigureSender(settings: restarted.settings, hasCentered: false)
        )
    }

    private func realTelemetrySettings() -> AppSettings {
        var settings = AppSettings.defaults
        settings.demoModeEnabled = false
        return settings
    }

    private func makeLiveTelemetry(timestamp: Date) -> TelemetryState {
        TelemetryState(
            timestamp: timestamp,
            batteryVoltage: 14.8,
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
            panTiltMode: .disabled,
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

    private func fixtureData(_ name: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: repoRoot.appendingPathComponent("tests/fixtures/\(name)"))
    }

    private func assertHeadTrackingFixtureSchema(
        _ name: String,
        enabled: Bool,
        centered: Bool
    ) throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any]
        )

        XCTAssertEqual(object["protocol_version"] as? Int, 1)
        XCTAssertNotNil(object["seq"] as? Int)
        XCTAssertNotNil(object["timestamp_ms"] as? Int)
        XCTAssertNotNil(object["yaw_deg"] as? Double)
        XCTAssertNotNil(object["pitch_deg"] as? Double)
        XCTAssertNotNil(object["roll_deg"] as? Double)
        XCTAssertEqual(object["tracking_enabled"] as? Bool, enabled)
        XCTAssertEqual(object["centered"] as? Bool, centered)
        XCTAssertEqual(object["timeout_ms"] as? Int, 250)
    }

    private func inspectNAL(type: UInt8) throws -> H265NALInspection {
        let packet = makeRTPPacket(
            payloadType: 96,
            sequenceNumber: UInt16(type),
            timestamp: 100,
            ssrc: 200,
            payload: makeH265NALHeader(type: type) + [0x00]
        )
        let header = try RTPDiagnosticParser.parseHeader(packet)
        return try RTPDiagnosticParser.inspectH265Payload(packet, header: header)
    }

    private func makeRTPPacket(
        payloadType: UInt8,
        sequenceNumber: UInt16,
        timestamp: UInt32,
        ssrc: UInt32,
        payload: [UInt8]
    ) -> Data {
        var bytes: [UInt8] = [
            0x80,
            payloadType & 0x7F,
            UInt8(sequenceNumber >> 8),
            UInt8(sequenceNumber & 0xFF),
            UInt8(timestamp >> 24),
            UInt8((timestamp >> 16) & 0xFF),
            UInt8((timestamp >> 8) & 0xFF),
            UInt8(timestamp & 0xFF),
            UInt8(ssrc >> 24),
            UInt8((ssrc >> 16) & 0xFF),
            UInt8((ssrc >> 8) & 0xFF),
            UInt8(ssrc & 0xFF)
        ]
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    private func makeH265NALHeader(type: UInt8) -> [UInt8] {
        [(type & 0x3F) << 1, 0x01]
    }
}
