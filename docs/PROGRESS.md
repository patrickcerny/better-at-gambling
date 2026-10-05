# Progress

## Current milestone: M6 done (0.6.0-m6). M7 waits for Patrick's word.
## Next step: Patrick says go for M7. Still owed by Patrick: 7 poly.pizza models, 6 licence lines, the roulette wheel texture; "update the server" so the VPS auto-update runs again.

## Status by milestone
- M0: DONE (evidence: `scripts/test.sh all` green; `godot --headless --path . -- --smoke-test` exit 0; exports built)
- M1: DONE (evidence: 105 unit tests + 8 sim tests green, RTP table in DECISIONS.md, commits 47210ec…)
- M2: DONE (evidence: `scripts/test.sh all` green — unit 109, sim 8, integration 15, physics 10, ui 5, smoke 1, boot, 185 s scripted session with 0 errors; screenshots in `build/screenshots/` via `scripts/screenshots.sh`)
- M3: DONE (evidence: `scripts/test.sh net` — 3-minute server + 2 clients match with identical balance digests, grab/throw/shove/knockout at 150 ms + 2% loss with ragdoll agreement ≤ 0.03 m, version mismatch refused, orchestrator end to end with join by code and port freed; `scripts/test.sh orchestrator` 62 pytest; unit 120, integration 21, physics 10, session 0 errors; ~4.6 KB/s per client)
- M4: DONE (evidence: `scripts/test.sh net` — 5-minute match, server + 2 autoplay clients + 2 bots, lobby to results with two quizzes and drafts, identical money+item digests on all three processes; unit 149, integration 29 (`test_match_flow.gd`: quiz schedule 5/30 min, Last Call, Hot Table, comps, closing tables, tiebreakers, secrecy over a full match, play again twice in one room), ui 9 (quiz by key/pad/mouse), session 0 errors; screenshots `quiz_question`, `quiz_end`, `results`)
- M5: DONE (evidence: unit 175 (`test_items.gd` 26: every item, Bodyguard/Mirror, protections, grace, cooldown, discard flow, Pickpocket min/max/broke, Double Trouble × Hot × Last Call order, Golden Chip exactness, banana conservation), integration 35 (`test_items_flow.gd`: intents, items off, Spring Glove, Bodyguard KO, draft → inventory → discard, bots use items in a full match with money conservation), physics 17 (`test_items_scene.gd`: keys, target picker, range ring, banners, peels, effect tags, discard keys, Shift while seated), session with items 0 errors, `scripts/test.sh net` with autoplay clients using drafted items online and identical digests; screenshot `items`)
- Patrick's item batch (0.5.1): DONE. 15 new items plus the Gift Shop from docs/ITEM_IDEAS.md (jail is a todo). Evidence: unit 200 (`test_items_extra.gd`, `test_items_duels_shop.gd`: every item, duel outcomes, decline/timeout/tie replay, bots, conservation, shop stock/prices/one buy per segment), integration 40 (`test_items_stations.gd`: Out of Order blocks sitting and expires, shop through intents), physics 21 (`test_items_extras_scene.gd`: kiosk prompt + panel + buy with keys, duel Y/N and 1–3 prompts, Out of Order sign).
- Pre-M6 batch (0.5.3, on main): settings (Esc + main menu), fixed colours, skins and props, 3D dealt blackjack cards with free look and keys, hot-table arrow, blackjack table and roulette wheel models.
- M6: DONE, with Patrick's changes: **no bots** (removed from the game; tests use `--dummies N` standing players and scripted intents), loading screen added. Evidence:
  - Bots gone: lobby slots, difficulty, add/remove intents, quiz/draft/duel/item bot logic; Practice is solo (`test_room_lobby.gd`, `test_lobby_controller.gd`).
  - Proximity voice (μ-law 8 kHz, 40 ms frames, ~65 kbit/s per speaker, 20 m hearing radius, global in quiz/rewards/results, same table at any distance, push-to-talk T / open mic / off, per-player mute in the Esc panel, mouth flap, talking icons): 39 tests in `test_voice_*.gd` and `test_voice_relay.gd`. No real microphone has been tried yet.
  - Reconnect: `tests/net` crash-and-rejoin (client killed mid-match, rejoins by uid, identical digests). Host leaving: `test_leader_handoff.gd`.
  - Hardening: `tests/sim/test_many_matches.gd`, 50 scripted matches (seeds 1–50, 2–8 players, 5–30 min) reach results with no errors, valid events and money conserved (~47 s).
  - Loading screen + menu backdrop: `CasinoPanorama` (live casino, slow drifting camera, gentle roll, blur), tips; video `/mnt/project-files/better-at-gambling/screenshots/loading_screen.mp4`.
  - Pause menu with settings (since 0.5.3), first-time tips (sit, items, shake), settings persisted.
  - Load: one room with 4 players ≈ 9% of one core, 320 MB RAM peak (`tools/stress/room_load.py`); RAM bounds the VPS (cap 8 rooms). A live stress run on the VPS needs Patrick's PC session.
- M7–M11: NOT STARTED

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

- M2 server layer: `MatchServer` (20 Hz fixed step, timescale), `PhaseMachine`, `StationManager` (VIP ×3 limits), `IntentValidator` + `RateLimiter`, `WorldQuery`, `PickupSystem`, `InteractionResolver` — `tests/integration/*` (15 tests: full phase sequence, play at every station through intents, VIP gating, rate limit, shove→KO→shake→piles conservation, grab/throw/break-free, guard offences).
- Greybox Lucky Lounge (`maps/lucky_lounge/`): lobby with fountain, revolving door, reception, ropes, stairs to the VIP mezzanine with bouncer gate and low railing, blackjack lounge, roulette pit, slot rows, Plinko wall, bar; navmesh (baked at load), LOS raycasts, props on Jolt — `tools/scene_probe.gd`, smoke tests.
- Bean avatar (`player/`): CharacterBody3D with procedural wobble/lean/squash, dot eyes, voice-ready mouth, floppy arms; first/third-person camera, seated camera anchors; 5-body ragdoll with impact/settle signals; held/thrown/seated/stunned/away states; `move` intents at 20 Hz — `tests/physics/test_match_scene.gd`.
- Match scene (`match/match_scene.gd`): in-process Practice server with bots, HUD, station overlays, guards (navmesh patrol, sight cone, chase, throw-out + respawn), fountain (soak + knockout), revolving door push, VIP bouncer pushback + buzzer, mezzanine fall knockout, chip piles + pickups, Plinko chip playback, emotes, results panel, kill floor — `tests/physics/test_match_scene.gd` (10 tests), `scripts/test.sh session`.
- HUD (money with ±pops, timer, rank, items, feed, prompt, toast, leaderboard), `BetPanel` (keyboard + joypad), Blackjack/Roulette/Slots/Plinko overlays — `tests/ui/test_bet_panel.gd`, screenshots.
- `PlinkoSteering` (constrained random walk ending in the server's slot; 1,000 seeded drops) — `tests/unit/test_plinko_steering.gd`.
- Theme (`ui/theme/main_theme.tres` from `tools/gen_theme.gd`, Barlow Condensed), generated placeholder SFX (`tools/gen_audio.py`), `Audio` director with pooled players and music crossfade.

- M3 networking (`net/`, `core/net/`): ENet transport + `DelayedTransport`, `Wire` framing, handshake with version check and token verification, event seq + gap recovery + backlog replay, 4 Hz station status, binary 20 Hz world stream (`WorldCodec`), `InterpBuffer` (100 ms), `NetClock`, `MoveSanity` with force-position — `tests/unit/test_net_codec.gd`, `tests/integration/test_delayed_transport.gd`, `tests/net/`.
- Dedicated room server (`--server`, `RoomHost`): orchestrator verify/heartbeat/closing, reconnect by uid, room full / in progress refusals, closes when empty — `tests/net/test_orchestrator_e2e.py`; exported `Linux Server` binary boots and hosts a match.
- Room orchestrator (`services/orchestrator/`, FastAPI): rooms, codes, port pool, join tokens, spawn/heartbeat/reap, rate limits, dev/Steam auth — 62 pytest.
- Entrance-hall lobby: ready pads, wardrobe mirror and settings board prompts, closed doors until the match starts, `LobbyPanel` (slots, colors, hats, ready, leader settings, add/remove bots), `LobbyController` — `tests/unit/test_lobby_controller.gd`, `tests/integration/test_room_lobby.gd`, screenshot `build/screenshots/online_lobby.png`.
- Body authority handoff (client while standing, server while held/ragdolled/thrown), puppet ragdolls and guards, prop sync, grab/shove prediction — `tests/net/test_net_match.py`.
- Main menu Play Online: create party, join by code, join by address, rejoin last party, connection errors.

- M4 match flow: Casino Quiz (`QuizLogic`, `QuestionBank` with 97 questions in `data/quiz/questions_en.json`, 2 dynamic templates, RTT-credited timing, ties) — `test_quiz_logic.gd`, `test_question_bank.gd`, `test_dynamic_questions.gd`; `QuizStage` — `tests/ui/test_quiz_input.gd`, screenshots.
- Rewards (`RewardDirector`: placement cash, private draft, defaults, bots, 3-slot cap, cash-only mode) — `test_rewards.gd`; `RewardPanel` draft UI.
- Hot Table, House Comp, "Table closing", Last Call — `tests/integration/test_match_flow.gd`.
- Results podium + `Awards`, play again in the same room (leader or 60 s timer) — `test_awards.gd`, `test_match_flow.gd`, screenshot `results.png`.

## Implemented but unverified
- Lobby panel and the wardrobe mirror / settings board prompts by hand (they send the same intents the integration tests cover, but nobody has clicked through them yet), and the Play Online menu with a real mouse.
- Gamepad play end to end (bindings exist and the bet panel is tested with joypad events; nobody has held a real pad yet).
- The reward draft panel and the results buttons by hand (the intents they send are tested; the draft panel has no screenshot yet because the screenshot tool's frame timing skips past the 8 s draft).
- Revolving door "stuck" feel and the mezzanine railing shove-off: both work in tests, tuning is by eye in M7.

## Known bugs
- The lobby doors' sign is partly hidden behind the fountain from some spawn points (greybox layout; M7 art pass).
- Stairs are not on the navmesh (guards never go upstairs; players do, it's physics). Fine for now, revisit when bots roam (M6).
- The slots camera anchor sits too close to the cabinet screen (M7 station polish).

## Blockers
- None for M5. Needed from Patrick later: a domain for TLS (optional), Steamworks App ID + Web API key (M8).

## Session log
### 2026-10-04 / session 1
- Readiness check passed; M0 built and committed (see git log).
- M1 built: all core logic + the four game logics with unit tests; RTP tuned (slot weights, Plinko weights, roulette generosity 4%) with Monte-Carlo sims; decisions logged.
- Patrick's art & audio direction adopted as `docs/ART_DIRECTION.md` (+ concept image); master prompt presentation sections now defer to it.
- Tests: `scripts/test.sh all` → lint ok, unit 105/105, sim 8/8, smoke 1/1, boot ok.
### 2026-10-04 / session 2 (M2)
- Server layer + integration tests, greybox casino, avatar/camera/ragdoll, HUD + station overlays, guards/hazards, Plinko chip, autoplay driver, physics + UI suites, screenshots script.
- Bugs found by the scripted session and fixed: seats faced away from tables (players stood up into the felt), knockback accumulated into vertical velocity (players hit the ceiling), navmesh bake never reached the NavigationServer (guards stood still), stools were "climbable" for the navmesh, the ramp slab had a lip, the porch had no floor.
- Tests: `scripts/test.sh all` green (see M2 evidence above).
### 2026-10-05 / session 3 (M3)
- Orchestrator service, transport/protocol/world stream, room host, lobby, authority handoff, online menus, network test harness (`tests/net`, pytest driving real Godot processes).
- Bugs found by the network tests and fixed: events that arrived before the match scene loaded were lost (backlog replay), snapshots overtook events on another channel (moved to the events channel), bots blocked the lobby exit (they now start on the casino floor), transports leaked through signal cycles, a shoved local player slid ~8 m (push compounding, also in practice).
### 2026-10-05 / session 3b (VPS deploy, pulled forward from M6)
- Deploy kit (`deploy/`): Docker image with Godot + orchestrator, Caddy, install.sh (root or rootless), rollback, auto-update, status.sh.
- Deployed to the VPS at http://152.53.33.53:4300 (rootless, max 8 rooms); the client defaults to it.
- Verified: local Docker stack create/join/match; two clients on Patrick's PC created and joined a party on the VPS with no flags.
- Bug fixed: install.sh exited after the health check for a user without a crontab (pipefail).
### 2026-10-05 / session 4 (M4)
- Quiz (logic, questions, dynamic templates, stage), minigame framework, reward director + draft panel, Hot Table, House Comp, closing tables, awards, results podium, play again in the same room, half-RTT from ENet, autoplay answers and drafts, `--skip-to` for screenshots.
- Bugs found and fixed: the quiz scoreboard and reveal read typed int-keyed dictionaries with string keys (engine errors in the full-match session), opening the quiz called a missing `EmoteWheel.close()`, results beans stood on the floor inside the podiums and faced away, quiz beans faced away, the old question stayed on the big screen under the winner banner, a hot table could repeat the same station.
- Patrick's PC set up `.github/workflows/release.yml`: every push to main publishes a GitHub Release (`releases/latest`).
