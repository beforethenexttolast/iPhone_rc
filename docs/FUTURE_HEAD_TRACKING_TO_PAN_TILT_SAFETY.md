# Future Head Tracking To Pan/Tilt Safety Design

This document describes a future safety design for mapping iPhone head-tracking intent into camera pan/tilt control. It is documentation only.

No active control is implemented by this document. No CRSF channel 9/10 mapping is implemented yet. No vehicle or gimbal movement should be tested from iPhone head tracking until real iPhone bench validation is complete and a separate reviewed implementation milestone exists.

## System Authority

Windows remains the final authority for control decisions.

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
  -> Windows validation / arming / mixing / limits / failsafe
  -> existing pan/tilt output path
  -> CRSF channels 9/10 only after explicit future implementation
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
- Stale timeout behavior at the Windows bridge.
- Manual override behavior using the current DualShock/right-stick pan/tilt source.
- Priority rules between manual stick input and iPhone head tracking.
- Safe output limits for pan and tilt.
- Bench-only operation with servos/gimbal mechanically unloaded or safely constrained.
- Clear visual/log indication of current state, source, and stale/fault condition.

If any precondition is unknown, untested, or ambiguous, active mapping must remain disabled.

## Proposed States

The future Windows bridge should expose an explicit state machine:

- `disabled`: bridge or head tracking is disabled; no pan/tilt output.
- `receiving`: valid packets are arriving, but active output is not armed.
- `ready_not_centered`: tracking is enabled but no accepted center/calibration exists.
- `centered`: tracking has been centered and packets are valid, but output is not armed.
- `active`: output is armed, packets are fresh, centered, valid, and no override conflict exists.
- `stale`: previously valid packet stream has exceeded the freshness timeout.
- `fault`: invalid packet stream, invalid configuration, axis validation failure, unsafe range, or internal bridge error.

Only `active` may produce future pan/tilt output. Every other state must produce no new iPhone-driven pan/tilt command.

## Safety Gates

All gates must pass before Windows maps iPhone intent to pan/tilt:

- Tracking enabled in the iPhone app.
- Tracking enabled in Windows.
- User has explicitly centered/calibrated the iPhone in the mounted neutral position.
- Operator has armed iPhone pan/tilt input in Windows.
- Packet age is fresh, target threshold `<= 300 ms`.
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

If any gate fails, Windows must not output iPhone-derived pan/tilt commands.

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

The initial implementation should prefer conservative limits and slow rates. It is easier to widen a safe envelope later than to debug a violent first movement.

## Manual Override

Manual control must have a clear priority policy before active mapping:

- Current DualShock/right-stick pan/tilt input should remain a trusted manual source.
- Manual override should be able to suppress or replace iPhone head tracking immediately.
- If manual input exceeds a configured threshold, Windows should leave `active` or mark iPhone tracking overridden.
- Re-entering active iPhone control should require either a deliberate operator action or a clearly documented automatic policy.

The operator must always be able to disable iPhone head tracking without touching the iPhone.

## Fail-Safe Behavior

Recommended behavior:

- Stale packet: stop applying new iPhone intent and either hold last safe output briefly or return to center using a controlled rate.
- Invalid packet: ignore packet and keep the last valid state unchanged.
- Repeated invalid packets: enter `fault`.
- Bridge disabled: no iPhone-derived output.
- iPhone app disconnect: enter `stale`, then safe state.
- Tracking disabled: no iPhone-derived output.
- Not centered: no iPhone-derived output.
- Operator disarm: no iPhone-derived output.
- Manual override: no iPhone-derived output or blend only if a future reviewed design explicitly allows blending.
- Windows telemetry/control fault: no iPhone-derived output.

The first active-control milestone should prefer no output or controlled return-to-center over holding an unknown stale command indefinitely.

## Test Plan Before First Servo Movement

Complete these tests before allowing any physical gimbal movement:

1. Schema validation with golden head-tracking packets.
2. Malformed JSON rejection.
3. Unsupported `protocol_version` rejection.
4. Sequence/timestamp validation.
5. Stale timeout validation using packet drops.
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
17. Bench test with simulated output only.
18. Bench test with gimbal mechanically safe and vehicle power path isolated.

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
