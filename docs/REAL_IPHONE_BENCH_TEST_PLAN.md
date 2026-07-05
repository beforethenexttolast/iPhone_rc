# Real iPhone Bench Test Plan

This plan validates the FPV HUD app on a real iPhone for the first time after the pre-hardware freeze.

This is log-only bench testing. It does not command vehicle hardware, does not map head tracking to CRSF channels 9/10, does not move servos or a camera gimbal, and does not prove APFPV video latency.

## Required Equipment

- Mac with full Xcode installed.
- Real iPhone capable of running the app target.
- USB cable for first install and debugging.
- Same Wi-Fi/LAN setup for the iPhone and the Mac or laptop running UDP scripts.
- Laptop/Mac terminal running the checked-in UDP scripts.
- Optional phone holder or VR-style phone glasses for readability and comfort checks.
- Optional external power for the iPhone during longer thermal/battery observation.

## Pre-Test Checklist

Complete these before installing on the iPhone:

- Record repo commit or tag under test:

```sh
git rev-parse --short HEAD
git status --short
```

- Confirm `scripts/dev_check.sh` passed on the Mac:

```sh
scripts/dev_check.sh
```

- Confirm any intended pre-hardware changes are committed or intentionally noted.
- Confirm Xcode opens `FPVHUDApp.xcodeproj`.
- Confirm Xcode Signing & Capabilities has a valid Apple Development team selected.
- Confirm bundle identifier is unique if Xcode rejects `com.example.FPVHUDApp`.
- Enable iPhone Developer Mode:
  - Settings -> Privacy & Security -> Developer Mode.
  - Restart and confirm after reboot if prompted.
- Confirm the iPhone and Mac are on the same Wi-Fi/LAN for UDP tests.
- Note the iPhone Wi-Fi IP address.
- Note the Mac Wi-Fi IP address.

## Install Checklist

1. Connect the iPhone to the Mac with USB.
2. Open `FPVHUDApp.xcodeproj` in Xcode.
3. Select the `FPVHUDApp` scheme.
4. Select the real iPhone as the run destination.
5. Select the Apple Development team in Signing & Capabilities.
6. Build and run.
7. If prompted on the iPhone, trust the developer app/profile.
8. If prompted by Xcode or iOS, allow Developer Mode or local debugging.
9. Confirm the app icon and display name appear correctly.

Expected result: the app installs and launches without requiring simulator-only code paths.

## Basic Launch Validation

Start with default settings.

Expected safe startup state:

- App launches into Drive / FPV mode.
- Demo telemetry may be active.
- Head tracking is off by default.
- No head-tracking packets are sent before tracking is enabled and centered.
- APFPV diagnostics are off by default.
- No APFPV RTP receiver starts automatically.

Landscape checks:

1. Hold the phone in landscape left.
2. Confirm Drive mode fills the screen and does not show portrait fallback.
3. Hold the phone in landscape right.
4. Confirm Drive mode recovers and remains correctly oriented.
5. Open Debug / Setup.
6. Open Settings.
7. Close Settings.
8. Return to Drive mode.

Expected result: Settings and Debug open/close without leaving Drive mode rotated, clipped, or stuck in a portrait layout.

Safe-area checks:

- Top telemetry strip avoids notch/Dynamic Island/sensor housing.
- Top-right video/settings controls do not overlap.
- Speed, input, warning, and head-tracking chips remain readable.
- Debug / Setup scrolls if content does not fit.

## Local Network Validation

The first UDP use may trigger the iOS Local Network permission prompt. Allow it.

If permission is denied, re-enable it in:

```text
iOS Settings -> Privacy & Security -> Local Network -> FPV HUD
```

### Telemetry Receive

In the iPhone app:

1. Open Debug / Setup.
2. Open Settings.
3. Turn `Demo telemetry` off.
4. Set telemetry UDP port to `5601`.
5. Apply settings.

From the Mac, send telemetry to the iPhone Wi-Fi IP:

```sh
python3 scripts/send_demo_telemetry.py --host <iphone-wifi-ip> --port 5601 --rate 20 --profile normal
```

Expected result:

- Drive mode shows live battery, LQ, RSSI, SNR, speed, gear, ERS, input bars, and video state.
- Debug / Setup shows recent telemetry packet age.
- No malformed packet count increases during normal traffic.

### Stale And Lost Telemetry

Send telemetry briefly, then stop:

```sh
python3 scripts/send_demo_telemetry.py --host <iphone-wifi-ip> --port 5601 --rate 20 --drop-after 5 --duration 10
```

Expected result:

- Live values show while packets arrive.
- After about `1s` without packets, the HUD shows a stale telemetry warning.
- After more than `3s` without packets, the HUD shows `TELEMETRY DATA LOST >3S`.
- Unsafe stale values clear to placeholders:
  - battery `--.- V`
  - LQ `--`
  - RSSI `--`
  - SNR `--`
  - speed `-- km/h`
  - gear `--`
  - ERS `--`
  - source/mode `--` or `UNKNOWN`

### Malformed Telemetry

Send malformed payloads:

```sh
python3 scripts/send_demo_telemetry.py --host <iphone-wifi-ip> --port 5601 --malformed
python3 scripts/send_demo_telemetry.py --host <iphone-wifi-ip> --port 5601 --profile noisy --malformed-every 10 --duration 10
```

Expected result:

- App does not crash.
- Debug / Setup malformed count increases.
- Last valid display state is not corrupted by malformed JSON.

## Core Motion Validation

The real iPhone uses `CoreMotionService`; the simulator-only mock motion panel should not appear.

1. Open Debug / Setup.
2. Confirm raw yaw/pitch/roll values update when the phone moves.
3. Hold the phone in the intended neutral FPV mount orientation.
4. Tap Center/Calibrate.
5. Move the phone slowly around each axis.

Yaw checks:

- Rotate phone left/right around the vertical axis.
- Record which physical direction makes yaw increase.
- Record whether yaw wraps smoothly around `-180...180`.

Pitch checks:

- Tilt phone up/down in the intended holder orientation.
- Record which physical direction makes pitch increase.
- Confirm centered pitch returns near `0 deg` in neutral position.

Roll checks:

- Roll phone clockwise/counterclockwise.
- Record which physical direction makes roll increase.
- Confirm roll is logged only as intent telemetry; it is not mapped to output.

Drift checks:

- Center the phone and leave it still for 60 seconds.
- Record raw and centered yaw/pitch/roll drift.
- Repeat once with the phone in the holder or VR-style glasses.

Center/calibrate checks:

- Centering sets current raw yaw/pitch/roll as neutral.
- Centered yaw/pitch/roll read near `0 deg` immediately after center.
- Reset calibration returns app to not-centered state.

## Head-Tracking Safety Validation

Start the receiver on the Mac:

```sh
python3 scripts/receive_head_tracking.py --host 0.0.0.0 --port 5602 --timeout-ms 300 --print-rate
```

In the iPhone app Settings:

- Set Windows host/IP to the Mac Wi-Fi IP.
- Set head-tracking output port to `5602`.
- Keep send rate at `30...60 Hz`.
- Apply settings.

Run these gates in order:

1. Tracking disabled.
   - Expected: receiver shows no packets.
2. Tracking enabled but not centered.
   - Expected: app shows a not-centered state; receiver shows no packets.
3. Tap Center/Calibrate.
   - Expected: receiver starts printing packets.
4. Move phone slowly.
   - Expected: yaw/pitch/roll values change in receiver output.
5. Tap Reset calibration.
   - Expected: packets stop; receiver warns after about `300 ms`.
6. Disable tracking.
   - Expected: packets stop and stay stopped.
7. Enter invalid host or invalid port.
   - Expected: settings validation prevents Apply/Save, sender does not start, and Drive mode does not show a misleading active state.

Safety pass condition: at no point may uncentered or disabled tracking send head-look packets.

## UDP Packet Validation

Watch `receive_head_tracking.py` output.

Expected fields:

- `seq`
- packet age
- yaw
- pitch
- roll
- `tracking_enabled`
- `centered`
- packet rate once per second if `--print-rate` is active

Packet expectations:

- `seq` increments monotonically while packets are sent.
- Packet age remains low on the same LAN.
- Packet rate is near configured send rate.
- `tracking_enabled=true` only when tracking is enabled.
- `centered=true` only after Center/Calibrate.
- Receiver warns if packets stop for more than `300 ms`.

If packet rate is unstable, record:

- iPhone model.
- iOS version.
- App send rate setting.
- Wi-Fi network.
- Battery/thermal state.
- Whether Low Power Mode is enabled.

## VR/Holder Readability Notes

Run these checks in the intended phone holder or VR-style glasses if available:

- Text is readable without squinting.
- Top telemetry strip is not hidden by lenses or holder edges.
- Speed display is readable but not distracting.
- Head-tracking chip is readable and does not clip.
- Warnings are visible but not overwhelming.
- Bright video/background does not wash out telemetry.
- Minimum usable screen brightness is acceptable.
- Maximum brightness is not uncomfortable.
- Eye comfort is acceptable for at least 5 minutes.
- The holder does not press buttons or trigger accidental orientation changes.

Record any UI element that should move, shrink, hide, or gain a high-contrast mode later.

## Thermal And Battery Notes

Short run:

- Run Drive mode with demo telemetry for 5 minutes.
- Record battery percentage before/after.
- Record whether the phone becomes warm.

Network run:

- Run UDP telemetry receive plus head-tracking send for 10 minutes.
- Record battery percentage before/after.
- Record whether iOS reports thermal pressure, dimming, or performance changes.

Holder run:

- Repeat in the phone holder or VR-style glasses if available.
- Note whether enclosed mounting increases heat.

Do not use these tests to make final video-runtime claims; APFPV decode is not implemented yet.

## Pass/Fail Criteria

Pass requires all of the following:

- App installs and launches on the real iPhone.
- Landscape layout is usable in both landscape orientations.
- Debug and Settings open/close without orientation corruption.
- Local Network prompt appears when expected, or UDP works if permission was already granted.
- Telemetry UDP receive works from Mac to iPhone.
- Stale and lost telemetry warnings appear at expected thresholds.
- Lost telemetry clears unsafe stale values.
- Core Motion raw and centered values update.
- Center/calibrate works.
- No head-tracking packets are sent while tracking is disabled.
- No head-tracking packets are sent while tracking is enabled but not centered.
- Packets send only after explicit Center/Calibrate.
- Reset calibration stops packets again.
- Invalid settings do not start the sender.
- No CRSF, servo, gimbal, ESC, or vehicle-control path is exercised.

Fail the bench test if any of these occur:

- App crashes on launch or during Settings/Debug flow.
- Drive mode remains stuck in the wrong orientation.
- UDP sender starts before tracking is enabled and centered.
- Uncentered tracking sends packets.
- Lost telemetry keeps showing old live-looking speed, gear, battery, LQ, RSSI, SNR, or ERS.
- App appears to control or attempt to control vehicle hardware.
- APFPV diagnostics attempt to decode/render video.

## Explicit Boundaries

- No CRSF mapping is implemented or tested.
- No head-tracking mapping to CRSF channels 9/10 is allowed.
- No servo, ESC, gimbal, or vehicle movement is allowed.
- Head-tracking packets are camera-look intent only.
- Windows remains the future authority for mixing, limits, failsafe, and any later pan/tilt mapping.
- APFPV diagnostics, if used later, are receive-statistics only.
- No APFPV decode or latency claim may be made from this bench test.
- Core Motion axes must not be tuned for control without real iPhone data from this plan.

## Results Table Template

| Test | Expected Result | Actual Result | Pass/Fail | Notes |
| --- | --- | --- | --- | --- |
| Repo commit recorded | Commit/tag and dirty state recorded |  |  |  |
| `scripts/dev_check.sh` | Passes before install |  |  |  |
| Xcode install | App installs on real iPhone |  |  |  |
| First launch | App opens in Drive mode |  |  |  |
| Landscape left | Layout usable, no portrait fallback |  |  |  |
| Landscape right | Layout usable, no portrait fallback |  |  |  |
| Debug open/close | No orientation or clipping issue |  |  |  |
| Settings open/close | No orientation or clipping issue |  |  |  |
| Safe areas | HUD avoids notch/Dynamic Island/holder edges |  |  |  |
| Local Network permission | Prompt handled, UDP allowed |  |  |  |
| Telemetry live | Live values update from Mac UDP script |  |  |  |
| Telemetry stale | Warning appears after about 1s |  |  |  |
| Telemetry lost | `TELEMETRY DATA LOST >3S` appears |  |  |  |
| Lost placeholders | Unsafe stale values clear |  |  |  |
| Malformed telemetry | No crash, malformed count increases |  |  |  |
| Raw yaw | Updates with yaw movement |  |  |  |
| Raw pitch | Updates with pitch movement |  |  |  |
| Raw roll | Updates with roll movement |  |  |  |
| Center/calibrate | Centered values near zero |  |  |  |
| Drift 60s | Drift observed and recorded |  |  |  |
| Tracking disabled | No packets received |  |  |  |
| Enabled not centered | No packets received |  |  |  |
| Centered tracking | Packets received |  |  |  |
| Packet sequence | Sequence increments |  |  |  |
| Packet rate | Near configured send rate |  |  |  |
| Reset calibration | Packets stop again |  |  |  |
| Invalid settings | Apply blocked, sender not started |  |  |  |
| Holder readability | HUD readable and comfortable |  |  |  |
| Thermal 5 min demo | Heat/battery recorded |  |  |  |
| Thermal 10 min UDP | Heat/battery recorded |  |  |  |
| Safety boundary | No CRSF/gimbal/vehicle control exercised |  |  |  |
