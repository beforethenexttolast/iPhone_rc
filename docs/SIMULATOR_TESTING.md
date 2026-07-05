# Simulator Testing

This guide validates the iOS FPV HUD app in Simulator with local UDP scripts. It does not prove real iPhone Core Motion behavior, real iPhone Wi-Fi behavior, APFPV video latency, or any vehicle-control path.

## What This Covers

- Launching the app in iOS Simulator.
- Sending normalized UDP telemetry from the Mac to the Simulator app.
- Stopping telemetry to verify stale and lost display behavior.
- Sending malformed telemetry to verify robust JSON rejection.
- Checking settings validation.
- Verifying head-tracking packets are not sent until tracking is enabled and centered, using simulator mock motion.

## Build And Launch

The easiest path is Xcode:

1. Open `FPVHUDApp.xcodeproj`.
2. Select the `FPVHUDApp` scheme.
3. Select an iPhone Simulator, for example `iPhone 17`.
4. Run the app.

For a command-line launch with a predictable app path:

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

If the simulator is already booted, `xcrun simctl boot` may report that it is already booted; that is harmless.

## Mac To Simulator Telemetry

In the app:

1. Open Debug / Setup.
2. Open Settings.
3. Turn `Demo telemetry` off.
4. Keep telemetry UDP port at `5601`.
5. Apply settings.

From the repo root on the Mac, send telemetry to the Simulator app:

```sh
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --rate 20 --profile normal
```

Expected result:

- HUD exits demo display and shows live telemetry.
- Battery, LQ, RSSI, SNR, speed, gear, ERS, throttle, brake, steering, video state, and warnings update.
- Debug / Setup shows recent telemetry packet age.

If `127.0.0.1` does not work on your simulator/runtime combination, try the Mac Wi-Fi IP address as `--host`.

## Stale And Lost Telemetry

Send telemetry for five seconds, then stop sending while the script stays alive:

```sh
python3 scripts/send_demo_telemetry.py \
  --host 127.0.0.1 \
  --port 5601 \
  --rate 20 \
  --profile normal \
  --drop-after 5 \
  --duration 10
```

Expected result:

- During the first five seconds, values look live.
- About one second after packets stop, the HUD shows stale telemetry warning.
- After more than three seconds without packets, the HUD shows `TELEMETRY DATA LOST >3S`.
- Lost state clears unsafe stale values to placeholders such as `--.- V`, `--`, `-- km/h`, gear `--`, and ERS `--`.

The `stale` profile can also mark source fields as stale while packets are still flowing:

```sh
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --profile stale
```

## Malformed Telemetry

Send one malformed packet:

```sh
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --malformed
```

Send mostly valid telemetry with every tenth packet malformed:

```sh
python3 scripts/send_demo_telemetry.py --host 127.0.0.1 --port 5601 --profile noisy --malformed-every 10
```

Expected result:

- The app does not crash.
- Debug / Setup malformed-packet count increases.
- Valid packets continue to update the HUD.

## Settings Validation

Manual checks:

1. Open Settings.
2. Set Windows host to an empty string or `bad_host_name`.
3. Confirm an inline validation message appears.
4. Confirm Apply is disabled and settings are not saved.
5. Enter a valid value such as `127.0.0.1` or `groundstation.local`.
6. Confirm Apply is enabled.

Numeric fields use bounded controls in the UI, so edge cases such as port `0`, port `65536`, send rate `61`, and timeout `99 ms` are covered by unit tests:

```sh
xcodebuild -project FPVHUDApp.xcodeproj \
  -scheme FPVHUDApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## Simulator Head-Tracking Gating

The Simulator uses `MockMotionService`, so it can validate packet plumbing and safety gating, but not real IMU orientation or mount geometry.

Start the local receiver:

```sh
python3 scripts/receive_head_tracking.py --port 5602 --timeout-ms 300 --print-rate
```

In the app:

1. Open Debug / Setup.
2. Open Settings.
3. Set Windows host to `127.0.0.1`.
4. Set head-tracking UDP port to `5602`.
5. Leave `Head tracking input to Windows` off and apply.

Expected result: receiver prints no head-tracking packets.

Now enable tracking but do not center:

1. Open Settings.
2. Turn `Head tracking input to Windows` on.
3. Apply settings.
4. Do not tap Center/Calibrate yet.

Expected result:

- Drive mode should show `HEAD NOT CENTERED`.
- Receiver still prints no head-tracking packets.

Now center/calibrate:

1. In Debug / Setup, tap Center/Calibrate.
2. Watch the receiver output.

Expected result:

- Receiver prints JSON packets with `tracking_enabled=true` and `centered=true`.
- Packet rate should be close to the configured head send rate, normally `30...60/s`.
- Disable tracking or tap Reset calibration; packets should stop.
- The receiver warns if packets stop for more than `300 ms`.

## Script Reference

Telemetry sender:

```sh
python3 scripts/send_demo_telemetry.py --help
```

Useful options:

- `--host`: destination IP, usually `127.0.0.1` for Simulator.
- `--port`: telemetry UDP port, default `5601`.
- `--rate`: telemetry packet rate in Hz.
- `--duration`: total runtime, or send duration when `--drop-after` is not used.
- `--drop-after`: stop sending after N seconds while the process stays alive.
- `--malformed`: send one malformed payload and exit.
- `--malformed-every N`: mix malformed packets into a live stream.
- `--profile normal|stale|noisy`: choose telemetry behavior.

Head-tracking receiver:

```sh
python3 scripts/receive_head_tracking.py --help
```

Useful options:

- `--port`: UDP listen port, default `5602`.
- `--timeout-ms`: no-packet warning threshold, default `300`.
- `--print-rate`: print packet rate once per second.
- `--no-print-rate`: suppress packet-rate lines.

## Boundaries

Simulator testing does not validate:

- Real iPhone Core Motion axes, drift, or mount calibration.
- Real iPhone local-network permission behavior.
- Real APFPV RTP/H.265 video reception or latency.
- Windows ground-station integration.
- Any car, servo, gimbal, ESC, or CRSF channel behavior.

The iPhone app still sends camera-look intent only. It does not directly command the car.
