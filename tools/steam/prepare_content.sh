#!/usr/bin/env bash
# Unpacks the three release zips into one SteamPipe content folder per depot:
#   <out>/content/windows  BetterAtGambling.exe + DLLs (GodotSteam, steam_api64.dll)
#   <out>/content/linux    BetterAtGambling.x86_64 + .so files
#   <out>/content/macos    "Better at Gambling.app"
# Usage: tools/steam/prepare_content.sh <dir with the zips> <out dir>
set -euo pipefail
src="$1"; out="$2"
rm -rf "$out/content"; mkdir -p "$out/content/windows" "$out/content/linux" "$out/content/macos"
unzip -q "$src/BetterAtGambling-windows.zip" -d "$out/content/windows"
unzip -q "$src/BetterAtGambling-linux.zip" -d "$out/content/linux"
unzip -q "$src/BetterAtGambling-macos.zip" -d "$out/content/macos"
chmod +x "$out/content/linux/BetterAtGambling.x86_64"
test -s "$out/content/windows/BetterAtGambling.exe"
test -s "$out/content/windows/steam_api64.dll"
test -x "$out/content/linux/BetterAtGambling.x86_64"
test -d "$out/content/macos/Better at Gambling.app"
# Steam supplies the App ID itself; a stray steam_appid.txt must not ship.
find "$out/content" -name steam_appid.txt -delete
du -sh "$out/content"/*
