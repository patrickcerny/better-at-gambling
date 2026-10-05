# TODO

Generated from §13 of the master implementation prompt at M0. Tick items only when implemented AND tested.

## M0 — Toolchain & skeleton

### Tasks
- [x] create project folder `better-at-gambling/`
- [x] `git init`
- [x] `.gitignore` (`.godot/`, `build/`, `tools/godot*`, `*.import` caches as appropriate)
- [x] `tools/setup_toolchain.sh`
- [x] install Godot + export templates + GUT (or mini runner)
- [x] `project.godot` (name, version 0.1.0, window 1920×1080 stretch mode `canvas_items`/aspect `expand`, input map for all actions in §2.4/§2.8/§2.14 with keyboard+joypad, audio bus layout, autoload stubs)
- [x] folder structure (§5)
- [x] `docs/` files (copy §13 task list into `TODO.md`; create `PROGRESS.md`, `DECISIONS.md`, `TOOLCHAIN.md`, `GDD.md` summary, `ARCHITECTURE.md`)
- [x] `scripts/*.sh`
- [x] `core/boot/cmdline.gd`
- [x] `Log` autoload
- [x] empty main menu scene that boots

### Tests
- [x] one trivial passing test and one deliberately failing test (confirm the runner exits non-zero, then delete the failing test)
- [x] smoke test that boots main scene headless for 60 frames

### Acceptance criteria
- [x] `scripts/test.sh` runs headless and passes
- [x] `godot --headless --path . -- --smoke-test` exits 0
- [x] `TODO.md` contains all milestone tasks
- [x] first commit made

## M1 — Core logic library (no visuals)

### Tasks
- [x] `SeededRng`
- [x] `LuckRng` (reroll mechanics)
- [x] `Card/Shoe/HandEval`
- [x] `BlackjackLogic` (state machine: idle → betting → dealing → acting → dealer → payout; simultaneous player actions; timeouts; auto-resolve)
- [x] `RouletteLogic` (bet validation, all MVP bet types, payout + generosity bonus, luck neighbor/jinx rules)
- [x] `SlotsLogic` (weighted reels, wild, paytable, luck reroll)
- [x] `PlinkoLogic` (risk rows, weighted slot outcome, luck reroll) + `ProgressiveJackpot`
- [x] `InteractionRules` (pure rules for shove/knockout counting, immunities, shake amounts and caps, guard-sight decision given positions)
- [x] `StationLogicBase` interface
- [x] `Economy` + ledger
- [x] `ModifierStack`
- [x] `BalanceConfig` + `balance.tres`
- [x] `MatchSchedule` (durations → segment times, Last Call)
- [x] `MatchState/PlayerState`
- [x] `GameEvents` factory
- [x] `Serializer` + protocol constants
- [x] `QuizScoring`
- [x] `LootTables`

### Tests
- [x] unit tests for every class: blackjack totals (soft/hard aces, blackjack vs 21, dealer S17, double, bust), shoe reshuffle at penetration, simultaneous actions & timeout auto-stand
- [x] roulette color/dozen/column mapping for all 37 numbers, payouts per bet type, limits
- [x] slots paytable incl. wild substitution and cherry rules
- [x] Plinko multipliers/weights per risk row and jackpot feed/accounting
- [x] interaction rules (3 shoves in 4 s → knockout, immunity windows, shake cap 8% / $400 × multiplier, same-attacker 20 s limit, seated players immune)
- [x] luck reroll: L=0 never rerolls, L>0 never yields worse quality than the first draw, probability ≈ 0.12·L (statistical)
- [x] economy cannot go negative, every change has a reason
- [x] schedule table from §2.1 exactly
- [x] serializer round-trip for MatchState
- [x] quiz scoring boundaries (0 s → 1000, 12 s → 500, wrong → 0, ties). **Sim tests:** RTP within 100.5–102% at L=0 for each game (tune constants until true), monotonic RTP over L∈[−3,3]

### Acceptance criteria
- [x] all tests green
- [x] RTP table recorded in `DECISIONS.md` with final tuned constants
- [x] no Node references in `core/` (enforce with a grep test)

## M2 — Local playable sandbox (single player, in-process server)

### Tasks
- [x] `MatchServer` + `PhaseMachine` (casino-only for now)
- [x] `StationManager`
- [x] in-process local session (host = local player, no network peer yet, but go through the same intent/event API)
- [x] greybox Lucky Lounge (layout §2.3, navmesh, spawn points, all MVP stations placed via `MapDefinition`)
- [x] wobbly bean avatar (walk/sprint/jump, procedural wobble, dot eyes; mouth is driven by `AvatarVisuals.mouth_open`, voice hookup in M8)
- [x] 5-body ragdoll + get-up
- [x] **grab/shove/throw/knockout/shake** against dummy bean bots via server-side `InteractionResolver`
- [x] props (stools, chip piles) on Jolt physics
- [x] fountain hazard
- [x] revolving door
- [x] 2 security guards with patrol + sight cone + throw-out
- [x] VIP mezzanine with bouncer check and railing
- [x] first-person camera + third-person toggle + auto third-person when ragdolled
- [x] emote wheel
- [x] Plinko station with server-steered chip and recorded path playback
- [x] interaction prompts
- [x] sit/leave
- [x] station scenes with placeholder visuals
- [x] **betting UI component**
- [x] Blackjack/Roulette/Slots UIs wired to logic through intents/events
- [x] HUD (money, timer, event feed)
- [x] money popups
- [x] basic SFX hookup with generated placeholders (run `tools/gen_audio.py`)
- [ ] toon shader (file exists in `vfx/shaders/toon.gdshader`; applying it to beans/props is M7 polish per ART_DIRECTION "keep shaders simple")
- [x] main menu → "Practice" → casino

### Tests
- [x] scene smoke tests for all new scenes
- [x] physics integration tests (shove ×3 → knockout; throw into fountain → slow; shake drops exactly the capped amount and chip piles sum to it; seated player immune; guard throws out an attacker in sight but not one out of sight; Plinko chip lands in the server-chosen slot in 1,000 seeded drops)
- [x] integration test: scripted local player intents sit at each station type, places bets, plays rounds
- [x] money in HUD matches server state
- [x] leave mid-round auto-resolves correctly
- [x] UI navigation test with keyboard and joypad events on bet panel

### Acceptance criteria
- [x] you can launch the game, walk around, grab/shove/throw dummy beans and shake chips out of them, get thrown out by a guard, and play all four games with correct payouts using mouse/keyboard and gamepad (verified by automated UI tests + screenshots)
- [x] no errors in log during a scripted 3-minute session

## M3 — Networking, dedicated server & lobby

### Tasks
- [x] `Dedicated Server` export preset and `--server` boot path
- [x] **Room Orchestrator** (§4.0) with `AUTH_MODE=dev`
- [x] port pool
- [x] spawn/heartbeat/reap
- [x] room codes
- [x] join tokens and `/internal/verify`
- [x] client `OnlineService` (create party, join by code, rejoin); the room side is `RoomHost` (server) + `Net` (client)
- [x] `NetSession`
- [x] `TransportFactory`
- [x] ENet transport
- [x] handshake/versioning
- [x] `NetIntents` & `NetEvents`
- [x] `IntentValidator` + `RateLimiter`
- [x] `ClientMatchView`/`ClientMatchState`
- [x] snapshot + delta with seq/gap recovery
- [x] `NetClock`
- [x] player avatar replication with interpolation and server sanity checks
- [x] **physical entrance-hall lobby** (ready pads, wardrobe mirror, host settings board) plus the mirrored 2D lobby panel (slots, colors, hats, ready, host settings, bot slots placeholder)
- [x] physics/ragdoll replication with **authority handoff** (client-owned while standing, server-owned while ragdolled/grabbed/thrown) and prop sync
- [x] client-side prediction of grab/shove animations with server confirm/deny
- [x] host/join by IP menus
- [x] connection error UI
- [x] `DelayedTransport` for tests (the `DelayedPeer` of the spec)
- [x] command-line `--server/--connect/--autoplay`

### Tests
- [x] orchestrator **pytest** suite (room create/join/full/closed, port allocation and release, heartbeat timeout reaping, empty-room shutdown, one-room-per-owner, rate limits, version mismatch, dev auth refused when `ENV=production`, join token single-use)
- [x] end-to-end local test: start orchestrator → create room via API → orchestrator spawns a headless server → 2 autoplay clients join by room code → match runs → room shuts down when empty and the port is freed
- [x] serializer/protocol tests
- [x] validator tests (bet over money, wrong phase, not seated, foreign station, spam > 20/s)
- [x] multi-process integration: headless server + 2 headless autoplay clients play 3 minutes of casino
- [x] assert client mirrors equal server (state hash) at end
- [x] version-mismatch rejection
- [x] networked physics test (client A grabs and throws client B; both clients and server agree on B's final position within 0.3 m and on the knockout event; authority returns to B after get-up)
- [x] latency test 150 ms/2% loss (including a shove exchange)
- [x] bandwidth measured < 30 KB/s/client

### Acceptance criteria
- [x] with the orchestrator running locally, one client creates a party, a second client joins by room code (`tests/net/test_orchestrator_e2e.py`)
- [x] both ready up, enter the casino, see each other move and wobble, shove and throw each other, play at the same roulette/blackjack table and Plinko board together, and money stays consistent (`tests/net/test_net_match.py`: shared blackjack_3/roulette_1/plinko_1, identical balance digests on server and both clients)
- [x] all tests green

## M4 — Match flow, timer, Quiz minigame, rewards (cash only for now)

### Tasks
- [x] full `PhaseMachine` (intro, casino segments, pre-minigame warning, minigame, rewards, Last Call, results)
- [x] match timer & HUD countdowns
- [x] durations from lobby
- [x] `MinigameDirector` + `MinigameBase`
- [x] quiz stage scene
- [x] `QuizMinigame` (question flow, server timing with RTT compensation, reveal, scoreboard, ranking with tiebreaks)
- [x] `questions_en.json` with ≥ 60 questions (aim 150 by M10) + JSON schema validation
- [x] 2 dynamic question templates
- [x] reward phase with cash prizes (item draft UI built but items stubbed)
- [x] Hot Table director
- [x] bankruptcy comp
- [x] results screen (podium, final money, rematch/leave)
- [x] auto-resolve all stations at phase end

### Tests
- [x] schedule integration (5-minute match at timescale → exactly 2 quizzes at 1:40/3:20 casino time; 30-minute → 7)
- [x] each quiz exactly 3 questions, no repeats within a match
- [x] correct index never present in any client-bound event before reveal (assert on serialized traffic)
- [x] scoring with simulated latencies
- [x] ties
- [x] question JSON validation (4 answers, valid index, unique ids, non-empty)
- [x] Last Call multiplier applied only in final 60 s
- [x] comp rules
- [x] results tiebreakers

### Acceptance criteria
- [x] full multi-process match (server + 2 autoplay clients + 2 bots stubs or scripted players) completes from lobby to results for 5-minute duration
- [x] quiz playable with keyboard/mouse/gamepad
- [x] screenshots of quiz and results look correct

## M5 — Items, luck, sabotage, pickups

### Tasks
- [x] `ItemSystem`
- [x] inventory (3 slots, discard flow)
- [x] `ItemDefinition`/`ItemEffect` for the 11 MVP items (incl. Spring Glove's physical effect and Bouncer NPC hook-up when Bouncer lands in M10)
- [x] targeting UI (picker + proximity indicator ring)
- [x] activation banners/VFX/SFX placeholders
- [x] luck HUD meter
- [x] effect timers HUD
- [x] protections (Bodyguard/Mirror/spawn protection/away protection)
- [x] negative-item grace window
- [x] cooldowns
- [x] `PickupSystem` (dropped chips, banana peel slip)
- [x] reward draft with real items + loot tables + Underdog rule
- [x] game-specific luck hooks
- [x] peek dealer card for Hot Hands (private event to that player only)

### Tests
- [x] unit test per item (activate, effect, expiry, interaction with Bodyguard and Mirror, edge cases: target broke, target away, target protected, self-target invalid, out of range)
- [x] Pickpocket min/max/never-negative
- [x] Double Trouble × Last Call × Hot Table stacking order
- [x] Golden Chip refund exactness
- [x] banana drop amount & pickup conservation (money dropped = money picked up + despawned, despawned money is logged as `pickup_expired`)
- [x] draft offers follow loot weights (statistical)
- [x] Underdog only with ≥ 3 players
- [x] integration: bots/autoplay use items during a full match without errors

### Acceptance criteria
- [x] every MVP item is usable in a networked match with visible feedback for all players
- [x] money conservation test passes with items enabled
- [x] all tests green

## Later (Patrick's ideas, not scheduled)
- [ ] Jail when caught by security: growing timeout (8 s / 15 s / 25 s) and a Get Out of Jail Free item that also resets the caught counter (details in docs/ITEM_IDEAS.md). Patrick, 2026-10-05: not now, keep as a todo.

## M6 — Bots, reconnects, MVP hardening → **MVP COMPLETE**

> **Patrick, 2026-10-05 19:23 UTC: "this game does not need bots, just remove them entirely. Rather think about other stuff."**
> M6 drops every bot task below (BotDirector/BotBrain, lobby bot slots, bot quiz answers/item use/physical behaviour, bot test criteria) and removes bots from the game: lobby bot slots, Practice-with-bots, server bot logic (duels, rewards, items). Scripted test players for the automated tests stay, as test tooling only. Do this when Patrick starts M6.

### Tasks
- [x] **VPS deployment** (§4.0, done early on 2026-10-05; see deploy/README.md): `deploy/` Dockerfile + compose + Caddyfile + firewall script + `deploy.sh`/`status.sh`
- [ ] if the owner has provided SSH access
- [x] deploy to the VPS (dev auth mode, or production mode only once a Steam App ID and Web API key exist) and run the internet test below
- [ ] if not
- [x] run the same stack locally in Docker and log VPS deployment as waiting on the owner
- [ ] `BotDirector`/`BotBrain` with personalities and difficulties (§2.19)
- [ ] lobby bot slots
- [ ] bot quiz answers
- [ ] bot item use
- [ ] bot physical behavior (§2.19)
- [ ] **proximity voice**: `VoiceChannel`
- [ ] `VoiceCapture` (mic bus + `AudioEffectCapture`)
- [ ] μ-law `VoiceCodec`
- [ ] server relay with distance filtering
- [ ] `VoicePlayback` (3D `AudioStreamPlayer3D` + `AudioStreamGenerator` + jitter buffer)
- [ ] global-voice exceptions (quiz, rewards, results, same table)
- [ ] push-to-talk/open-mic
- [ ] per-player mute
- [ ] mouth-flap from decoded RMS
- [ ] talking indicator
- [ ] disconnect → away state
- [ ] reconnect by `player_uid` with snapshot
- [ ] host-left flow
- [ ] pause menu (Resume/Leave/basic settings: volumes, fullscreen)
- [ ] contextual hints
- [ ] loading tips
- [ ] fix all known bugs
- [ ] basic settings persistence

### Tests
- [ ] internet test: 2–4 headless autoplay clients connect to the deployed VPS orchestrator, create/join a room by code and finish a 5-minute match with zero errors (or the same against the local Docker stack if no VPS access)
- [ ] load test filling rooms until CPU 70%, record rooms-per-VPS
- [ ] deploy rollback works (deploy a broken build on purpose in a staging port range, confirm the health check rolls back)
- [ ] 50 headless bot-only matches (mixed durations, seeds 1–50, timescale) with zero errors and money conservation
- [ ] multi-process reconnect test
- [ ] host-left test
- [ ] voice tests: μ-law encode/decode round trip within error bound, jitter buffer reorder/loss handling, proximity filter (speaker at 25 m not relayed, at 3 m relayed, global during quiz), mouth openness rises with a fed sine tone and returns to closed in silence, voice bandwidth per speaker under cap (use a WAV file fed into the capture path instead of a real microphone in headless tests)
- [ ] bots take part in shoves/knockouts/chip pickups in ≥ 80% of matches
- [ ] bots visit all four game types in ≥ 90% of matches
- [ ] average bot decision cost < 0.2 ms

### Acceptance criteria
- [ ] all MVP criteria in §6 verified and listed with evidence (test names, screenshot paths) in `PROGRESS.md`. Tag the commit `v0.1.0-mvp`. Produce a Linux and Windows debug export that launches (smoke test the Linux one)

## M7 — Polish: UI/UX, audio, VFX, animation, feel

### Tasks
- [ ] full theme pass
- [ ] animated money counters
- [ ] card dealing/chip sliding/roulette ball/slot reel animations
- [ ] win/lose/jackpot VFX and hit-stop
- [ ] character squash/stretch
- [ ] slip
- [ ] cheer
- [ ] sad animations
- [ ] face reactions (eyes widen on wins, droop on losses)
- [ ] better ragdoll flail and get-up
- [ ] knockout birdies
- [ ] guard carry-and-toss animation
- [ ] fountain splash VFX
- [ ] waiter NPC who trips and spills puddles
- [ ] Megaphone prop
- [ ] crown on leader
- [ ] Hot Table spotlight/fire
- [ ] Last Call lighting & music
- [ ] quiz show juice (host cat reactions, confetti)
- [ ] results podium animations + fun awards + money-over-time graph
- [ ] music crossfades
- [ ] all SFX hooked
- [ ] emotes wheel
- [ ] blackjack **split**
- [ ] input glyph switching (keyboard ↔ gamepad)
- [ ] improved placeholder art (better procedural props, lighting, glow)

### Tests
- [ ] smoke tests for all scenes
- [ ] split logic unit tests
- [ ] awards computation tests
- [ ] no FPS regression in a scripted benchmark scene (record FPS in PROGRESS.md if a renderer is available)

### Acceptance criteria
- [ ] screenshots of every screen show a cohesive, readable, polished look
- [ ] game feel checklist in `docs/GDD.md` ticked (every action has visual + audio feedback)

## M8 — Steam integration (invites must work end to end)

### Tasks
- [ ] GodotSteam install
- [ ] `SteamService` (+ stub fallback)
- [ ] Steam lobby ↔ VPS room flow exactly as §4.0.1 (create party = room + Steam lobby, lobby data, invite button, overlay invites, `join_requested`, `+connect_lobby`/`+join_room` launch args, rich presence `connect` + `steam_player_group`, leader handoff, reconnect)
- [ ] Web API auth tickets for every orchestrator call and orchestrator-side `AuthenticateUserTicket` validation (`AUTH_MODE=steam`)
- [ ] production config on the VPS with domain + TLS
- [ ] **Steam Voice codec** behind `VoiceCodec` (fall back to μ-law when Steam is unavailable)
- [ ] friends-only default lobby and in-game "Invite friends" button
- [ ] rich presence
- [ ] overlay invites
- [ ] "Join Game" handling (`+connect_lobby` launch arg + `join_requested` signal)
- [ ] achievements & stats (`AchievementService` fed by `StatsTracker`)
- [ ] Steam Cloud paths documented
- [ ] offline/"Steam not running" fallback

### Tests
- [ ] unit tests with the stub (achievement unlock conditions from event streams, lobby data encode/decode, launch-arg parsing, invite → join flow state machine)
- [ ] orchestrator tests with the Steam Web API mocked (valid ticket, invalid ticket, wrong app id, Steam API timeout → clear error)
- [ ] **two-account Steam test script** `docs/STEAM_INVITE_TEST.md` (account A creates party, invites B via button and via overlay, B accepts while the game is closed and while it is running, "Join Game" from profile, A leaves and B stays, B disconnects and rejoins) — run it yourself if two Steam accounts/clients are available, otherwise hand it to the owner and record the result they report
- [ ] app runs headless with Steam unavailable without errors
- [ ] if a Steam client is available, run two-account manual test (otherwise mark in RELEASE_CHECKLIST as manual)

### Acceptance criteria
- [ ] builds work with and without Steam
- [ ] Steam code paths are exercised by stub tests
- [ ] against the production VPS with the owner's real App ID, the two-account invite test passes (verified by you or reported by the owner, and recorded as such). Until the owner's App ID and Web API key exist, M8 stays "IMPLEMENTED, waiting on owner" rather than done

## M9 — Onboarding, settings, accessibility, balancing

### Tasks
- [ ] interactive tutorial (§2.13)
- [ ] full settings menu (§2.17) with persistence and rebinding
- [ ] colorblind/reduce-motion/text-size options
- [ ] localization CSV with all strings via `tr()`
- [ ] credits screen
- [ ] balancing via `scripts/sim_match.sh` × 500 bot matches → `tools/check_balance.py` report vs targets in §2.21
- [ ] tune `balance.tres`
- [ ] record results

### Tests
- [ ] settings save/load round-trip
- [ ] rebinding persistence
- [ ] tutorial completes via scripted input
- [ ] no untranslated user-facing string literals (grep test)
- [ ] balance report meets targets

### Acceptance criteria
- [ ] a new player can learn the game from the tutorial alone (scripted run passes)
- [ ] balance targets met (or deviations justified in DECISIONS.md)

## M10 — Content expansion (extensibility proof)

### Tasks
- [ ] add **Big Wheel**
- [ ] **Hi-Lo** and **Duck Derby** using only `ADDING_CONTENT.md` steps
- [ ] add items robin_hood
- [ ] jackpot_magnet
- [ ] bouncer
- [ ] wild_card
- [ ] grease
- [ ] bribe
- [ ] **Loan Shark co-op mode** (§2.24) touching only `modes/loan_shark/` + registries
- [ ] **cosmetic unlocks** with Casino Tokens (§2.23: fixed prices, no randomness, wardrobe mirror UI)
- [ ] quiz bank to ≥ 150 questions + 2 more dynamic templates
- [ ] 2 more fun awards

### Tests
- [ ] same per-game/per-item test sets as M1/M5
- [ ] RTP sims for new games
- [ ] Loan Shark: quota progression, shared-account economy conservation, run ends on missed quota
- [ ] cosmetics: token earn/spend persistence, no purchasable or random path exists (grep test for any store/IAP API usage)
- [ ] registry tests (every registered entry loads and passes interface checks)

### Acceptance criteria
- [ ] new content works in full matches
- [ ] `ADDING_CONTENT.md` updated with anything you had to do that wasn't documented (then fix the architecture so it isn't needed)

## M11 — Release candidate

### Tasks
- [ ] export presets finalized (including the dedicated server)
- [ ] `scripts/export.sh all`
- [ ] release server deployed to the VPS with production auth
- [ ] smoke-test exports
- [ ] app icons
- [ ] placeholder store assets
- [ ] `RELEASE_CHECKLIST.md`
- [ ] `STORE_PAGE.md`
- [ ] Steamworks VDF templates
- [ ] achievements json
- [ ] final full test run
- [ ] README with build/run/test instructions
- [ ] version `1.0.0-rc1`

### Tests
- [ ] full `scripts/test.sh all`
- [ ] 100 bot matches error-free
- [ ] exported Linux build smoke test
- [ ] exported client builds connect to the production VPS (room code, autoplay) and complete a match
- [ ] orchestrator health check green after deploy

### Acceptance criteria
- [ ] release builds for Windows/Linux (macOS exported) exist in `build/`
- [ ] every manual-only item listed clearly
- [ ] PROGRESS.md states exactly what was verified and what still requires a human (Steam partner setup, Web API key, domain DNS, real art/audio replacement, multi-machine and Steam client testing, macOS signing)

## Deferred

- (none yet)

## Bugs

### Patrick's playtest, 2026-10-05 19:01 UTC (next fix round, wait for his word)
- [x] Party host leaves: nobody is host anymore. Hand host to another player in the room. (Leaving now frees the slot on the server at once instead of waiting for ENet's timeout, so leadership moves immediately; `test_leader_handoff.gd`.)
- [x] Empty room (everyone left): shut it down right away. (5 s after the last player leaves, `RoomHost.LEFT_EMPTY_CLOSE`.)
- [x] Roulette bet display is one spot off, so it's unclear where the bet sits. (Badge was anchored before layout; now centred on its own spot.)
- [x] Text overlaps on many screens. (Station panels sit above the item bar, HUD labels outlined, quiz question no longer printed twice, quiz answer dots cleared at the end.)
- [x] Plinko: the UI covers the board, so you can't see where the chip drops in. (Panel docked at the right edge.)
- [x] Sounds are still bad. (Recorded CC0 Kenney sounds for footsteps, chips, cards, hits, UI; generated placeholders remain for splash, whistle, jackpot, big win.)
- [x] Gift Shop doesn't work in his game. (Online clients overwrote the stock with their stale join snapshot every refresh, so the kiosk never offered anything.)
