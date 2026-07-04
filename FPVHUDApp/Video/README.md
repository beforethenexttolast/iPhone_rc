# Future Native APFPV Video Path

This milestone intentionally does not decode OpenIPC/APFPV video.

The preferred low-latency iPhone video path is independent from telemetry and head tracking:

```text
APFPV RTP/UDP H.265
  -> iPhone UDP receiver
  -> RTP/H.265 depacketizer
  -> VideoToolbox decoder
  -> video surface
  -> SwiftUI/UIKit HUD overlay
```

Do not assume Windows must forward, proxy, or re-encode video for the iPhone path. Windows remains the authority for normalized telemetry forwarding and for receiving head-tracking intent packets, but direct APFPV video to iPhone remains Option A.

## Boundary

- Video module: receives APFPV RTP/UDP and renders decoded frames.
- Telemetry module: receives Windows-normalized JSON snapshots.
- Head-tracking module: sends yaw/pitch/roll intent packets to Windows.

These paths should stay separate so video latency work does not couple to command authority, failsafe logic, or telemetry parsing.

## Later Implementation Shape

1. Bind a UDP socket to the APFPV video port, likely `5600`.
2. Parse RTP headers and sequence/timestamp fields.
3. Reassemble H.265/HEVC NAL units.
4. Feed compressed samples into VideoToolbox.
5. Render decoded frames behind the existing HUD overlay.

The current `VideoSurface` is only a placeholder that keeps the HUD and service architecture moving.

