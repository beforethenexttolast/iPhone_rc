# Future Head Tracking To Pan/Tilt Safety Design

Last updated: 2026-07-14

This document describes a future safety design for mapping iPhone head-tracking intent into camera pan/tilt control. It is documentation only.

No active control is implemented by this document. No CRSF channel 9/10 mapping is implemented yet. No vehicle or gimbal movement should be tested from iPhone head tracking until real iPhone bench validation is complete and a separate reviewed implementation milestone exists.

## System Authority

Windows remains the control/integration authority. The future arbitration mapper belongs in an owned/forked `elrs-joystick-control`, where DualShock right-stick input and final CRSF channel encoding already meet. Electron remains viewer/configuration/logging only. Firmware alone produces physical servo outputs.

The iPhone sends head-look intent only:

- yaw intent
- pitch intent
- roll telemetry for diagnostics only
- tracking enabled/disabled
- centered/calibrated state
- packet timestamp/sequence/freshness data

The firmware must not trust the iPhone directly. The iPhone must not send CRSF, servo commands, gimbal commands, ESC commands, or vehicle commands.

The future authority chain should remain:

```text
iPhone Core Motion
  -> iPhone head-tracking UDP intent
  -> elrs-joystick-control validation / arming / arbitration / limits / failsafe
  -> final CRSF channels 9/10 only after explicit future implementation
  -> firmware ChannelDecoder / ServoOutput
  -> physical servos
```

The car firmware already supports camera gimbal pan/tilt through decoded controls mapped to CRSF channels 9/10. Future iPhone head tracking should become another Windows-side input source for pan/tilt intent, not a direct firmware input.

## Required Preconditions

Before any active mapping is allowed, all of the following must be validated:

- Real iPhone Core Motion axis behavior on physical hardware.
- Real phone mount orientation in the intended FPV/VR holder.
- Yaw, pitch, and roll sign conventions.
- Neutral center/calibration workflow.
- Operator-controlled enable/arm flow in Windows.
- Windows bridge packet schema validation.
- Packet timestamp, sequence, and age validation.
- An iPhone local motion-sample freshness gate no greater than `250 ms`; packet generation must stop when the sensor sample is older.
- Stale timeout behavior at the Windows bridge.
- Manual override behavior using the current DualShock/right-stick pan/tilt source.
- Priority rules between manual stick input and iPhone head tracking.
- Safe output limits for pan and tilt.
- Bench-only operation with servos/gimbal mechanically unloaded or safely constrained.
- Clear visual/log indication of current state, source, and stale/fault condition.

If any precondition is unknown, untested, or ambiguous, active mapping must remain disabled.

## Proposed States

The future mapper and Windows diagnostics should expose the same explicit active-control state machine:

- `disabled`: bridge or head tracking is disabled; no pan/tilt output.
- `receiving`: valid packets are arriving, but active output is not armed.
- `ready_not_centered`: tracking is enabled but no accepted center/calibration exists.
- `centered`: tracking has been centered and packets are valid, but output is not armed.
- `armed`: the operator has armed head tracking, but one or more remaining active gates are not yet satisfied.
- `active`: output is armed, packets are fresh, centered, valid, and no override conflict exists.
- `manual_override`: trusted manual pan/tilt input has authority and iPhone contribution is suppressed.
- `stale`: previously valid packet stream has exceeded the freshness timeout.
- `fault`: invalid packet stream, invalid configuration, axis validation failure, unsafe range, or internal bridge error.

Only `active` may accept new iPhone-derived contribution. Other states must not use head intent, although the mapper may still issue a reviewed rate-limited safety return or honor the trusted manual source. This distinction prevents fail-safe motion from being mislabeled as active iPhone authority.

## Safety Gates

All gates must pass before the mapper accepts iPhone intent for pan/tilt:

- Tracking enabled in the iPhone app.
- Tracking enabled in Windows.
- User has explicitly centered/calibrated the iPhone in the mounted neutral position.
- Operator has armed iPhone pan/tilt input in Windows.
- Packet receive age is fresh: integer ages `299 ms` and `300 ms` are fresh; `301 ms` is stale. Local receive time is authoritative.
- Packet sequence and timestamp are valid.
- Packet schema is valid.
- `centered == true`.
- Yaw, pitch, and roll values are finite numbers.
- Yaw/pitch values are inside configured accepted input ranges.
- Windows axis mapping has been selected and validated for the physical mount.
- No manual override conflict is present.
- Output limits are configured and valid.
- Rate limiting and smoothing are configured and valid.
- Bridge is not in stale or fault state.

If any gate fails, the mapper must stop accepting new iPhone-derived contribution. It may still honor trusted manual input or issue the reviewed rate-limited commanded return-to-center.

## Mapping Plan

Initial mapping should be deliberately simple:

- yaw -> pan
- pitch -> tilt
- roll ignored initially

Roll may still be logged for diagnostics, but it should not affect gimbal output in the first active-control milestone.

Mapping should include:

- Configurable yaw sign flip.
- Configurable pitch sign flip.
- Center offset from the accepted calibration action.
- Pan min/max limits.
- Tilt min/max limits.
- Input deadband around center.
- Smoothing to remove small IMU jitter.
- Output rate limiting to prevent sudden gimbal movement.
- Optional gain/scaling per axis.
- Optional maximum head-look angle accepted from iPhone.

The selected behavior is hybrid position/rate mapping:

- Near neutral, centered head angle maps directly to a commanded camera target around a bounded `virtualCameraCenter`.
- Near the comfortable head-turn boundary, a smooth rate term advances the virtual center.
- Anti-windup bounds the virtual center to the calibrated command range.
- Mechanical/command limits clamp the final target.
- One output rate limiter remains active across arm, recenter, manual override, stale, disarm, fault, and return-to-center transitions.

The commanded mechanical center is CRSF `992` for both pan and tilt. It is a command anchor, not measured physical camera feedback.

On a deliberate controller recenter, the mapper should:

- accept the current head pose as neutral;
- re-seed the virtual center from the current authoritative commanded target;
- clear accumulated edge-rate displacement;
- remain bumpless and rate-limited.

The initial implementation should prefer conservative limits and slow rates. It is easier to widen a safe envelope later than to debug a violent first movement.

## Manual Override

Manual control must have a clear priority policy before active mapping:

- Current DualShock/right-stick pan/tilt input should remain a trusted manual source.
- Manual override should be able to suppress or replace iPhone head tracking immediately.
- If manual input exceeds a configured threshold, Windows should leave `active` or mark iPhone tracking overridden.
- Entering `manual_override` discards the active virtual center.
- Releasing manual input must not automatically restore iPhone authority. Re-entry requires deliberate recenter and rearm.

The operator must always be able to disable iPhone head tracking without touching the iPhone.

## Fail-Safe Behavior

Selected first-active behavior:

- Stale packet: stop applying new iPhone intent, discard the virtual center, and command a rate-limited return toward CRSF `992`.
- Invalid packet: ignore packet and keep the last valid state unchanged.
- Repeated invalid packets: enter `fault`.
- Bridge disabled/operator disarm: discard the virtual center and command a rate-limited return toward `992`.
- iPhone app disconnect: enter `stale`, then safe state.
- Tracking disabled: no iPhone-derived output.
- Not centered: no iPhone-derived output.
- Manual override: discard the virtual center; the trusted manual source owns the commanded target. Do not blend unless a later reviewed design explicitly allows it.
- Mapper fault: discard the virtual center and command a rate-limited return toward `992` when the command path remains operational.
- Windows telemetry/control fault: no iPhone-derived contribution.

Reconnection or fault recovery must not restore head authority automatically. Recenter/rearm is required.

These are commanded-output rules, not guarantees of physical motion. If radio, CRSF, firmware, servo power, or linkage has failed, the center command may not reach or move the mechanism. Each failure layer must remain visible in diagnostics and test evidence.

### Canonical Timeout Domains

- Local motion sample: future active sender gate `<= 250 ms`. The current app's `500 ms` motion staleness is not acceptable for active use because packets are timestamped at send time.
- W3 mapper receive age: `300 ms` remains fresh; `301 ms` is stale.
- Packet `timeout_ms`: sender hint only, currently `250 ms`; it never overrides mapper receive-time authority.

Telemetry display timing and local video-frame timing are independent of these three W3 domains.

### Open Video-Loss Decision

The current W3 schema carries no iPhone decoder/video-health field. Before active control, the owner must separately choose and review one of these paths:

1. add reviewed local video health to W3;
2. stop W3 transmission when the iPhone decoder is stale/lost;
3. add a separate reviewed iPhone-to-Windows health path; or
4. keep video and head intent independent and rely on explicit operator/Windows disarm policy.

No path is chosen here. Windows `video_lock` cannot be used as a proxy for iPhone-local video health.

## Test Plan Before First Servo Movement

Complete these tests before allowing any physical gimbal movement:

1. Schema validation with golden head-tracking packets.
2. Malformed JSON rejection.
3. Unsupported `protocol_version` rejection.
4. Sequence/timestamp validation.
5. Stale timeout validation using packet drops.
   - `299 ms` fresh.
   - `300 ms` fresh.
   - `301 ms` stale.
6. Disabled-state validation.
7. Not-centered validation.
8. Center/calibration validation.
9. Operator arm/disarm validation.
10. Manual override validation with the DualShock/right stick.
11. Axis sign validation on a real iPhone in the intended mount.
12. Yaw/pitch range validation with slow deliberate phone movement.
13. Limit validation with output disconnected from hardware.
14. Deadband validation.
15. Smoothing/rate-limit validation.
16. Logging/state display validation.
17. Virtual-center anti-windup and discard/re-seed validation.
18. Rate-limiter continuity across every authority transition.
19. Bench test with simulated output only.
20. Bench test with gimbal mechanically safe and vehicle power path isolated.

Only after these pass should a limited first servo movement test be considered.

## First Servo Movement Rules

Before first movement:

- Vehicle drive system disabled.
- Wheels off ground or vehicle otherwise immobilized.
- Gimbal mechanically clear and safe.
- Conservative pan/tilt limits configured.
- Low output rate configured.
- Manual override verified immediately before test.
- Windows logs visible.
- iPhone state visible.
- One operator action available to disable iPhone mapping immediately.

The first movement should use tiny limits and slow motion. Do not test at full range or full speed first.

## Explicit Non-Implementation Statement

This project currently implements no active pan/tilt mapping from iPhone head tracking.

No CRSF channel 9/10 mapping is implemented yet.

No vehicle, servo, or gimbal movement should be tested from iPhone head tracking until real iPhone bench validation is complete and a separate implementation milestone is reviewed.
