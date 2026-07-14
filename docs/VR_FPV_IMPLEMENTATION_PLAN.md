# W17 iPhone VR FPV Implementation Plan

Last updated: 2026-07-14

## Progress Tracking

This document defines the target design and implementation order. It is not evidence that a feature or batch has been implemented.

Use these companion documents for continuing work:

- `docs/VR_FPV_IMPLEMENTATION_TRACKER.md` is the canonical implementation-status ledger.
- `docs/NEW_SESSION_PROMPT.md` contains the reusable prompt for starting a new Codex session.

At the end of every implementation session, update the tracker with the exact files changed, validation performed, hardware evidence obtained, blockers, decisions, and next action. Do not mark a batch complete based only on documentation, simulator output, mocks, or log-only validation when its exit gate requires real hardware.

## Status And Safety Boundary

This document is a planning roadmap. It does not implement video decoding, change the iPhone/Windows bridge contract, authorize active pan/tilt, or authorize vehicle driving with head-controlled pan/tilt.

The app should become a monoscopic binocular FPV client: decode one camera stream once, render it into two independently calibrated eye views, duplicate a reduced HUD, and send head-look intent to Windows. Windows remains the control/integration authority and owns operator arming and final intent arbitration. The future `elrs-joystick-control` mapper produces final CRSF channel targets; only the vehicle firmware produces physical servo outputs.

The existing ownership and safety boundaries remain in force:

- The iPhone is a thin HUD/client.
- Windows remains the control and integration authority.
- The iPhone must not send CRSF, servo positions, gimbal commands, ESC commands, or vehicle commands.
- Active pan/tilt remains a separate reviewed safety milestone.
- Windows and firmware repositories are not modified as part of iPhone implementation work.
- Any bridge schema or contract change must be deliberate, reviewed, mirrored on both sides, and accompanied by aligned schema/example changes.

## Target System

```text
OpenIPC camera — H.264 1280×720 60 fps baseline
  └─ direct RTP/UDP video ───────────────► iPhone video receiver
                                            │
                                            ▼
                                      one hardware decoder
                                            │
                                 ┌──────────┴──────────┐
                                 ▼                     ▼
                            left-eye view        right-eye view
                                 └──── duplicated VR HUD ────┘

  └─ retained RTSP ─► Windows MediaMTX/WHEP viewing path

Windows ground station / control stack
  ├─ telemetry UDP 5601 ─────────────────► iPhone HUD
  ├─ Electron UI: viewer/configuration/logging only
  └─ elrs-joystick-control: future validation/arbitration mapper
          ▲
          │ head-look intent UDP 5602 topology not yet selected
          │
       iPhone Core Motion

elrs-joystick-control mapper
  └─ validation → arm state → manual override → limits → final CRSF ch9/ch10 targets
                                                               │
                                                               ▼
                                                        vehicle firmware
                                                               └─ physical servo outputs
```

This preserves the existing repo boundary documented in `README.md` and the established video direction in `FPVHUDApp/Video/README.md`.

## Decisions Now Fixed

- Target device: iPhone 15 running its currently installed latest iOS.
- Headset: Esperanza Shinecon 3D VR EMV400.
- Operating orientation: landscape with the Dynamic Island physically on the left. The corresponding UIKit orientation name must be confirmed on the real phone because Apple's landscape naming can be counterintuitive.
- One physical camera and one decoded frame.
- Shipping video baseline: H.264, 1280×720, 60 fps, direct RTP/UDP unicast to the iPhone when the camera supports it, with the RTSP path retained for Windows MediaMTX/WHEP viewing.
- Simultaneously usable iPhone and Windows video is required. A degraded single-receiver mode, H.265-only mode, or RTP-push-only mode must never be substituted silently.
- Dual-stream output is an experiment only unless measurement proves that it is required and does not add unacceptable latency or instability.
- The same video content is shown to both eyes. The app will not fabricate stereo parallax from a mono camera.
- Each eye gets independent horizontal offset, vertical offset, zoom/crop, enable/disable, mask, and distortion calibration.
- The HUD is duplicated for both eyes.
- Head roll does not rotate the video, shift the HUD, or command the gimbal.
- Head yaw maps to gimbal pan; head pitch maps to gimbal tilt.
- In the current log-only milestone, head tracking remains independent from the video receiver and a temporary video failure does not itself stop motion packet generation. The active-control reaction to iPhone-local video loss remains an explicit open safety decision in Section 6.
- Windows owns arm/disarm, controller bindings, override priority, and stale/fault policy. The future mapping/arbitration host is `elrs-joystick-control`; Electron remains viewer/configuration/logging only. Firmware alone produces hardware servo output.
- The iPhone never sends CRSF, servo positions, or gimbal commands.
- The app starts manually and the user presses an explicit `Enter VR` action before inserting it into the headset.
- Windows can discover/readiness-check the foreground app, but it cannot force-launch the app or force it into VR mode.

## Important Facts That Remain Measurement Gates

Do not silently interpret “64/65 codec” as H.264/H.265 or “RTPS” as RTSP. Those are plausible meanings, but Batch 0 must record the exact labels and resulting traffic.

The following must be established on hardware:

- Whether the camera actually sustains the approved H.264 1280×720 60 fps baseline to both required receivers.
- The exact meaning of the camera's RTP/RTPS labels and how direct RTP and retained RTSP are configured together.
- UDP destination and port.
- Unicast, multicast, or IP broadcast behavior.
- RTP payload type and packetization.
- Resolution, frame rate, bitrate, and keyframe interval.
- Parameter-set availability and loss recovery.
- Simultaneous iPhone RTP and Windows RTSP/MediaMTX/WHEP stability, latency, and resource cost.
- EMV400 lens distortion coefficients and usable eye centers.
- Comfortable head-angle thresholds.
- Gimbal mechanical center, direction, endpoints, and safe velocity.

OpenIPC's current APFPV documentation shows a typical direct H.265 RTP receiver on UDP 5600 and a common AP network arrangement, but this is only a diagnostic starting point, not the approved shipping topology and not proof of the Greg firmware's actual configuration on this camera.

Reference: [OpenIPC APFPV guide](https://docs.openipc.org/use-cases/fpv/apfpv/apfpv/)

## 1. App Architecture

The three real-time paths stay separate:

1. `VideoSession`

   Receives, depacketizes, decodes, and publishes the latest frame.

2. `TelemetrySession`

   Keeps the current Windows-to-iPhone UDP snapshot path.

3. `HeadTrackingSession`

   Keeps the current iPhone-to-Windows intent path and its conservative enable/center gates.

A higher-level `FPVSessionCoordinator` should expose status to the UI but should not copy video frames through SwiftUI or `FPVHUDViewModel`. Video packets, access units, pixel buffers, and render callbacks must remain on dedicated queues. SwiftUI should observe only low-rate state such as:

- listening;
- awaiting parameter sets;
- awaiting keyframe;
- live;
- stalled;
- unsupported stream;
- decoder fault;
- packet-loss counters;
- measured frame rate;
- last-frame age.

This prevents frequent `ObservableObject` updates from adding display latency.

## 2. Video Receiver And Decoder

The existing receiver in `FPVHUDApp/Video/APFPVDiagnosticReceiver.swift` is a useful packet diagnostic, but it deliberately does not assemble or decode frames. Its current NAL interpretation is H.265-specific: under the H.264 baseline, only codec-neutral RTP statistics are trustworthy until H.264 payload inspection is deliberately added. The current `FPVHUDApp/Video/VideoSurface.swift` remains the placeholder until the decoder is proven.

Proposed pipeline:

```text
Network.framework UDP receiver
  → RTP parser
  → codec-specific depacketizer
  → access-unit assembler
  → VideoToolbox decoder
  → CVPixelBuffer
  → CVMetalTextureCache
  → Metal VR renderer
```

Apple provides the intended native pieces: `VTDecompressionSession` for real-time decoding and Core Video's Metal texture cache for mapping decoded buffers to GPU textures without an extra image copy.

References:

- [VideoToolbox decompression](https://developer.apple.com/documentation/videotoolbox/vtdecompressionsession-api-collection)
- [Core Video Metal texture cache](https://developer.apple.com/documentation/corevideo/cvmetaltexturecache-q3j)

Implementation policy:

- Build only the codec confirmed during capture first.
- Abstract the codec boundary so the other codec can be added later.
- For the H.264 baseline, support single NAL units, STAP-A aggregation packets, and FU-A fragmentation units. Add H.265 packetization support only if a later measured experiment justifies it.
- Support RTP sequence wraparound, padding, CSRC entries, header extensions, packet loss, duplicates, and out-of-order packets.
- Cache VPS/SPS/PPS or SPS/PPS and recreate the decoder when they or the resolution change.
- After unrecoverable loss, discard dependent frames and wait for a clean keyframe.
- Do not construct a large playback buffer.
- Maintain at most a very shallow decode/display queue.
- If rendering falls behind, discard old completed frames and display the newest viable frame.
- Configure VideoToolbox for real-time, hardware-accelerated decoding and verify that hardware decoding is actually active.
- Keep color conversion in Metal.
- Do not decode the same frame twice for the two eyes.

### Network Topology

The preferred topology is:

```text
APFPV/OpenIPC Wi-Fi network
  ├─ camera
  ├─ iPhone
  └─ Windows PC
```

That lets the iPhone receive camera video while Windows sends telemetry and receives head tracking on the same subnet.

Two separate Wi-Fi networks, one for the camera and another for Windows, must not be a supported assumption. The iPhone cannot normally participate in two independent Wi-Fi LANs simultaneously.

Prefer configurable unicast RTP to the iPhone. If the camera really uses broadcast or multicast UDP, iOS distribution may require Apple's multicast networking entitlement. Apple explicitly calls this out for multicast and broadcast UDP.

Reference: [Apple networking guidance](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)

Simultaneous Windows+iPhone video is a required baseline, not an optimization:

- Configure H.264 1280×720 60 fps RTP/UDP unicast to the iPhone when supported.
- Retain the camera RTSP path for the Windows MediaMTX/WHEP viewer.
- Measure both paths running together, including packet loss, latency, encoder load, thermal behavior, and recovery.
- If the baseline cannot be sustained, report the exact limitation and return it for an owner decision. Do not silently fall back to one receiver, H.265-only output, or RTP-push-only output.
- Treat separate dual-stream encoding as an experiment, not a default architecture.

## 3. Binocular Renderer

The renderer should use one decoded `CVPixelBuffer` and sample it into two eye render targets.

Per-eye profile:

- horizontal optical-center offset;
- vertical optical-center offset;
- zoom;
- crop/overscan;
- eye viewport size;
- eye enable;
- circular/rounded visibility mask;
- distortion profile;
- HUD horizontal offset;
- HUD vertical offset;
- HUD disparity/depth;
- HUD scale.

### Distortion Strategy

Google Cardboard's iOS SDK already supports per-eye textures, viewer profiles, distortion meshes, and a Metal distortion renderer. It is therefore worth evaluating rather than immediately building a proprietary optical model.

References:

- [Cardboard iOS rendering](https://developers.google.com/cardboard/develop/ios/quickstart)
- [Cardboard Metal distortion renderer](https://developers.google.com/cardboard/reference/c/group/distortion-renderer)

However, the supplied EMV400 dimensions are insufficient to derive an accurate optical profile. Lens diameter and adjustable IPD do not tell us the lens distortion coefficients, screen-to-lens distance, vertical alignment, or effective field of view.

Batch 1 should compare:

- Cardboard Metal distortion with a custom EMV400 profile;
- a custom Metal distortion mesh;
- a simpler unwarped dual-eye view with crop and optical-center adjustment.

The real-headset grid test decides which looks best. Do not assume maximum distortion correction is automatically more comfortable.

### Recommended Visual Behavior

- Video content is identical for both eyes.
- Per-eye video offsets are used only for lens/eye alignment, not simulated depth.
- Video remains camera-fixed.
- Head yaw, pitch, and roll never transform the displayed video.
- HUD is screen/head-fixed.
- Keep important HUD elements near the center where the EMV400 optics are clearest.
- Apply a very small symmetric binocular HUD offset, bounded by a comfort limit.
- Provide an immediate zero-disparity option.
- Text should remain at zero or near-zero disparity; the reticle may tolerate slightly more apparent depth.
- Never place different information in the two eyes during normal operation.
- Independent-eye enablement is primarily a calibration and diagnostic feature.

The exact nonzero HUD offset should be selected during on-head testing, not hardcoded from IPD millimetres.

## 4. VR Preparation And Calibration Flow

Before insertion:

1. Open the app.
2. Confirm Windows discovery/telemetry status.
3. Confirm local APFPV video.
4. Choose the saved `EMV400 / iPhone 15` profile.
5. Physically set the headset IPD and focus.
6. Open the binocular calibration grid.
7. Adjust left/right horizontal alignment.
8. Adjust left/right vertical alignment.
9. Adjust zoom/crop until no distracting black edge enters either lens.
10. Select distortion mode.
11. Adjust HUD depth using the reticle/text sample.
12. Enable tracking.
13. Perform the app's session calibration.
14. Press `Enter VR`.
15. Insert the phone into the headset.

VR mode should:

- lock to the physical Dynamic-Island-left orientation;
- prevent auto-lock;
- hide system chrome;
- suppress accidental touch controls;
- keep all important controls available through Windows/controller;
- restore the idle timer and orientation policy on exit;
- show a high-visibility local video-stale warning;
- monitor thermal state and sustained frame drops.

Calibration remains local to the iPhone and may persist as an optical profile. Head-tracking neutral remains session-only.

## 5. HUD Rework

The current HUD contains useful data, but duplicating the whole debug-oriented presentation into each eye would obscure too much video.

### Minimal VR HUD

Always available:

- central reticle;
- battery;
- speed;
- gear/drive mode;
- link quality or combined link warning;
- authoritative tracking mode;
- critical warnings;
- local video stale/fault indication.

Conditionally visible:

- commanded camera pan/tilt targets near command saturation; these are not measured camera aim;
- telemetry stale;
- head-tracking stale;
- manual override;
- thermal or decoder degradation.

For the current version-1 telemetry contract, a coarse near-limit notice may use the existing human-readable `warning` field. The iPhone must not parse that text as a structured safety signal. A dedicated `camera_limit_state`-style field is deferred until a separately reviewed schema revision is justified and mirrored; no field is added in this documentation pass.

Keep outside the headset/debug screen:

- raw yaw/pitch/roll;
- packet counts;
- SSRC/payload type/NAL details;
- network addresses and ports;
- detailed RSSI/SNR history;
- calibration controls;
- per-eye tuning controls.

The app must distinguish:

- iPhone-local decoded-video status;
- Windows-reported `video_lock`;
- telemetry freshness.

Windows may report no local Windows video while the iPhone video is working perfectly, so those states must not be conflated.

## 6. Head Tracking And Gimbal Behavior

The current intent packet already carries yaw, pitch, roll, tracking state, centered state, sequence, send timestamp, and a timeout hint. That is enough for the first hybrid controller only if the iPhone stops sending when its underlying Core Motion sample is no longer locally fresh. No schema change is required for that initial guarantee.

The existing safety design in `docs/FUTURE_HEAD_TRACKING_TO_PAN_TILT_SAFETY.md` remains authoritative.

### Hybrid Mapping

Implement this in an owned/forked `elrs-joystick-control` mapper, not the iPhone and not Electron:

```text
filtered head angle
  ├─ center deadband
  ├─ position region
  ├─ smooth transition region
  └─ edge-rate region
```

The mapper maintains a bounded `virtualCameraCenter` while head authority is active.

- Near neutral, the output target is:

  `virtualCameraCenter + positionGain × centeredHeadAngle`

- Near the comfortable head limit, a rate term begins changing `virtualCameraCenter`.
- The rate term increases smoothly toward the edge.
- Returning the head to neutral leaves the camera looking in the newly reached direction rather than snapping to its original center.
- Mechanical limits clamp the final target at all times.
- Anti-windup clamps the virtual center itself so continued edge-rate input cannot accumulate unreachable displacement beyond the calibrated command range.
- The output rate limiter applies across every authority transition, including arm, recenter, manual override, stale, disarm, fault, and controlled return-to-center.

This produces natural small movements while allowing continued panning without forcing the driver to keep turning their head farther.

Filtering should be minimal:

- Core Motion remains the canonical iPhone sensor source.
- Do not introduce a second Cardboard head-tracking pipeline for gimbal control.
- Apply deadband and a light adaptive or rate-aware filter in the mapper.
- Avoid heavy smoothing at both ends of the connection.

### Recenter

The controller recenter action should be processed by the mapper:

- record the latest accepted iPhone yaw/pitch as the new head neutral;
- re-seed the virtual camera center from the current authoritative commanded target, not a presumed measured camera position;
- make the operation bumpless, with no camera jump;
- clear accumulated edge-rate displacement relative to the new center.

The commanded mechanical center is CRSF `992` on both pan and tilt. On stale input, disarm, or mapper fault, discard the active virtual center and command a rate-limited return toward `992`. On manual override, discard the active virtual center and give the manual source authority. A later recenter may seed a new virtual center from the then-authoritative commanded target. Neither `992` nor telemetry command mirrors prove the mechanism physically reached center.

The iPhone still performs its initial session calibration so packets can pass the existing sender safety gate. Later controller recentering does not require a new Windows-to-iPhone command channel.

### Manual Override

Recommended behavior:

- Any meaningful right-stick gimbal input immediately wins.
- The mapper enters `manual_override`.
- Head tracking stops contributing.
- Releasing the stick does not automatically restore head authority.
- Resuming head tracking requires explicit arm/recenter.

This avoids an unexpected camera jump when the stick returns to center.

### Stale And Fault Behavior

- One malformed packet: reject it.
- Repeated invalid packets: enter `fault`.
- The mapper uses local receive time as the only stale authority: integer receive age `299 ms` and `300 ms` are fresh; `301 ms` is stale. The packet's `timeout_ms` remains a diagnostic hint and cannot weaken the `300 ms` receiver threshold.
- Stale head packets: immediately stop applying new iPhone contribution, discard the virtual center, and begin a rate-limited commanded return to CRSF `992`.
- Disarm and mapper fault follow the same virtual-center discard and commanded-center rule. Manual input remains authoritative during override; releasing it does not restore head authority, and re-entry requires deliberate recenter/rearm.
- Reconnection does not automatically rearm head control.
- Tracking off, app backgrounded, Wi-Fi lost, or calibration reset all remove iPhone authority.
- Operator disarm is always immediately available from Windows.

#### Motion-Sample Freshness Review

Three different timeout domains must remain distinct:

1. iPhone Core Motion sample freshness: the current implementation marks motion stale only after `500 ms`, while `timestamp_ms` is stamped when a packet is built. That can make a frozen sample look newly sent.
2. Mapper receive-time freshness: the canonical active threshold is `300 ms`, with `301 ms` stale.
3. Packet `timeout_ms`: the current app default is `250 ms`; it is a diagnostic sender hint, not receiver authority.

Before active mapping, tighten the iPhone's local motion-sample gate to no more than `250 ms` and guarantee that packet generation stops when the sample exceeds that age. Keep `timestamp_ms` as packet send time for diagnostics; do not reinterpret it as sample time. Do not add a sample-age field in this documentation pass. A future sample-age field would be a deliberate canonical schema revision with aligned schema/example/mirror updates, not an ordinary UI change.

Telemetry display stale/lost timing and video-frame stale timing are separate again and do not alter these W3 rules.

#### Open Video-Loss Safety Decision

W3 contains no decoder or local-video-health field. Current log-only behavior keeps video and motion transport independent, but active control must not ship until the owner chooses and reviews one reaction path:

1. extend W3 with reviewed local video-health data;
2. make the iPhone stop W3 packets when its local decoder is stale/lost;
3. add a separate reviewed iPhone-to-Windows health side channel; or
4. keep the paths independent and rely on explicit operator/Windows disarm policy.

No option is selected by this plan. No active implementation may infer iPhone video health from Windows `video_lock` or from missing telemetry.

The first physical limits remain the conservative bench values proposed in `docs/FIRST_ACTIVE_PAN_TILT_MILESTONE.md`. Full limits are derived only after measuring the actual mechanism.

## 7. Implementation Batches

### Batch 0 — Hardware Evidence And Configuration Freeze

Work:

- Photograph/export every Greg OpenIPC stream setting.
- Resolve “64/65” and “RTP/RTPS” precisely.
- Record codec, resolution, FPS, bitrate, GOP, destination, port, and transport.
- Attempt the approved H.264 1280×720 60 fps baseline first; retain RTSP for Windows and configure RTP/UDP unicast to the iPhone if supported.
- Run the existing APFPV diagnostics on the real iPhone.
- Capture representative packets for reproducible tests.
- Determine unicast versus broadcast/multicast.
- Test the one-LAN topology with Windows and iPhone.
- Prove that the iPhone RTP path and Windows RTSP/MediaMTX/WHEP path remain simultaneously usable, or document the exact blocker for an owner decision.
- Measure the usable EMV400 eye centers and confirm the physical landscape orientation.

Exit gate:

- The iPhone receives repeatable real RTP packets.
- Codec and packetization are known.
- Parameter-set and keyframe behavior are known.
- Supported network topology is documented.
- Simultaneous Windows+iPhone video at the baseline is proven, or its limitation is explicitly escalated; no silent substitute is accepted.
- No decoder work begins before this passes.

### Batch 1 — VR Shell And Optical Calibration

Work:

- Add VR preparation, calibration, and active modes.
- Render a local grid/test image into two eye viewports.
- Implement every per-eye adjustment requested.
- Add saved `EMV400 / iPhone 15` profile.
- Compare Cardboard Metal distortion, custom distortion, and no-distortion modes.
- Add bounded HUD disparity calibration.
- Lock to Dynamic-Island-left physical orientation.
- Add idle-timer handling.

Exit gate:

- Both eyes can be aligned independently.
- No visible doubled reticle/text at the selected profile.
- No important content falls behind the Dynamic Island or unusable lens edges.
- A 15–30 minute on-head static comfort session succeeds.

### Batch 2 — Native Video Core In Flat Mode

Work:

- Separate production receiver from diagnostic receiver.
- Implement confirmed RTP/codec depacketization.
- Assemble access units.
- Decode with VideoToolbox.
- Render a single flat Metal view.
- Add lifecycle and loss recovery.
- Add recorded-packet fixtures and corruption tests.

Exit gate:

- Real video starts, stops, reconnects, and recovers from packet loss.
- Hardware decoding is confirmed.
- Ten-minute playback does not accumulate delay.
- Old frames are dropped rather than queued.

### Batch 3 — Video Plus Binocular Renderer

Work:

- Feed one decoded texture into both eye render targets.
- Apply independent transforms and selected distortion.
- Integrate the duplicated HUD.
- Keep debug UI outside VR mode.
- Add eye masks, overscan, local stale warning, and interruption recovery.

Exit gate:

- Exactly one decoder is active.
- Both eyes show the same current frame.
- Adjustments do not trigger decoder recreation.
- Video remains comfortable and aligned for a 30-minute headset session.

### Batch 4 — APFPV Latency And Quality Tuning

Test matrix:

- Approved H.264 720p60 baseline versus explicitly labeled experiments such as H.265 or 1080p30, if genuinely available.
- Bitrate and GOP/keyframe settings.
- Unicast versus broadcast where allowed.
- simultaneous Windows+iPhone baseline under normal and degraded network conditions.
- Short and extended-range Wi-Fi conditions.

Measurements:

- camera-to-display glass-to-glass latency;
- median and p95 latency;
- packet loss;
- decoder drops;
- startup/keyframe wait;
- freeze duration;
- iPhone thermal state;
- battery consumption.

Initial engineering target, not a promise, is median glass-to-glass latency at or below 150 ms and p95 at or below 200 ms. If hardware cannot meet that, record the real result and choose the lowest stable configuration instead of hiding delay behind buffering.

Exit gate:

- A shipping codec/resolution/FPS/bitrate/GOP preset is chosen from measurements.
- Simultaneous usable reception is proven. Any inability to meet it is reported for an owner decision rather than converted into an undocumented single-target shipping mode.

### Batch 5 — Real Headset Motion Validation, Log-Only

Work:

- Validate Core Motion axes with the phone mounted in the EMV400.
- Confirm yaw/pitch signs and roll isolation.
- Measure comfortable yaw and pitch ranges.
- Tune deadband and filtering against actual head movement.
- Exercise recenter, virtual-center, anti-windup, and timeout calculations in a reference Python harness owned with the iPhone handoff; this is not production Windows code and does not begin Batch 7.
- Test packet loss, app background, Wi-Fi interruption, and reconnect.
- No servo output.

Exit gate:

- Real-device axes and orientation are documented.
- Recenter produces no target jump in logs.
- Roll has zero pan/tilt effect.
- Simulator behavior is not used as proof.

### Batch 6 — Mapper Handoff Specification

Deliver to the `elrs-joystick-control` owner before any active mapper work:

- state machine;
- packet validation rules;
- hybrid mapping formula;
- CRSF `992` center semantics, bounded virtual-center behavior, discard/re-seed rules, and anti-windup;
- exact `300 ms` receive-time rule and `299/300/301 ms` boundary vectors;
- calibrated degrees-to-CRSF-count conversion and sign/limit data;
- mapping from the current log-only states to the future active state machine;
- controller bindings;
- arm/disarm flow;
- manual override priority;
- stale/fault behavior;
- output limits and rate-limiter requirements;
- required logs and UI states;
- test vectors from the iPhone repo.

The production mapper host is `elrs-joystick-control`, because that process owns the DualShock right-stick input and final CRSF channel encoding. Electron remains viewer/configuration/logging only and must not become a control-path relay.

UDP `5602` is currently an exclusive socket owned by Electron only when its log-only receiver is enabled; otherwise nothing binds it. The available `elrs-joystick-control` head-intent ingest capability is unverified because its source/binary is not present here. Architecture selection is therefore blocked. The reviewed choices are:

1. the mapper owns `5602` and republishes a read-only diagnostics stream for Electron;
2. the iPhone sends to two separately configured destinations; or
3. a deliberately owned fan-out relay receives once and publishes to mapper and diagnostics consumers.

Do not choose or implement one of these from the iPhone repo without the mapper investigation and owner review. In particular, do not assume two processes can bind UDP `5602` concurrently.

Windows states:

```text
disabled
receiving
ready_not_centered
centered
armed
active
manual_override
stale
fault
```

Only `active` may accept new iPhone-derived contribution. Safety-return and trusted manual commands are separate authority paths.

No sibling repo is modified from this work. Any required bridge schema extension must be separately reviewed and mirrored on both sides.

### Batch 7 — Mapper Simulated-Output Integration

Work performed by the `elrs-joystick-control` owner:

- consume real iPhone packets;
- implement the reviewed package inside `elrs-joystick-control` and calculate hybrid output;
- operate with physical output disconnected;
- validate controller recenter;
- validate manual override;
- validate stale return-to-center;
- verify limit/rate/smoothing behavior in logs.

Exit gate:

- Every safety transition passes without physical servo movement.

### Batch 8 — First Physical Gimbal Bench Milestone

- Vehicle propulsion disabled.
- Vehicle immobilized.
- Servos unloaded or linkage constrained first.
- Tiny movement limits.
- Slow rate limit.
- Immediate controller disarm proven.
- Yaw test, pitch test, stale test, app-close test, Wi-Fi-loss test, and manual-override test.
- Reconnect must not automatically rearm.

No driving during this batch.

### Batch 9 — Controlled Driving And Release Hardening

- Expand limits incrementally after mechanical measurement.
- Validate camera clearance and cable routing.
- Test the minimal HUD while driving at low speed.
- Use a spotter, a closed clear area, low vehicle speed, both video feeds, a pre-verified manual override/stale-return path, and a rehearsed abort procedure for the first moving test.
- Run thermal, battery, Wi-Fi-range, app-interruption, and 30–60 minute soak tests.
- Confirm calibration recovery after removing/reinserting the phone.
- Freeze the EMV400 shipping profile only after repeated comfort tests.

## Proposed iPhone Module Layout

```text
Video/
  Transport/
  RTP/
  Decoder/
  Rendering/
  Diagnostics/

VR/
  VRProfile
  VREyeConfiguration
  VRCalibrationView
  VRPreparationView
  VRSessionCoordinator

UI/
  VRHUD/
  Debug/
```

Production video and diagnostics should share tested RTP parsing primitives, but diagnostics must remain independently usable when decoding fails.

## Definition Of Done

The redesign is ready only when:

- real camera video, not a synthetic sender, renders in both eyes;
- one decoder feeds both eyes;
- every requested per-eye adjustment works;
- the saved EMV400 profile survives relaunch;
- video and HUD never rotate with head roll;
- the minimal HUD remains readable without hiding the road;
- no sustained video queue builds latency;
- local video status and Windows video status are distinct;
- head packets remain intent-only;
- controller manual override always wins;
- reconnect cannot silently restore active gimbal authority;
- active pan/tilt passes the separate stationary bench milestone before any driving test;
- all current unit tests plus RTP/decode/VR tests pass on simulator and real iPhone where applicable.
