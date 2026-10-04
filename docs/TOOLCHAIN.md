# Toolchain

Installed by `tools/setup_toolchain.sh` (idempotent, verifies SHA-512).

| Component | Version | Source | Checksum (SHA-512) |
|---|---|---|---|
| Godot (Linux x86_64, standard) | 4.7.2-stable (`4.7.2.stable.official.ed1daf0bf`) | github.com/godotengine/godot/releases/tag/4.7.2-stable | `9aa00f7a…ed54c65` (`Godot_v4.7.2-stable_linux.x86_64.zip`) |
| Export templates | 4.7.2-stable | same release, `Godot_v4.7.2-stable_export_templates.tpz` | `ca4d71c4…cb84079` |
| GUT | 9.7.1 (tag `v9.7.1`) | github.com/bitwes/Gut | vendored in `addons/gut/` |
| GodotSteam | not installed yet (M8) | github.com/GodotSteam/GodotSteam | — |
| Python | 3.11 in the dev container (orchestrator targets 3.12 in Docker) | system | — |

Locations:
- Godot binary: `tools/godot/godot` (gitignored). Override with `GODOT=/path/to/godot`.
- Export templates: `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Xvfb (`xvfb-run`) is available in the dev container; `scripts/screenshot.sh` renders with the
  Compatibility renderer (OpenGL via Mesa llvmpipe) and works.

Verified at M0 (2026-10-04): headless `--version`, GUT run, Linux/Windows/Linux-server exports, the
exported Linux binary booting with `--smoke-test`, and a 1920×1080 screenshot under Xvfb.
