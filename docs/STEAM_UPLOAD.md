# Steam: uploads, Cloud, achievements

App **5623410** (Steamworks: https://partner.steamgames.com/apps/landing/5623410). Online play
only runs through Steam lobbies (host mode, `SteamParty`); `services/steam_service.gd` uses this
App ID. Everything below was set up on 2026-11-14 and published in Steamworks.

## Depots and launch options

| Depot | OS | Content | Launch option |
|---|---|---|---|
| 5623411 | Windows | `BetterAtGambling.exe` + DLLs | `BetterAtGambling.exe` |
| 5623412 | Linux + SteamOS | `BetterAtGambling.x86_64` + `.so` | `BetterAtGambling.x86_64` |
| 5623413 | macOS | `Better at Gambling.app` | `Better at Gambling.app` |

All three depots are in all three packages (store, beta testing, developer comp).

## Uploading a build

The `steam` job in `.github/workflows/release.yml` runs only when started by hand (Actions → Build & release →
Run workflow, tick "steam"), and only when Patrick says so; pushes to main never upload to Steam. It downloads that version's
release zips, unpacks one content folder per depot (`tools/steam/prepare_content.sh`), writes the
SteamPipe scripts (`tools/steam/write_vdfs.sh`) and runs `steamcmd +run_app_build` on Linux, which
keeps the executable bits the Linux and Mac depots need.

It needs the repository secrets `STEAM_USERNAME` and `STEAM_CONFIG_VDF`. Make them once on a
Windows PC with `tools/steam/steam_login.ps1` (Steam password + Steam Guard typed by the account
owner; the script puts the saved login in the clipboard and opens the GitHub secrets page).
Without the secrets the workflow says so and stays green.

Uploaded builds are **not** live. Steamworks → SteamPipe → Builds → pick the build → "Set build
live now" on `default` (Valve does not allow setting `default` live from steamcmd).

## Testing before release

The app is unreleased, so nobody can see it. Testers need a key: Steamworks → "Request Steam
Product Keys" for the "BetterAtGambling for Beta Testing" package.

## Steam Cloud (Auto-Cloud, no code)

Quota 1 MB / 10 files per user. Synced: `profile.cfg` (XP, level, Coins, owned cosmetics) under
`WinAppDataRoaming/Godot/app_userdata/Better at Gambling`, with root overrides macOS →
`MacAppSupport` (same subfolder) and Linux → `LinuxXdgDataHome` +
`godot/app_userdata/Better at Gambling`. `settings.cfg` is not synced on purpose (per-PC
resolution, audio devices).

## Achievements

19 achievements, API names in `services/achievements.gd` (`Achievements.DEFS`), English and
German texts in Steamworks, icon designs in `docs/steam/achievements/` (`<API>_ACHIEVED.png`,
`<API>_UNACHIEVED.png`, 256×256; the copies in Steamworks were redrawn in the same chip style). Steamworks bulk import (Stats & Achievements → Achievements →
"Massenimport/-export") takes these files plus a definitions and a localization CSV.
Thresholds: `BIG_WIN_AMOUNT` and `HIGH_ROLLER_MONEY` in the same file.
