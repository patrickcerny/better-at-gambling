# Progress

## Current milestone: M7 (0.7.0-m7, protocol 4) built locally, not pushed: Patrick said "dont push yet to git or swrver".
## Next step: Patrick says ship, then main + release + VPS deploy (from his PC session). Still owed by Patrick: 7 poly.pizza models, 6 licence lines, the roulette wheel texture.

## Status by milestone
- M0: DONE (evidence: `scripts/test.sh all` green; `godot --headless --path . -- --smoke-test` exit 0; exports built)
- M1: DONE (evidence: 105 unit tests + 8 sim tests green, RTP table in DECISIONS.md, commits 47210ec…)
- M2: DONE (evidence: `scripts/test.sh all` green — unit 109, sim 8, integration 15, physics 10, ui 5, smoke 1, boot, 185 s scripted session with 0 errors; screenshots in `build/screenshots/` via `scripts/screenshots.sh`)
- M3: DONE (evidence: `scripts/test.sh net` — 3-minute server + 2 clients match with identical balance digests, grab/throw/shove/knockout at 150 ms + 2% loss with ragdoll agreement ≤ 0.03 m, version mismatch refused, orchestrator end to end with join by code and port freed; `scripts/test.sh orchestrator` 62 pytest; unit 120, integration 21, physics 10, session 0 errors; ~4.6 KB/s per client)
- M4: DONE (evidence: `scripts/test.sh net` — 5-minute match, server + 2 autoplay clients + 2 bots, lobby to results with two quizzes and drafts, identical money+item digests on all three processes; unit 149, integration 29 (`test_match_flow.gd`: quiz schedule 5/30 min, Last Call, Hot Table, comps, closing tables, tiebreakers, secrecy over a full match, play again twice in one room), ui 9 (quiz by key/pad/mouse), session 0 errors; screenshots `quiz_question`, `quiz_end`, `results`)
- M5: DONE (evidence: unit 175 (`test_items.gd` 26: every item, Bodyguard/Mirror, protections, grace, cooldown, discard flow, Pickpocket min/max/broke, Double Trouble × Hot × Last Call order, Golden Chip exactness, banana conservation), integration 35 (`test_items_flow.gd`: intents, items off, Spring Glove, Bodyguard KO, draft → inventory → discard, bots use items in a full match with money conservation), physics 17 (`test_items_scene.gd`: keys, target picker, range ring, banners, peels, effect tags, discard keys, Shift while seated), session with items 0 errors, `scripts/test.sh net` with autoplay clients using drafted items online and identical digests; screenshot `items`)
- Patrick's item batch (0.5.1): DONE. 15 new items plus the Gift Shop from docs/ITEM_IDEAS.md (jail is a todo). Evidence: unit 200 (`test_items_extra.gd`, `test_items_duels_shop.gd`: every item, duel outcomes, decline/timeout/tie replay, bots, conservation, shop stock/prices/one buy per segment), integration 40 (`test_items_stations.gd`: Out of Order blocks sitting and expires, shop through intents), physics 21 (`test_items_extras_scene.gd`: kiosk prompt + panel + buy with keys, duel Y/N and 1–3 prompts, Out of Order sign).
- Pre-M6 batch (0.5.3, on main): settings (Esc + main menu), fixed colours, skins and props, 3D dealt blackjack cards with free look and keys, hot-table arrow, blackjack table and roulette wheel models.
- Polish 1 (Patrick's playtest, seated tables): the cursor is free at every station (only walking captures the mouse), the head follows the cursor ±25° yaw / ±15° pitch (right stick on a pad), clicks reach every overlay button (the blackjack free look used to keep the mouse captured, so the cursor was hidden and locked to the screen centre), a click no longer leaves focus behind for Space to re-press; blackjack seat views lean in over the rail, hands tilt 28° towards their seat, the dealer's cards stand at 68° in a rack turned to your seat (hole card face down until the reveal). Evidence: physics `test_seated_view.gd` (mouse mode per station and through the Esc menu, cursor head turn, real mouse clicks on chip/BET/HIT/STAND, card normals face every seat); screenshots `/mnt/project-files/better-at-gambling/screenshots/polish1/blackjack_*`.
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
- Plinko polish (Patrick, 2026-10-06): `PlinkoFlight` gravity arcs peg to peg with spin, plinks and peg flashes, no tunnelling, chip falls from the drop and touches down as the server settles; gold-trimmed board with marquee, funnel, MultiMesh pegs, payout-coloured buckets and multiplier plates (×13, ×0.5, jackpot chance on High) that follow the picked risk; slim right-docked panel (risk, bet stepper, DROP, last drops) — `tests/unit/test_plinko_flight.gd`, `tests/physics/test_plinko_board.gd`, `test_items_extras_scene.gd`.
- Theme (`ui/theme/main_theme.tres` from `tools/gen_theme.gd`, Barlow Condensed), generated placeholder SFX (`tools/gen_audio.py`), `Audio` director with pooled players and music crossfade.

- M3 networking (`net/`, `core/net/`): ENet transport + `DelayedTransport`, `Wire` framing, handshake with version check and token verification, event seq + gap recovery + backlog replay, 4 Hz station status, binary 20 Hz world stream (`WorldCodec`), `InterpBuffer` (100 ms), `NetClock`, `MoveSanity` with force-position — `tests/unit/test_net_codec.gd`, `tests/integration/test_delayed_transport.gd`, `tests/net/`.
- Dedicated room server (`--server`, `RoomHost`): orchestrator verify/heartbeat/closing, reconnect by uid, room full / in progress refusals, closes when empty — `tests/net/test_orchestrator_e2e.py`; exported `Linux Server` binary boots and hosts a match.
- Room orchestrator (`services/orchestrator/`, FastAPI): rooms, codes, port pool, join tokens, spawn/heartbeat/reap, rate limits, dev/Steam auth — 62 pytest.
- Entrance-hall lobby: ready pads, wardrobe mirror and settings board prompts, closed doors until the match starts, `LobbyPanel` (slots, colors, hats, ready, leader settings, add/remove bots), `LobbyController` — `tests/unit/test_lobby_controller.gd`, `tests/integration/test_room_lobby.gd`, screenshot `build/screenshots/online_lobby.png`.
- Body authority handoff (client while standing, server while held/ragdolled/thrown), puppet ragdolls and guards, prop sync, grab/shove prediction — `tests/net/test_net_match.py`.
- Main menu Play Online: create party, join by code, join by address, connection errors ("Host on this PC" and "Rejoin last party" removed after Patrick's playtest notes).

- M4 match flow: Casino Quiz (`QuizLogic`, `QuestionBank` with 97 questions in `data/quiz/questions_en.json`, 2 dynamic templates, RTT-credited timing, ties) — `test_quiz_logic.gd`, `test_question_bank.gd`, `test_dynamic_questions.gd`; `QuizStage` — `tests/ui/test_quiz_input.gd`, screenshots.
- Rewards (`RewardDirector`: placement cash, private draft, defaults, bots, 3-slot cap, cash-only mode) — `test_rewards.gd`; `RewardPanel` draft UI.
- Hot Table, House Comp, "Table closing", Last Call — `tests/integration/test_match_flow.gd`.
- Results podium + `Awards`, play again in the same room (leader or 60 s timer) — `test_awards.gd`, `test_match_flow.gd`, screenshot `results.png`.

## Implemented but unverified
- Lobby panel and the wardrobe mirror / settings board prompts by hand (they send the same intents the integration tests cover, but nobody has clicked through them yet), and the Play Online menu with a real mouse.
- Gamepad play end to end (bindings exist and the bet panel is tested with joypad events; nobody has held a real pad yet).
- The reward draft panel and the results buttons by hand (the intents they send are tested; the draft panel has no screenshot yet because the screenshot tool's frame timing skips past the 8 s draft).
- Revolving door "stuck" feel and the mezzanine railing shove-off: both work in tests, tuning is by eye in M7.

- M7: built (local only until Patrick says ship). Evidence: lint; unit 251, integration 68, physics 48, ui 26, sim 9, smoke 1; `scripts/test.sh net` 5/5 (12.5 min). Contents:
  - Tables and VFX (`vfx/`): chips slide onto the felt, roulette ball and number ring, slot reels, win/loss deltas, coin bursts, shake, hit-stop, HUD money counter, Hot Table spotlight and fire, Last Call lighting.
  - Characters: squash/stretch, arm swing, blink, win/big win/loss/slip reactions, ragdoll flail and get-up, KO stars and birdies, guard carry-and-toss, fountain splash, leader crown (`tests/physics/test_chaos_feel.gd`).
  - Blackjack split (P / RB, rules in DECISIONS.md, Dealer Bust Bonus now 1.07:1, RTP 101.5%), emote wheel (G / D-pad down), keyboard/gamepad glyphs.
  - Quiz host cat, confetti, results podium show, 12 awards (`test_awards.gd`), money-over-time graph, name tags.
  - Five generated lounge-jazz loops with mood crossfades by phase (`audio/music_mood.gd`), new SFX, every event sounded (`audio/event_sfx.gd`, table in GDD.md); music and SFX not yet listened to by a human.
  - Waiter NPC who trips (by himself, on bumps or shoves) and leaves slippery puddles; Megaphone at the bar (E, 10 s of full-volume voice). Protocol 4: old 0.6 clients are refused.
  - Pixel look: removed in 0.9.15 at Patrick's request (see the session log); the code is saved on the branch `pixel-look-saved` (commit 8c4ff3c). The 3D world still renders in `PixelView`'s sub viewport, now always at the window's full resolution with linear filtering. Tests: `tests/ui/test_pixel_view.gd`, `tests/smoke/test_world_view_scenes.gd`, `tests/unit/test_settings_removed_keys.gd`.

## Known bugs
- (fixed 2026-10-06) The VIP mezzanine could not be reached on foot: the south-east pillar and the back bar
  stood across the bottom of the first stair flight (0.55 m gap for a 0.84 m capsule), flight 2 ran into the
  mezzanine landing's side face, and the east mezzanine railing ran straight across the VIP gate. Covered by
  `tests/physics/test_vip_access.gd` (walk up, bounce while broke, walk in and sit when rich).
- The lobby doors' sign is partly hidden behind the fountain from some spawn points (greybox layout; M7 art pass).
- Stairs are not on the navmesh (guards never go upstairs; players do, it's physics). Fine for now, revisit when bots roam (M6).
- (checked 2026-10-07, S13) The slots camera anchor no longer sits too close: the seated view frames the marquee and reels at about 1 m with the panel below them. No change needed.

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
### 2026-10-06 / polish 1 (map)
- VIP access fixed (see Known bugs); stairs rebuilt as two flights meeting their landings flush, rail guards
  as invisible walls under visible handrails, bar moved east of the staircase, pillars moved off it.
- Lucky Lounge textures and decor (client only, `lounge_decor.gd`): CC0 set from the texture research
  (casino carpet + fibre normal, checker marble, herringbone parquet, damask wallpaper, mahogany wainscot,
  brass, black marble, velvet, coffered ceiling; ~1.8 MB), Quaternius columns/windows/curtains/doors, Poly
  Haven mirror, paintings, bust and horse (~3.7 MB). `tools/import_textures.sh` regenerates the textures.
  Map shots: `scripts/map_shots.sh` (free camera via `tools/screenshot.gd --cam/--look`), copies in
  `/mnt/project-files/better-at-gambling/screenshots/polish1/map/`.
### 2026-10-11 / 0.9.2 and 0.9.3 (host mode, ten minigames)
- 0.9.2: host mode ("Host on this PC (Steam)": a hidden headless room server on the host's PC, friends join
  through Steam invites / Join Game over Steam's relay, GodotSteam 4.23.1, test App ID 480), the coin logo,
  and the first four games of the minigame round: Find the Lady, Forehead Poker, Spy, Pass the Bomb (the
  first walkable room, W).
- 0.9.3: Patrick's 0.9.2 playtest fixes and the other six games. Fixes: online moves inside a minigame
  room were refused as "off the map" by the move sanity check (the room is 200 m from the casino), so
  nobody could move in Pass the Bomb; minigames come from a shuffled bag (no repeat until every game the
  table can play has come once); Escape opens the pause menu in every minigame (own layer above the stage
  UI). Games: Bat Heist (vault, bats, coin stealing), Last Seat at the Table (parlor, musical chairs),
  Grab Your Hand (card hall, poker hands), Roulette Sumo (wheel room, fast wheel that flings you
  outward, rolling ball, little pushes, no bats), Dodge the Dice (climb room "board": tilted roulette board, falling hazards, climbing
  kit), Jackpot Climb (climb room "towers": chip stacks up to the JACKPOT sign).
- Rooms: `minigames/common/{vault_arena,parlor_room,card_hall,wheel_room,climb_room,chip_towers}.gd`,
  climbing helpers in `climb_kit.gd`. Each game has its own unit test and an integration test through
  `ServerFixture` with `minigame_pool`.
### 2026-10-26 / 0.9.16 XP, Coins, colours
- **XP and levels** (Patrick: "Create a XP level and an ingame currency. There will be a shop for
  cosmetics."): a local profile (`ProfileManager` autoload, `PlayerProfile`, `user://profile.cfg`,
  every value clamped on load, no DRM) keeps XP, level, Coins, owned and preferred cosmetics and
  lifetime stats. The server works out each player's XP from the match (`Progression.breakdown`,
  numbers in `data/progression/progression.tres`): match played 100, placement 120/80/50/30/20,
  30 per minigame won, 1 per $20 profit (max 100), 2 per table hand (max 60); Practice half. It
  sends the rows in `match_ended` (`progress`, `match_id`, also in the RESULTS snapshot) and each
  client adds its own row once per match id. Level L→L+1 costs 100 + 35(L−1) up to level 10
  (2,160 XP, about 8 typical ~280 XP matches), then 450 + 50(L−10); cap 99.
- **Coins**: a tenth of the match's XP plus 50 per level gained, a drawn gold coin icon
  (`CoinIcon`). Only for cosmetics, never at the tables; the UI says the $ starts fresh each match.
  Main menu: a LEVEL / XP bar / Coins line top left (`ProfileBadge`). Results: "+N XP" on every
  standings row, YOUR XP breakdown bottom left and the level bar filling with the Coins bottom right.
- **Cosmetics shop** (COSMETICS in the main menu, the T-shirt button and the lobby tablet,
  `CosmeticsPanel`): 16 bean colours, the 8 player colours free, Ruby, Mint, Lavender, Teal, Lime,
  Onyx, Silver, Gold 150–400 Coins (`data/progression/cosmetics_shop.tres`, `CosmeticDef` with a
  kind so hats can follow); a turning bean preview, BUY and WEAR.
- **Bean colour vs slot colour**: the server still gives every player one of the 8 slot colours
  (HUD, name plate, pedestal). The bean wears the preferred colour from the hello when no other
  bean wears it, else the slot colour, else the first free one (`Cosmetics.bean_color_for`); two
  beans never match. `PlayerState.bean_color` on the wire, intent `set_color`, event
  `player_color`, error `color_taken`.
- **Pedestal colour panel** (Patrick: "under the podest should be a color panel you can click"):
  a brass lectern beside every ready pedestal with a 4×4 swatch plaque (`ColorPlaque`,
  `ColorPanelController`); look at a swatch on your own and click or press E to wear it (lobby
  only); it also becomes your preferred colour. Worn colours dimmed, yours framed.
- **Skins removed** ("Remove all other skins"): the six poly.pizza skin models, `SkinLibrary`,
  `SkinArmModifier`, the skin preview view, the clothes panel, `Cosmetics.SKINS`, the `skin` field
  in the hello and player state, `set_skin`/`player_skin`, the skin parts of `AvatarVisuals`,
  `RagdollBody` and `PlayerAvatar`, and the skin rows in CREDITS and MODELS. The Tab list's
  portraits are now the player's bean in its colour. `PROTOCOL_VERSION` 10 → 11.
- Tests: new `test_progression`, `test_player_profile`, `test_bean_colors` (unit),
  `test_progress_results` (integration), `test_cosmetics_shop`, `test_color_panel` (ui), more in
  `test_results_stage`; skin tests deleted or rewritten; the main menu test lists COSMETICS. Dev
  shot `tools/dev/cosmetics_shot.tscn` (shop, menu, plaque, results). Suites: lint ok; unit 850,
  ui 291, integration 261, physics 170, smoke 4 + boot, session green.

### 2026-10-19 / 0.9.15 Pixel look removed
- **Pixel look removed** (Patrick: "OK no actually remove that filter overall. Save the code
  though if i want to implement it again"): the game always renders at the window's full
  resolution with linear filtering, in menus, the match and minigames. The whole feature as it
  was in 0.9.14 lives on the GitHub branch `pixel-look-saved` (commit 8c4ff3c) for a later
  return. Gone: the first-launch PIXEL LOOK / SHARP LOOK card (`PixelLookPrompt`), the "Pixel
  look" toggle and hint in Settings > Video, the setting `video/pixel_look` (an old settings file
  loses it and the older `video/pixel_scale` quietly on load, `Settings.drop_removed_keys`),
  `Settings.pixel_scale()/pixel_look()/has_pixel_look_choice()/choose_pixel_look()/
  set_pixel_override()/PIXEL_SCALE`, the "[video] pixel look" log line, the name tags' larger
  minimum under a shrink, and the screenshot tool's `--pixel N` (still accepted on old command
  lines, ignored with a note). Kept: `PixelView` itself (class and `pixel_view` names unchanged to
  avoid churn), because the match's 3D lives in its sub viewport: the HUD and stage UIs sit on the
  window outside it, Find the Lady maps clicks through it (`PixelView.to_canvas`, also needed
  when the window is stretched), the dev shot tools put cameras in its `world`. It is now fixed at
  stretch 1 with linear filtering and no longer listens to settings. The logo, the skin previews
  and the menu panorama (still half resolution under its deliberate blur) no longer read a shrink.
  Tests: deleted `test_settings_pixel_look.gd` and `test_pixel_look_prompt.gd`; rewrote
  `tests/ui/test_pixel_view.gd` (full window size, linear filtering, unchanged by settings, no
  Video toggle); `tests/smoke/test_pixel_scenes.gd` became `test_world_view_scenes.gd` (one run
  at full resolution); new `tests/unit/test_settings_removed_keys.gd`; the Find the Lady click
  test now simulates a stretched window (viewport at twice the canvas) instead of 1/3.

Voice relay: "reached nobody" now tells "with nobody else in the room" apart from out of reach
(`VoiceRelay.alone_from`, in the summary and the first-relay log line). The hosted-room voice net
tests had failed on one last frame said after the friend left the room, which the 0.9.13 check
read as a reach problem; they now require only that no frame was out of reach while the other
player was present.

### 2026-10-19 / 0.9.14 Patrick's batch: hot arrow, closer seat views, pixel look choice, Sword Tapper panel, F11
- **Hot arrow** ("a bit too big. Make it always the same size, wall see through is good"): the
  bouncing 3D arrow over the hot table (`StationBase` hot marker, not the HUD's screen-edge
  pointer) grew with distance (`d / 6`, clamped 1..5), so it was 1/4 of the screen up close and a
  speck beyond 30 m. Its scale now follows the camera's distance and field of view
  (`StationBase.hot_marker_scale`): always 12% of the screen's height (the old one was ~19% at
  mid range), the bounce scaled with it, the fixed-size "HOT ×1.25" label no longer scaled twice;
  still drawn through walls. Test in `tests/ui/test_hot_pointer.gd`.
- **Closer seat views** ("Even closer on craps and sword tapper ... almost the whole screen should
  be the game"; "Same for fortune wheel"): craps looks almost straight down from over the felt
  (the felt end to end, every bet spot, the dice and the stickman in the left two thirds; the
  sign behind the table is out of the picture), the wheel view sits close over the layout (the
  wheel over half the screen's height, every box's chips and the dealer in view, the layout's front
  edge cut), the Sword Tapper view is right over the pedestal top (the ring ~65% of the height,
  like Patrick's crop); its multiplier now slams down past the far rim so it never covers the
  gems. Default FOV 85; the overlay column untouched. Framing tests: `test_craps_table.gd`,
  `test_wheel_table.gd` (updated to the new framing: the sign / the layout's front corners
  dropped, bigger minimum spans), new `tests/physics/test_sword_tapper_view.gd`.
- **Pixel look choice** ("leave an option to make the noise filter on the texture ... to disable
  it. When first started the game, give an option"): the only filter that makes the textures
  grainy is the pixel look (`PixelView`: the world at 1/3 resolution, nearest-neighbour); there is
  no film grain, dither or noise post effect (the casino floor's noise is its material). New
  setting `video/pixel_look` (default on): off renders at full resolution with linear filtering.
  First launch: `PixelLookPrompt` over the main menu (PIXEL LOOK / SHARP LOOK), shown only while no
  choice is saved and the game booted normally (never under `--smoke-test`, the dev/test boot
  flags, headless, GUT or the screenshot tool); Settings > Video has the toggle and switches it
  live. The developer override (`Settings.set_pixel_override`, `--pixel N`) still wins. Tests:
  `tests/unit/test_settings_pixel_look.gd`, `tests/ui/test_pixel_look_prompt.gd`,
  `tests/ui/test_pixel_view.gd` (live toggle; its "no pixel option" test now checks the single
  on/off toggle).
- **Sword Tapper panel** ("this ui field of sword tapper is very weird. make it better, probably
  also a bit smaller (make the ui the same as the game / the 3d model)"): a compact column (470 px,
  only as tall as its content; `StationUi._column_width` / `_column_fills_height`) that draws the
  pedestal top (`SwordRingView`): gem dots where the lamps are, sized like them
  (`SwordTapperStation.gem_radius`, the ruby biggest and red at the top), the prize for the stake
  beside each, the multiplier rule on the stone, and the pedestal's lit gems lit as they light;
  "PRIZES AT $25", chips and PULL under it, compact last pulls. Test: `tests/ui/test_sword_tapper_ui.gd`.
- **F11** ("On f11 press fullscreen toggle"): new action `toggle_fullscreen` (F11, remappable in
  Controls > Camera & system), handled in the `Settings` autoload's `_input` so it works in the
  menus, a match, minigames and the pause menu; it flips and saves `video/fullscreen` and the
  Video tab's box follows (`SettingsPanel.checks` resync on `Settings.changed`). F11 was unbound;
  Esc stays pause. Test: `tests/unit/test_fullscreen_toggle.gd` (headless: the setting and the
  window mode asked for, `Settings.window_mode_for`).

Reward items: the player who leads the money never draws a leader-only item (Robin Hood) any
more, as the main or the Underdog item. The full-suite net run for 0.9.14 showed Bob leading,
drawing Robin Hood after both quizzes and having every use refused with `you_lead`, so the
"items get used online" check failed; the roll is now made after every prize is paid and skips
`LootTables.leader_only` for the leader (`RewardDirector._leads`). Tests in test_rewards.gd.

### 2026-10-19 / 0.9.13 Sword Tapper
A new casino-floor station from Patrick's Hard Rock picture (Greentube's Lucky Sword – Tapper),
built to the design in `/mnt/project-files/better-at-gambling/SWORD_TAPPER.md` (GDD entry under
Casino games):
- **Game** (`games/sword_tapper/`): `SwordTapperLogic` (one player per pedestal, $10–$100 × limits,
  all-in over the balance, decided at the tap in one `sword_pull` event, paid when the 2.5 s reveal
  ends or at once on walking away / knock-off / casino close / minigame start, never refunded;
  "Table closing!" under 3 s; not a Hot Table candidate via `StationLogicBase.hot_table_candidate`).
  Ring of 17 gems (6 × 0.1, 4 × 0.2, 2 × 0.3, 2 × 0.5, 1, 2, ruby 5), 3–17 lit, ×2/×3/×5/×10 on
  9 gems or fewer, `sword_pull_chance` 0.24 + quiet `sword_favour` 0.08, luck through `LuckRng.draw`.
  Exact RTP at luck 0 **100.91%** (95.1% without the house rule; Monte Carlo 400k pulls through the
  real logic 100.75% ± 1.4%); free 25.5%, ≥ 10× 1 in 59, ≥ 50× 1 in 3,200, best pull 100×. No
  tuning needed.
- **Pedestal** (`SwordTapperStation`): marble plinth, brass rim, velvet disc with 17 gem lamps and
  their prizes, stone and gold sword, warm spotlight shaft and dust motes; the bean stands (seat
  `stand` meta) and heaves at the hilt; stuck: wobble, thud, dust puff; free: ring of light, gems pop
  in order with rising plinks, the multiplier slams down; a ≥ 20× pull raises a golden light column
  and posts "X pulled the sword: $N!". New sfx `stone_grind`, `sword_ring` (`gen_sfx.py`).
- **Overlay** (`SwordTapperUi`, docked right column, seat camera over the right shoulder): stake
  chips, PULL (Space / E / pad A pulls again), the ring's prizes for the stake, the multiplier rule,
  the result after the reveal, last 8 pulls, HOW IT WORKS.
- **Floor**: `sword_1` / `sword_2` side by side in all six layouts (`docs/FLOOR_PLAN.md`), the full
  floor map, HUD money-on-table line, feed label "Sword Tapper 1". PROTOCOL_VERSION 10.
- Found on the way: with The Grand Hall's pedestals against the lobby wall (z 6.9), a lobby spawn
  was inside the 3.5 m interact range through the wall (E in the lobby stepped up to the sword).
  They stand at z 5.9 now; `test_sword_tapper_pedestal.gd` checks no lobby spawn gets a casino
  prompt in any layout. The leader's crown hides with your own bean in a seat view (it floated in
  front of the standing seat camera).
- Tests: `tests/sim/test_rtp_sword_tapper.gd`, `tests/integration/test_sword_tapper_flow.gd`,
  `tests/physics/test_sword_tapper_pedestal.gd`, `tests/ui/test_sword_tapper_ui.gd`,
  `tests/unit/test_floor_plan.gd` (two pedestals per layout). Dev render
  `tools/dev/sword_tapper_shot.tscn` (`--view front|seat|close|floor|match`).

### 2026-10-19 / 0.9.13 macOS .dmg
Patrick: "allow mac dmg". The release now also carries `BetterAtGambling-macos.dmg` next to the
zip: `tools/macos/package.sh` takes an optional third path and writes an ISO 9660 image (Rock
Ridge + Apple extensions, `genisoimage`) of the signed .app, checking that the game binary kept its
executable bit. Release notes point Mac players at the .dmg first. Tested here with a stand-in app
and a stand-in signer; mounting on a real Mac is untested (no Mac available).

### 2026-10-19 / 0.9.13 voice net tests on a busy machine
The two voice net tests (`test_voice_from_one_client...` in `test_net_match.py`,
`test_voice_goes_both_ways...` in `test_net_host_mode.py`) failed with other suites running
("heard 0.219 vs 0.366", "0.323"). Reproduced next to a looping net test and busy loops (0.182),
and every time by freezing the listening client twice for 0.7 s mid-match (SIGSTOP/SIGCONT, the
way a busy machine stalls it): 0.108 and 0.068 vs 0.366. Three causes in the tests, no voice fault:
- **The level was one Goertzel over the whole dump**, which reads it only while the tone stays in
  phase. A stall makes a burst, the jitter buffer drops its oldest frames on purpose (35 in the
  frozen run), the tone jumps phase there and the parts cancel: every played frame (942)
  was the tone at 0.363–0.367, the whole dump read 0.108. The tests now check the tone frame by
  frame (`_tone_frames`): every played frame at the speaker's level unless the buffer concealed
  it, no more phase jumps than counted missing frames (none when nothing is missing), the other
  tones and the RMS over the whole dump as before. Doctored dumps (half or 85% level, two frames
  swapped, frames dropped, a 1000 Hz tone, every other frame silent) all fail it.
- **Voice said while the listener's match was still loading** waits in their socket (the room
  relays to a joined player whose game is still loading the scene), arrives in one burst and the
  jitter buffer keeps the newest 12 frames: up to 84 frames dropped on the busy machine, all before
  the first frame played (instrumented: the 96 frames came in 1.35 s), over the 5% "drops stay
  rare" bound. Right for players (otherwise that speaker is late all match).
  `VoiceJitterBuffer.overflowed_before_start` counts it, the voice summary says "overflowed N (M
  before the first frame played)", and the bound is on the drops while playing. The bridged
  friend's "3-4% burst drops" were this backlog too (0-1 drops while playing in 5 runs), so that
  leg is held to 5% now instead of 8%.
- **"reached nobody" < 200** timed how long the host talked before the bridged friend joined
  (119-170 quiet, 210-239 busy). The room now logs the count when it first relays to a listener
  ("relaying player 1's voice to player(s) [2] (lobby, after 170 that reached nobody)") and the test
  wants every unheard frame to be from before that.
- Checked, not a playback bug for players: the game clock kept up with the wall clock under load
  (delta sum within 0.1 s of wall time over 39 s), no spurt ever ran dry, and real-audio playback
  paces itself by the generator, not by `delta`. Headless playback is clocked by `delta`, which
  Godot caps after a long frame (8 physics steps), so a frozen headless listener drops a little
  more than a real one would; the counts cover it.
- Runs (each a whole test, 60-80 s): before the fix, frozen listener: match 0.108, host loopback
  0.068 (fail). After: frozen listener 3/3 match, 3/3 host loopback; next to a looping net test and
  five busy loops on two pinned cores 3/3 match, 3/3 host loopback, 3/3 host bridge; quiet machine
  2/2 of all three. `scripts/test.sh unit`, `integration`, `lint` green.

### 2026-10-18 / 0.9.12 voice fixes
Patrick: "other people online dont hear me", "no, friends can't hear each other". Every headless
test was green because headless playback never makes a sound (it only clocks frames through the
mouth), so this time a real windowed client ran under Xvfb with PulseAudio (null sink, its monitor
recorded with `parec`) next to a headless server and a `--voice-test` speaker. That client did
play voice; what kept real players from hearing each other were the rules and the defaults:
- **Push-to-talk was the default and nobody held T.** The VPS log had 15 voice frames (0.6 s) in a
  whole casino round. Open mic is the default now (`services/settings_manager.gd` DEFAULTS
  voice/mode, `voice/voice_channel.gd` `DEFAULT_MODE`; `VoiceChannel` and the Split or Steal hint
  used to pass their own "push_to_talk" fallback, which beat the defaults). A saved choice stays.
- **The lobby was proximity voice.** 73 lobby frames "reached nobody". The lobby, the intro and the
  regroup are global now (`voice/voice_proximity.gd` `GLOBAL_PHASES`); the casino and the
  pre-minigame warning stay proximity. The server's positions were checked and are right (moves
  in the lobby and casino, seats, rooms); the real client heard the speaker at 37% at 14 m in the
  lobby before, 100% now.
- **A slow client threw half the voice away.** With a fixed 80 ms generator lead, a frame longer
  than 80 ms (the real client ran at 8 fps under Xvfb) let the generator run dry every frame, voice
  played slower than it arrived and the jitter buffer overflowed: received 1069, played 528,
  overflowed 540. `VoicePlayback.lead_seconds(delta)` queues a frame and a half plus 40 ms when
  frames are slow (capped at 80% of the generator buffer, now 0.5 s): received 1080, played 982,
  the rest dropped on load hitches.
- Checked and fine on the real client: the Voice bus exists in the layout and at runtime
  (-1.8 dB at the default 0.9 slider, unmuted, sends to Master), the pixel view's viewport has
  `audio_listener_enable_3d`, the playback is created by player id under that player's avatar, the
  3D player starts, the generator runs at the output mix rate, distance gain is from the local
  camera, and table/global voice play at full volume.
- New tests: `tests/ui/test_voice_heard_in_match.gd` (a real match scene; `VoicePlayback.force_audio`
  keeps the real `AudioStreamPlayer3D` on headless, the Dummy driver mixes it and an
  `AudioEffectCapture` on the Voice bus must hear the 440 Hz tone a relayed packet carries; the
  Voice bus exists unmuted at the setting's volume; global voice full volume; a muted player is
  silent; it fails with the listener switched off); `test_voice_relay.gd` (everyone hears everyone
  in the lobby wherever they stand; lobby, intro, regroup global); `test_voice_playback.gd` (8, 10
  and 14 fps play every frame with no overflow; the lead's bounds); `test_voice_end_to_end.gd` (a
  fresh install talks on open mic with no key; the T key itself talks with a text field focused,
  the HUD says "Hold T to talk").
- Not verified: Windows WASAPI output and real microphones in a real online party; open-mic echo
  from players on speakers.

### 2026-10-18 / 0.9.11 (built, held back: Patrick "do it now but dont push it")
- PROTOCOL_VERSION 9 (the floor plan payload names the layout and carries positions).
- Patrick's 2026-10-17/18 notes, all in: third-person camera straight behind the bean; scratch
  cards fixed price (no all-in: a $100 card is not sold for $76); the hot table's arrow and label
  hidden while a minigame stage is up; wheel and craps seat cameras close on the table with the
  overlay in a right-hand column; six hand-made floor layouts rotating every round with the bar,
  the ropes, the CLOSED TONIGHT signs and the TONIGHT'S FLOOR board gone and the scratch kiosk on
  the casino floor by the Gift Shop; Jackpot Climb a run with seven short hops and a 604-spot
  no-trap test. Details in the three entries below.
- Voice ("other people online dont hear me"): no broken path found. New net test
  `test_voice_goes_both_ways_between_the_host_and_a_friend_in_a_hosted_room` (loopback and
  through the host's `HostBridge`, `--bridge-port` dev flag) is green both ways. Fixed on the way:
  `VoiceChannel._exit_tree` assigned a freed playback (SCRIPT ERROR at match end, skipped the voice
  shutdown); `VoiceCapture._note_held_back` logs once when a mic heard 2 s of sound but nothing was
  sent (push-to-talk not held, or under the open-mic gate); a mic losing audio is a warning. In a
  match nobody hears their own voice; only Settings > TEST MICROPHONE plays you back.
- Hot table HUD arrow: `_point_at_hot_table` guards a target on the camera plane (engine
  `p.d == 0` errors after a floor switch); `tests/ui/test_hot_pointer.gd`.
- Suite: lint ok; unit 820; sim 22; integration 244; physics 169; ui 273; smoke 4 + boot;
  session; orchestrator 68; net 13/14 in the full run: `test_create_join_by_code_play_and_room_closes_when_empty`
  timed out once creating the room (HTTPRequest result 13 after 8 s, the orchestrator logged no
  request) and passed 3/3 on reruns; the orchestrator now logs `room_create_requested` on arrival
  so a repeat shows whether the request got there.
- Not verified: real online play of the new floor rotation and views with several clients; the
  Steam relay; Windows WASAPI; whether Patrick held T or used open mic.

### 2026-10-18 / 0.9.11 (Jackpot Climb: a run, not a jump-and-run)
- Jackpot Climb is a run now, not a jump-and-run (Patrick: "you can get stuck on climb game"): felt
  ramps and spiral walkways round the three tiers, a steady lane with no jumps and a bold lane with
  seven short hops in all; no pockets, ledges or gaps to get stuck in. Clean run 32.4 s steady,
  27.3 s bold (was 31.5 s). Evidence: `tests/physics/test_jackpot_climb_course.gd` drives a real
  `PlayerAvatar` (via `tests/helpers/climb_runner.gd`) up every lane, from every flag spot, and
  from 604 dropped spots on a 1.25 m grid over the whole course: all reach the next checkpoint or
  are sent back to a flag (no trap); geometry checks in `tests/unit/test_jackpot_climb_logic.gd`.
### 2026-10-18 / 0.9.11 (floor layouts: a different casino floor every round)
- Patrick: "After every minigame, the games (and layout change)... rotate between these layouts",
  "there shouldn't be an out of order sign... just another layout", "remove the tongiths floor its
  stupid", "remove the bar", the scratch kiosk by the Gift Shop, the wheel turned round.
- Six hand-made floor layouts (`FloorLayout`, `data/floor_layouts/*.tres`, listed in
  `data/balance/floor_plan.tres`): The Grand Hall (the full floor; `LuckyLounge.STATIONS` is this
  layout plus the fixed stations), Wheel Night, The Pit, The Arcade, The Long Room, The Salon.
  Tables and the changes from the design sketches in `docs/FLOOR_PLAN.md`.
- `FloorRotation`: a bag shuffled from the match seed, no repeats before it is empty, a fresh bag
  never starts with the layout that just stood; a layout whose game has weight 0 or that fails the
  fit check is skipped, and if none can be used The Grand Hall stands. Lobby opening, Play Again
  (fresh bag) and every regroup take the next layout. Practice and the menu keep The Grand Hall.
- No closed spots any more: ropes, CLOSED TONIGHT signs, plants on empty spots and the TONIGHT'S
  FLOOR board are gone (`maps/lucky_lounge/floor_props.gd` deleted). The feed says "The floor has
  changed!".
- The bar is gone (counter, back bar, stools, parquet). The scratch counter stands on the casino
  floor by the Gift Shop (never in the entrance hall); the Wheel of Fortune always has its back to
  a wall or a slot bank.
- Tables that move are fresh tables (`StationManager.apply_stations` `moved`): seated players are
  stood up (`floor_changed`) and refunded, a hot table that moves cools.
- PROTOCOL_VERSION 9: `floor_plan` is `{round, layout, stations: {station id: [game, [x, y, z],
  yaw degrees]}}` in `match_started`, `regroup_started`, `match_reset` and the snapshot.
- Dev: `--floor random|full|<layout id>`; `tools/dev/tutorial_shot.gd --view floor --floor <id>`
  renders the floor from inside the lobby doors.
- Tests: `tests/unit/test_floor_plan.gd` (rotation, layouts, wire, geometry),
  `tests/integration/test_floor_plan_flow.gd` (through `ServerFixture`),
  `tests/physics/test_floor_plan_scene.gd` (every layout in the real scene: no overlaps, every
  chair reachable, patrol points and doors walkable), `tests/physics/test_scratch_kiosk.gd`.
- Not verified: real online play with several clients across a layout change; the area rugs stay
  where The Grand Hall puts them.
### 2026-10-17 / 0.9.11 (wheel and craps: closer table, overlay on the right)
- Patrick (screenshot of the wheel seat view): "rather zoom in on this ... craps the same, closer
  look at the table, and ui on the right (else you dont see anything)".
- Seat views: both tables now give every stool its own view (`StationBase._add_seat_camera`, eye +
  aim point, the player camera's `seated_look` head turn unchanged). Wheel: eye at (0.8, 2.8, 1.3)
  local, 0.08 × the stool's x along, looking down 26° at the wheel; the wheel face spans ~30% of the
  width (was 16%), wheel + layout ~50% of the width and over 80% of the height, dealer and chips in
  view, all in the left two thirds. Craps: eye at (1.0, 3.2, 1.35), 0.05 × the stool's x along, looking straight
  down the table at 39°; the felt spans 58–62% of the width (was 46%, centred under the old strip),
  stickman, sign and every seat's chips in view, all in the left two thirds.
- Overlays: `StationUi._dock_column` puts the panel in a 600 px column at the right edge, from under
  the HUD clock (y 196) to over the HUD rank (104 px from the bottom). Wheel: symbols in a 4-wide
  grid, chips, status, result / last spins, your bets. Craps: the four bets in a 2 × 2 grid, chips,
  your bets, SHOOT, the point, the shooter / last roll. The explanation moved into a folded
  HOW IT WORKS line (`_rules_text`, also its tooltip); key hints and shortcuts unchanged, the
  camera lock unchanged.
- Evidence: `tests/ui/test_wheel_ui.gd`, `tests/ui/test_craps_ui.gd` (panel in the right third,
  under 40% wide, every visible control right of 2/3 of the width, in several states and with the
  rules open), `tests/physics/test_wheel_table.gd`, `tests/physics/test_craps_table.gd` (per seat at
  the default 85° FOV: wheel rim / felt corners, dealer, chips projected into the left two thirds,
  screen extents, nothing solid between eye and bets). Dev shots `wheel_shot` / `craps_shot
  --view seat --seat n` draw the overlay too.

### 2026-10-16 / 0.9.10 (four new games, random floor, Patrick's second feedback burst)
- Released 2026-10-16. PROTOCOL_VERSION 8 (tipping gone from the wire, new station events, the
  floor plan in `match_started` / `regroup_started` / the snapshot, blackjack hands carry `clock`,
  emotes in the snapshot).
- New casino games, each with the house rule from 0.9.6 (a losing draw redone once with a small
  chance, then luck; never shown) and RTP 101–102%: Wheel of Fortune (`wheel_1`, 54 segments),
  Hi-Lo (`hilo_1` at (18.6, 0, −4.8), east of craps), craps with two thrown dice (`craps_1` at
  (14, 0, −6): Pass / Don't Pass / Field / Any Seven, the shooter throws, the client's dice tumble
  onto the server's faces) and scratch cards (`scratch_1` kiosk at (−19, 0, 10)). Registry entries
  7–10. Hot table, House Comp, stats and items work at all of them.
- Random casino floor (`core/match/floor_plan.gd`, `docs/FLOOR_PLAN.md`): every non-fixed station
  spot is redrawn from the match seed when the lobby opens, on Play Again and at every regroup;
  spots close at random (a rope and CLOSED TONIGHT sign, or a plant), nothing is guaranteed, soft
  cap of two per table game, at least 60% of the spots open. `FloorGeometry` checks each drawn
  floor against the real colliders and the navmesh (gap 0.35 m, every chair reachable). Practice
  keeps the full floor; minigames-only never draws. Seated players at a vanished table are stood
  up and refunded; the TONIGHT'S FLOOR board by the doors lists the draw. Tuning in
  `data/balance/floor_plan.tres`; `--floor random|full` for dev.
- Emotes: all ten are animated in 3D (`Emotes.SECONDS` 2.5; the bean's arms, lean, feet and face;
  skins act them out through their own clips or driven arm bones), with a front camera view.
- Settings: voice loudness slider (an amplifier for a loud or quiet mic), the microphone test
  clutter removed, the Controls tab in sections (movement, interaction, tables, minigames), more
  frame limits.
- Odd Jobs: a tutorial page, the aim box covers the whole cabinet front, no click rate limit
  (client or server; `IntentValidator.UNLIMITED`).
- Waiting room: the play-money note under the title is gone.
- Blackjack split: two real hands played in turn, the second hand's card dealt when play reaches
  it, a per-player decision clock with `bj_split_time_bonus`, a rim outline and HAND 1/2 marker on
  the hand in play.
- Bets over the balance go all-in (`core/economy/bet_clamp.gd`: `StationLogicBase.bet_limits`,
  `clamp_bet`, `with_all_in`; `bet_placed` carries `all_in` and `requested`), at every table.
- Dealer tipping removed entirely (Patrick: "that was a stupid idea from me"): no `tip_dealer`
  intent, no `dealer_tipped` event, no tip jar, no tip balance settings.
- Fixes on the way: `HotTableDirector` remembers its last pick after the table cools, so the same
  table is never hot twice in a row; the emote physics test no longer samples the pose during a
  blink and settles by frames rather than the clock; the net voice test counts the jitter
  buffer's deliberate drops (`late`, `overflowed`, `lost` now in Bob's voice summary line).
- Suite before release: lint ok; unit 815; sim 22; integration 242; physics 166; ui 270; smoke 4
  + boot; session; orchestrator 68; net 12. Not verified: real online play of the new games with
  several clients, the scratch feel with a real mouse, the new sounds by ear.
### 2026-10-16 / Wheel of Fortune (0.9.10)
- Patrick approved a Big Six money wheel as a new table: `wheel_1` on the casino floor east of the
  blackjack lounge (11, 0, 5), registered as game `wheel` (data/registry/games.tres, map stations,
  Hot Table candidate). 54 segments ($1 ×24, $2 ×15, $5 ×7, $10 ×4, $20 ×2, Joker, Logo), chips on
  any symbols at the layout, honest odds on the table (1:1 … 20:1, Joker/Logo 40:1), $10 min, $200
  per spin, 5 stools, a dealer beside the wheel (DealerLogic: shove/bat cancels and refunds, tip jar).
  Round: the countdown (12 s) starts with the first bet, the dealer spins (3 s), the server announces
  the segment (`wheel_result`) and every client slows the wheel onto it in 4.5 s (a cubic that keeps
  the spin's speed and stops exactly on time; the clicker flaps on every peg); the bets pay as it
  rests. House rule (0.9.6): a spin nobody would win is redrawn once with `wheel_favour` 0.31, then
  each bettor's luck rerolls it by what it pays them; never on the wire. RTP alone at the wheel
  98.8–104.9% by symbol, 101.3% over the seven (honest odds alone 76–89%), `tests/sim/test_wheel_rtp.gd`.
- New events `wheel_spin_started {station}`, `wheel_result {station, segment, symbol, seconds}`; bet
  shape `{symbol: 0..6, amount}`; public state adds `segment` (once it is told), `landing`, `history`.
  Tests: unit `test_wheel.gd`, sim `test_wheel_rtp.gd`, integration `test_wheel_flow.gd`, ui
  `test_wheel_ui.gd`, physics `test_wheel_table.gd` (the real casino: no overlaps, dealer, navmesh,
  sit and bet). Dev shot: `tools/dev/wheel_shot.tscn`.
### 2026-10-16 / scratch cards (0.9.10)
- Patrick approved a new casino game, scratch cards. A brass-and-wood kiosk with a card dispenser,
  a desk lamp, a "SCRATCH CARDS" board and an attendant bean, in the start room by the west wall
  (`scratch_1` at (-19, 0, 10), facing east); one player at a time like a slot machine.
- Server (`games/scratch/scratch_logic.gd`): buying a $10 / $25 / $50 card (× limits) draws the
  outcome from the tier's odds (blank, $, or three of a symbol on one line), redraws a blank once
  with `scratch_favour` 25% (house rule, never shown or sent), lets luck reroll the card, and builds
  a 3×3 card showing exactly that outcome (fillers never finish a second line). One `scratch_card`
  event carries it; `action reveal` pays the printed prize (Hot Table, items and Last Call multiply
  the winnings as everywhere). Walking away pays it, a minigame refunds it, it scratches itself
  after 60 s. Exact RTP with the house rule: 101.18% / 101.22% / 101.22% (hit 58% / 49% / 39%).
- Panel (`ui/stations/scratch_ui.gd`, `scratch_card_view.gd`): the card 500×750 in the middle of
  the screen with the tier's header, the prize table printed in dollars, foil scratched off with the
  mouse (coin-sized brush, flakes, `scratch` sound from `tools/audio/gen_sfx.py`), a cell pops once
  less than 45% of its foil is left, REVEAL ALL scratches the rest; the prize stamp shows only once
  the whole card is bare.
- Wire: new event `scratch_card {station, player, tier, price, serial, card}`, new station state
  `{game, player, card, tier, stake, serial, last}`, `place_bet {tier}` (or `{amount}`), `action
  reveal`. Protocol version unchanged.
- All-in (BetClamp): `ScratchLogic.clamp_bet` prices a `{tier}` bet, `bet_limits` spans the card
  prices, so a card the balance can't cover sells for the balance (if that covers the $10 card) and
  prints its prizes on that stake; `bet_placed` carries `all_in` / `requested`. The buy buttons say
  "$X ALL IN" then. Registered as games.tres entry 10 after wheel, Hi-Lo and craps.

### 2026-10-16 / Hi-Lo table (0.9.10)
- Patrick approved a new table: Hi-Lo (`games/hilo/`). Oval card table with burgundy felt, a dealer
  (DealerLogic; no tipping), 4 seats, one shared single deck, everyone plays
  their own hand: ante, a card up, HIGHER or LOWER (aces high, a tie loses), ride or cash out up a
  six-step ladder (pot capped at 50× the ante). The buttons show the true chance from the cards
  left and the pay, both locked by the server when the card goes up (`HiLoLogic.pay_for`: fair odds
  less an edge, ×2.00 on an 8 either way). House rule from 0.9.6: a losing card is redrawn once with
  `hilo_favour` 15%, then luck rerolls it; nothing of it is published. Measured RTP over 120k hands
  per strategy: likelier side 1.0154, random side 1.0206, long shot 1.0157 (expectations 1.014 to
  1.016); the printed pays alone return 0.93 to 0.97.
- On the casino floor at (18.6, 0, −4.8), east of the craps table (the spot asked for, (16, 0, 7), is
  the bar and its back bar). New events `hilo_dealt`, `hilo_call`, `hilo_reshuffle`; no new intents
  (`place_bet {amount}`, `action higher|lower|cash_out`).

### 2026-10-16 / 0.9.9 (Patrick's feedback burst)
- Voice: Patrick "Sound input works, but i do not hear myself". Playback now runs the generator at
  the sound card's mix rate and upsamples the 8 kHz voice itself (linear, phase kept between
  frames), the player is primed and restarted if it stops, the talk spurt is no longer cut between
  two packets (the choppiness heard on Linux), `clear()` no longer calls `clear_buffer()` on a live
  generator. TEST MICROPHONE says "Playback failed: <reason>" when the player is not playing, and
  the log carries driver, output device, rates, Voice/Master bus state, underruns and restarts.
  Reproduced on Linux at 44.1/48 kHz: 3.00 s of 440 Hz, no gaps. The Windows cause is still not
  proven; the next log from Patrick's PC settles it.
- Practice is a plain solo casino game again (no minigame selection).
- HUD: luck gauge centred over the item slots with the LUCK label above it.
- Horse race: gold outline on the horse you backed, a crown on the leader (moves only when the new
  leader is clearly ahead, winner keeps it), field spreads out (talent ±12%, surge/stumble/cruise
  streaks; first-to-last at the line 1.0 → 2.7 horse lengths over 200 seeds).
- Odd Jobs: a real 3D arcade button on the cabinet (aim at it and click or press E), no popup; one
  shared bar for the whole casino, each click adds that player's share, the click that fills it
  wins the $50; the cabinet glows and the button gets a warm outline when you are broke (below the
  House Comp line).
- Odd Jobs, round two (Patrick: "the red button click thing is too small", "no rate limit", "Add
  smash the button to the tutorial"): aiming counts anywhere on the cabinet's front
  (`OddJobsCabinet.AIM_BOX`, 1.1 m wide by 1.45 m: deck, bar riser, marquee; was 0.24 m around
  the cap) from up to 2 m around the stand spot, and the outline covers cap, dome and bezel. No rate
  limit: the client's 14/s cap and the cabinet's 12/s per player are gone and `IntentValidator`
  exempts `odd_jobs_press` from its 20/s limit; bar events stay throttled to 10/s. New tutorial page
  SMASH THE BUTTON after ITEMS (9 pages; picture `assets/tutorial/oddjobs.webp`, view `oddjobs`).
- Megaphone the right way round (bell forward, held in the fist; first person shows it in front of
  the camera); waiters hold the drinks tray on the palm (`AvatarVisuals.hold_right_arm`); dealers
  stand on the floor (`DealerLogic.OFFSETS` y 0.5 → 0).
- Tab list "THE TABLE": skin portraits in the player's colour, colour bar, rank and money, leader
  crown, HOST badge, talking icon, ready/waiting in the lobby; no READY button anywhere, only the
  pedestal readies you.
- Waiting room behind the start room's door: one blackjack table and four slot machines on play
  money (`FunRoom`: own StationManager and Economy, nothing reaches stats, comps, items or the real
  balance; $1,000 play chips per visit). Open only in an online lobby; at match start seated players
  stand, anyone inside is sent back to their spawn, the door shuts and MoveSanity closes the room.
- Find the Lady: cards clickable again. The stage lives inside the pixel view (SubViewport at 1/3),
  so clicks arrived in viewport pixels while the card rectangles were in canvas pixels; every click
  landed a third of the way to the top-left and missed. Mapped onto the canvas now; one test clicks
  through the real window and pixel view, one runs the minigame on the authoritative server.
- Roulette Sumo: wheel 0.55 → 1.4 rad/s over 25 s (was 0.25 → 1.2 over 60 s), outward pull 0.12 →
  0.5 (a still bean falls off in 2.85 s at the start, 0.55 s at full speed), round 60 s; no bats,
  no freeze, no knockdowns; E/shove/grab push the bean in front (4 m/s, about 1 m, 0.8 s cooldown).
- Dodge the Dice: two betting layouts stacked (25 rows, 65 m flat, 1.9× the way), round 150 s, a
  hazard every 0.5 → 0.2 s, 45% aimed, plus ball racks across the board (4–6 of 7 lanes, one gate
  always open).
- Jackpot Climb: three giant-chip tiers with checkpoint flags (8.5 / 16 / 21.5 m of 26 m), two lanes
  per tier (steady hops on one side, one or two wide gaps on the other, four wide gaps in total),
  falls return you to your last flag (server-decided, 1.5 s grace), 150 s round, a non-finisher's
  height never counts below their checkpoint. Chips redrawn: flush edge spots, bevelled rim, face
  rings, 0.12 m thick, core under the top face (the old inserts stuck out and every top was black).
- Tests: `scripts/test.sh all` → lint ok, unit 721/721, sim 9/9, integration 191/191, physics 126/126 (one
  Odd Jobs prompt-timing test made to wait for the aim after a miss on the slow runner), ui 236/236,
  smoke 4/4, boot ok, session ok (87 steps), orchestrator 68, net 12/12 (22 min).

### 2026-10-13 / 0.9.8 (voice chat)
- Patrick: "Why is the voicechat still not working? Test it somehow". Three real losses found and
  fixed with a test each: (1) Godot 4.7.2 `ENetMultiplayerPeer.create_server` passes the channel
  count as the incoming bandwidth, so clients throttled to 1/32 about 1 s after connecting (47% of
  a new player's voice frames lost for ~9 s) → `host.bandwidth_limit(0, 0)` in enet_transport;
  (2) ENet's throttle kept dropping unreliable packets for seconds after a client hitch →
  `throttle_configure(5000, 2, 0)` per peer; (3) `ClientMatchView.resync` made the match scene
  rebuild late joiners' avatars on every sit-down, dropping their voice playback → departed
  avatars removed deferred. Also: one-channel mics no longer halved, open-mic gate -45 dB, mic
  rate measured and corrected, own distance curve for voice, explicit generator mix rate.
  Proof: tests/integration/test_voice_tone_roundtrip (Goertzel on decoded frames), the net voice
  test with `--voice-dump` (Bob's WAV: 440 Hz at 0.365 of 0.366, 978 sent / 971 played), a manual
  PulseAudio run on Linux. Settings > Audio > TEST MICROPHONE (3 s record and playback through the
  real path, plain verdict) and a Voice status line; one log line per stage (see the 0.9.8 notes
  in the thread). Unverifiable here: WASAPI quirks (>2-channel mics, 24-bit), real Steam relay.

### 2026-10-13 / 0.9.7 (macOS build)
- Patrick: "How hard would it be to ship the game for mac too?" (has an Apple Developer account and a
  MacBook). GodotSteam 4.23.1 macOS universal dylibs in addons/godotsteam/osx, ETC2/ASTC import on,
  "macOS" export preset (universal .app in a zip, bundle id at.bulldogrealestate.betterAtGambling,
  microphone usage text, entitlements in tools/macos/entitlements.plist), release.yml exports it on
  ubuntu and tools/macos/package.sh signs with rcodesign 0.29.0: Developer ID + notarization when the
  six Apple secrets exist, ad-hoc otherwise (release notes then explain "Open Anyway"). Host mode paths
  (ready file, host_server.log) live under user://. First release 0.9.7 shipped ad-hoc signed; nothing
  was run on a real Mac yet.

### 2026-10-13 / 0.9.6 (horse race odds)
- Patrick: "Horse Race is always favoured to win for you (by a bit, like the other games, but dont
  show it), pays 1:4 (but bit better payout)". The server draws the race seed with a 30% chance to
  redraw once when no backed horse would win, then each bettor's luck rerolls the seed like a card
  or a wheel (`HorseRaceLogic._draw_seed`); clients only see the final seed. Payout 4.5x the stake
  while the table still says 1:4 (`horse_payout_ratio`, `horse_favour` in BalanceConfig).

### 2026-10-12 / 0.9.5 (tutorial, jail in the wall, horse race, later ideas)
- Tutorial: eight picture pages (real in-game renders in assets/tutorial, `tools/tutorial_pictures.sh`)
  with BACK/NEXT/DONE, opens the first time PRACTICE or PLAY ONLINE is pressed (`tutorial/seen` in
  settings), a "?" button next to the gear in the main menu and the pause menu reopens it.
- Map: the jail is an alcove cut into the east wall (bars flush with the wall, gate in the middle);
  ready pedestals get a warm spotlight from above instead of a material change; brass name plates
  behind the pedestals; Reception desk and wardrobe mirror gone; settings tablet by the host spawn
  (press E); finer marble floor with a brass border and the runner to the lobby doors.
- Race Hall: a new annex east of the casino, north of the jail beside the VIP lounge, through an
  arch with "THE BEAN DERBY" sign. Horse race table: 4 procedurally built horses with a gallop cycle,
  random names each round (48 in the pool), deterministic seeded race replayed on every client,
  1:4 payout, one horse per player per race, 6 seats.
- UI: "Party" is "Lobby" everywhere; clothes menu (T-shirt button) replaces the in-game skin picker;
  third-person camera during an emote; bat 1.35x bigger in hand; curtain polish (velvet sheen,
  pelmet, sway); minigame selector in the lobby settings (picture per game, host enables/disables,
  `minigame_pool` lobby setting); end screen closes table panels.

### 2026-10-11 / 0.9.4 (playtest batch 2)
- Vote Race: 3D game-show runway instead of the 2D strip. Bat orientation in hand fixed (model axis).
  Item-aim outline fixed (grew in model units). Minigames-only: no item card on results, no item slots.
  Bat Heist rework: LMB swing/throw/steal, RMB grab, click fast to steal, bigger vault. Find the Lady
  faster. Odd Jobs button-smash cabinet next to the Gift Shop ($50 per bar, harder with money, refused
  at $500+, server-owned).
- Suite caught before release: the Odd Jobs panel crashed on `player_joined` on every online server;
  a jail carry under lag was logged as an implausible move (now info within the server-move grace).
