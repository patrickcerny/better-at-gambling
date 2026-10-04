# Progress

## Current milestone: M1 — Core logic library (no visuals)
## Next step: implement `core/rng/seeded_rng.gd` and `core/rng/luck_rng.gd` with unit tests (M1 task list in docs/TODO.md).

## Status by milestone
- M0: DONE (evidence: `scripts/test.sh all` green; `godot --headless --path . -- --smoke-test` exit 0; exports built)
- M1: NOT STARTED
- M2–M11: NOT STARTED

## Verified features (IMPLEMENTED+TESTED)
- Toolchain: Godot 4.7.2 headless, export templates, GUT 9.7.1 (`tools/setup_toolchain.sh`, checksums verified).
- `Cmdline` parser — `tests/unit/test_cmdline.gd` (5 tests).
- Main menu boots headless for 60 frames with no errors — `scripts/test.sh smoke` (boot step).
- Every scene instantiates — `tests/smoke/test_scenes.gd`.
- GUT runner exits non-zero on a failing test (checked with a deliberate failing test, then removed).
- Lint gate rejects untyped declarations (checked with a deliberately untyped file, then removed).
- Exports: Linux, Windows and Linux Server presets export; exported Linux binary boots with `--smoke-test`.
- Screenshot pipeline under Xvfb: `build/screenshots/main_menu.png` rendered and inspected.

## Implemented but unverified
- (none)

## Known bugs
- (none)

## Blockers
- None for M1–M5. Needed from Patrick later: VPS SSH access/specs and a domain (M6), Steamworks App ID + Web API key (M8).

## Session log
### 2026-10-04 / session 1
- Readiness check passed: repo push works; github.com release downloads work; Godot 4.7.2 + templates + GUT run headless.
- M0 built: project.godot (1920×1080 canvas_items/expand, Jolt, Forward+ with Compatibility fallback, 37 input actions keyboard+mouse+joypad, audio buses, 7 autoload stubs), folder structure, `Cmdline`, `Log`, main menu, scripts (test/lint/import/run_server/run_client/sim_match/screenshot/export/run_orchestrator), docs, SessionStart hook for future cloud sessions.
- Tests: `scripts/test.sh all` → lint ok, unit 5/5, smoke 1/1, boot ok.
