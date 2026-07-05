# Bench Test Runbook

This runbook is the single no-hardware and first-bench-test workflow for the iPhone FPV HUD project. It is intentionally log-only: none of these scripts command vehicle hardware, CRSF channels, servos, ESCs, or the camera gimbal.

## Script Map

Use one script per purpose:

- `scripts/send_demo_telemetry.py`: send Windows-normalized UDP telemetry JSON to the iOS app.
- `scripts/receive_head_tracking.py`: receive iPhone head-tracking UDP JSON intent packets.
- `scripts/send_fake_head_tracking.py`: fake an iPhone by sending head-tracking JSON to the bridge harness.
- `scripts/iphone_companion_bridge.py`: log-only Windows ground-station bridge harness.
- `scripts/send_synthetic_rtp.py`: send synthetic RTP/H.265-like packets to the APFPV diagnostic receiver.
- `scripts/dev_check.sh`: run Python syntax checks and the Xcode test suite.

The old overlapping fake iPhone sender was removed. `send_fake_head_tracking.py` is now the canonical fake iPhone sender and includes pattern, disabled, uncentered, and malformed-packet modes.

For the focused bridge checklist, see `docs/WINDOWS_BRIDGE_LOG_ONLY_TEST.md`.

## Quick Command Summary

```sh
scripts/dev_check.sh

python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --rate 20
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --drop-after 5 --duration 10
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --malformed

python3 scripts/receive_head_tracking.py --port 5602 --timeout-ms 300 --print-rate

python3 scripts/iphone_companion_bridge.py --iphone-host 127.0.0.1 --duration 15
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --pattern sine
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --uncentered
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --malformed

python3 scripts/send_synthetic_rtp.py --host 127.0.0.1 --port 5600 --duration 5 --include-parameter-sets
```

## Simulator-Only Flow

1. Build and launch the app in iOS Simulator.
2. Open Debug / Setup.
3. Open Settings.
4. Keep demo mode on for initial visual sanity, then turn demo mode off for UDP telemetry tests.
5. Use `127.0.0.1` for Mac-to-Simulator UDP unless your local simulator runtime requires the Mac LAN IP.

Command-line launch, if desired:

```sh
xcodebuild -project FPVHUDApp.xcodeproj \
  -scheme FPVHUDApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/FPVHUDDerived \
  build

xcrun simctl boot "iPhone 17"
xcrun simctl install booted /private/tmp/FPVHUDDerived/Build/Products/Debug-iphonesimulator/FPVHUDApp.app
xcrun simctl launch booted com.example.FPVHUDApp
```

## Fake Telemetry To iOS Simulator

In the app, turn `Demo telemetry` off and keep telemetry port `5601`.

Send live telemetry:

```sh
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --rate 20 --profile normal
```

Expected result: Drive and Debug modes show live battery, LQ, RSSI, SNR, speed, gear, ERS, inputs, video lock, and packet age.

Test stale/lost behavior:

```sh
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --drop-after 5 --duration 10
```

Expected result: after packets stop, the HUD first shows stale telemetry, then `TELEMETRY DATA LOST >3S`; unsafe stale values clear to placeholders.

Test malformed telemetry:

```sh
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --malformed
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --profile noisy --malformed-every 10
```

Expected result: the app does not crash, valid telemetry continues, and the malformed count increases in Debug / Setup.

## Mock Motion To Head-Tracking Receiver

Start the receiver:

```sh
python3 scripts/receive_head_tracking.py --port 5602 --timeout-ms 300 --print-rate
```

In the Simulator app:

1. Set Windows host to `127.0.0.1`.
2. Set head-tracking output port to `5602`.
3. Turn tracking off and apply. No packets should arrive.
4. In Debug / Setup, use the `SIMULATOR / MOCK` motion controls.
5. Turn tracking on but do not center. No packets should arrive.
6. Tap Center, then move yaw/pitch/roll sliders. Packets should arrive at the configured send rate.
7. Tap Reset calibration or turn tracking off. Packets should stop and the receiver should warn after the timeout.

This validates packet plumbing and safety gating only. It does not validate real iPhone IMU axes, drift, or mounting.

## Fake iPhone Sender To Windows Bridge

Run the log-only bridge harness:

```sh
python3 scripts/iphone_companion_bridge.py --iphone-host 127.0.0.1 --duration 15
```

In another terminal, fake iPhone head tracking:

```sh
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --pattern sine
```

Useful variants:

```sh
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --pattern static
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --pattern sweep
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --pattern noisy
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --disable-after 2
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 5 --uncentered
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --malformed
python3 scripts/send_fake_head_tracking.py --host 127.0.0.1 --port 5602 --duration 3 --malformed-every 10
```

Expected result: the bridge logs packet rate, age, yaw/pitch/roll, enabled/centered state, validation errors, and stale state if packets stop.

## Windows Bridge Log-Only Test

The bridge harness represents the first Windows milestone but lives in this iOS repo for local testing. It forwards demo telemetry to the iPhone/Simulator and receives head-tracking intent.

For same-machine Simulator testing:

```sh
python3 scripts/iphone_companion_bridge.py \
  --iphone-host 127.0.0.1 \
  --telemetry-port 5601 \
  --head-port 5602 \
  --duration 30
```

For first real iPhone testing, replace `127.0.0.1` with the iPhone Wi-Fi IP for telemetry output, and set the app's Windows host to the Mac or Windows machine's LAN IP for head-tracking return traffic.

The bridge must remain log-only. It must not map iPhone yaw/pitch/roll to CRSF channels 9/10 in this milestone.

## APFPV Diagnostic Synthetic Test

Enable `APFPV RTP diagnostics` in Debug / Setup settings. Keep the diagnostic UDP port at `5600`.

Send synthetic RTP/H.265-like packets:

```sh
python3 scripts/send_synthetic_rtp.py \
  --host 127.0.0.1 \
  --port 5600 \
  --rate 60 \
  --duration 5 \
  --include-parameter-sets
```

Exercise gap and out-of-order counters:

```sh
python3 scripts/send_synthetic_rtp.py --host 127.0.0.1 --port 5600 --gap-every 20 --duration 5
python3 scripts/send_synthetic_rtp.py --host 127.0.0.1 --port 5600 --out-of-order-every 20 --duration 5
```

Expected result: Debug / Setup shows RTP fields, packet rate, approximate bitrate, sequence gaps, out-of-order packets, last packet age, and VPS/SPS/PPS detection where present.

This is diagnostics only. It does not assemble frames, does not decode H.265, and does not prove video latency.

## What Requires A Real iPhone

- Core Motion yaw/pitch/roll axes, sign conventions, drift, and update stability.
- Landscape-only behavior on physical safe areas, notch, and phone holders.
- iOS Local Network permission behavior.
- Real Wi-Fi routing between iPhone, Mac/Windows ground station, and APFPV camera AP.
- Thermal and battery behavior with motion, UDP, and future video work.

## What Requires An APFPV Camera

- Actual RTP payload type and packetization.
- H.265 VPS/SPS/PPS availability and cadence.
- Sequence gaps, jitter, and bitrate on the camera's Wi-Fi AP.
- Direct camera-to-iPhone UDP reachability.
- Any real latency measurement.

## Do Not Do Yet

- Do not map iPhone head tracking into CRSF channels 9/10.
- Do not command the car, ESC, servo, or gimbal from these scripts.
- Do not claim real APFPV video decode or latency from synthetic RTP tests.
- Do not add VideoToolbox decode until diagnostic receive behavior is understood.
- Do not treat Simulator mock motion as proof of real iPhone mount behavior.
