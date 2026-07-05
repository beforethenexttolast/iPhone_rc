# OpenIPC/APFPV Diagnostic Test Plan

This plan captures and characterizes real OpenIPC/APFPV video packets before any native iPhone decoding work.

This is diagnostic-only. Do not implement VideoToolbox decode from this plan, do not replace the Drive mode mock video surface, and do not make latency claims until real decode/render measurement exists.

## Required Equipment

- OpenIPC camera flashed with Greg's APFPV firmware.
- APFPV Wi-Fi access point/router connection from the camera.
- Mac or Linux laptop with Wi-Fi and packet-capture tools.
- Wireshark and/or `tcpdump`.
- iPhone later for app diagnostic receiver testing.
- Optional USB Ethernet or second network adapter if the test setup needs separate internet/control and APFPV networks.
- Optional tripod or stable camera mount so packet behavior is not affected by power/movement interruptions.

## Known Assumptions

These are assumptions to verify, not facts to build decode code around yet:

- APFPV runs normal IP traffic over its Wi-Fi AP/router mode.
- Video is likely UDP/RTP carrying H.265/HEVC.
- The common/default video UDP port is likely `5600`.
- RTP payload type, SSRC behavior, packetization mode, and parameter-set cadence must be measured from the real camera.
- The iPhone preferred low-latency path remains direct APFPV camera -> iPhone video. Windows does not need to forward or re-encode video for this path.

## Safety And Scope Boundary

- No decoding yet.
- No VideoToolbox yet.
- No H.265 frame assembly yet.
- No Drive mode video replacement yet.
- No APFPV latency claims yet.
- No vehicle, gimbal, CRSF, or control behavior is involved in this test.
- Telemetry and head tracking remain independent from APFPV video diagnostics.

## Network Discovery

Connect the laptop to the APFPV Wi-Fi network first. Record:

- Wi-Fi SSID.
- Laptop Wi-Fi interface name.
- Laptop IP address.
- Camera/AP gateway IP address.
- Any APFPV web UI or status page IP/port if available.

On macOS, list interfaces:

```sh
ifconfig
networksetup -listallhardwareports
```

On Linux, list interfaces:

```sh
ip addr
ip route
```

Find the receiving host IP:

```sh
ipconfig getifaddr en0
```

or on Linux:

```sh
hostname -I
```

Find likely camera/AP IP:

```sh
netstat -rn
arp -a
```

or on Linux:

```sh
ip route
ip neigh
```

Ping where possible:

```sh
ping <camera-or-ap-ip>
```

Ping may be disabled. Lack of ping does not prove UDP is blocked. Continue with packet capture if the Wi-Fi association is good.

## Packet Capture Plan

Start laptop capture before starting or power-cycling the camera video stream. Capture broadly first, then narrow after the active UDP flow is known.

### tcpdump Broad Capture

macOS or Linux:

```sh
sudo tcpdump -i <wifi-interface> -n -vv udp
```

Save a capture file:

```sh
sudo tcpdump -i <wifi-interface> -n -s 0 -w apfpv_first_capture.pcap udp
```

If port `5600` appears active, capture that port specifically:

```sh
sudo tcpdump -i <wifi-interface> -n -s 0 -w apfpv_5600_capture.pcap udp port 5600
```

If the source or destination host is known:

```sh
sudo tcpdump -i <wifi-interface> -n -s 0 -w apfpv_host_capture.pcap host <camera-ip> and udp
```

### Wireshark Workflow

Open the `.pcap` in Wireshark and start with these display filters:

```text
udp
udp.port == 5600
ip.addr == <camera-ip>
rtp
```

If Wireshark does not auto-detect RTP:

1. Right-click a likely UDP packet.
2. Choose Decode As.
3. Decode the UDP payload as RTP.
4. Re-check RTP fields and sequence behavior.

Useful columns to add:

- UDP source port.
- UDP destination port.
- RTP payload type.
- RTP sequence number.
- RTP timestamp.
- RTP SSRC.
- Packet length.
- Delta time.

## UDP Port Identification

Record every high-rate UDP flow:

- Source IP and port.
- Destination IP and port.
- Packets per second.
- Average packet size.
- Approximate bitrate.
- Whether traffic starts automatically or only after a viewer connects.
- Whether destination is unicast, broadcast, or multicast.

If multiple UDP ports are active, classify them:

- Candidate video RTP.
- Control/status traffic.
- DHCP/DNS/other network traffic.
- Unknown.

Do not assume port `5600` until the capture confirms it.

## RTP Detection

For the candidate video flow, verify whether the payload looks like RTP:

- First two bits indicate RTP version `2`.
- Payload type is stable or explainably variable.
- Sequence number increments by one for normal packet order.
- RTP timestamp changes at frame/access-unit cadence, not every packet.
- SSRC is stable during a stream.
- Marker bit behavior is noted.

If RTP is not detected, record the first bytes of packet payload and treat packetization as unknown.

## RTP/H.265 Fields To Record

For the first real capture, record:

- Capture date/time.
- Camera firmware/APFPV version if known.
- Camera Wi-Fi SSID/config if relevant.
- Laptop OS and Wi-Fi interface.
- UDP source IP and port.
- UDP destination IP and port.
- Unicast/broadcast/multicast behavior.
- RTP payload type.
- RTP SSRC.
- Sequence number start and wrap behavior if observed.
- Sequence gaps.
- Out-of-order packets.
- RTP timestamp cadence.
- Packets per second.
- Approximate bitrate.
- Packet-size distribution.
- Marker bit behavior.
- H.265 NAL unit types observed.
- VPS/SPS/PPS presence.
- VPS/SPS/PPS cadence.
- IDR/keyframe-related NAL units if visible.
- Whether FU fragmentation is present.
- Whether aggregation packets are present.
- Whether stream starts with parameter sets.
- Whether parameter sets repeat after stream start.

## H.265 NAL Inspection Notes

For H.265 RTP payloads, record packetization behavior before writing decoder code:

- Single NAL unit packets.
- Fragmentation units.
- Aggregation packets.
- VPS NAL type.
- SPS NAL type.
- PPS NAL type.
- IDR/keyframe NAL types.
- Any APFPV-specific headers before RTP or before H.265 payload.

If the diagnostic receiver reports NAL types but they do not match Wireshark, save both observations and the `.pcap`; do not adjust decode assumptions from only one tool.

## iPhone Diagnostic Receiver Test

Only after laptop capture identifies the likely APFPV UDP/RTP flow:

1. Install the FPV HUD app on the iPhone.
2. Connect the iPhone to the APFPV Wi-Fi network.
3. Open Debug / Setup.
4. Open Settings.
5. Enable `APFPV RTP diagnostics`.
6. Set the diagnostic UDP port to the captured video port, likely but not assumed to be `5600`.
7. Apply settings.
8. Return to Debug / Setup and inspect the `APFPV RTP Diagnostic` panel.

Expected Debug stats:

- Enabled/listening state is visible.
- UDP port matches the configured port.
- Packet count increases when APFPV packets arrive.
- Packets per second is nonzero.
- Approximate bitrate is nonzero.
- Last packet age remains low while packets arrive.
- Payload type appears.
- Sequence number updates.
- RTP timestamp updates.
- SSRC appears.
- Sequence gaps and out-of-order counters remain near zero on a stable link.
- NAL description updates if H.265 payload inspection succeeds.
- VPS/SPS/PPS flags become true if parameter sets are seen.

No-packet/stale behavior:

- If no packets arrive, packet count stays unchanged and last packet age grows or remains unknown.
- The app must not crash.
- Drive mode remains mock/placeholder video.
- No decode/render attempt occurs.

## Capture And Replay Workflow

Laptop capture is the source of truth for the first diagnostic milestone.

Capture:

```sh
sudo tcpdump -i <wifi-interface> -n -s 0 -w apfpv_first_capture.pcap udp
```

Trim or filter to candidate video port:

```sh
tcpdump -r apfpv_first_capture.pcap -n udp port <video-port> -w apfpv_video_only.pcap
```

Replay options depend on local tools and OS support. If `tcpreplay` is available on a suitable interface:

```sh
sudo tcpreplay -i <interface> apfpv_video_only.pcap
```

For simulator/debug receiver testing, prefer synthetic traffic first:

```sh
python3 scripts/send_synthetic_rtp.py --host 127.0.0.1 --port 5600 --duration 5 --include-parameter-sets
```

If real packet replay is needed later, build a separate replay tool or use a known packet-replay utility. Do not implement decode as part of replay setup.

Replay expectations:

- Diagnostic receiver counters update.
- RTP fields match the captured packet metadata.
- Sequence gap/out-of-order counters reflect the replay stream.
- NAL inspection agrees with capture notes where packet payloads are preserved.

## Unknowns To Resolve Before VideoToolbox

Resolve these before implementing native decode:

- Exact UDP port or port negotiation behavior.
- Whether stream is RTP over UDP or another packet format.
- RTP payload type.
- H.265 packetization mode.
- FU fragmentation behavior.
- Aggregation packet behavior.
- Whether parameter sets are sent in-band.
- VPS/SPS/PPS cadence and whether they repeat.
- Keyframe cadence and IDR availability.
- Marker bit meaning.
- RTP timestamp clock rate.
- Relationship between RTP timestamp and frame duration.
- Packet loss behavior on the APFPV Wi-Fi link.
- Whether the stream can start mid-flight and still recover parameter sets.
- Required buffering/reordering depth for low latency.
- Whether iOS receives packets directly from the APFPV AP without routing issues.

Do not start VideoToolbox work until these are written down from real capture data.

## Results Template For First Real APFPV Capture

| Field | Result | Notes |
| --- | --- | --- |
| Test date/time |  |  |
| Camera model |  |  |
| APFPV firmware/build |  |  |
| Wi-Fi SSID |  |  |
| Laptop OS |  |  |
| Capture interface |  |  |
| Laptop IP |  |  |
| Camera/AP IP |  |  |
| Ping result |  |  |
| Capture filename |  |  |
| Candidate video UDP port |  |  |
| UDP source IP:port |  |  |
| UDP destination IP:port |  |  |
| Unicast/broadcast/multicast |  |  |
| RTP detected |  |  |
| RTP payload type |  |  |
| RTP SSRC |  |  |
| Marker bit behavior |  |  |
| Sequence increments normally |  |  |
| Sequence gaps observed |  |  |
| Out-of-order packets observed |  |  |
| RTP timestamp cadence |  |  |
| Packets/sec |  |  |
| Approx bitrate |  |  |
| Packet size range |  |  |
| H.265 NAL types seen |  |  |
| VPS seen |  |  |
| SPS seen |  |  |
| PPS seen |  |  |
| Parameter set cadence |  |  |
| IDR/keyframe evidence |  |  |
| FU fragmentation present |  |  |
| Aggregation packets present |  |  |
| Stream starts with parameter sets |  |  |
| iPhone diagnostic receiver tested |  |  |
| iPhone packet count/rate |  |  |
| iPhone diagnostic bitrate |  |  |
| iPhone NAL/VPS/SPS/PPS result |  |  |
| No decode attempted |  |  |
| No latency claim made |  |  |
| Open questions |  |  |
