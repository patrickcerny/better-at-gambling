# Toolchain

Installed by `tools/setup_toolchain.sh` (idempotent, verifies SHA-512).

| Component | Version | Source | Checksum (SHA-512) |
|---|---|---|---|
| Godot (Linux x86_64, standard) | 4.7.2-stable (`4.7.2.stable.official.ed1daf0bf`) | github.com/godotengine/godot/releases/tag/4.7.2-stable | `9aa00f7a…ed54c65` (`Godot_v4.7.2-stable_linux.x86_64.zip`) |
| Export templates | 4.7.2-stable | same release, `Godot_v4.7.2-stable_export_templates.tpz` | `ca4d71c4…cb84079` |
| GUT | 9.7.1 (tag `v9.7.1`) | github.com/bitwes/Gut | vendored in `addons/gut/` |
| GodotSteam (GDExtension) | 4.23.1, Steamworks SDK 1.65 (win64, linux64, osx universal) | codeberg.org/godotsteam/godotsteam/releases/tag/v4.23.1 | vendored in `addons/godotsteam/` |
| rcodesign (CI only) | apple-codesign 0.29.0 | github.com/indygreg/apple-platform-rs | SHA-256 `dbe85ced…0600002`, pinned in `release.yml` |
| Python | 3.11 in the dev container (orchestrator targets 3.12 in Docker) | system | — |

Locations:
- Godot binary: `tools/godot/godot` (gitignored). Override with `GODOT=/path/to/godot`.
- Export templates: `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Xvfb (`xvfb-run`) is available in the dev container; `scripts/screenshot.sh` renders with the
  Compatibility renderer (OpenGL via Mesa llvmpipe) and works.

Verified at M0 (2026-10-04): headless `--version`, GUT run, Linux/Windows/Linux-server exports, the
exported Linux binary booting with `--smoke-test`, and a 1920×1080 screenshot under Xvfb.

## macOS build

Exported from Linux like the others: preset "macOS" (`scripts/export.sh macos`) writes
`build/macos/BetterAtGambling.zip` with a universal (x86_64 + arm64) `Better at Gambling.app`;
GodotSteam and `libsteam_api.dylib` land in `Contents/Frameworks`. The universal export needs both
texture formats, so `import_etc2_astc` is on next to S3TC/BPTC. Godot only ad-hoc signs (its
rcodesign mode refuses apps with GDExtension libraries); `tools/macos/package.sh` re-signs the .app
with rcodesign: Developer ID + hardened runtime + `tools/macos/entitlements.plist`, then
notarization and stapling when the six Apple secrets are set (see the header of `release.yml`),
ad-hoc otherwise. Keep the preset's `codesign/entitlements/*` switches and the plist in sync.
The release carries the app twice: `BetterAtGambling-macos.zip` and `BetterAtGambling-macos.dmg`.
The .dmg is an ISO 9660 image with Rock Ridge and Apple extensions written by `genisoimage`
(installed in the workflow; the recipe Bitcoin Core used for its Mac builds), which macOS mounts
like any disk image; the image itself is unsigned, Gatekeeper judges the signed .app inside it.
Launching the app, Gatekeeper, the microphone prompt, Steam and host mode can only be tested on a Mac.
