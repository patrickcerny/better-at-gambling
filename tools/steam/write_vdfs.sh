#!/usr/bin/env bash
# Writes the SteamPipe build scripts for <build dir> (content/ from prepare_content.sh) into
# <build dir>/scripts: app_build.vdf and one depot_build_<id>.vdf per depot.
# App and depot IDs come from APP_ID / DEPOT_WINDOWS / DEPOT_LINUX / DEPOT_MACOS (defaults below).
# Usage: tools/steam/write_vdfs.sh <build dir> "<build description>"
set -euo pipefail
root="$1"; desc="${2:-Better at Gambling}"
APP_ID="${APP_ID:-5623410}"
DEPOT_WINDOWS="${DEPOT_WINDOWS:-5623411}"
DEPOT_LINUX="${DEPOT_LINUX:-5623412}"
DEPOT_MACOS="${DEPOT_MACOS:-5623413}"
mkdir -p "$root/scripts" "$root/output"
desc="${desc//\"/}"
depot() { # id folder
	cat > "$root/scripts/depot_build_$1.vdf" <<VDF
"DepotBuild"
{
	"DepotID" "$1"
	"ContentRoot" "$root/content/$2"
	"FileMapping"
	{
		"LocalPath" "*"
		"DepotPath" "."
		"Recursive" "1"
	}
	"FileExclusion" "*.pdb"
	"FileExclusion" "steam_appid.txt"
}
VDF
}
depot "$DEPOT_WINDOWS" windows
depot "$DEPOT_LINUX" linux
depot "$DEPOT_MACOS" macos
cat > "$root/scripts/app_build.vdf" <<VDF
"AppBuild"
{
	"AppID" "$APP_ID"
	"Desc" "$desc"
	"ContentRoot" "$root/content"
	"BuildOutput" "$root/output"
	"Depots"
	{
		"$DEPOT_WINDOWS" "depot_build_$DEPOT_WINDOWS.vdf"
		"$DEPOT_LINUX" "depot_build_$DEPOT_LINUX.vdf"
		"$DEPOT_MACOS" "depot_build_$DEPOT_MACOS.vdf"
	}
}
VDF
echo "SteamPipe scripts in $root/scripts"
