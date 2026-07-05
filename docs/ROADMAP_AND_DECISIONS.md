# Roadmap And Decisions

This document summarizes the current state, architectural decisions, roadmap, and decision log for the iPhone FPV HUD project.

## Current Project Status

Status: pre-hardware frozen.

What is true now:

- Simulator/dev checks are passing.
- The iOS app is prepared for first real iPhone testing.
- Real iPhone validation is pending.
- OpenIPC/APFPV real camera capture is pending.
- Windows ground-station repo integration is pending.
- APFPV VideoToolbox decoding is not implemented.
- Active pan/tilt mapping is not implemented.
- CRSF channel 9/10 mapping from iPhone head tracking is not implemented.

Validation currently covers:

- SwiftUI app build in iOS Simulator.
- Unit tests for telemetry freshness, settings validation, packet encoding, safety gates, golden fixtures, and RTP diagnostic parsing.
- Python script syntax checks.
- Protocol example and fixture validation.
- Simulator telemetry receive workflow.
- Simulator/mock head-tracking send-gating workflow.
- Log-only bridge harness behavior.

Validation does not yet cover:

- Real iPhone Core Motion axes.
- Real iPhone local-network permission behavior.
- Real iPhone Wi-Fi routing to a Mac/Windows host.
- Real OpenIPC/APFPV RTP/H.265 packets.
- Real video latency.
- Windows production bridge integration.
- Any physical pan/tilt movement.

## Core Architecture Decisions

### iPhone Is A Thin Client

The iPhone app is a display and intent device:

- FPV/HUD presentation.
- Windows-normalized telemetry display.
- Core Motion head-look intent output.
- APFPV video diagnostics now, direct video receive/decode later.

The iPhone does not own car control authority.

### Windows Remains Authority

Windows remains responsible for:

- Gamepad input.
- Command mixing.
- Limits.
- Failsafe.
- Telemetry decode/merge.
- Future decision to map head-look intent into pan/tilt channels.

### Head Tracking Is Intent Only

iPhone head tracking sends yaw/pitch/roll intent packets to Windows.

The packets are not servo commands, CRSF commands, or vehicle commands.

### No Direct iPhone To Firmware Control

The iPhone must not send directly to firmware, ELRS, CRSF, servos, ESCs, or the camera gimbal.

Any future physical output must pass through Windows authority and safety gates.

### APFPV Decoding Delayed Until Diagnostics

APFPV native video decode is delayed until real camera packet diagnostics answer:

- UDP port.
- RTP payload type.
- H.265 packetization.
- VPS/SPS/PPS availability.
- Fragmentation behavior.
- Timing model.

The app currently has a diagnostic receiver only. It does not assemble H.265 frames or call VideoToolbox.

### Portrait HUD Unsupported For Now

The product is phone FPV driving and possible VR-style phone glasses.

Portrait does not need a full HUD. The app is landscape-first/landscape-only for real use.

### Landscape-First / Landscape-Only App

The app is configured for landscape iPhone use. Drive mode is optimized for landscape, with Debug / Setup as a utility view.

## Done Milestones

- SwiftUI iPhone FPV HUD scaffold.
- Drive / FPV AR-style HUD.
- Debug / Setup mode.
- Settings panel.
- Safe settings defaults and persistence.
- Settings validation.
- Demo telemetry mode.
- UDP JSON telemetry receiver.
- Telemetry stale/lost display handling.
- Core Motion service with simulator/mock fallback.
- Simulator mock motion controls.
- Head-tracking packet model and sender.
- Head-tracking send gating requiring tracking enabled and centered.
- Compact Drive-mode head-tracking status/error display.
- UDP test scripts:
  - telemetry sender
  - head-tracking receiver
  - fake iPhone head-tracking sender
  - synthetic RTP sender
- Protocol contract.
- JSON schemas.
- Golden fixtures.
- Standalone Python reference bridge.
- Log-only Windows bridge harness.
- Bench-test runbook.
- Simulator test workflow.
- Real iPhone bench-test plan.
- OpenIPC/APFPV diagnostic test plan.
- Windows bridge integration plan.
- Future head tracking to pan/tilt safety design.
- First active pan/tilt safety milestone checklist.
- GitHub Actions validation workflow.
- Local `scripts/dev_check.sh` validation workflow.

## Blocked Milestones

These are blocked by missing hardware or external repo availability:

- Real iPhone bench validation.
- Real iPhone Core Motion axis/sign validation.
- Real iPhone mount/VR holder validation.
- iOS Local Network permission behavior on device.
- APFPV real packet capture.
- APFPV camera-to-iPhone UDP reachability.
- APFPV RTP/H.265 packetization decisions.
- Windows production bridge integration.
- First physical pan/tilt movement.

## Future Milestones

### 1. Real iPhone Bench Test

Use `docs/REAL_IPHONE_BENCH_TEST_PLAN.md`.

Goals:

- Install on real iPhone.
- Validate landscape behavior.
- Validate local network prompts.
- Validate UDP telemetry receive.
- Validate Core Motion raw/centered values.
- Validate head-tracking packets only after enable plus center.
- Record thermal, battery, and holder readability notes.

### 2. APFPV Diagnostic Capture

Use `docs/OPENIPC_APFPV_DIAGNOSTIC_TEST_PLAN.md`.

Goals:

- Capture real APFPV UDP traffic on laptop first.
- Identify UDP port and RTP behavior.
- Record payload type, SSRC, sequence/timestamp behavior.
- Record H.265 NAL types and VPS/SPS/PPS cadence.
- Test iPhone Debug-mode diagnostic receiver only after laptop capture.

### 3. Windows Log-Only Bridge

Use `docs/WINDOWS_BRIDGE_INTEGRATION_PLAN.md`.

Goals:

- Port log-only telemetry publisher and head-tracking receiver into the Windows app.
- Validate schema, stale behavior, malformed rejection, packet rate, and state display.
- Prove no joystick/control/mixer/failsafe/CRSF path is affected.

### 4. Active Pan/Tilt Safety Review

Use:

- `docs/FUTURE_HEAD_TRACKING_TO_PAN_TILT_SAFETY.md`
- `docs/FIRST_ACTIVE_PAN_TILT_MILESTONE.md`

Goals:

- Review real iPhone axis data.
- Review mount orientation.
- Review Windows operator arm/disarm.
- Review manual override.
- Review limits, deadband, smoothing, rate limiting, and stale fail-safe.
- Only then consider bench-only first movement.

### 5. APFPV VideoToolbox Decoding

Prerequisite: APFPV diagnostic capture complete.

Goals:

- Implement RTP/H.265 depacketization.
- Assemble H.265 access units.
- Feed VideoToolbox safely.
- Render decoded frames behind the existing HUD.
- Measure real device latency only after decode/render works on hardware.

### 6. VR Glasses HUD Tuning

Prerequisite: real iPhone holder or VR-style glasses.

Goals:

- Tune text size, safe regions, brightness, contrast, and warning placement.
- Confirm readability and comfort.
- Avoid adding debug information back into Drive mode.

## Explicit Non-Goals

- No autonomous driving.
- No direct iPhone-to-firmware control.
- No direct iPhone-to-CRSF control.
- No direct iPhone-to-servo control.
- No servo or gimbal movement before the active pan/tilt safety milestone.
- No pan/tilt testing while the vehicle is moving in the first active milestone.
- No APFPV decode before real diagnostic capture.
- No video latency claims before real APFPV hardware testing.
- No Windows re-encode/proxy assumption for the preferred iPhone video path.
- No raw CRSF parsing inside the iPhone app in the current milestone.

## Open Questions

- What are the real iPhone Core Motion yaw/pitch/roll sign conventions in the intended mount?
- What is the final phone mount orientation for FPV/VR use?
- How stable is Core Motion yaw over several minutes?
- Does iOS Local Network permission behave cleanly with UDP receive and send on the real device?
- Does the iPhone route correctly on APFPV camera Wi-Fi while still reaching the Windows/Mac telemetry host?
- What UDP port does APFPV actually use for video in this setup?
- Is APFPV definitely RTP over UDP, or is there an extra/custom header?
- What H.265 packetization mode does APFPV use?
- Are VPS/SPS/PPS sent in-band, and how often?
- What is the APFPV keyframe cadence?
- Where should the Windows bridge UI live in the real ground-station app?
- What is the safest manual override policy between DualShock/right-stick pan/tilt and iPhone head tracking?
- Should first active fail-safe hold, disable, or return-to-center for the actual gimbal hardware?

## Decision Log

| Date | Decision | Reason | Consequences |
| --- | --- | --- | --- |
| 2026-07-05 | Keep iPhone as thin client. | Windows already owns control mixing, failsafe, and final command authority. | iPhone sends display/intent data only; no direct firmware or CRSF path. |
| 2026-07-05 | Windows remains final authority. | Safety-critical decisions belong in the ground station/car side, not the FPV viewer. | Head tracking cannot move hardware until Windows explicitly validates, arms, limits, and maps it. |
| 2026-07-05 | Head tracking packets are intent only. | Yaw/pitch/roll need Windows-side validation and future mixing before any pan/tilt use. | Packet schema includes state/freshness fields; no servo command format is exposed. |
| 2026-07-05 | Require center/calibrate before sending head-tracking packets. | Uncentered orientation could create unsafe pan/tilt jumps later. | Sender is gated until tracking is enabled and centered; calibration is not persisted across launches. |
| 2026-07-05 | Keep APFPV video independent from telemetry and head tracking. | Video latency work should not couple to command authority or telemetry parsing. | Direct APFPV camera -> iPhone remains preferred; Windows does not need to forward video. |
| 2026-07-05 | Delay VideoToolbox decode until APFPV diagnostics. | Real packetization, parameter sets, and timing are unknown. | Diagnostic receiver parses RTP/H.265 headers only; mock video surface remains. |
| 2026-07-05 | Use landscape-only / landscape-first iPhone UX. | FPV driving and phone VR-style use are landscape-primary. | Portrait HUD is not a product target for now. |
| 2026-07-05 | Split Drive and Debug presentation modes. | Drive mode must remain video-first and uncluttered; Debug needs detailed state. | Drive HUD shows compact widgets; Debug/Setup owns detailed telemetry, motion, sender, and APFPV stats. |
| 2026-07-05 | Clear unsafe telemetry values when data is lost. | Old speed/gear/battery/link values can be misleading in an FPV/control HUD. | Lost telemetry shows placeholders and warnings instead of stale live-looking values. |
| 2026-07-05 | First Windows bridge milestone is log-only. | Need to validate packet paths and state handling before any output authority. | Bridge may forward telemetry and log head tracking; no CRSF channel 9/10 mapping. |
| 2026-07-05 | First active pan/tilt test must be bench-only. | Physical movement requires real iPhone, mount, stale, override, and fail-safe validation. | Vehicle driving and pan/tilt-in-motion remain explicitly unauthorized. |
