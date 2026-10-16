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
  - Pixel look (Patrick: "the pixelated effect Yap Yap has"): `client/pixel_view.gd` renders the 3D world (casino, quiz set, podium, menu panorama) in a nearest-upscaled sub viewport at 1/2, 1/3 or 1/4 of the window's pixels; all 2D stays sharp. Now fixed at 1/3 for everyone (Patrick: "pixel look cannot be set"); old saved choices are dropped, `Settings.set_pixel_override` is for dev tools only. Never built on the dedicated server. `tests/ui/test_pixel_view.gd`, `tests/smoke/test_pixel_scenes.gd`; screenshots `screenshots/polish1/pixel/`. Not verified by a human eye on a real GPU (xvfb only); 3D audio relies on the sub viewport's listener flag.

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
### 2026-10-16 / next build (Wheel of Fortune)
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
### 2026-10-16 / scratch cards (after 0.9.9, not released)
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

### 2026-10-16 / Hi-Lo table (after 0.9.9, not released)
- Patrick approved a new table: Hi-Lo (`games/hilo/`). Oval card table with burgundy felt, a dealer
  (DealerLogic; no tipping), 4 seats, one shared single deck, everyone plays
  their own hand: ante, a card up, HIGHER or LOWER (aces high, a tie loses), ride or cash out up a
  six-step ladder (pot capped at 50× the ante). The buttons show the true chance from the cards
  left and the pay, both locked by the server when the card goes up (`HiLoLogic.pay_for`: fair odds
  less an edge, ×2.00 on an 8 either way). House rule from 0.9.6: a losing card is redrawn once with
  `hilo_favour` 15%, then luck rerolls it; nothing of it is published. Measured RTP over 120k hands
  per strategy: likelier side 1.0154, random side 1.0206, long shot 1.0157 (expectations 1.014 to
  1.016); the printed pays alone return 0.93 to 0.97.
- On the casino floor at (16, 0, −5), east of the roulette pit (the spot asked for, (16, 0, 7), is
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
