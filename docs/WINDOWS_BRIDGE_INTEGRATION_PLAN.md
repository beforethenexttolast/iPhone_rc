# Windows Bridge Integration Plan

This plan defines the first real Windows ground-station integration milestone for the iPhone FPV HUD app.

The first milestone is log-only. It forwards normalized telemetry to the iPhone and receives iPhone head-tracking intent packets, but it must not map those packets to CRSF channels, servos, the gimbal, or vehicle control.

## Architecture

The intended data flow is:

```text
Car / ELRS / CRSF telemetry
  -> Windows ground station decode / merge / normalize
  -> UDP JSON telemetry snapshot
  -> iPhone FPV HUD
```

```text
iPhone Core Motion
  -> iPhone head-tracking UDP JSON intent
  -> Windows ground station validation / stale tracking / logging
  -> no control output in the first milestone
```

Authority rules:

- Windows remains the final control authority.
- The iPhone never talks directly to firmware, ELRS, CRSF, servos, ESCs, or the camera gimbal.
- The iPhone sends camera-look intent only.
- Firmware must not trust the iPhone directly.
- Any future pan/tilt mapping must happen inside Windows after a separate safety review.
- APFPV video remains a separate direct camera-to-iPhone path and should not be coupled to the Windows bridge.

## Required Windows Components

The real Windows app should add these components behind existing ground-station ownership boundaries:

- Telemetry snapshot publisher.
- iPhone head-tracking UDP receiver.
- Head-tracking packet validator.
- Stale-state tracker.
- Packet-rate calculator.
- Debug UI/log panel.
- Bridge configuration model.
- Runtime enable/disable control.
- Non-blocking warning/error reporting.

Keep these components independent from joystick input, mixer output, failsafe logic, and CRSF output code in the first milestone.

## Configuration

Minimum configuration fields:

- Bridge enabled/disabled.
- iPhone IP address or hostname.
- Telemetry output UDP port, default `5601`.
- Head-tracking input UDP port, default `5602`.
- Head-tracking packet timeout, default `300 ms`.
- Telemetry publish rate.

Recommended debug-only fields:

- Bind address for head-tracking UDP input, default `0.0.0.0`.
- Last send error.
- Last receive error.
- Valid packet count.
- Invalid packet count.
- Last valid packet age.

Safe defaults:

- Bridge disabled is acceptable for production startup.
- If bridge defaults enabled for bench builds, it must still be log-only.
- No CRSF/pan/tilt output may be enabled by this bridge setting.
- Invalid config must prevent socket start and must show a clear warning.

## Telemetry Forwarding

Windows should publish normalized telemetry snapshots using the contract in `docs/PROTOCOL_CONTRACT.md` and `schemas/telemetry_snapshot.schema.json`.

Recommended fields:

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

Update rate:

- Start with `10...20 Hz` for bench testing.
- Avoid tying telemetry publish rate to render frame rate.
- Avoid blocking control loops on UDP send.

Stale behavior:

- If upstream telemetry is stale or unavailable, Windows should either stop sending snapshots or send snapshots with explicit stale/unknown fields.
- The iPhone already treats no valid telemetry for `>1 s` as stale and `>3 s` as lost.
- Lost telemetry must not keep old speed, gear, ERS, battery, LQ, RSSI, or SNR looking live.

Unknown/null behavior:

- Optional unknown fields may be omitted or set to `null` only where the schema allows it.
- Empty `warning` means no warning.
- Unknown enum tokens should be avoided; use documented values or `UNKNOWN` where allowed.
- Extra fields are allowed but must not activate control behavior.

## Head-Tracking Receive

Windows should receive iPhone packets using the contract in `docs/PROTOCOL_CONTRACT.md` and `schemas/head_tracking_packet.schema.json`.

Required fields:

- `seq`
- `timestamp_ms`
- `yaw_deg`
- `pitch_deg`
- `roll_deg`
- `tracking_enabled`

Recommended fields:

- `protocol_version`
- `centered`
- `timeout_ms`

Validation rules:

- Packet must be valid JSON object.
- `protocol_version`, if present, must be supported.
- `seq` must be a non-negative integer.
- `timestamp_ms` must be a non-negative integer.
- `yaw_deg`, `pitch_deg`, and `roll_deg` must be finite numbers.
- Yaw/pitch/roll must be inside documented debug ranges.
- `tracking_enabled` must be boolean.
- `centered`, when present, must be boolean.
- `timeout_ms`, when present, must be a positive integer in the accepted range.
- Malformed packets must be rejected without replacing the last valid packet state.

Runtime tracking:

- Compute packet age using Windows receive time as the authority.
- Log sender timestamp delta for diagnostics, but do not depend on clock sync.
- Calculate packet rate over a rolling one-second window.
- Track sequence increments and report gaps or regressions.
- Mark head tracking stale if no valid packet arrives for more than the configured timeout, default `300 ms`.

Centered/tracking handling:

- `tracking_enabled=false`: valid input, but state is inactive/log-only.
- `tracking_enabled=true` and `centered != true`: valid input, but not ready for future control.
- `tracking_enabled=true` and `centered=true`: valid active intent for logging only in this milestone.
- None of these states may produce control output in the first milestone.

## Safety States

Use explicit bridge states in the Windows UI/logs:

- `disabled`: bridge disabled; sockets closed or ignored.
- `receiving`: packets are arriving and being validated.
- `ready`: packets are valid enough for logging, but not active or not centered.
- `active_log_only`: packets are fresh, tracking is enabled, and centered is true; still no output.
- `stale`: no valid packet within timeout.
- `invalid`: last received packet was malformed or semantically invalid.
- `fault`: configuration error, socket failure, repeated validation failures, or internal bridge error.

State-to-output rule for the first milestone:

| State | CRSF output | Servo/gimbal output | Logging |
| --- | --- | --- | --- |
| `disabled` | No | No | Optional |
| `receiving` | No | No | Yes |
| `ready` | No | No | Yes |
| `active_log_only` | No | No | Yes |
| `stale` | No | No | Yes |
| `invalid` | No | No | Yes |
| `fault` | No | No | Yes |

## Log-Only Milestone

Before any future active control mapping, the log-only milestone must prove:

- Telemetry snapshots reach the iPhone/Simulator.
- iPhone head-tracking packets reach Windows.
- Packet schema validation is correct.
- Malformed packets are rejected safely.
- Last valid state is not overwritten by invalid packets.
- Packet age and packet rate are visible.
- Stale timeout works.
- Centered/not-centered state is visible.
- Tracking enabled/disabled state is visible.
- Restarting the bridge clears stale state.
- Disabling the bridge closes sockets or ignores traffic.
- No joystick/control flow is affected.
- No CRSF output changes occur.

Expected debug UI/log output:

- Bridge enabled state.
- iPhone telemetry target IP/port.
- Head-tracking input bind address/port.
- Last valid packet age.
- Packet rate.
- Sequence number.
- Sequence gaps or warnings.
- Yaw, pitch, roll.
- `tracking_enabled`.
- `centered`.
- State: `disabled`, `receiving`, `ready`, `active_log_only`, `stale`, `invalid`, or `fault`.
- Valid and invalid packet counts.
- Last concise error.

## Future Active Pan/Tilt Milestone

Active mapping is not part of the first Windows bridge milestone.

A future active milestone requires a separate design review and must include:

- Explicit operator arm control in Windows.
- Clear operator disarm control in Windows.
- Manual override from the current DualShock/right-stick pan/tilt source.
- Priority rules between manual input and iPhone head tracking.
- Configurable yaw -> pan mapping.
- Configurable pitch -> tilt mapping.
- Roll ignored initially.
- Axis sign flips validated on a real iPhone mount.
- Center offset handling.
- Conservative pan/tilt limits.
- Input deadband.
- Smoothing.
- Output rate limiting.
- Stale fail-safe.
- Invalid-packet fail-safe.
- Fault state.
- Bench test with output disconnected.
- Bench test with gimbal mechanically constrained.

No active milestone should begin until real iPhone Core Motion axes, mounting orientation, packet stale behavior, and manual override behavior have been validated.

## Tests

### Fake iPhone Sender To Windows

Run the Windows bridge or Python harness, then send fake iPhone packets:

```sh
python3 scripts/send_fake_head_tracking.py --host <windows-ip> --port 5602 --duration 5 --pattern sine
```

Expected result:

- Valid packets are logged.
- Packet rate is near send rate.
- State becomes `active_log_only` when packets are fresh, enabled, and centered.
- No control output changes.

### Windows To iOS Simulator Telemetry

Run the bridge with telemetry output to Simulator:

```sh
python3 scripts/iphone_companion_bridge.py --iphone-host 127.0.0.1 --telemetry-port 5601 --duration 30
```

Expected result:

- iOS Simulator receives live telemetry.
- Packet age updates in Debug / Setup.
- Stale/lost behavior works when telemetry stops.

### Malformed Packet

Send malformed packets:

```sh
python3 scripts/send_fake_head_tracking.py --host <windows-ip> --port 5602 --malformed
python3 scripts/send_fake_head_tracking.py --host <windows-ip> --port 5602 --duration 3 --malformed-every 10
```

Expected result:

- Malformed packets are rejected.
- Invalid count increases.
- Current valid state is not replaced by invalid data.
- No control output changes.

### Stale Timeout

Send packets briefly, then stop:

```sh
python3 scripts/send_fake_head_tracking.py --host <windows-ip> --port 5602 --duration 2 --pattern static
```

Expected result:

- State becomes stale after no valid packet arrives for more than the configured timeout.
- Stale state is visible in UI/logs.
- No control output changes.

### Restart Behavior

1. Start bridge.
2. Send valid packets.
3. Stop bridge.
4. Restart bridge.

Expected result:

- Valid/invalid counts reset or clearly indicate session boundaries.
- Last packet age resets.
- State starts as `disabled`, `receiving`, or `ready` depending on config.
- Stale state from the previous session is not treated as fresh.
- No control output changes.

## Porting Checklist From Python Reference Bridge

Use `scripts/iphone_companion_bridge.py` and `scripts/reference_iphone_bridge.py` as behavior references, not production code.

Checklist:

- Add Windows config fields:
  - bridge enabled
  - iPhone IP
  - telemetry output port
  - head-tracking input port
  - packet timeout
  - telemetry publish rate
- Add UDP telemetry publisher.
- Add normalized telemetry snapshot builder from existing ground-station telemetry state.
- Add head-tracking UDP receiver.
- Add packet JSON parser.
- Add schema/semantic validator.
- Add packet age calculation from Windows receive time.
- Add packet-rate calculation.
- Add sequence tracking and gap warnings.
- Add stale timeout state.
- Add valid/invalid counters.
- Add concise malformed-packet logging.
- Add debug UI/log panel.
- Add bridge enable/disable lifecycle.
- Ensure bridge disabled opens no sockets or ignores traffic.
- Ensure invalid config prevents socket start.
- Ensure no joystick/control/mixer/failsafe code depends on the bridge state.
- Ensure no CRSF output path reads iPhone yaw/pitch/roll.
- Add unit tests for packet validation.
- Add integration test using `send_fake_head_tracking.py`.
- Add telemetry-to-iOS Simulator test using the iPhone app.
- Add restart/stale tests.
- Document any deviations from the protocol contract.

## Explicit Non-Implementation Statement

The first Windows bridge milestone must not implement CRSF channel 9/10 mapping.

It must not move servos.

It must not command the camera gimbal.

It must not command the car.

It must not produce any control output from iPhone packets.

It must only forward telemetry to the iPhone and log validated iPhone head-tracking intent.
