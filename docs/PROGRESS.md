# Progress

## Current milestone: M2 — Local playable sandbox (single player, in-process server)
## Next step: build `server/match_server.gd` + `phase_machine.gd` (casino-only) + `station_manager.gd` wired to the M1 logic, then the greybox Lucky Lounge per `docs/ART_DIRECTION.md` (warm luxury look, lobby with fountain/revolving door, VIP balcony).

## Status by milestone
- M0: DONE (evidence: `scripts/test.sh all` green; `godot --headless --path . -- --smoke-test` exit 0; exports built)
- M1: DONE (evidence: 113 unit tests + 8 sim tests green, RTP table in DECISIONS.md, commits 47210ec…)
- M2–M11: NOT STARTED

## Verified features (IMPLEMENTED+TESTED)
- Toolchain: Godot 4.7.2 headless, export templates, GUT 9.7.1 (`tools/setup_toolchain.sh`, checksums verified).
- `Cmdline` parser — `tests/unit/test_cmdline.gd`.
- Main menu boots headless 60 frames; every scene instantiates — `scripts/test.sh smoke`.
- Exports: Linux, Windows, Linux Server presets; exported Linux binary boots with `--smoke-test`; Xvfb screenshots work.
- `SeededRng`, `LuckRng` (0.12·L reroll, never worse for L>0, never better for L<0) — `test_rng.gd`.
- `Economy` + `MoneyLedger` (never negative, reason required, events) — `test_economy.gd`.
- `Modifier`/`ModifierStack` (luck, multipliers, consume on win/loss, rounds, expiry) — `test_modifier_stack.gd`.
- `Card`/`HandEval`/`Shoe` (soft/hard, blackjack vs 21, 6-deck, 75% penetration) — `test_cards.gd`.
- `BlackjackLogic` (simultaneous play, S17, 3:2, double, timeout stand, bust bonus, peek flag, auto-resolve, leave mid-round) — `test_blackjack.gd`.
- `RouletteLogic` (37 numbers mapping, all MVP bet types, limits, cycle, clear bets, lucky neighbour / jinx) — `test_roulette.gd`.
- `SlotsLogic` (paytable, wild, cherry rules, skip-stop, jackpot) and `PlinkoLogic` (rows, cooldown, weighted slots) — `test_slots.gd`, `test_plinko.gd`.
- `ProgressiveJackpot` — `test_jackpot.gd`.
- `InteractionRules` (shove windows, knockout, immunities, shake 2%/8%/$400×mult, same-attacker 20 s, guard sight cone) — `test_interaction_rules.gd`.
- `MatchSchedule` + `MatchPresets` (exact §2.1 table, Last Call, segment index, limits multiplier) — `test_match_schedule.gd`.
- `MatchState`/`PlayerState`/`Serializer`/`Protocol` (wire round-trip through bytes, state hash, room codes) — `test_serializer.gd`.
- `QuizScoring` (500–1000 points, latency compensation, tie ranking) — `test_quiz_scoring.gd`.
- `LootTables` (draft shapes per placement, no duplicates, Underdog ≥ 3 players, weights) — `test_loot_tables.gd`.
- `core/` purity (no Node/scene/I/O) — `test_core_purity.gd`.
- RTP sims: slots 1M spins, roulette 500k per core type, blackjack 400k hands, Plinko 200k per row, all 100.5–102% at L=0, strictly increasing over L∈[−3,3] — `tests/sim/test_rtp.gd` (~100 s).

## Implemented but unverified
- (none)

## Known bugs
- (none)

## Blockers
- None for M2–M5. Needed from Patrick later: VPS SSH access/specs and a domain (M6), Steamworks App ID + Web API key (M8).

## Session log
### 2026-10-04 / session 1
- Readiness check passed; M0 built and committed (see git log).
- M1 built: all core logic + the four game logics with unit tests; RTP tuned (slot weights, Plinko weights, roulette generosity 4%) with Monte-Carlo sims; decisions logged.
- Patrick's art & audio direction adopted as `docs/ART_DIRECTION.md` (+ concept image); master prompt presentation sections now defer to it.
- Tests: `scripts/test.sh all` → lint ok, unit 113/113, sim 8/8, smoke 1/1, boot ok.
