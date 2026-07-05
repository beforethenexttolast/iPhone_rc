# Windows Bridge Log-Only Test

This guide tests the iPhone companion bridge harness without an iPhone, RC car, APFPV camera, or Windows ground-station integration.

The bridge is log-only. It does not command vehicle hardware, does not map iPhone head tracking to CRSF channels 9/10, and does not interfere with joystick/control flow.

The packet contract is documented in `docs/PROTOCOL_CONTRACT.md`. The bridge accepts current version 1 head-tracking intent packets, including packets with or without the optional `protocol_version` field.

## What The Harness Does

- Forwards normalized demo telemetry snapshots to a configured iPhone or iOS Simulator UDP port.
- Receives fake or real iPhone head-tracking UDP JSON packets.
- Validates packet schema.
- Logs packet age, packet rate, yaw, pitch, roll, `tracking_enabled`, and `centered`.
- Marks head-tracking input stale if no valid packet arrives for more than the configured timeout, default `300 ms`.

## Configuration Fields

The harness exposes the bridge settings that the real Windows ground station will eventually need:

- `--bridge-enabled` / `--bridge-disabled`
- `--iphone-host`
- `--telemetry-port`
- `--head-bind-host`
- `--head-port`
- `--telemetry-rate`
- `--head-stale-ms`
- `--no-demo-telemetry`

Check available options:

```sh
python3 scripts/iphone_companion_bridge.py --help
```

Verify that disabled mode opens no UDP sockets:

```sh
python3 scripts/iphone_companion_bridge.py --bridge-disabled
```

## Start The Log-Only Bridge

For same-machine Simulator testing:

```sh
python3 scripts/iphone_companion_bridge.py \
  --bridge-enabled \
  --iphone-host 127.0.0.1 \
  --telemetry-port 5601 \
  --head-bind-host 0.0.0.0 \
  --head-port 5602 \
  --duration 15
```

Expected console output includes:

- `iPhone companion bridge harness: LOG-ONLY`
- `bridge_enabled=True`
- `telemetry -> ...`
- `head-tracking <- ...`
- periodic `head_rx_rate=... state=...` lines

## Send Fake iPhone Head Tracking

In another terminal:

```sh
python3 scripts/send_fake_head_tracking.py \
  --host 127.0.0.1 \
  --port 5602 \
  --duration 5 \
  --pattern sine
```

Expected bridge behavior:

- Valid packets are logged with sequence, age, yaw, pitch, roll, enabled, and centered.
- The rate line shows `state=ACTIVE` while packets are fresh, enabled, and centered.
- After packets stop, the bridge prints `HEAD TRACK STALE` and rate lines show `state=STALE`.

## Validate Non-Active States

Tracking disabled:

```sh
python3 scripts/send_fake_head_tracking.py \
  --host 127.0.0.1 \
  --port 5602 \
  --duration 5 \
  --disable-after 2
```

Expected result: after `--disable-after`, valid packets continue but rate lines show `state=INACTIVE`.

Not centered:

```sh
python3 scripts/send_fake_head_tracking.py \
  --host 127.0.0.1 \
  --port 5602 \
  --duration 5 \
  --uncentered
```

Expected result: packets are valid but rate lines show `state=NOT_CENTERED`.

## Validate Malformed Packet Rejection

One malformed packet:

```sh
python3 scripts/send_fake_head_tracking.py \
  --host 127.0.0.1 \
  --port 5602 \
  --malformed
```

Mixed malformed packets:

```sh
python3 scripts/send_fake_head_tracking.py \
  --host 127.0.0.1 \
  --port 5602 \
  --duration 3 \
  --malformed-every 10
```

Expected bridge behavior:

- Malformed payloads print a concise `invalid iPhone head packet ...` warning.
- Invalid packets increment the invalid count.
- Invalid packets do not replace the last valid head-tracking state.

## Confirm Telemetry Forwarding To Simulator

1. Launch the iOS app in Simulator.
2. Open Settings.
3. Turn demo telemetry off.
4. Keep telemetry port `5601`.
5. Run the bridge with `--iphone-host 127.0.0.1`.

Expected result: the iOS app displays live normalized telemetry from the bridge harness. Debug / Setup should show recent packet age.

## First Real iPhone Variant

Use the iPhone Wi-Fi IP for telemetry output:

```sh
python3 scripts/iphone_companion_bridge.py \
  --bridge-enabled \
  --iphone-host <iphone-wifi-ip> \
  --telemetry-port 5601 \
  --head-bind-host 0.0.0.0 \
  --head-port 5602
```

In the iPhone app, set the Windows host to the Mac or Windows machine LAN IP and set the head-tracking output port to `5602`.

macOS or Windows firewall prompts may appear. Allow Python or the bridge process to receive local UDP packets for this bench test.

## Safety Boundary

Do not proceed from this harness to active pan/tilt control until a separate reviewed milestone defines:

- Axis conventions and sign mapping from real iPhone Core Motion.
- Input priority with DualShock/right-stick pan/tilt.
- Limits, smoothing, timeout behavior, and failsafe behavior in Windows.
- Explicit mapping from Windows head-look intent to CRSF channels 9/10.

Until then, the bridge remains log-only.
