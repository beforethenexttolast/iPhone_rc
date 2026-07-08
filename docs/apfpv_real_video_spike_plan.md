# APFPV Real Video Spike Plan

Last updated: 2026-07-08

This plan defines the first real-video spike for the existing W17 iPhone FPV HUD app.

This is planning only. Do not implement decoding from this document. Do not make latency claims until measured on real hardware. Do not change firmware. Do not make the video path affect vehicle control, failsafe, telemetry authority, or head-tracking authority. Do not remove the existing diagnostic APFPV receiver stub.

## Scope

The spike answers one question:

Can the iPhone receive and display usable low-latency FPV video from the OpenIPC/APFPV system, and which path should become the first production candidate?

The spike does not authorize:

- H.265 VideoToolbox implementation before packet diagnostics are complete.
- WebRTC/WHEP implementation before a supported stream source is proven.
- Windows re-encode/proxy as a default assumption.
- Vehicle control changes.
- CRSF changes.
- Servo, pan, tilt, gimbal, ESC, or car movement.
- Video-dependent control/failsafe behavior.

## 1. Current App Video State

### What Exists

The app currently has a video-first SwiftUI HUD with a mocked video surface:

- `FPVHUDApp/Video/VideoSurface.swift` draws the placeholder background and `NO VIDEO` / `APFPV RTP / H.265 PIPELINE STUBBED` message.
- Drive mode overlays compact HUD widgets over the placeholder.
- Debug / Setup mode exposes APFPV diagnostic status when enabled.
- `FPVHUDApp/Video/FutureRTPHEVCReceiver.swift` documents the planned future native path:

```text
APFPV RTP/UDP H.265
  -> iPhone UDP receiver
  -> RTP/H.265 depacketizer
  -> VideoToolbox decoder
  -> video surface
  -> SwiftUI/UIKit HUD overlay
```

### What Is Diagnostic-Only

`FPVHUDApp/Video/APFPVDiagnosticReceiver.swift` is diagnostic-only. It can listen on a configured UDP port and parse packet-level metadata:

- RTP version.
- RTP payload type.
- RTP sequence number.
- RTP timestamp.
- RTP SSRC.
- Packets per second.
- Approximate bitrate.
- Sequence gaps.
- Out-of-order packets.
- Last packet age.
- H.265 NAL type where possible.
- VPS/SPS/PPS detection where possible.

It does not:

- Assemble H.265 frames.
- Depacketize full access units.
- Decode video.
- Use VideoToolbox.
- Replace the mock video surface.
- Prove latency.

APFPV diagnostics are off by default and session-only.

### What Is Mocked Or Stubbed

- Drive mode video is a visual placeholder.
- APFPV RTP/H.265 native decode is stubbed.
- H.265 frame assembly is not implemented.
- VideoToolbox decode is not implemented.
- WebRTC/WHEP playback is not implemented.
- Windows video relay/transcode is not implemented in this repo.

### Existing Tests

Current automated coverage includes:

- Synthetic RTP header parsing tests.
- Invalid RTP version / short packet rejection tests.
- H.265 NAL type inspection tests.
- VPS/SPS/PPS detection tests.
- Fragmentation-unit original NAL type inspection tests.
- Synthetic RTP packet sender workflow through `scripts/send_synthetic_rtp.py`.

Current docs already separate diagnostics from decode:

- `docs/OPENIPC_APFPV_DIAGNOSTIC_TEST_PLAN.md`
- `docs/PROTOCOL_CONTRACT.md`
- `docs/BENCH_TEST_RUNBOOK.md`
- `docs/ROADMAP_AND_DECISIONS.md`

No real OpenIPC/APFPV camera capture has been validated yet.

## 2. Candidate Video Paths

### A. Direct iPhone To OpenIPC/APFPV RTP/H.265

```text
OpenIPC/APFPV camera
  -> Wi-Fi RTP/UDP H.265
  -> iPhone UDP receiver
  -> RTP/H.265 depacketizer
  -> VideoToolbox HEVC decoder
  -> iPhone video surface
  -> SwiftUI/UIKit HUD overlay
```

Why test it:

- It is the preferred low-latency iPhone path if APFPV packets are reachable and decodable on iOS.
- It avoids Windows re-encode latency and CPU cost.
- It keeps video independent from telemetry/head tracking.

Main risks:

- APFPV may use H.265 in a packetization shape that needs careful depacketization.
- iOS may require parameter sets or sample timing in a specific format.
- APFPV Wi-Fi may not route packets cleanly to iPhone while Windows telemetry/head tracking also works.
- Windows viewing may be affected if APFPV supports only one client or one selected output target.

Spike prerequisites:

- Real APFPV capture confirms UDP port, RTP behavior, H.265 packetization, parameter sets, keyframe cadence, and bitrate.
- iPhone can receive the APFPV UDP stream in diagnostic mode.
- No dependency on Windows forwarding/re-encoding.

### B. Direct iPhone To MediaMTX/WebRTC/WHEP

```text
Camera or local video service
  -> MediaMTX / WebRTC / WHEP endpoint
  -> iPhone WebRTC/WHEP client
  -> video surface
  -> HUD overlay
```

Why test it:

- It may simplify iPhone playback if the stream is H.264 and served through a standard browser/mobile-friendly path.
- WebRTC/WHEP can handle jitter, timing, and network adaptation.

Main risks:

- The camera/APFPV source may be H.265-only.
- H.265 in WebRTC support is less universal than H.264.
- Transcoding to H.264 may add latency and CPU load.
- A WebRTC stack adds complexity compared with native UDP/VideoToolbox.

Spike prerequisites:

- A camera, MediaMTX, or relay path can produce a WHEP/WebRTC stream the iPhone can decode.
- Codec is confirmed, ideally H.264 for broad compatibility.
- End-to-end latency is measured, not assumed.

### C. Windows Receives Video And Relays/Transcodes To iPhone

```text
OpenIPC/APFPV camera
  -> Windows ground station receive
  -> optional relay/transcode/repacketize
  -> iPhone video client
  -> HUD overlay
```

Why test it:

- It may preserve Windows as the known video receiver if direct iPhone is blocked by protocol, codec, Wi-Fi routing, or APFPV client limitations.
- It may allow Windows to produce an iPhone-friendly stream such as H.264/WebRTC.

Main risks:

- Added latency.
- Windows CPU/GPU load.
- More moving parts in the ground station.
- Potential interference with control-loop responsiveness if implemented poorly.

Hard rule:

- Windows video relay/transcode must not block or degrade joystick/control mixing, failsafe logic, telemetry forwarding, or head-tracking receive.

### D. User-Selected Video Target: Windows Only Or iPhone Only

```text
Operator selects:
  - Windows viewer target
  - iPhone viewer target
```

Why test it:

- Some APFPV/camera configurations may handle one primary video destination reliably but not two.
- Operator-selected target mode may be safer than unstable simultaneous viewing.

Main risks:

- Operator workflow must be clear.
- Switching targets may interrupt video.
- Telemetry and head tracking still need to continue regardless of selected video target.

Pass condition:

- The selected target receives stable video.
- Non-selected client remains safe and clearly shows no video.
- Control path is unaffected.

### E. Simultaneous Windows And iPhone Viewing

```text
OpenIPC/APFPV camera
  -> Windows viewer
  -> iPhone viewer
```

or:

```text
OpenIPC/APFPV camera
  -> relay/multicast/split path
  -> Windows viewer + iPhone viewer
```

Why test it:

- It is operationally attractive: Windows ground station retains video while iPhone/VR HUD also gets video.

Main risks:

- APFPV camera may not support multiple unicast viewers.
- Wi-Fi bitrate may not support two clients.
- Packet loss may increase.
- Windows and iPhone may compete for airtime.
- Simultaneous mode may be less stable than selected-target mode.

Pass condition:

- Both clients remain stable at the same time.
- Packet loss/freezes remain acceptable.
- Control/telemetry/head tracking remain unaffected.

## 3. Measurements

Record measurements per candidate path. Do not compare paths unless the same camera settings, Wi-Fi topology, lighting, and test duration are used.

### Stream And Codec

Record:

- Codec: H.264 or H.265/HEVC.
- Resolution.
- Frame rate.
- GOP/keyframe interval.
- Bitrate target and observed bitrate.
- RTP payload type if RTP.
- RTP packetization mode.
- VPS/SPS/PPS or SPS/PPS availability and cadence.
- Whether stream is unicast, multicast, broadcast, WebRTC, WHEP, or other.

### iOS Decoder Path

Record:

- Native RTP/H.265 + VideoToolbox candidate.
- H.264 path if available.
- WebRTC/WHEP path if used.
- Hardware decode confirmed or unknown.
- Startup requirements such as parameter sets and keyframe wait.
- Decoder errors or unsupported codec messages.

### Glass-To-Glass Latency

Measure only on real hardware.

Suggested methods:

- Stopwatch or high-refresh timer in camera view, recorded by the iPhone screen or external camera.
- LED flash / physical event visible to camera and display.
- High-speed phone/camera recording both source event and iPhone/Windows display if available.

Record:

- Median observed latency.
- Best observed latency.
- Worst observed latency.
- Test method.
- Camera settings.
- Display brightness and screen recording status.

Do not make latency claims from synthetic RTP tests, simulator tests, or packet diagnostics alone.

### Startup Time

Measure:

- Time from app receiver start to first decoded frame.
- Time from camera stream start to first decoded frame.
- Time after Wi-Fi reconnect to first decoded frame.
- Time after app background/foreground to video recovery.
- Time waiting for keyframe or parameter sets.

### Packet Loss, Freezes, And Recovery

Record:

- Packet loss or sequence gaps.
- Out-of-order packets.
- Visible freezes.
- Freeze duration.
- Decoder recovery behavior.
- Whether recovery requires a keyframe.
- Whether the HUD clearly shows video lost or stale.

### iPhone Temperature And Battery

Record:

- iPhone model.
- iOS version.
- Screen brightness.
- Approximate starting/ending battery percent.
- Test duration.
- Whether the phone becomes warm/hot.
- Thermal warnings if visible.
- Frame drops or performance degradation over time.

### Wi-Fi Bitrate And Link Behavior

Record:

- Wi-Fi SSID / AP mode.
- Camera/AP channel and band if known.
- iPhone IP.
- Windows/Mac IP.
- Observed video bitrate.
- Packet rate.
- Link quality from telemetry if available.
- Whether telemetry/head-tracking UDP remains stable during video.
- Whether simultaneous viewing increases packet loss.

### Windows Load For Relay/Transcode Paths

Only for candidate C or any relay/transcode path, record:

- Windows CPU usage.
- Windows GPU usage if applicable.
- Process memory.
- Encoder/transcoder settings.
- Output codec.
- Output bitrate.
- Added latency.
- Control-loop timing warnings if available.
- Telemetry publish jitter if available.
- Head-tracking receive packet loss/stale events.

## 4. Pass/Fail Criteria

### General Pass Criteria

A candidate path passes the spike only if:

- Video starts reliably across repeated runs.
- Startup time is acceptable for FPV use.
- Measured glass-to-glass latency is acceptable for FPV use.
- No major freezes occur during the test window.
- Video loss is detected and shown clearly.
- Unsupported codec/protocol is shown clearly.
- Windows control path is unaffected.
- Telemetry and head-tracking remain independent of video state.
- App remains responsive.
- iPhone temperature and battery behavior are acceptable for the intended test duration.

### General Fail Criteria

A candidate path fails the spike if:

- Video cannot start reliably.
- Codec or protocol cannot be decoded on the selected path.
- Latency is too high for FPV use.
- Frequent freezes occur.
- Video failure causes app instability.
- Video path interferes with telemetry/head tracking.
- Windows relay/transcode causes unacceptable CPU/GPU load or control-loop risk.
- The operator cannot clearly tell whether video is live, stale, lost, or unsupported.

### Simultaneous Viewing Pass Criteria

Candidate E passes only if:

- Windows and iPhone both receive stable video simultaneously.
- Both clients recover from brief packet loss or reconnect.
- Wi-Fi bitrate remains within a stable margin.
- No major freezes occur on either client.
- Windows control path remains unaffected.
- Telemetry and head-tracking remain stable.

If either client becomes unstable, simultaneous viewing fails and selected-target mode should be preferred for the next milestone.

## 5. Decision Rule

Use this decision rule after real measurements:

1. If direct iPhone APFPV RTP/H.265 is stable and low-latency, prefer direct iPhone video.
2. If direct iPhone video works but breaks or destabilizes Windows viewing, use selected-target mode: Windows only or iPhone only.
3. If direct iPhone video fails because of codec, protocol, routing, or APFPV stream limitations, test Windows relay/transcode.
4. If Windows relay/transcode works but latency is too high for FPV, keep iPhone video experimental/diagnostic.
5. If simultaneous Windows+iPhone viewing is stable, document it as a supported candidate; otherwise do not rely on it.
6. If no path meets FPV latency and stability requirements, keep Drive mode on the placeholder/diagnostic path and do not claim real-video readiness.

## 6. Safety Note

Video failure must not affect vehicle control or failsafe.

Rules:

- Control authority remains with Windows/control chain.
- Firmware does not know about iPhone video.
- Video success must not enable vehicle control.
- Video failure must not disable failsafe.
- Video failure must not alter joystick/control mixing.
- Video failure must not alter CRSF output.
- Head-tracking intent must remain gated by tracking enabled + centered/calibrated + fresh motion.
- No control commands may depend on video success.
- The app must clearly show `NO VIDEO`, `VIDEO LOST`, or `UNSUPPORTED CODEC` when appropriate.
- APFPV diagnostics and future video decode must remain independent from telemetry and head-tracking services.

## 7. Test Runbook

This runbook starts after `docs/OPENIPC_APFPV_DIAGNOSTIC_TEST_PLAN.md` has identified the real APFPV UDP/RTP stream.

### Required Equipment

- Real iPhone with the FPV HUD app installed.
- OpenIPC camera with Greg's APFPV firmware.
- Windows ground station present for control/telemetry context.
- Mac/Linux laptop for packet capture and notes.
- Wireshark and/or `tcpdump`.
- Optional high-speed recording device for latency measurements.
- Optional phone holder or VR-style phone glasses.
- Power source for camera and phone for longer tests.

### Network Topology To Record

Record the exact topology before each run:

- APFPV camera Wi-Fi SSID.
- Camera/AP IP.
- iPhone IP.
- Windows IP.
- Laptop capture IP.
- Whether iPhone and Windows are on the APFPV AP, same LAN, or bridged networks.
- UDP video destination behavior: unicast, multicast, broadcast, selected target, relay.
- Telemetry UDP path: Windows -> iPhone.
- Head-tracking UDP path: iPhone -> Windows.

### Baseline Capture

Before attempting decode:

1. Connect laptop to APFPV network.
2. Capture candidate UDP video traffic.
3. Confirm UDP port, RTP behavior, payload type, SSRC, sequence behavior, bitrate, and H.265 NAL types.
4. Save `.pcap` files and Wireshark screenshots.
5. Enable iPhone APFPV diagnostics and confirm packet count/rate/bitrate update.
6. Capture Debug / Setup screenshot showing APFPV diagnostic stats.

Required artifacts:

- `tcpdump` command used.
- `.pcap` filename.
- Wireshark screenshot of RTP fields.
- iPhone Debug / Setup APFPV diagnostic screenshot.
- Notes on packet gaps/out-of-order/NAL types/VPS/SPS/PPS.

### Candidate A: Direct iPhone APFPV RTP/H.265

Only after diagnostics are understood, plan a separate implementation spike for native decode.

When that implementation exists, test:

1. Launch app in Drive mode.
2. Start direct APFPV video receive.
3. Record startup time to first frame.
4. Record 5 minute stability test.
5. Measure glass-to-glass latency.
6. Stop/restart camera stream.
7. Disconnect/reconnect Wi-Fi.
8. Background/foreground app.
9. Confirm telemetry still updates.
10. Confirm head-tracking sender gating still behaves.
11. Confirm Windows control path is unaffected.

Logs/screenshots:

- iPhone screen recording or external recording.
- App Debug stats.
- Packet stats.
- Thermal/battery notes.
- Windows control/telemetry logs showing no interference.

### Candidate B: WebRTC/WHEP

If a MediaMTX/WebRTC/WHEP source is available:

1. Record source codec and transcode settings.
2. Confirm iPhone can connect to WHEP/WebRTC endpoint.
3. Record startup time.
4. Measure glass-to-glass latency.
5. Run 5 minute stability test.
6. Check if stream remains stable while telemetry/head tracking run.
7. Record server CPU and logs if transcoding is involved.

Pass only if latency and stability are acceptable for FPV.

### Candidate C: Windows Relay/Transcode

If Windows receives and relays/transcodes video:

1. Start Windows ground station without active vehicle control changes.
2. Start camera video into Windows.
3. Start relay/transcode output to iPhone.
4. Record Windows CPU/GPU/memory.
5. Measure iPhone startup time and glass-to-glass latency.
6. Run 5 minute stability test.
7. Check telemetry forwarding.
8. Check head-tracking receive/log-only behavior.
9. Check control-loop timing and failsafe logs.

Fail this path if relay/transcode risks the control path or adds unacceptable latency.

### Candidate D: Selected Target

Test Windows-only:

1. Select Windows as video target.
2. Confirm Windows video stable.
3. Confirm iPhone clearly shows no video or unsupported target.
4. Confirm iPhone telemetry/head tracking still work.

Test iPhone-only:

1. Select iPhone as video target.
2. Confirm iPhone video stable.
3. Confirm Windows control path remains stable without local video or with its expected no-video state.
4. Confirm telemetry/head tracking still work.

Record switching behavior:

- How long target switch takes.
- Whether camera stream restarts.
- Whether either app needs manual reconnect.
- Whether telemetry/head tracking continue during switch.

### Candidate E: Simultaneous Viewing

1. Start Windows viewing.
2. Start iPhone viewing.
3. Record both clients side by side if possible.
4. Run at least 5 minutes.
5. Record packet loss/freezes on both clients.
6. Measure latency on both clients if possible.
7. Confirm Windows control path remains unaffected.
8. Confirm telemetry/head tracking remain stable.

Pass only if both clients are stable together. If not, prefer selected-target mode.

### Required Result Template

Use one row per candidate/path/run.

| Field | Value |
| --- | --- |
| Date/time |  |
| Commit/build |  |
| iPhone model/iOS |  |
| Camera firmware/APFPV build |  |
| Candidate path | A / B / C / D / E |
| Codec | H.264 / H.265 / unknown |
| Resolution/FPS |  |
| Bitrate observed |  |
| Network topology |  |
| Startup time |  |
| Latency method |  |
| Latency observed |  |
| Packet loss/gaps |  |
| Freezes |  |
| Recovery behavior |  |
| iPhone temp/battery |  |
| Windows CPU/GPU if applicable |  |
| Telemetry stable | yes / no |
| Head tracking stable | yes / no |
| Windows control path unaffected | yes / no |
| Pass/fail |  |
| Notes/screenshots/pcap links |  |

## Stop Conditions

Stop the spike and do not proceed to implementation if:

- Real APFPV packet format is still unknown.
- iPhone cannot receive APFPV packets in diagnostic mode.
- Video testing interferes with telemetry, head tracking, or Windows control behavior.
- The only working path requires unsafe Windows CPU/GPU load.
- The only working path has unacceptable latency for FPV.
- The app cannot clearly distinguish no video, lost video, and unsupported codec.

## Expected Next Documented Decision

After real measurements, update `docs/ROADMAP_AND_DECISIONS.md` with:

- Selected video candidate path.
- Measured codec and transport.
- Measured latency range.
- Known failure modes.
- Whether Windows viewing and iPhone viewing can run simultaneously.
- Whether native VideoToolbox work should proceed, remain experimental, or be deferred.
