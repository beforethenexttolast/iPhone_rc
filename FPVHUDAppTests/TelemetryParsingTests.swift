import XCTest
@testable import FPVHUDApp

final class TelemetryParsingTests: XCTestCase {
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
}
