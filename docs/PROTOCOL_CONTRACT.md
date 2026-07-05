# iPhone FPV HUD Protocol Contract

This document defines the current bench-test packet contract between the iPhone FPV HUD app, the future Windows ground-station bridge, and local test scripts.

The iPhone app is a thin client. Windows remains the vehicle-control authority. No packet in this contract directly commands CRSF channels, servos, ESCs, the gimbal, or the car.

## Protocol Version

Current contract version: `1`.

JSON packets may include:

```json
"protocol_version": 1
```

For compatibility with the current app and scripts, `protocol_version` is optional in version 1. Receivers should treat a missing `protocol_version` as version 1 during the bench-test phase. Future incompatible changes should increment the version and keep version handling explicit.

## Packet Directions

| Direction | Transport | Payload | Purpose |
| --- | --- | --- | --- |
| Windows or fake bridge -> iPhone | UDP JSON | Telemetry snapshot | Normalized car/link/video HUD telemetry |
| iPhone -> Windows or fake bridge | UDP JSON | Head-tracking packet | Camera-look intent only |
| APFPV camera -> iPhone | UDP RTP/H.265 | RTP packet with H.265 payload | Diagnostic receive stats only in this milestone |

## Units

| Field | Unit |
| --- | --- |
| `timestamp_ms` | milliseconds since Unix epoch unless otherwise stated by sender |
| `battery_v` | volts |
| `speed_kmh` | kilometers per hour |
| `yaw_deg`, `pitch_deg`, `roll_deg` | degrees |
| `camera_yaw_deg`, `camera_pitch_deg` | degrees |
| `rssi_dbm` | dBm |
| `snr_db` | dB |
| `link_quality` | percent, `0...100` |
| `ers_percent` | percent, `0...100` |
| `throttle`, `brake` | normalized command/input magnitude, `0.0...1.0` |
| `steering` | normalized command/input, `-1.0...1.0` |
| `timeout_ms` | milliseconds |

## Telemetry Snapshot

Direction: Windows/fake bridge -> iPhone.

Schema: `schemas/telemetry_snapshot.schema.json`

Example: `examples/telemetry_snapshot.example.json`

The Windows ground station is responsible for decoding/merging upstream CRSF/ELRS telemetry and forwarding a normalized JSON snapshot. The iPhone app does not parse raw CRSF in this milestone.

Recommended full snapshot fields:

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

Required for a full normalized snapshot:

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

Optional:

- `protocol_version`
- `warning`
- `stale_data_warnings`
- `link_state`
- `mode`
- test-only fields such as `test_sequence`

Accepted `drive_mode` tokens:

- `TRAINING`
- `GEARBOX`
- `GEARBOX_ERS`

Accepted `head_tracking_mode` tokens:

- `OFF`
- `DS4`
- `HEAD_TRACKING`
- `MIXED`

Accepted `stale_data_warnings` tokens:

- `battery`
- `linkQuality`
- `speed`
- `flightMode`
- `camera`
- `video`
- `telemetry`

## Telemetry Unknown And Null Behavior

Receivers must not crash on missing optional fields, explicit `null`, unknown enum tokens, or extra fields.

Current iPhone behavior:

- Missing telemetry fields are tolerated.
- Malformed JSON is rejected and increments the malformed count.
- Unknown drive/head-tracking tokens map to an unknown state.
- Extra fields are ignored.
- Empty `warning` is treated as no warning.

Safety display rule: stale values must not remain visually live after telemetry is lost. When telemetry is lost, unsafe stale values such as battery, LQ, RSSI, SNR, speed, gear, ERS, and source/mode should clear to unknown placeholders.

## Telemetry Freshness

The iPhone bases stale/lost state on local receive time, not only the sender timestamp.

- Fresh: latest valid telemetry packet age `<= 1.0 s`.
- Stale: latest valid telemetry packet age `> 1.0 s` and `<= 3.0 s`.
- Lost: latest valid telemetry packet age `> 3.0 s`.

Lost telemetry must not be treated as a safe stopped vehicle state unless Windows explicitly sends a fresh valid stopped state.

## Head-Tracking Packet

Direction: iPhone -> Windows/fake bridge.

Schema: `schemas/head_tracking_packet.schema.json`

Example: `examples/head_tracking_packet.example.json`

Head-tracking packets are camera-look intent only. They are not vehicle-control commands.

Required:

- `seq`
- `timestamp_ms`
- `yaw_deg`
- `pitch_deg`
- `roll_deg`
- `tracking_enabled`

Recommended:

- `centered`
- `timeout_ms`
- `protocol_version`

Current iPhone app sends `centered` and `timeout_ms`. Some fake bench scripts may omit `timeout_ms`; the bridge treats it as optional for compatibility.

## Head-Tracking Unknown And Null Behavior

Receivers must reject malformed or semantically invalid head-tracking packets. Invalid packets must not update the last valid state.

Rules:

- `seq` must be a non-negative integer.
- `timestamp_ms` must be a non-negative integer.
- `yaw_deg`, `pitch_deg`, and `roll_deg` must be finite numbers.
- `tracking_enabled` must be boolean.
- `centered`, when present, must be boolean.
- `timeout_ms`, when present, must be a positive integer.
- Extra fields must not activate control behavior.

## Head-Tracking Freshness

The Windows bridge should mark head tracking stale if no valid packet arrives for more than `300 ms`.

Recommended bridge states:

- `IDLE`: no valid packet received.
- `ACTIVE`: valid, fresh, `tracking_enabled=true`, `centered=true`.
- `INACTIVE`: valid and fresh, but `tracking_enabled=false`.
- `NOT_CENTERED`: valid and fresh, tracking enabled but `centered` is not true.
- `STALE`: last valid packet age `> 300 ms`.

Stale or invalid packets must not be mapped into pan/tilt output.

## Safety Contract

- The iPhone does not directly command the car.
- The iPhone does not send CRSF.
- The iPhone sends camera-look intent only.
- Windows remains responsible for command mixing, limits, failsafe, and any future mapping to camera pan/tilt channels 9/10.
- Head tracking must not be mapped to CRSF channels 9/10 until a later reviewed milestone.
- Stale, malformed, uncentered, disabled, or invalid head-tracking packets must not control hardware.
- Telemetry stale/lost state must be visible to the operator and must not present old values as live.

## APFPV RTP/H.265 Diagnostic Packets

Direction: APFPV camera -> iPhone.

Transport: UDP RTP carrying H.265 payloads, commonly on port `5600`.

This milestone is diagnostic-only:

- Parse RTP version, payload type, sequence number, timestamp, and SSRC.
- Track packets per second, approximate bitrate, sequence gaps, out-of-order packets, and last packet age.
- Inspect H.265 NAL type where possible, including VPS/SPS/PPS detection.
- Do not assemble H.265 frames.
- Do not call VideoToolbox.
- Do not replace the mock video surface.

The future native path remains:

```text
APFPV RTP/UDP H.265
  -> iPhone UDP receiver
  -> RTP/H.265 depacketizer
  -> VideoToolbox decoder
  -> video surface
  -> SwiftUI/UIKit HUD overlay
```

APFPV video remains independent from telemetry and head tracking.
