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

## Audio buses
Master → Music, SFX, UI, Ambience, Voice (`audio/default_bus_layout.tres`).

## Events and RPCs
To be listed here as they are implemented (M1 `GameEvents`, M3 protocol).
