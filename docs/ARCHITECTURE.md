# Architecture

Full spec: [`docs/MASTER_PROMPT.md`](MASTER_PROMPT.md) §3.5–§5.

## Layers (lower never references higher)
```
Presentation  scenes, UI, VFX, audio, camera, input          client only; renders state, sends intents
Net           NetSession, intents/events, state replication  RPCs, serialization, snapshots/deltas
Simulation    MatchServer + subsystems                        server only (dedicated or in-process)
Core logic    pure RefCounted classes in core/ and games/*/   deterministic given a seed, no Nodes/I/O
```

## Autoloads
| Name | Script | Status |
|---|---|---|
| `Log` | services/log.gd | M0 done: tagged levels, `error_count` for smoke tests |
| `Settings` | services/settings_manager.gd | M0 stub (ConfigFile load/save) |
| `SceneRouter` | services/scene_router.gd | parses cmdline; boots `--server`, `--connect`, `--join-code`/`--create-room`, practice; profile name/cosmetics; `--capture` |
| `Registry` | services/registry.gd | stub |
| `Net` | net/net_session.gd | M3: LOCAL (practice), CLIENT and SERVER sessions; owns `RoomHost` (server) and `OnlineService` (`Net.online`) |
| `SteamSvc` | services/steam_service_stub.gd | stub (M8); not `Steam`, see DECISIONS |
| `Audio` | audio/audio_director.gd | stub (M7) |

## Command line (after `--`, parsed by `core/boot/cmdline.gd`)
| Flags | Effect |
|---|---|
| `--smoke-test [--frames N \| --seconds S]` | run, then exit 1 if anything logged an error |
| `--practice`, `--autoplay [--autoplay-variant 1 \| --autoplay-script thrower\|victim]` | practice match / scripted local player |
| `--server --port P [--bots N --duration M --seed N --timescale X --min-players N --empty-timeout S]` | headless dedicated room server (dev mode trusts client names) |
| `… --room-id ID --room-code CODE --room-secret S --orchestrator URL --build B` | added by the orchestrator: verify join tokens, heartbeats, close when empty |
| `--connect host:port --name N [--uid U --color C --hat H --build B]` | join a server directly (dev/tests) |
| `--orchestrator URL --create-room \| --join-code CODE` | create/join a party through the orchestrator |
| `--net-latency MS --net-loss P [--net-seed N]` | wrap the client transport in `DelayedTransport` |
| `--quit-after-results`, `--quit-on-disconnect` | scripted clients exit instead of returning to the menu |
| `--capture out.png --capture-at S` | save a screenshot of whatever is on screen after S seconds |
| `--give-items a,b,c` | Practice only: every player starts with these items (tests, screenshots) |
| `--skip-to S [--timescale X]` | Practice only: fast-forward to casino time S at start (100 = first quiz of a 5-minute match; screenshots) |

## Netcode (M3)
* **Transport:** `ENetTransport` (4 channels, range-coder compression) behind `NetTransport`;
  `TransportFactory` wraps it in `DelayedTransport` for latency/loss tests. No `@rpc`: every packet is
  `[type, payload]` (`Wire`, `var_to_bytes` without objects, validated by `Serializer.is_wire_safe`).
* **Channels:** 0 events, intents, snapshots (reliable, ordered); 1 status, private data, pong,
  force-position (reliable); 2 `MOVE` up / `WORLD` down (unreliable, 20 Hz); 3 voice (later).
* **Handshake:** `HELLO {protocol, build, join_token, name, color, hat}` → `RoomHost` checks the
  version, verifies the token with the orchestrator (`/v1/internal/verify`), maps the uid to a player
  (reconnects keep their player) → `WELCOME {player, snapshot, private, server_time, room_code}` or
  `REJECT {code, message}`.
* **State:** events carry a global `seq`; the client mirror (`ClientMatchState`) skips old ones and
  requests a fresh snapshot on a gap. Events that arrive before the match scene exists are replayed
  from `Net.events_since_snapshot()`. Station public state comes from 4 Hz `STATUS` deltas (changed
  stations only); per-player private state (`PRIVATE`) only when its hash changes.
* **World:** `NetWorld.build()` packs players (state, pos, yaw, airborne, ragdoll pose), guards and
  moving props with `WorldCodec` (binary, ~30 B per standing player). Clients render remote bodies
  100 ms in the past through `InterpBuffer`s; props become kinematic followers.
* **Authority:** a standing player's own client moves its body (`MOVE`, checked by `MoveSanity`;
  implausible moves get `FORCE_POSITION`). While held, ragdolled, knocked out or thrown out the
  server owns the body (`MatchServer.set_server_owned`), simulates the real ragdoll and streams its
  pose; it hands the body back with `player_got_up {pos}` / `player_respawned {pos}`.
  Avatars have a `Drive`: INPUT (our player), SIM (bots, and everything in practice), PUPPET
  (network-driven).
* **Prediction:** grab and shove pose immediately on press; the server's event confirms it, an
  `intent_rejected` (or 0.6 s of silence) drops it.
* **Lobby:** `LobbyController` on the server: leader = longest-connected human, ready = own pad or
  the panel toggle, everyone ready and ≥ 2 participants → 3 s countdown → `start_match`.

## Match flow, minigames and rewards (M4)
* **Phases:** `PhaseMachine` (LOBBY → INTRO → CASINO ⇄ PRE_MINIGAME → MINIGAME → REWARDS → … →
  RESULTS). Casino time only advances in CASINO and PRE_MINIGAME, so quizzes land exactly on the
  `MatchSchedule` (5 min: 1:40 and 3:20). Last Call ×1.5 is the stations' global multiplier for the
  final 60 s.
* **Casino rules on the server:** `HotTableDirector` (a random station ×1.25 for 30 s every 45–60 s
  of casino time), House Comp in `MatchServer._check_comps` (once per segment, nothing in play),
  and "Table closing": `StationManager.closing_in` refuses a bet whose round (`round_seconds()`)
  would outlast the pre-minigame warning or the match.
* **Minigames:** a `MinigameDefinition` (`minigames/<id>/<id>.tres`, registered in
  `data/registry/minigames.tres`) names a pure-logic `MinigameLogicBase` (server) and a
  `MinigameStage` (client set at z = 400 with its own camera and UI layer). `MinigameDirector`
  picks one (weighted, no immediate repeat) and keeps the used-question set for the match. The
  logic gets `submit_*` intents, emits events, and exposes public and private state; the stage only
  reads events and snapshots and sends intents.
* **Casino Quiz:** `QuizLogic` (3 questions from `QuestionBank`, at most one `DynamicQuestions`
  template, server timing with half-RTT credit from `NetSession.half_rtt_of`, capped at 250 ms),
  `QuizStage` (podiums, big screen, 2×2 answers on keys 1–4 / A B X Y / mouse). The correct index
  leaves the server only in `quiz_reveal`.
* **Rewards:** `RewardDirector` pays placement cash (× the played segment's limits, ×2 with items
  off) and runs the private item draft (offers only in `PRIVATE`, default = first option, bots
  pick at once). Items are data-only until M5.
* **Results and play again:** `match_ended {standings, awards, return_in}`; `ResultsStage` (z = −400)
  shows the podium, `Awards` and the buttons. In a room the leader's `return_to_lobby` (or the
  60 s timer) resets money, items and stats and rebuilds the match systems; clients take a fresh
  snapshot on `match_reset`.

## Items, luck and sabotage (M5)
* **Server:** `ItemSystem` (server/items/) owns inventories (3 slots, discard choice), activation
  (`use` → cooldown, incapacitated, target resolution, protections, Mirror then Bodyguard), banana
  peels and the private item state. Effects are `ItemEffect` scripts named by each
  `ItemDefinition` (`items/<id>/<id>.tres`, `effect_script` + `params`); most are
  `ModifierItemEffect`, which pushes a `Modifier` onto the `ModifierStack` the games already read
  (luck, payout multiplier, refund, `peek_dealer`, `spring_glove`, `bodyguard`, `mirror`).
* **Wire:** events `item_used {player, item, target, result: applied|blocked|reflected, …}`,
  `inventory_changed`, `discard_needed`, `item_discarded`, `effect_ended`, `bodyguard_saved`,
  `banana_placed`/`banana_slip`/`banana_removed`. Snapshot `effects` (ids per player) and
  `peels`; private `items {luck, effects[{item, left, uses}], discard?}`.
* **Client:** `ItemController` (client/) sends `use_item`/`discard_item`, runs the target picker
  (wheel/shoulders cycle, same key or E confirms, 4 s), the range ring and target marker;
  `ItemBar` (ui/hud/) shows slots, the luck meter, effect timers and the discard choice;
  `MatchScene` shows banners, callouts, effect tags over heads and banana peel meshes.

## Audio buses
Master → Music, SFX, UI, Ambience, Voice (`audio/default_bus_layout.tres`).

## Events and RPCs
To be listed here as they are implemented (M1 `GameEvents`, M3 protocol).
