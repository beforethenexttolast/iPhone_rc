# W17 Windows Bridge Handoff

Last updated: 2026-07-08

This document records the current handoff state between the W17 iPhone FPV HUD app and the Windows ground-station bridge.

Ownership boundary:

- `iPhone_rc` is maintained in ChatGPT Codex sessions.
- Windows, firmware, and manual-side work are maintained separately with Claude Code.
- Do not modify Windows or firmware repositories from this iPhone Codex session.
- Do not touch `/Users/vitaliykhomenko/Documents/Codex/w17-rc-print-codex` from this iPhone repo work.

Reference Windows checkpoint (read-only):

- `w17-ground-station` `HEAD` / `origin/main`: `9e57a2e`
- Windows W1/W2/W3 are reported implemented, committed, and pushed.
- Bridge integration test plan is committed at `w17-ground-station/docs/iphone_windows_bridge_test_plan.md`.
- Real-device iPhone <-> Windows validation is still pending unless later evidence says otherwise.

## A. Architecture

The W17 bridge keeps the existing authority model:

```text
Windows ground station
  -> final control authority / integration point

iPhone FPV HUD
  -> thin HUD + telemetry client + head-tracking intent source

Firmware
  -> consumes only final already-arbitrated control outputs later
```

Data paths:

- Windows sends normalized telemetry snapshots to the iPhone over UDP `5601`.
- iPhone sends head-tracking intent packets to Windows over UDP `5602`.
- Firmware does not parse iPhone UDP.
- Firmware does not parse iPhone JSON.
- Firmware does not receive iPhone packets.
- APFPV/OpenIPC video is separate from this telemetry/head-tracking bridge.

There is no iPhone -> firmware path and no iPhone -> car-control path in the current contract.

## B. W2 Status: Windows -> iPhone Telemetry

Current Windows-side status:

- W2 telemetry sender is implemented in `w17-ground-station`.
- Windows sends iPhone-compatible UDP JSON telemetry snapshots.
- Telemetry uses snake_case JSON fields matching the iPhone contract.
- Windows owns CRSF/ELRS decoding, merging, and normalization.
- The iPhone app receives normalized snapshots only and must not parse raw CRSF.
- Real-device iPhone validation is still required.

Compatibility details:

- Unknown values are omitted rather than faked as zero.
- Windows includes stale/unknown status instead of presenting stale car fields as fresh.
- The W2 integer-normalization patch is implemented for iPhone `JSONDecoder` compatibility.
- Swift `Int` fields are normalized as JSON integers:
  - `link_quality`
  - `ers_percent`
  - `gear`
  - `rssi_dbm`
- `timestamp_ms` is normalized as a non-negative JSON integer.
- Double fields remain numeric/fractional where appropriate:
  - `battery_v`
  - `snr_db`
  - `speed_kmh`
  - `throttle`
  - `brake`
  - `steering`
  - `camera_yaw_deg`
  - `camera_pitch_deg`

iPhone expectations:

- Fresh packets show live HUD values.
- Missing/unknown values must not appear as fake zeros.
- If telemetry stops, the iPhone shows stale after about `1 s`.
- If telemetry is lost for more than about `3 s`, unsafe values clear to placeholders:
  - battery
  - link quality
  - RSSI
  - SNR
  - gear
  - ERS
  - speed
  - source/mode

## C. W3 Status: iPhone -> Windows Head Tracking

Current Windows-side status:

- W3 head-tracking receiver is implemented in `w17-ground-station`.
- Windows receives and validates iPhone head-tracking intent packets on UDP `5602`.
- Windows tracks diagnostic/log-only state.
- W3 is log-only.
- W3 does not produce CRSF output.
- W3 does not produce servo output.
- W3 does not produce pan/tilt output.
- W3 does not affect joystick/control flow.

Windows should classify packets and states using the canonical head-tracking contract:

- Valid fresh enabled + centered packets may become an active/log-only diagnostic state.
- `tracking_enabled=false` packets are valid but inactive.
- `centered=false` or missing/false centered state is not ready for future control.
- Uncalibrated/not-centered input is ignored for any control use.
- Malformed packets are rejected and must not replace the last valid state.
- Stale packets are rejected/ignored safely.

Safe rejection/ignore cases include:

- malformed JSON
- wrong shape or missing required fields
- invalid numeric ranges
- disabled tracking
- uncentered tracking
- uncalibrated tracking
- stale packet stream
- sequence/timestamp diagnostics that indicate restart, gap, or regression

For this milestone, every one of those cases is diagnostic only. None may command hardware.

## D. Safety Boundary

The current bridge does not authorize active camera movement.

Explicitly not implemented:

- No active pan/tilt.
- No iPhone -> CRSF path.
- No iPhone -> servo path.
- No iPhone -> firmware UDP/JSON path.
- No iPhone -> direct vehicle-control path.
- No firmware awareness of iPhone UDP/JSON.

Active pan/tilt requires a separate reviewed safety milestone. That milestone must include at minimum:

- Operator enable/arm control.
- Operator disarm/disable control.
- Manual override behavior.
- Priority rules between manual/gamepad input and iPhone head tracking.
- Real iPhone axis validation.
- Real phone mount orientation validation.
- Physical endpoint limits.
- Configurable sign flips.
- Center offset handling.
- Deadband.
- Smoothing.
- Rate limiting.
- Stale timeout behavior.
- Stale decay-to-center or hold/disable decision.
- Invalid-packet rejection.
- Bench-only servo validation.
- Servo testing with conservative limits.
- No vehicle driving during first active pan/tilt tests.

Until that milestone is explicitly approved, W3 remains log-only.

## E. Canonical Contract Ownership

Canonical iPhone/Windows bridge contract ownership:

- `iPhone_rc` owns the canonical packet contract.
- `iPhone_rc/schemas/` owns the canonical JSON schemas.
- `iPhone_rc/examples/` owns canonical example packets.
- `w17-ground-station` keeps an implementation copy for Windows-side development.

Current canonical iPhone files:

- `docs/PROTOCOL_CONTRACT.md`
- `docs/windows_bridge_contract.md`
- `schemas/telemetry_snapshot.schema.json`
- `schemas/head_tracking_packet.schema.json`
- `examples/telemetry_snapshot.example.json`
- `examples/head_tracking_packet.example.json`

Change rule:

- Any contract change must update both sides.
- Any schema change must be deliberate and reviewed.
- Future Codex sessions must not invent fields.
- Future Codex sessions must not casually change schemas.
- Windows implementation docs may record implementation status, but they must not contradict the iPhone canonical schemas/examples.

No schema change is required by the current W2/W3 status update.

## F. What To Do Next

Next bridge validation should use the Windows test plan:

- `w17-ground-station/docs/iphone_windows_bridge_test_plan.md`

Run real iPhone <-> Windows bridge validation:

1. Confirm Windows ground station is at the intended checkpoint or newer.
2. Confirm iPhone repo is at the intended checkpoint.
3. Put Windows and iPhone on the same Wi-Fi/LAN.
4. Enable Windows telemetry sender for UDP `5601`.
5. Disable iPhone demo telemetry.
6. Confirm iPhone receives Windows telemetry on UDP `5601`.
7. Confirm iPhone stale/lost telemetry behavior if Windows telemetry stops.
8. Validate iOS Local Network permission.
9. Validate iOS Motion permission.
10. Configure iPhone Windows host/IP and head-tracking UDP `5602`.
11. Confirm no head-tracking packets are sent until tracking is enabled and centered/calibrated.
12. Confirm Windows receives head-tracking packets on UDP `5602`.
13. Confirm Windows shows/logs packet age, packet rate, yaw, pitch, roll, tracking enabled, centered, malformed count, stale state, and sequence diagnostics.
14. Confirm malformed, disabled, uncentered, uncalibrated, and stale packets do not update usable control state.
15. Keep active pan/tilt blocked.

Evidence to capture:

- Windows commit hash and clean status.
- iPhone commit hash and clean status.
- Windows console/log output for W2/W3.
- iPhone Debug / Setup packet age and sender status.
- iOS Local Network permission state.
- iOS Motion permission state.
- Sample telemetry packet.
- Sample head-tracking packet.
- Stale/lost telemetry screenshots.
- Proof that no CRSF/servo/pan-tilt output occurred.

## G. What Not To Do

Do not:

- Implement active pan/tilt.
- Map iPhone head tracking to CRSF.
- Map iPhone head tracking to servo output.
- Modify firmware for iPhone UDP/JSON.
- Add an iPhone-to-firmware side channel.
- Add an iPhone-to-control path.
- Treat W3 log-only validation as physical camera-control validation.
- Treat simulator mock motion as real iPhone axis validation.
- Treat telemetry receive success as proof of video/APFPV readiness.
- Change iPhone schemas without updating Windows implementation docs/tests.
- Touch `/Users/vitaliykhomenko/Documents/Codex/w17-rc-print-codex`.

## Notes For Future Codex Sessions

This repo is the iPhone-side source of truth for the bridge contract. Windows status can move independently, but iPhone docs/schemas/examples should remain conservative and compatibility-focused.

Before changing schemas or packet fields:

1. Check the Windows implementation copy.
2. Check the Windows bridge tests.
3. Update examples and fixtures.
4. Update validation scripts.
5. Run both sides' test suites where available.

Do not use this handoff as permission to implement active control.
