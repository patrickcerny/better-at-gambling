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
| `SceneRouter` | services/scene_router.gd | M0: parses cmdline, `--smoke-test` |
| `Registry` | services/registry.gd | stub |
| `Net` | net/net_session.gd | stub (M3) |
| `SteamSvc` | services/steam_service_stub.gd | stub (M8); not `Steam`, see DECISIONS |
| `Audio` | audio/audio_director.gd | stub (M7) |

## Command line (after `--`, parsed by `core/boot/cmdline.gd`)
`--smoke-test [--frames N]` (implemented), and planned: `--server --port N --bots N --duration M
--timescale X --seed N --autostart`, `--connect ip:port --name X --autoplay`, `--sim-match`, debug
flags from §8.

## Audio buses
Master → Music, SFX, UI, Ambience, Voice (`audio/default_bus_layout.tres`).

## Events and RPCs
To be listed here as they are implemented (M1 `GameEvents`, M3 protocol).
