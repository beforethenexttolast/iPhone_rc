# First Active Pan/Tilt Safety Milestone

This checklist defines the exact conditions required before iPhone head tracking is allowed to move real camera pan/tilt servos.

This document is not an implementation. It does not authorize CRSF mapping by itself, does not authorize vehicle driving, and does not authorize pan/tilt use while the vehicle is in motion. The first active test is bench-only.

## Purpose

The first active pan/tilt milestone may begin only after the log-only iPhone bridge has proven that iPhone head tracking can be received, validated, displayed, timed out, and safely ignored.

The goal of the first active milestone is one narrow proof:

```text
Fresh, centered, armed iPhone head-look intent
  -> Windows validation and safety gates
  -> limited pan/tilt bench output
```

Anything beyond that is out of scope.

## Required Completed Milestones

All items must be complete and documented before first physical movement:

- Real iPhone bench test passed using `docs/REAL_IPHONE_BENCH_TEST_PLAN.md`.
- Core Motion yaw/pitch/roll axes documented on the real iPhone.
- Phone mount orientation documented for the intended holder or VR-style setup.
- Center/calibrate behavior validated on the real iPhone.
- Head-tracking send gating validated:
  - tracking disabled -> no packets
  - tracking enabled but not centered -> no packets
  - reset calibration -> packets stop
- Windows log-only bridge validated using `docs/WINDOWS_BRIDGE_INTEGRATION_PLAN.md`.
- Packet schema validation implemented and tested in Windows.
- Malformed packet rejection validated.
- Packet stale behavior validated at the Windows bridge.
- Packet rate and sequence behavior observed.
- Manual override behavior designed.
- Operator arm/disarm behavior designed.
- Output limits, deadband, smoothing, and rate limiting designed.
- A rollback plan exists to return to log-only behavior.

If any item is unknown, untested, or only simulator-validated, do not proceed.

## Hardware Safety Setup

Minimum bench setup:

- Vehicle drive system disabled.
- Wheels off ground, vehicle immobilized, or vehicle power path isolated.
- Camera pan/tilt mechanism mechanically clear.
- Servos mechanically disconnected first, if possible.
- If servos cannot be disconnected, linkage loosened or movement range physically constrained.
- Low-power bench setup preferred over full vehicle battery power.
- Conservative current limits or fused power path where practical.
- Emergency stop or immediate disable procedure available.
- Windows operator can disable iPhone pan/tilt without touching the iPhone.
- iPhone screen visible.
- Windows logs/debug panel visible.
- One person watches the mechanism during movement.
- No propulsive or steering control testing during this milestone.

Before connecting servos:

- Verify simulated/logged pan/tilt output only.
- Verify sign, limits, rate limiting, and stale behavior in logs.
- Verify manual override suppresses iPhone-derived output.

## Software Safety Gates

Every gate must pass before Windows produces any iPhone-derived pan/tilt output:

- Bridge enabled.
- Tracking enabled in the iPhone app.
- Tracking enabled/accepted in Windows.
- iPhone has been centered/calibrated.
- Packet includes `centered == true`.
- Packet age is fresh, target `<= 300 ms`.
- Packet schema is valid.
- Packet sequence/timestamp accepted.
- Yaw/pitch/roll are finite numbers.
- Yaw/pitch are inside accepted input range.
- Operator has explicitly armed iPhone pan/tilt in Windows.
- Windows settings are valid.
- Output limits are valid.
- Deadband is valid.
- Smoothing is valid.
- Rate limiting is valid.
- Axis sign configuration has been selected from real iPhone data.
- No manual override conflict exists.
- No bridge fault exists.
- No telemetry/control fault exists.
- No stale packet state exists.

If any gate fails, output must be disabled immediately.

## Required Windows States

Windows should expose clear states before active movement:

- `disabled`: bridge or feature disabled; no output.
- `receiving`: valid packets arriving; no output.
- `ready_not_centered`: tracking enabled but not centered; no output.
- `centered`: packets fresh and centered; no output until armed.
- `armed`: operator has armed but output is still waiting for all gates.
- `active`: all gates pass and limited bench output is allowed.
- `manual_override`: trusted manual source suppresses iPhone output.
- `stale`: packet timeout exceeded; fail-safe active.
- `fault`: invalid config, repeated invalid packets, socket failure, or unsafe condition.

Only `active` may move pan/tilt. Every other state must produce no new iPhone-derived movement.

## Mapping Plan

Initial mapping:

- yaw -> pan
- pitch -> tilt
- roll ignored

Required mapping controls:

- Configurable yaw sign flip.
- Configurable pitch sign flip.
- Center offset from accepted calibration.
- Maximum pan angle limit.
- Maximum tilt angle limit.
- Input deadband around center.
- Smoothing for small IMU jitter.
- Output rate limiting.
- Optional gain/scaling per axis.

Initial recommended limits:

- Start with tiny pan/tilt limits, for example `+/-5 deg`.
- Start with slow output rate, for example no faster than `10 deg/s`.
- Increase only after stale, disconnect, override, and emergency-disable tests pass.

Roll must be logged only. Roll must not affect pan or tilt in the first active milestone.

## Fail-Safe Choice

Chosen first-milestone fail-safe: disable iPhone-derived output and return to center at a controlled rate where the mechanism supports safe centering.

Rationale:

- Holding an unknown stale command can leave the camera pointed at an unintended extreme.
- Snapping immediately to center can produce sudden movement.
- Disabling output alone may leave some servo systems holding the last command.
- Controlled return-to-center is easiest to observe and reason about during bench testing.

Fallback if controlled centering is not implemented or not safe for the mechanism:

- Disable iPhone-derived output and hold the last known safe command for a short bounded interval, then require manual/operator intervention.

Fail-safe triggers:

- No valid packet for more than configured timeout.
- iPhone app closed or stops sending.
- Wi-Fi disconnect.
- Tracking disabled.
- Calibration reset.
- `centered != true`.
- Operator disarm.
- Manual override.
- Invalid packet.
- Repeated malformed packets.
- Bridge fault.
- Invalid output configuration.

Fail-safe behavior must be visible in Windows logs/UI.

## First Movement Test Sequence

Run these tests in order. Do not skip ahead after a failure.

### 1. Servo Disconnected / Log-Only Output

Setup:

- Output mapping code may calculate intended pan/tilt values.
- Physical servo output is disconnected or disabled.
- CRSF output to channels 9/10 remains disabled if possible.

Checks:

- Move iPhone yaw slowly.
- Verify logged pan target changes in the expected direction.
- Move iPhone pitch slowly.
- Verify logged tilt target changes in the expected direction.
- Roll changes are logged but do not affect output.
- Limits clamp target output.
- Deadband suppresses small center jitter.
- Smoothing and rate limits are visible in logged target output.
- Stale packet test triggers fail-safe.
- App close test triggers fail-safe.
- Wi-Fi disconnect test triggers fail-safe.
- Manual override suppresses iPhone-derived output.

Go/no-go: proceed only if every log-only output check passes.

### 2. Servo Connected But Unloaded

Setup:

- Servo connected to bench power or safe low-power setup.
- Mechanism unloaded or linkage disconnected.
- Small angle limit active.
- Slow rate limit active.
- Emergency disable verified immediately before test.

Checks:

- Arm iPhone pan/tilt.
- Move yaw slightly.
- Confirm pan servo moves slowly in expected direction.
- Return phone to center.
- Confirm servo returns toward center smoothly.
- Move pitch slightly.
- Confirm tilt servo moves slowly in expected direction.
- Trigger stale packet by stopping app or blocking packets.
- Confirm chosen fail-safe behavior.
- Disable tracking.
- Confirm output stops/fail-safe engages.
- Reset calibration.
- Confirm output stops/fail-safe engages.
- Trigger manual override.
- Confirm iPhone-derived output is suppressed.

Go/no-go: proceed only if movement is slow, limited, reversible, and fail-safe behavior is correct.

### 3. Mechanism Connected With Tiny Limits

Setup:

- Camera/gimbal linkage connected.
- Vehicle drive still disabled.
- Wheels off ground or vehicle immobilized.
- Pan/tilt limits remain tiny.
- Rate limit remains slow.

Checks:

- Repeat yaw and pitch tests.
- Observe mechanical clearance.
- Confirm no binding.
- Confirm no sudden motion.
- Confirm center is safe.
- Confirm stale/app-close/Wi-Fi-disconnect/manual-override tests.

Go/no-go: do not expand limits until all tiny-limit tests pass.

## Stale Packet Test

With output armed and active:

1. Start valid centered iPhone packets.
2. Confirm limited output responds.
3. Stop packets by closing the app, disabling tracking, or blocking UDP.
4. Confirm Windows marks state `stale` after timeout.
5. Confirm fail-safe behavior starts immediately after stale detection.
6. Confirm no new iPhone-derived command is applied while stale.

Expected result: stale packets cannot keep moving or holding unsafe pan/tilt output.

## App Close Test

1. Start active limited bench output.
2. Close or background the iPhone app.
3. Confirm packets stop or become stale.
4. Confirm Windows enters stale/fail-safe state.
5. Confirm output does not remain under iPhone authority.

Expected result: closing the app cannot leave active iPhone pan/tilt authority alive.

## Wi-Fi Disconnect Test

1. Start active limited bench output.
2. Disconnect iPhone Wi-Fi or move out of AP range.
3. Confirm Windows detects stale input.
4. Confirm fail-safe behavior.
5. Reconnect Wi-Fi.
6. Confirm output does not resume automatically unless the operator explicitly re-arms.

Expected result: reconnect does not silently re-enable active iPhone movement.

## Manual Override Test

1. Start active limited iPhone output.
2. Move the trusted manual pan/tilt source, such as the DualShock/right stick.
3. Confirm Windows leaves `active` or marks iPhone tracking overridden.
4. Confirm manual source has priority.
5. Release manual input.
6. Confirm re-entering iPhone active mode requires the documented policy.

Expected result: the operator can suppress iPhone pan/tilt immediately without touching the iPhone.

## Go/No-Go Table

| Gate | Go Condition | No-Go Condition | Result | Notes |
| --- | --- | --- | --- | --- |
| Real iPhone bench test | Passed and documented | Not run, failed, or simulator-only |  |  |
| Core Motion axes | Yaw/pitch/roll signs documented | Axis signs unknown |  |  |
| Mount orientation | Physical orientation documented | Mount unknown or changed |  |  |
| Windows log-only bridge | Validated with fake and real iPhone packets | Not validated |  |  |
| Packet validation | Malformed/stale packets rejected | Invalid packet updates state |  |  |
| Stale timeout | Fail-safe triggers at timeout | Stale input remains active |  |  |
| Operator arm | Explicit arm required | Output can start without arm |  |  |
| Operator disarm | Immediate disable verified | Disable path unclear |  |  |
| Manual override | Manual source suppresses iPhone output | Override conflict unresolved |  |  |
| Output limits | Tiny limits configured and tested | Full range or unknown limits |  |  |
| Rate limit | Slow rate configured and tested | Sudden output possible |  |  |
| Deadband | Center jitter suppressed | Jitter moves servo |  |  |
| Smoothing | Jitter reduced without lag surprise | Behavior unknown |  |  |
| Servo disconnected test | Log-only output passes | Sign/limit/fail-safe issue |  |  |
| Servo unloaded test | Slow, limited, fail-safe movement | Sudden/wrong movement |  |  |
| Mechanism tiny-limit test | No binding, no unsafe motion | Binding or unsafe motion |  |  |
| App close test | Enters fail-safe | Output remains active |  |  |
| Wi-Fi disconnect test | Enters fail-safe and requires re-arm | Auto-resumes unsafely |  |  |
| Vehicle safety | Drive disabled/wheels off ground | Vehicle can move |  |  |

## Stop Conditions

Stop immediately if any of these occur:

- Servo moves opposite the expected direction.
- Servo moves faster than expected.
- Servo exceeds configured tiny limit.
- Output starts before operator arm.
- Output continues after stale timeout.
- Output continues after app close.
- Output resumes automatically after Wi-Fi reconnect.
- Manual override does not suppress iPhone output.
- Mechanism binds or chatters.
- Windows logs disagree with observed movement.
- Vehicle drive system is not fully disabled.

After any stop condition, return to log-only mode and review logs before trying again.

## Explicit Non-Authorization

This document does not authorize vehicle driving.

This document does not authorize pan/tilt testing while the vehicle is moving.

This document does not authorize full-range pan/tilt movement.

This document does not authorize autonomous or unattended testing.

This document does not authorize bypassing Windows authority.

This document does not authorize direct iPhone-to-firmware, iPhone-to-CRSF, or iPhone-to-servo control.

The first test is bench-only.
