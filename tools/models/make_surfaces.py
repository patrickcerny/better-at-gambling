#!/usr/bin/env python3
"""Paints the Lucky Lounge surface textures procedurally (seamless, albedo + OpenGL normal map),
so no third-party texture ships with the game. Each one keeps the layout the lounge's UV scales
expect (tile counts and orientation of the textures it replaced).

  black_marble      dark marble with pale veins                    1024 albedo, 512 normal
  brass             warm brushed brass                             512 / 512
  casino_carpet     fibre normal for our carpet pattern            1024 normal (albedo is ours already)
  checker_marble    6 x 6 checker of cream and black marble tiles  1024 / 1024
  coffered_ceiling  6 x 6 recessed dark wood coffers               1024 / 1024
  herringbone_parquet  oak herringbone                             1024 / 1024
  velvet            deep red velvet                                512 / 512
  wooden_panels     2 x 5 raised mahogany panels (wainscot)        1024 / 1024

Usage: python3 tools/models/make_surfaces.py [name ...]   (needs numpy, pillow)
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/textures"


# --- Helpers ------------------------------------------------------------------------------------

def noise(n: int, beta: float = 2.0, seed: int = 0, stretch: tuple[float, float] = (1.0, 1.0)) -> np.ndarray:
	"""Seamless fractal noise (n x n, 0..1): white noise shaped by 1/f^beta in Fourier space.
	`stretch` (sx, sy) > 1 stretches features along that axis."""
	rng = np.random.default_rng(seed)
	w = rng.standard_normal((n, n))
	fy = np.fft.fftfreq(n)[:, None] * stretch[1]
	fx = np.fft.fftfreq(n)[None, :] * stretch[0]
	f = np.sqrt(fx * fx + fy * fy)
	f[0, 0] = 1.0
	spec = np.fft.fft2(w) / f ** (beta * 0.5)
	spec[0, 0] = 0
	out = np.real(np.fft.ifft2(spec))
	out -= out.min()
	return out / max(out.max(), 1e-9)


def resize(a: np.ndarray, n: int) -> np.ndarray:
	if a.shape[0] == n:
		return a
	img = Image.fromarray(a.astype(np.float32), mode="F").resize((n, n), Image.BICUBIC)
	return np.asarray(img)


def normal_map(h: np.ndarray, strength: float) -> np.ndarray:
	"""OpenGL normal map (green up) from a seamless height field (0..1)."""
	dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
	drow = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
	n = np.dstack([-dx, drow, np.ones_like(h)])
	n /= np.linalg.norm(n, axis=2, keepdims=True)
	return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def colorize(t: np.ndarray, stops: list[tuple[float, tuple[int, int, int]]]) -> np.ndarray:
	xs = [s[0] for s in stops]
	out = np.zeros(t.shape + (3,))
	for c in range(3):
		out[..., c] = np.interp(t, xs, [s[1][c] for s in stops])
	return out


def save(name: str, albedo: np.ndarray | None, normal: np.ndarray | None, a_size: int, n_size: int) -> None:
	d = OUT / name
	d.mkdir(parents=True, exist_ok=True)
	if albedo is not None:
		Image.fromarray(albedo.clip(0, 255).astype(np.uint8)).resize((a_size, a_size), Image.LANCZOS).save(d / "albedo.jpg", quality=90)
	if normal is not None:
		Image.fromarray(normal).resize((n_size, n_size), Image.LANCZOS).save(d / "normal.jpg", quality=92)
	print("wrote", d)


def marble(n: int, seed: int, base, vein, dark_veins: bool = False) -> tuple[np.ndarray, np.ndarray]:
	"""Marble: a cloudy base and thin veins along warped noise contours. Returns (rgb, height)."""
	cloud = noise(n, 2.4, seed)
	warp = noise(n, 4.4, seed + 1)
	field = noise(n, 4.6, seed + 2) * 1.2 + warp * 0.8 + noise(n, 3.0, seed + 4) * 0.08
	veins = np.exp(-(np.sin(field * 9.0) ** 2) / 0.004)
	fine = np.exp(-(np.sin(field * 23.0 + warp * 4.0) ** 2) / 0.0025) * 0.35
	v = np.clip(veins * (0.55 + 0.45 * cloud) + fine * (cloud > 0.45), 0, 1)
	col = np.array(base, float) * (0.85 + 0.3 * cloud[..., None])
	col = col * (1 - v[..., None]) + np.array(vein, float) * v[..., None]
	return col, cloud * 0.2 - v * 0.15


def wood_grain(n: int, seed: int, rings: float, light, dark, along_x: bool = True) -> tuple[np.ndarray, np.ndarray]:
	"""Wood: long streaky grain plus soft growth rings; grain runs along x (or y)."""
	st = (1.0, 14.0) if along_x else (14.0, 1.0)
	streak = noise(n, 1.6, seed, st)
	warp = noise(n, 2.5, seed + 1, (1.0, 3.0) if along_x else (3.0, 1.0))
	coord = (np.arange(n)[:, None] if along_x else np.arange(n)[None, :]) / n
	ring = 0.5 + 0.5 * np.sin((coord + warp * 0.08) * np.pi * 2 * rings)
	t = np.clip(streak * 0.65 + ring * 0.35, 0, 1)
	col = colorize(t, [(0.0, dark), (1.0, light)])
	return col, t


# --- Textures -----------------------------------------------------------------------------------

def black_marble() -> None:
	n = 1024
	col, h = marble(n, 11, (34, 33, 35), (196, 190, 182))
	save("black_marble", col, normal_map(resize(h, 512), 6.0), 1024, 512)


def brass() -> None:
	n = 512
	brush = noise(n, 1.4, 21, (1.0, 30.0))
	blot = noise(n, 2.6, 22)
	t = brush * 0.5 + blot * 0.5
	col = colorize(t, [(0.0, (196, 150, 72)), (0.5, (226, 184, 98)), (1.0, (246, 214, 140))])
	save("brass", col, normal_map(brush * 0.4, 3.0), 512, 512)


def casino_carpet() -> None:
	n = 1024
	fibre = noise(n, 0.6, 31)
	y = np.arange(n)[:, None] / n
	x = np.arange(n)[None, :] / n
	weave = (np.sin(y * np.pi * 2 * 128) * 0.5 + 0.5) * 0.4 + (np.sin(x * np.pi * 2 * 128) * 0.5 + 0.5) * 0.15
	h = fibre * 0.6 + weave
	save("casino_carpet", None, normal_map(h, 2.2), n, n)


def checker_marble() -> None:
	n = 1024
	tiles = 6
	light, hl = marble(n, 41, (214, 200, 178), (150, 132, 112))
	dark, hd = marble(n, 42, (24, 23, 24), (170, 160, 150))
	yy, xx = np.mgrid[0:n, 0:n] * tiles / n
	check = ((np.floor(xx) + np.floor(yy)) % 2).astype(bool)
	col = np.where(check[..., None], dark, light)
	h = np.where(check, hd, hl) * 0.3
	# Grout lines and a slight bevel at each tile edge.
	fx = np.minimum(xx % 1, 1 - xx % 1)
	fy = np.minimum(yy % 1, 1 - yy % 1)
	edge = np.minimum(fx, fy)
	grout = edge < 0.008
	col[grout] = (120, 112, 100)
	h = h + np.clip(edge / 0.03, 0, 1) * 0.6
	save("checker_marble", col, normal_map(h, 10.0), 1024, 1024)


def _bevel_panels(n: int, cols: int, rows: int, frame: float, bevel: float, raised: bool) -> tuple[np.ndarray, np.ndarray]:
	"""Height of a grid of panels: per cell, a flat frame round a raised (or recessed) panel with
	a bevelled edge. Returns (height 0..1, panel mask)."""
	yy, xx = np.mgrid[0:n, 0:n]
	u = (xx * cols / n) % 1
	v = (yy * rows / n) % 1
	du = np.minimum(u, 1 - u) * cols
	dv = np.minimum(v, 1 - v) * rows
	d = np.minimum(du / cols, dv / rows)  # distance to the cell edge in texture units
	t = np.clip((d - frame) / bevel, 0, 1)
	h = t if raised else 1 - t
	return h, d > frame


def coffered_ceiling() -> None:
	n = 1024
	h, inner = _bevel_panels(n, 6, 6, 0.022, 0.03, raised=False)
	grain, _ = wood_grain(n, 51, 7, (98, 52, 30), (40, 20, 12))
	grain_b, _ = wood_grain(n, 52, 9, (92, 48, 28), (36, 18, 10), along_x=False)
	col = np.where(inner[..., None], grain, grain_b)
	col = col * (0.75 + 0.25 * h[..., None])
	# A thin gold-tinted bead round each coffer.
	_, ring = _bevel_panels(n, 6, 6, 0.019, 0.001, raised=False)
	bead = ring & ~inner
	col[bead] = col[bead] * 0.6 + np.array([150, 110, 50]) * 0.4
	save("coffered_ceiling", col, normal_map(h * 0.9 + noise(n, 1.8, 53) * 0.03, 14.0), 1024, 1024)


def herringbone_parquet() -> None:
	n = 1024
	# Herringbone: planks 1 x 4 units, rotated +-45 degrees in alternating columns.
	reps = 8
	yy, xx = np.mgrid[0:n, 0:n] / n * reps
	col_i = np.floor(xx).astype(int)
	fx = xx % 1
	sign = np.where(col_i % 2 == 0, 1.0, -1.0)
	s = yy + sign * fx  # plank coordinate along the chevron
	plank_len = 1.0
	k = np.floor(s / plank_len * 2).astype(int)  # plank index along the column
	f = (s / plank_len * 2) % 1
	edge = np.minimum(np.minimum(f, 1 - f) * 4.0, np.minimum(fx, 1 - fx))
	rng = np.random.default_rng(61)
	tint = rng.uniform(0.82, 1.12, size=(reps * 8 + 8, reps * 4 + 8))
	tone = tint[(k % tint.shape[0]), (col_i % tint.shape[1])]
	grain = noise(n, 1.5, 62, (1.0, 10.0))
	streak = 0.55 + 0.45 * grain
	base = colorize(streak, [(0.0, (118, 74, 38)), (1.0, (196, 140, 82))])
	col = base * tone[..., None]
	gap = edge < 0.03
	col[gap] *= 0.45
	h = np.clip(edge / 0.06, 0, 1) * 0.5 + grain * 0.08
	save("herringbone_parquet", col, normal_map(h, 8.0), 1024, 1024)


def velvet() -> None:
	n = 512
	pile = noise(n, 1.0, 71)
	sheen = noise(n, 2.8, 72)
	t = pile * 0.35 + sheen * 0.65
	col = colorize(t, [(0.0, (120, 22, 34)), (0.6, (168, 36, 52)), (1.0, (196, 62, 76))])
	save("velvet", col, normal_map(pile * 0.5 + sheen * 0.2, 2.0), 512, 512)


def wooden_panels() -> None:
	n = 1024
	h, inner = _bevel_panels(n, 2, 5, 0.035, 0.025, raised=True)
	g_in, _ = wood_grain(n, 81, 5, (122, 62, 34), (54, 26, 14))
	g_out, _ = wood_grain(n, 82, 11, (110, 56, 30), (46, 22, 12), along_x=False)
	col = np.where(inner[..., None], g_in, g_out)
	col = col * (0.72 + 0.28 * h[..., None])
	# Dark shadow line where the frame meets the bevel.
	yy, xx = np.mgrid[0:n, 0:n]
	u = (xx * 2 / n) % 1
	v = (yy * 5 / n) % 1
	d = np.minimum(np.minimum(u, 1 - u) / 2, np.minimum(v, 1 - v) / 5)
	col[np.abs(d - 0.035) < 0.0015] *= 0.5
	save("wooden_panels", col, normal_map(h * 0.8 + noise(n, 1.6, 83, (1.0, 8.0)) * 0.03, 16.0), 1024, 1024)


ALL = {
	"black_marble": black_marble, "brass": brass, "casino_carpet": casino_carpet,
	"checker_marble": checker_marble, "coffered_ceiling": coffered_ceiling,
	"herringbone_parquet": herringbone_parquet, "velvet": velvet, "wooden_panels": wooden_panels,
}


if __name__ == "__main__":
	for name in sys.argv[1:] or list(ALL):
		ALL[name]()
