# FPVHUDApp

FPVHUDApp is the first iPhone companion-app scaffold for an RC car FPV system.

The Windows ground-station app remains the central control authority. This iPhone app is a thin client for:

- Low-latency FPV viewing in a later milestone.
- Native SwiftUI HUD display.
- Telemetry display from Windows-normalized car telemetry.
- Optional head-tracking yaw/pitch/roll input to Windows for future pan/tilt mapping.

The iPhone app does not directly command servos, ESCs, or the gimbal in this milestone.
Windows remains the integration point and authority for forwarding head-tracking input into the car-control path.
Video is a separate future path: the preferred low-latency iPhone Option A is direct APFPV RTP/UDP H.265 from camera to iPhone, not Windows-forwarded or Windows-re-encoded video.

## Architecture

The project is intentionally small and native:

```text
FPVHUDApp/
  App/          SwiftUI app entry point and view model
  UI/
    HUD/        Fullscreen FPV HUD views
    Screens/    Root view and settings/debug sheet
    Components/ Shared HUD controls and meters
  Models/       Telemetry, motion, and head-tracking data models
  Telemetry/    Demo source and future telemetry protocol seam
  Motion/       CoreMotion service plus simulator/mock service
  Networking/   UDP telemetry receiver and UDP head-tracking sender
  Video/        Placeholder video surface and RTP/H.265 stub notes
  Settings/     Runtime settings model
  Utilities/    Small formatting helpers
FPVHUDAppTests/  Focused protocol/model tests
```

`FPVHUDViewModel` owns the current app state and coordinates replaceable services:

- `TelemetrySource`
- `MotionService`
- `UDPTelemetryReceiver`
- `HeadTrackingSender`

## How To Run

Open the project in Xcode:

```sh
open FPVHUDApp.xcodeproj
```

Then select an iPhone simulator and run the `FPVHUDApp` scheme.

From a terminal with full Xcode selected, the simulator build command is:

```sh
xcodebuild -project FPVHUDApp.xcodeproj -scheme FPVHUDApp -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If `xcodebuild` reports that Command Line Tools are selected, switch to full Xcode first:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Real iPhone First Test

The app is prepared as a landscape-only iPhone target for first device testing. `Info.plist` declares Landscape Left and Landscape Right for iPhone, includes local network usage text for UDP telemetry/head-tracking traffic, and includes motion usage text for Core Motion head tracking.

### Install From Xcode

1. Connect the iPhone over USB, or pair it for wireless development in Xcode.
2. Open `FPVHUDApp.xcodeproj`.
3. Select the `FPVHUDApp` scheme and choose the real iPhone as the run destination.
4. In Signing & Capabilities, select your Apple Development team. If Xcode requires it, change the bundle identifier from `com.example.FPVHUDApp` to a unique value.
5. Build and run from Xcode. If iOS asks you to trust the developer app, follow the on-device prompt.

### Enable Developer Mode

On iOS 16 or newer, enable Developer Mode before or during the first Xcode install:

1. Open Settings on the iPhone.
2. Go to Privacy & Security -> Developer Mode.
3. Turn Developer Mode on, restart, and confirm after reboot.

If Developer Mode is not visible, try running the app from Xcode once with the phone connected.

### Landscape Test

Hold or mount the phone in landscape before testing. The current product target is FPV driving and possible phone-based VR goggles, so portrait does not provide a full HUD. Test both landscape directions and confirm Drive mode returns to a normal landscape layout after opening and closing Debug or Settings.

### Local Network Test

The first UDP network use may trigger the iOS Local Network permission prompt. Allow it for telemetry receive and head-tracking send tests. If permission is denied accidentally, re-enable it in iOS Settings -> Privacy & Security -> Local Network.

Demo mode does not require network access. Real telemetry mode expects the Windows ground station to normalize CRSF/ELRS telemetry and forward JSON snapshots to the iPhone telemetry port.

### Core Motion Test

The simulator uses mock motion. A real iPhone uses Core Motion.

1. Open Debug / Setup.
2. Enable head tracking.
3. Hold the phone in its intended neutral mount position.
4. Tap Center/Calibrate.
5. Move the phone and confirm raw and centered yaw/pitch/roll update.

Head-tracking UDP packets must not send until tracking is enabled and the phone has been centered/calibrated. Calibration is intentionally not persisted across launches.

### UDP Telemetry Receiver Test

Disable demo mode, then send a normalized JSON snapshot to the iPhone IP and telemetry port, default `5601`:

```python
import json
import socket
import time

IPHONE_IP = "192.168.1.50"
PORT = 5601

packet = {
    "timestamp_ms": int(time.time() * 1000),
    "battery_v": 14.8,
    "link_quality": 92,
    "rssi_dbm": -62,
    "snr_db": 18,
    "speed_kmh": 12.4,
    "gear": 3,
    "drive_mode": "GEARBOX_ERS",
    "ers_percent": 55,
    "throttle": 0.43,
    "brake": 0.0,
    "steering": -0.15,
    "camera_yaw_deg": -12.0,
    "camera_pitch_deg": 5.0,
    "head_tracking_mode": "OFF",
    "video_lock": True,
    "warning": ""
}

socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(
    json.dumps(packet).encode("utf-8"),
    (IPHONE_IP, PORT)
)
```

Confirm the HUD shows live values and Debug / Setup shows recent packet age. Stop sending packets and confirm the HUD transitions through stale and lost telemetry states instead of presenting old values as live.

### UDP Head-Tracking Sender Test

Run the Python UDP receiver from the `Head Tracking UDP Intent` section on the Windows ground-station machine or another computer on the same LAN. Set the app's Windows host and head-tracking port to that machine, enable tracking, center/calibrate, then confirm JSON packets arrive.

Safety reminders for first bench tests:

- Demo mode may default on.
- Tracking defaults off.
- Sending is blocked until tracking is enabled and centered/calibrated.
- The app sends camera-look intent only to Windows.
- The iPhone app does not directly command servos, pan/tilt channels, or the car.
- The APFPV RTP/H.265 receiver is still stubbed and does not auto-start.

## Implemented

- Fullscreen SwiftUI FPV placeholder screen.
- High-contrast native HUD overlay inspired by `references/f1_hud.html`.
- Top status bar with battery, link quality, RSSI, SNR, video lock, recording standby, and tracking state.
- Center crosshair.
- Speed, gear, drive mode, ERS, throttle, brake, steering, camera yaw/pitch, pan/tilt mode, and head yaw/pitch/roll readouts.
- Visible `SIM / DEMO` and `NO VIDEO` indicators.
- Animated demo telemetry mode.
- UDP telemetry receiver stub using `Network.framework`.
- Core Motion interface with real-device and simulator/mock implementations.
- UDP head-tracking sender stub with center/calibrate support.
- Settings/debug sheet for host, ports, demo mode, and tracking enable.
- UserDefaults-backed settings persistence with reset-to-defaults.

## Settings Persistence

The app persists runtime settings with `SettingsStore`:

- Windows host IP.
- Telemetry UDP port.
- Head-tracking UDP port.
- Motion and head-tracking send rates.
- Head-tracking packet timeout.
- Demo mode enabled/disabled.
- Tracking enabled/disabled.

Defaults are intentionally conservative: demo mode defaults on, and head tracking defaults off. Calibration is not persisted across launches; use `Center / calibrate` after mounting the phone before head-tracking packets are allowed to send. The settings/debug panel includes `Reset settings to defaults`.

## Telemetry Snapshot

When demo mode is off, the app listens for UDP JSON on the configured telemetry port.

The car and ground-station roadmap already define the upstream telemetry sources:

- CRSF battery frame `0x08` for battery voltage.
- `LINK_STATISTICS` from the ground TX module for link quality.
- CRSF GPS frame `0x02` groundspeed for real wheel speed.
- CRSF FLIGHTMODE frame `0x21` strings such as `G3 M2 E55` for gear, drive mode, and ERS.

The iPhone app does not parse raw CRSF in this milestone. It expects the Windows ground-station app to normalize and merge those sources into a simple UDP JSON snapshot.

Telemetry is independent from the future native APFPV video path. Windows forwards telemetry snapshots; it does not need to forward video for the preferred iPhone path.

Example packet:

```json
{
  "timestamp_ms": 12345678,
  "battery_v": 14.8,
  "link_quality": 92,
  "rssi_dbm": -62,
  "snr_db": 18,
  "speed_kmh": 12.4,
  "gear": 3,
  "drive_mode": "GEARBOX_ERS",
  "ers_percent": 55,
  "throttle": 0.43,
  "brake": 0.0,
  "steering": -0.15,
  "camera_yaw_deg": -12.0,
  "camera_pitch_deg": 5.0,
  "head_tracking_mode": "OFF",
  "video_lock": true,
  "warning": ""
}
```

Control values are normalized:

- `throttle`: `0.0...1.0`
- `brake`: `0.0...1.0`
- `steering`: `-1.0...1.0`
- `link_quality`: `0...100`
- `ers_percent`: `0...100`

Supported enum values:

- `drive_mode`: `TRAINING`, `GEARBOX`, `GEARBOX_ERS` or equivalent short tokens.
- `head_tracking_mode`: `OFF`, `DS4`, `HEAD_TRACKING`, `MIXED` or equivalent short tokens.
- Optional `stale_data_warnings`: `battery`, `linkQuality`, `speed`, `flightMode`, `camera`, `video`

Receiver behavior:

- Demo mode remains the fallback and does not require UDP packets.
- With demo mode disabled, the app listens on the configured telemetry UDP port.
- `timestamp_ms` is accepted from Windows, but stale detection and packet age are based on iPhone receive time.
- Malformed JSON is ignored safely and increments the debug malformed-packet count.
- If no valid telemetry arrives for more than 1 second, the HUD shows `TELEMETRY STALE >1S`.
- If no valid telemetry arrives for more than 3 seconds, the HUD shows `TELEMETRY DATA LOST >3S`.
- The settings/debug panel shows UDP listener state, last packet age, and malformed-packet count.

## Head Tracking UDP Intent

When enabled and motion is fresh, the app sends UDP JSON packets to the configured Windows host and output port at the configured `30...60 Hz` send rate:

```json
{
  "seq": 1,
  "timestamp_ms": 1783184400000,
  "yaw_deg": -12.5,
  "pitch_deg": 6.8,
  "roll_deg": 1.2,
  "tracking_enabled": true,
  "centered": true,
  "timeout_ms": 250
}
```

This is input telemetry for the Windows app only. It is not a direct vehicle-control path.
The current car firmware already supports gimbal pan/tilt on CRSF channels 9/10, currently fed by the right DualShock stick through `elrs-joystick-control`; future head tracking should be integrated by Windows as another input source, not by the iPhone directly commanding the car.
Windows should ignore packets older than `timeout_ms` relative to its receive time or local clock policy. The iPhone includes `timeout_ms` so Windows can reject stale head-look intent without guessing.

The settings/debug panel shows:

- Configured UDP state.
- Actual packet rate.
- Packet count.
- Last send age.
- Last send error, if any.

### Python UDP Receiver

For a simple local test, run this on the Windows ground-station machine and set the iPhone `Windows host IP` to that machine's LAN IP:

```python
import json
import socket
import time

PORT = 5602

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", PORT))
print(f"listening on UDP {PORT}")

while True:
    data, addr = sock.recvfrom(2048)
    received_ms = int(time.time() * 1000)
    try:
        packet = json.loads(data.decode("utf-8"))
    except json.JSONDecodeError as exc:
        print(f"{addr} bad json: {exc}")
        continue

    age_ms = received_ms - int(packet.get("timestamp_ms", received_ms))
    timeout_ms = int(packet.get("timeout_ms", 250))
    stale = age_ms > timeout_ms
    print(addr, packet, "age_ms=", age_ms, "stale=", stale)
```

## Testing Head Tracking On iPhone

The simulator uses `MockMotionService`; a real iPhone uses `CoreMotionService`.

1. Open `FPVHUDApp.xcodeproj` in Xcode.
2. Select a real iPhone target and run with your Apple development team selected.
3. Open settings in the HUD.
4. Set the Windows host IP and head-tracking UDP port.
5. Set the motion update rate and head send rate; both default to `60 Hz`.
6. Set the tracking timeout; the default is `250 ms`.
7. Tap `Center / calibrate` with the phone in the mounted neutral position.
8. Enable `Head tracking input to Windows`.

The debug panel shows raw yaw/pitch/roll, centered yaw/pitch/roll, and stored center offsets.
Drive mode uses compact head-tracking labels:

- `HEAD OFF`: tracking output is disabled.
- `HEAD NOT CENTERED`: tracking is enabled, but center/calibrate has not been performed, so no packets are sent.
- `HEAD ACTIVE`: motion is fresh and yaw/pitch/roll intent packets are being sent to Windows.
- `HEAD STALE`: the latest motion sample is stale.

Debug / Setup may show more verbose sender wording:

- `HEAD TX OFF`
- `HEAD TX READY - NOT CENTERED`
- `HEAD TX ACTIVE`
- `HEAD TX STALE`
- `HEAD TX ERROR`

These packets are still only intent packets to Windows. The iPhone app does not send CRSF and does not directly command the car or gimbal.

Head tracking is independent from the future native APFPV video path. The phone may eventually receive video directly from the APFPV camera while still sending head-look intent only to Windows.

## Future Native APFPV Video

The Windows roadmap identifies H.265/WebRTC/live video as a bench risk on the Windows side. That does not change the preferred low-latency iPhone Option A:

```text
APFPV RTP/UDP H.265
  -> iPhone UDP receiver
  -> RTP/H.265 depacketizer
  -> VideoToolbox decoder
  -> video surface
  -> SwiftUI/UIKit HUD overlay
```

This path should stay separate from:

- Windows-normalized telemetry JSON.
- iPhone-to-Windows head-tracking UDP intent.
- Car command mixing, limits, failsafe, and CRSF channel mapping.

Windows remains responsible for telemetry forwarding and head-tracking integration. It is not assumed to forward, proxy, or re-encode video for the iPhone native path.

## Intentionally Stubbed

- Real OpenIPC/APFPV RTP/H.265 reception.
- HEVC depacketization.
- VideoToolbox decode.
- WebRTC.
- Windows app changes.
- Any direct servo, ESC, or gimbal command path from iPhone.
- Raw CRSF parsing inside the iPhone app.

## Next Milestones

1. Align the UDP JSON snapshot with the Windows ground-station implementation.
2. Add packet age/staleness presentation for telemetry and head-tracking output.
3. Bench-test Core Motion orientation conventions on a real iPhone mount.
4. Implement native APFPV RTP/H.265 receive/depacketize/decode behind `VideoSurface`.
5. Add a future optional CRSF parser module only if iOS ever needs direct CRSF ingest.
6. Measure real end-to-end video latency on hardware.

No real iPhone video latency is proven by this milestone; it proves app structure, HUD behavior, mock telemetry, motion plumbing, and network stubs.
