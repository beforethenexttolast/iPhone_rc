# Current State Onboarding

Last updated: 2026-07-08

This document is an onboarding snapshot for the existing W17 iPhone FPV HUD and head-tracking companion app. It does not propose new app behavior. It records what is currently present, what is protected by tests/docs, and what remains unvalidated until real hardware is available.

## System Boundary

The iPhone app is a thin FPV/HUD/head-tracking companion client. The Windows ground station remains the central authority and control hub.

The iPhone app currently:

- Displays a native SwiftUI Drive / FPV HUD with demo or UDP telemetry.
- Provides a Debug / Setup mode and settings sheet.
- Receives Windows-normalized telemetry snapshots over UDP JSON.
- Sends head-tracking yaw/pitch/roll intent packets to Windows over UDP JSON.
- Provides simulator/mock motion controls for no-hardware testing.
- Provides diagnostic-only APFPV RTP/H.265 packet inspection.

The iPhone app does not:

- Send CRSF.
- Talk directly to car firmware.
- Directly command servos, ESCs, the gimbal, or the car.
- Map head tracking to CRSF channels 9/10.
- Decode APFPV H.265 video or replace the mock video surface.

## App Architecture

### Entry Point And State

- `FPVHUDApp/App/FPVHUDApp.swift` is the SwiftUI app entry point and creates one `FPVHUDViewModel`.
- `FPVHUDApp/App/FPVHUDViewModel.swift` is the main `@MainActor` coordinator. It owns UI-facing state, settings, telemetry display state, motion state, head-tracking display state, and APFPV diagnostic status.
- Service callbacks are marshaled back to the main actor before updating UI state.
- Head-tracking send pacing and motion-status refresh use `DispatchSourceTimer` instead of main-run-loop timers.

### SwiftUI Screens

- `FPVHUDApp/UI/Screens/RootView.swift` switches between Drive / FPV mode and Debug / Setup mode.
- `FPVHUDApp/UI/HUD/FPVHUDView.swift` contains the Drive HUD, Debug HUD, and related widgets.
- Drive mode is video-first and AR-style: top telemetry strip, floating speed, compact input indicators, compact head-tracking chip, warning chip, and placeholder video.
- Debug / Setup mode is a scrollable utility layout with panels for motion, mock motion, telemetry, head sender, car snapshot, APFPV diagnostics, and network settings.
- `FPVHUDApp/UI/Screens/SettingsPanelView.swift` contains the settings form and validation messaging.
- `FPVHUDApp/UI/Components/HUDComponents.swift` contains shared HUD styling primitives.

### Settings And Persistence

- `FPVHUDApp/Settings/AppSettings.swift` defines runtime settings and validation helpers.
- `SettingsStore` is a small `UserDefaults` wrapper in the same file.
- Defaults are conservative:
  - Demo telemetry defaults on.
  - Tracking defaults off.
  - APFPV diagnostics default off.
  - Head-tracking calibration is not persisted.
- `SettingsStore.save` intentionally does not persist `apfpvDiagnosticEnabled`, so APFPV diagnostics must be re-enabled per session.
- Invalid settings are not persisted and do not restart services.

### Telemetry

- `FPVHUDApp/Telemetry/DemoTelemetrySource.swift` animates demo telemetry for simulator/no-hardware use.
- `FPVHUDApp/Telemetry/TelemetryService.swift` defines the telemetry source seam, JSON decoding, and freshness states.
- `FPVHUDApp/Networking/UDPTelemetryReceiver.swift` uses `Network.framework` UDP receive and owns its mutable listener/connection/staleness state on a private queue.
- `FPVHUDApp/Models/TelemetryState.swift` separates raw telemetry from `TelemetryDisplayState`, which is what the HUD actually renders.

### Motion And Head Tracking

- `FPVHUDApp/Motion/MotionService.swift` defines the motion service interface and selects a simulator mock or real CoreMotion implementation.
- `FPVHUDApp/Motion/CoreMotionService.swift` uses `CMMotionManager` with `.xArbitraryCorrectedZVertical`.
- `FPVHUDApp/Motion/MockMotionService.swift` provides simulator yaw/pitch/roll controls through the same raw motion pipeline.
- `FPVHUDApp/Models/MotionState.swift` holds raw and centered yaw/pitch/roll plus head-tracking state and safety helpers.
- `FPVHUDApp/Networking/HeadTrackingSender.swift` sends UDP JSON intent packets using `Network.framework` and serializes mutable sender state on a private queue.
- `FPVHUDApp/Models/HeadTrackingPacket.swift` defines packet encoding plus UI-facing `HeadTrackingDisplayState`.

### APFPV Video Diagnostics

- `FPVHUDApp/Video/VideoSurface.swift` is still a mock video placeholder.
- `FPVHUDApp/Video/FutureRTPHEVCReceiver.swift` documents the future native path:

```text
APFPV RTP/UDP H.265
  -> iPhone UDP receiver
  -> RTP/H.265 depacketizer
  -> VideoToolbox decoder
  -> video surface
  -> SwiftUI/UIKit HUD overlay
```

- `FPVHUDApp/Video/APFPVDiagnosticReceiver.swift` is diagnostic-only. It parses RTP headers, inspects H.265 NAL types when possible, tracks packets/sec, bitrate, gaps, out-of-order packets, malformed packets, last packet age, and VPS/SPS/PPS detection.
- APFPV diagnostics are shown only in Debug / Setup and do not decode video.

### Tests, Fixtures, Protocol Docs

- `FPVHUDAppTests/TelemetryParsingTests.swift` contains the current unit test suite.
- `schemas/` contains JSON schemas for telemetry snapshots and head-tracking packets.
- `examples/` contains reference protocol examples.
- `tests/fixtures/` contains golden valid/minimal/malformed telemetry and head-tracking fixtures.
- `scripts/validate_protocol_examples.py` validates examples, fixtures, and generated script packets against the checked-in schema subset.
- `scripts/dev_check.sh` is the documented local no-hardware validation entry point.

## Current Protocols

The formal packet contract is in `docs/PROTOCOL_CONTRACT.md`.

### Windows/Fake Bridge To iPhone: Telemetry Snapshot

Transport: UDP JSON.

Schema: `schemas/telemetry_snapshot.schema.json`.

Example: `examples/telemetry_snapshot.example.json`.

Primary fields:

- `protocol_version`
- `timestamp_ms`
- `battery_v`
- `link_quality`
- `rssi_dbm`
- `snr_db`
- `speed_kmh`
- `gear`
- `drive_mode`
- `ers_percent`
- `throttle`
- `brake`
- `steering`
- `camera_yaw_deg`
- `camera_pitch_deg`
- `head_tracking_mode`
- `video_lock`
- `warning`
- `stale_data_warnings`

Windows is expected to normalize and merge upstream CRSF/ELRS data before sending this JSON. The iPhone app does not parse raw CRSF in this milestone.

The formal full snapshot schema requires the core HUD fields. The app decoder is intentionally tolerant for bench testing: extra fields are ignored, missing fields can merge with the previous raw telemetry state, unknown mode tokens map to unknown values, and malformed JSON is rejected safely.

### iPhone To Windows/Fake Bridge: Head-Tracking Intent Packet

Transport: UDP JSON.

Schema: `schemas/head_tracking_packet.schema.json`.

Example: `examples/head_tracking_packet.example.json`.

Current app packet fields:

- `seq`
- `timestamp_ms`
- `yaw_deg`
- `pitch_deg`
- `roll_deg`
- `tracking_enabled`
- `centered`
- `timeout_ms`

`protocol_version` is documented as optional for v1 compatibility. The current app encoder does not include it, and the schema allows that.

These packets are camera-look intent only. They are not vehicle-control commands.

### APFPV Camera To iPhone: RTP/H.265 Diagnostics

Transport: UDP RTP/H.265, likely port `5600`, still to be proven with real APFPV captures.

Current app behavior is diagnostic-only:

- Parse RTP version, payload type, sequence number, timestamp, SSRC.
- Inspect possible H.265 NAL type.
- Identify VPS/SPS/PPS when visible.
- Track receive statistics.
- Do not assemble frames.
- Do not call VideoToolbox.
- Do not replace the Drive video surface.

## Stale And Lost Behavior

Telemetry freshness is based on local receive age, not only sender timestamp:

- Fresh: latest valid packet age `<= 1s`.
- Stale: latest valid packet age `> 1s` and `<= 3s`.
- Lost: latest valid packet age `> 3s`.

Fresh telemetry shows actual values. Stale telemetry shows a warning while values may remain visible but marked degraded. Lost telemetry clears unsafe display values to placeholders:

- Battery: `--.- V`
- LQ: `--`
- RSSI: `--`
- SNR: `--`
- Gear: `--`
- ERS: `--`
- Speed: `-- km/h`
- Source/mode: `--` or `UNKNOWN`

Turning demo telemetry off without real telemetry also resets display values to the safe unknown state.

Head tracking is considered stale by the Windows-side contract if no valid packet arrives for more than `300 ms`.

## Settings Validation

Settings validation is implemented in `AppSettingsValidator`.

Current rules:

- Host is trimmed.
- Empty host is rejected.
- Valid IPv4 is accepted.
- Simple hostnames are accepted.
- Malformed numeric IPv4 and invalid hostnames are rejected.
- Ports must be integers in `1...65535`.
- Motion rate must be in `1...60 Hz`.
- Head-tracking send rate must be in `1...60 Hz` at validation level and is clamped to `30...60 Hz` for send-loop timing.
- Head-tracking timeout must be in `100...5000 ms`.

Invalid settings show inline validation, prevent Apply, are not persisted, and do not start/reconfigure networking or sender services.

## Current Safety Properties

### Sender Gating

Head-tracking UDP sending is gated before configuration and before each send.

The sender can be configured only when:

- Settings are valid.
- Tracking is enabled.
- The user has centered/calibrated tracking.

A packet can be sent only when:

- Settings are valid.
- Tracking is enabled.
- Tracking has been centered/calibrated.
- Motion status is active.

If tracking is disabled, sending stops. If calibration is reset, sending stops again. Calibration is not persisted across app restarts.

### Calibration And Centering

The center/calibrate action stores the current raw yaw/pitch/roll as the neutral center for this app session. Displayed centered yaw/pitch/roll are derived from raw motion minus that session center.

The app exposes both raw and centered values in Debug / Setup. Simulator mock controls use the same `MotionState` pipeline as CoreMotion.

### Error Display

Raw sender/network errors are kept for Debug / Setup. Drive mode maps them to compact labels such as:

- `HEAD TX ERROR`
- `HEAD TX NET ERROR`
- `SETTINGS INVALID`

Drive mode should not display full raw `Network.NWError` strings.

### Invalid Settings

Invalid settings block Apply/Save. Tests cover invalid host, port, rate, and timeout behavior. Invalid settings also cause `HeadTrackingSafety` to block sender configuration and sends.

### Telemetry Safety

Malformed telemetry is rejected and increments malformed count. It does not corrupt the last valid safe display state. Lost telemetry clears stale values instead of showing old gear, ERS, speed, battery, link quality, RSSI, or SNR as live.

### Authority Boundary

There is no code path that maps iPhone head tracking to vehicle/gimbal output. The app sends intent packets to Windows only. Windows is responsible for any future command mixing, limits, stale handling, manual override, and CRSF channel 9/10 mapping after a separate safety milestone.

## Current Validation Status

### Checks Run During This Onboarding Pass

`scripts/dev_check.sh` was run first. The Python syntax checks and protocol/schema validation passed. The combined script then hit a simulator destination/CoreSimulator lookup failure during its Xcode build phase:

```text
Unable to find a device matching the provided destination specifier:
platform:iOS Simulator, OS:latest, name:iPhone 17
```

`xcrun simctl list devices available` then confirmed an `iPhone 17` simulator is available.

Direct Xcode validation was then run successfully:

```sh
xcodebuild -project FPVHUDApp.xcodeproj -scheme FPVHUDApp -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project FPVHUDApp.xcodeproj -scheme FPVHUDApp -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Result:

- Simulator build succeeded.
- Simulator unit tests succeeded.
- 52 tests executed.
- 0 failures.

### Unit Test Coverage

Current tests cover:

- Settings store defaults, save/load, reset, corrupt-data fallback.
- APFPV diagnostic enable not being persisted.
- Settings validation for hostnames, IPv4, ports, rates, and timeouts.
- Invalid settings not being persisted through the view model.
- Telemetry JSON decoding.
- Missing telemetry fields.
- Malformed telemetry rejection.
- Telemetry control-value clamping.
- Telemetry freshness thresholds.
- Fresh/stale/lost display behavior.
- Lost telemetry clearing unsafe display values.
- Demo-off reset to unknown display state.
- Gear/ERS/speed not remaining after telemetry loss.
- Head-tracking packet sequence/timestamp/encoding.
- Compact Drive labels for head-tracking status/errors.
- Calibration and send gating.
- App restart not persisting calibration as valid.
- Mock motion controls and raw motion pipeline.
- RTP header parsing and synthetic H.265 NAL inspection.
- Golden fixtures and schema-compatible generated script packets.

### Scripts And Docs

No-hardware scripts exist for:

- Sending demo telemetry to the app.
- Receiving iPhone head-tracking packets.
- Sending fake iPhone head-tracking packets.
- Running a log-only bridge harness.
- Running a standalone reference bridge.
- Sending synthetic RTP/H.265-like packets.
- Validating protocol examples/fixtures.

Primary workflow docs:

- `docs/BENCH_TEST_RUNBOOK.md`
- `docs/SIMULATOR_TESTING.md`
- `docs/REAL_IPHONE_BENCH_TEST_PLAN.md`
- `docs/OPENIPC_APFPV_DIAGNOSTIC_TEST_PLAN.md`
- `docs/WINDOWS_BRIDGE_INTEGRATION_PLAN.md`
- `docs/WINDOWS_BRIDGE_LOG_ONLY_TEST.md`
- `docs/FUTURE_HEAD_TRACKING_TO_PAN_TILT_SAFETY.md`
- `docs/FIRST_ACTIVE_PAN_TILT_MILESTONE.md`
- `docs/ROADMAP_AND_DECISIONS.md`

## Not Yet Validated On Real Hardware

The following are explicitly pending:

- Real iPhone install/signing/provisioning flow.
- Real iPhone landscape-only behavior with notch/Dynamic Island/safe areas.
- iOS Local Network permission prompt behavior.
- Real iPhone Core Motion yaw/pitch/roll axes.
- Real phone mount orientation.
- Real Core Motion drift and update stability.
- Real UDP reachability between iPhone and Mac/Windows on Wi-Fi.
- Real head-tracking packet rate and stale behavior on device.
- Real OpenIPC/APFPV camera packet capture.
- APFPV UDP port, payload type, SSRC behavior, packetization, VPS/SPS/PPS cadence, keyframe cadence, jitter, bitrate, and packet loss.
- H.265 depacketization and VideoToolbox decoding.
- Real video latency.
- Integration with the actual Windows ground-station repository.

## Integration Assumptions

### What Windows Must Provide

Windows must:

- Remain the final control authority.
- Decode/merge upstream firmware/CRSF/ELRS telemetry.
- Forward normalized UDP JSON telemetry snapshots to the iPhone.
- Include battery, link quality, RSSI, SNR, speed, gear, drive mode, ERS, throttle, brake, steering, camera yaw/pitch, head/pan-tilt mode, video lock, and warnings where available.
- Mark or omit unknown data clearly.
- Avoid presenting stale upstream values as fresh.
- Provide configuration for iPhone IP, telemetry output port, head-tracking input port, bridge enabled/disabled, and stale timeout.

### What Windows Must Consume

Windows must receive and validate head-tracking intent packets:

- `seq`
- `timestamp_ms`
- `yaw_deg`
- `pitch_deg`
- `roll_deg`
- `tracking_enabled`
- `centered`
- optional `timeout_ms`
- optional `protocol_version`

The first Windows integration milestone must be log-only. It should show packet age, packet rate, yaw/pitch/roll, tracking enabled, centered, stale state, and malformed packet rejection.

### What Firmware Must Not Know

Firmware should not receive iPhone packets directly. Firmware should not trust iPhone telemetry or motion directly. Any future pan/tilt mapping must be performed by Windows after a separate safety review and must flow through existing authority, mixing, limits, and failsafe logic.

### What APFPV/Video Still Needs Proving

APFPV video is independent of Windows telemetry and head tracking. The preferred low-latency path remains direct APFPV camera -> iPhone. Before implementing VideoToolbox decode, the project still needs real captures that prove the actual UDP/RTP/H.265 stream shape.

## Risks And Unknowns

- Real iPhone Core Motion axis signs are unknown.
- Phone mount orientation is unknown.
- Motion drift and calibration stability are unknown.
- UDP packet loss/jitter on the intended Wi-Fi topology is unknown.
- iOS Local Network permission behavior must be observed on device.
- Real iPhone background/foreground behavior around UDP and motion still needs bench validation.
- APFPV stream details are not proven.
- H.265 RTP depacketization complexity is unknown until real captures exist.
- VideoToolbox decode latency is unmeasured.
- Phone/VR readability, eye comfort, brightness, and thermal behavior are untested.
- Windows bridge compatibility is unproven against the real Windows repo.
- Future pan/tilt behavior still requires manual override, operator arm, limits, smoothing, rate limiting, and stale fail-safe policy.

## Recommended Next Step

No implementation should happen as the next step unless the integration contract with Windows changes.

Recommended order:

1. Treat `docs/PROTOCOL_CONTRACT.md` and this onboarding report as the current iPhone-side contract snapshot.
2. Prepare the Windows integration contract against the real ground-station repository, preserving the log-only boundary.
3. Run the real iPhone bench plan in `docs/REAL_IPHONE_BENCH_TEST_PLAN.md` when a physical device is available.
4. Run the OpenIPC/APFPV diagnostic capture plan in `docs/OPENIPC_APFPV_DIAGNOSTIC_TEST_PLAN.md` when the camera is available.
5. Do not proceed to CRSF channel 9/10 pan/tilt mapping until the real iPhone bench test, Windows log-only bridge, and first active pan/tilt safety checklist are complete.
