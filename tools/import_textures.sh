#!/usr/bin/env bash
# Copies the CC0 surface textures picked for the Lucky Lounge from the research folder into
# assets/textures/<name>/, downscaled with ffmpeg (1K max, JPG) so the download stays small.
# Source: /mnt/project-files/better-at-gambling/textures (see NOTES.md there and CREDITS.md).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-/mnt/project-files/better-at-gambling/textures}"
DST=assets/textures
conv() { # src dst size quality
	mkdir -p "$(dirname "$2")"
	ffmpeg -v error -y -i "$1" -vf "scale=$3:$3:flags=lanczos" -q:v "$4" "$2"
	echo "$(du -k "$2" | cut -f1) KB  $2"
}
# floor
conv "$SRC/floor/custom_casino_carpet/casino_carpet_1k_Color.png" "$DST/casino_carpet/albedo.jpg" 1024 4
conv "$SRC/floor/acg_Fabric026_red_carpet_fibre/Fabric026_2K-JPG_NormalGL.jpg" "$DST/casino_carpet/normal.jpg" 1024 5
conv "$SRC/floor/acg_Tiles074_checker_marble/Tiles074_2K-JPG_Color.jpg" "$DST/checker_marble/albedo.jpg" 1024 4
conv "$SRC/floor/acg_Tiles074_checker_marble/Tiles074_2K-JPG_NormalGL.jpg" "$DST/checker_marble/normal.jpg" 1024 6
conv "$SRC/floor/ph_herringbone_parquet/herringbone_parquet_diff_2k.jpg" "$DST/herringbone_parquet/albedo.jpg" 1024 4
conv "$SRC/floor/ph_herringbone_parquet/herringbone_parquet_nor_gl_2k.jpg" "$DST/herringbone_parquet/normal.jpg" 1024 6
# walls
conv "$SRC/walls/custom_damask_wallpaper/damask_wallpaper_1k_Color.png" "$DST/damask_wallpaper/albedo.jpg" 1024 4
conv "$SRC/walls/custom_damask_wallpaper/damask_wallpaper_gold_1k_Color.png" "$DST/damask_wallpaper/albedo_gold.jpg" 1024 4
conv "$SRC/walls/ph_wooden_panels/wooden_panels_diff_2k.jpg" "$DST/wooden_panels/albedo.jpg" 1024 4
conv "$SRC/walls/ph_wooden_panels/wooden_panels_nor_gl_2k.jpg" "$DST/wooden_panels/normal.jpg" 1024 6
conv "$SRC/walls/acg_Marble016_black_marble/Marble016_2K-JPG_Color.jpg" "$DST/black_marble/albedo.jpg" 1024 4
conv "$SRC/walls/acg_Marble016_black_marble/Marble016_2K-JPG_NormalGL.jpg" "$DST/black_marble/normal.jpg" 512 6
conv "$SRC/walls/ph_velour_velvet/velour_velvet_diff_2k.jpg" "$DST/velvet/albedo.jpg" 512 4
conv "$SRC/walls/ph_velour_velvet/velour_velvet_nor_gl_2k.jpg" "$DST/velvet/normal.jpg" 512 6
# trim
conv "$SRC/trim/acg_Metal048A_brass/Metal048A_2K-JPG_Color.jpg" "$DST/brass/albedo.jpg" 512 4
conv "$SRC/trim/acg_Metal048A_brass/Metal048A_2K-JPG_NormalGL.jpg" "$DST/brass/normal.jpg" 512 6
# ceiling
conv "$SRC/ceiling/ph_dark_paneled_wood/dark_paneled_wood_diff_2k.jpg" "$DST/coffered_ceiling/albedo.jpg" 1024 4
conv "$SRC/ceiling/ph_dark_paneled_wood/dark_paneled_wood_nor_gl_2k.jpg" "$DST/coffered_ceiling/normal.jpg" 1024 6
du -sh "$DST"
