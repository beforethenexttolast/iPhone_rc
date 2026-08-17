# iPhone_rc — Claude Code rules (repo-specific)

Claude Code owns this repo (transferred from ChatGPT Codex, 2026-08-17). The workspace
rules in `../CLAUDE.md` — the seven safety boundaries, the one-session-per-working-tree
worktree discipline, and the commit/review rules — bind here **verbatim**; this file only
adds what is specific to `iPhone_rc`. `AGENTS.md` still holds for any guest session.

## What this app is

`FPVHUDApp`: a SwiftUI, zero-dependency iPhone FPV HUD for the W17 RC car. It is a thin
display client. It renders Windows-normalized telemetry, and — only when settings are
valid, tracking is enabled, the user has centered, and motion is fresh — sends
head-tracking *intent*. It is never a control path: no CRSF, no servo/gimbal/ESC output,
no firmware contact, no vehicle authority. Windows is the control/integration authority.

## Network truth (the complete list)

- **UDP 5601 in** — telemetry snapshots (Windows → iPhone),
  `FPVHUDApp/Networking/UDPTelemetryReceiver.swift`; while listening it also advertises
  `_w17hud._udp.local.` over Bonjour (advisory only, withdrawn on stop/background).
- **UDP 5602 out** — head-tracking intent (iPhone → Windows), LOG-ONLY on the Windows
  side (W3). The **one outbound send site** in the app is
  `FPVHUDApp/Networking/HeadTrackingSender.swift`; do not add another.
- Debug-only, off by default, session-only enable: APFPV RTP diagnostic listener
  (default 5600, receive-only, packet statistics only).

## Canonical contract ownership

This repo **owns** the canonical iPhone↔Windows bridge contract:
`docs/windows_bridge_contract.md` + `schemas/` + `examples/`. `w17-ground-station`
keeps an implementation mirror. Discipline: change the contract **here first**, as a
deliberate named step — never as a side effect of UI work — then mirror to the GS and
give it the canonical commit hash to cite. Schemas/examples move together with the
contract text.

## Test / run truth

- Gate: `./scripts/dev_check.sh` — python script syntax, schema/example validation,
  then simulator build + unit tests via
  `xcodebuild -project FPVHUDApp.xcodeproj -scheme FPVHUDApp
  -destination 'platform=iOS Simulator,name=iPhone 17'`.
- Baseline at the transfer (main = `84532ed`): 55 tests, all green (measured
  2026-08-17 by `dev_check.sh`; an earlier handoff note said 73 — trust the run).
  Keep it green.
- The suite touches no hardware; nothing in this repo ever flashes or powers anything.

## Inherited WIP branch

`codex-wip-vr-calibration` holds pre-transfer Codex WIP (VR shell/calibration slice and
an R10 gate slice), committed as-is. Treat it as read-only history: do not touch it,
base work on it, or merge from it without an explicit owner task.

## Head-tracking gate status (do not regress)

- FIRST_ACTIVE pan/tilt is **NO-GO** (R1–R16 not passed;
  `docs/FIRST_ACTIVE_PAN_TILT_MILESTONE.md`).
- `main`'s motion-staleness behavior is the 500 ms **log-only** tier
  (`HeadTrackingSafety.status`, `FPVHUDApp/Models/MotionState.swift`). The R10 250 ms
  send-time gate lives on the WIP branch only, **not on main**; real-device
  lifecycle/axes/mount validation is still owed before it counts for anything active.
- Sender gating (valid settings AND tracking enabled AND centered AND fresh motion) may
  only ever get stricter. Calibration stays session-only; never persist it.
