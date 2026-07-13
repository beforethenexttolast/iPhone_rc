# Adopted Proposal: mDNS/Bonjour Discovery Of The iPhone HUD (W2 Addressing)

**Status: adopted and implemented in `iPhone_rc`; Windows consumption and real-device discovery validation remain pending.**
Owner of the canonical bridge contract is the iPhone app repo (`iPhone_rc`,
Codex-maintained). This document preserves the Windows side's original
suggestion and records its deliberate iPhone-side adoption. The canonical
definition is now `docs/windows_bridge_contract.md`. Date: 2026-07-10.

## Motivation

The Windows ground station needs the iPhone's IP address as the destination
for W2 telemetry (UDP 5601). Today the setup flow offers manual entry plus a
"last W3 sender" suggestion — both work, but both need the user to know or
produce the address. Bonjour discovery makes the phone announce itself:
zero-config addressing on any network, including the `W17-GRID` hotspot.

Discovery direction: **Windows discovers the iPhone** (Windows needs the W2
destination; nothing about W3 changes — it stays receive-only and LOG-ONLY).

## Service definition (what the iPhone advertises)

- Service type: `_w17hud._udp.local.`
- Instance name: `W17 HUD (<user's device name>)`
- Port: the iPhone app's W2 telemetry **listen** port (default `5601`)
- TXT record keys (all ASCII, all optional except `v`):

| Key | Value | Meaning |
|---|---|---|
| `v` | `1` | bridge contract version the app speaks |
| `role` | `hud` | future-proofing if other peers ever advertise |
| `tport` | `5601` | telemetry listen port (mirrors the SRV port) |
| `feat` | `w2` or `w2,w3` | whether the app will also emit W3 head-tracking intent |
| `dev` | short device name | display label for the Windows picker |

## Windows consumption (separate Windows repo, later milestone)

- Plugs into the existing seam `shared/addressProviders.mjs` →
  `mdnsCandidates()` (a declared stub today; the setup UI already merges
  candidate lists).
- Resolved addresses are **hints only**: shown in the PIT WALL address field
  as candidates the user confirms by hand — never auto-applied. The GRID
  reachability check stays the ground truth.
- Implementation options (decide at build time): a minimal one-shot mDNS
  query over `node:dgram` (PTR → SRV/TXT/A on 224.0.0.251:5353), or a vetted
  dependency. The repo's no-runtime-deps preference suggests the former.

## Safety notes

- mDNS is unauthenticated local-network chatter. A spoofed advertisement can
  at worst cause Windows to offer a wrong candidate; because candidates are
  user-confirmed and W2 is SEND-ONLY display telemetry, the worst case is
  telemetry JSON sent to a wrong local host. No control semantics ride on
  discovery, W3 stays log-only, and nothing here touches the firmware or any
  control path.
- The advertisement contains no secrets (device name is user-visible anyway).

## iPhone Adoption

Implemented on the iPhone side:

1. `UDPTelemetryReceiver` attaches `_w17hud._udp` and the canonical TXT
   record to its W2 UDP `NWListener`.
2. `RootView` and `FPVHUDViewModel` start or withdraw the listener according
   to foreground state, telemetry mode, and configured telemetry port.
3. `Info.plist` declares `NSBonjourServices = _w17hud._udp` and explains
   Bonjour use in `NSLocalNetworkUsageDescription`.
4. `docs/windows_bridge_contract.md` owns the canonical service, TXT,
   advisory-only, lifecycle, and versioning rules.
5. Unit tests cover the canonical TXT values, printable device-name handling,
   configured port changes, foreground/background transitions, and demo-mode
   withdrawal.

The iOS Simulator test suite passes. This is not evidence of real iPhone
Bonjour visibility, real foreground/background behavior, or Windows discovery.
Those remain bench-validation tasks.

## Rollout

1. iPhone adoption and canonical contract update: implemented; commit still
   requires explicit user approval.
2. Windows re-sync and `mdnsCandidates()` implementation: pending in the
   separately maintained Windows repository.
3. Real iPhone/Windows bench validation on the hotspot and a shared network:
   pending. Only successful bench evidence may establish real discovery.
