# AGENTS.md

## Repo Scope
- `iPhone_rc` is the W17 iPhone FPV HUD app.
- The iPhone is a thin HUD/client.
- It receives telemetry snapshots from Windows.
- It may send head-tracking intent packets to Windows.
- It does not control the vehicle directly.
- Windows ground station is the control/integration authority.
- Firmware is separate and remains unaware of iPhone UDP/JSON.

## Ownership Split
- ChatGPT Codex owns and maintains this `iPhone_rc` repo.
- Claude Code owns and maintains:
  - `w17-control-fw`
  - `w17-ground-station`
  - `w17-soundlight-fw`
  - `learning-manual` / workspace docs
- Do not touch sibling repos from this repo.
- Do not modify Windows or firmware repos while working here.

## Bridge Contract Ownership
- `iPhone_rc` owns the canonical iPhone/Windows bridge contract, schemas, and examples:
  - `docs/windows_bridge_contract.md`
  - `schemas/`
  - `examples/`
- `w17-ground-station` keeps an implementation copy.
- Any schema or contract change must be deliberate, reviewed, and mirrored on both sides.
- Do not invent fields casually.
- Do not change schemas as part of ordinary UI work.
- Keep generated and example packets aligned with schemas when protocol work is approved.

## Current Bridge Boundaries
- UDP `5601`: Windows -> iPhone telemetry snapshots.
- UDP `5602`: iPhone -> Windows head-tracking intent.
- W3 / UDP `5602` is LOG-ONLY on the Windows side.
- Head tracking is intent/diagnostic only at this stage.
- The iPhone app must not parse raw CRSF/ELRS telemetry.
- APFPV/OpenIPC video work is separate from the telemetry/head-tracking bridge.

## Safety Boundaries
Non-negotiable:
- No active iPhone-derived pan/tilt until a separate reviewed safety milestone.
- No iPhone -> CRSF.
- No iPhone -> servo/gimbal/ESC.
- No iPhone -> firmware UDP/JSON path.
- No direct iPhone-to-control path.
- Do not treat log-only W3 validation as physical camera-control validation.
- Do not treat simulator/mock motion as real iPhone axis validation.

## Future Active Pan/Tilt Gate
If active pan/tilt is ever requested, it must be a separate reviewed milestone and must include:
- operator enable/arm;
- operator disable/disarm;
- manual override;
- priority rules between manual/gamepad input and iPhone head tracking;
- real iPhone axis validation;
- real phone mount orientation validation;
- physical endpoint limits;
- sign flips;
- center offsets;
- deadband;
- smoothing;
- rate limiting;
- stale timeout behavior;
- stale decay-to-center or hold/disable decision;
- invalid-packet rejection;
- bench-only servo validation;
- conservative servo limits;
- no vehicle driving during first active pan/tilt tests.

## Normal Codex Workflow
- Prefer small focused diffs.
- Show files changed before commit.
- Do not commit unless the user explicitly approves.
- Do not mix unrelated UI, schema, and bridge changes.
- For validation-only tasks, do not edit files unless explicitly approved.
- When uncertain, stop and ask rather than guessing protocol behavior.
- Read the relevant docs before changing behavior.
- Keep safety and authority boundaries visible in reviews and summaries.
- Do not update checkpoint/status files unless the user asks for that specific task.

## Change Hygiene
- Swift source changes belong only in tasks that explicitly ask for app behavior changes.
- Schema, example, script, and README/doc changes should be deliberate and scoped.
- Bridge contract changes require matching schema/example updates when applicable.
- Do not use local simulator success as proof of real iPhone motion-axis correctness.
- Do not use log-only bridge output as proof that physical pan/tilt is safe.
- Preserve conservative defaults: demo may be on, tracking starts off, calibration is session-only.

## Pointers
- `README.md`
- `docs/current_state_onboarding.md`
- `docs/W17_WINDOWS_BRIDGE_HANDOFF.md`
- `docs/windows_bridge_contract.md`
- `schemas/`
- `examples/`
- `scripts/`
