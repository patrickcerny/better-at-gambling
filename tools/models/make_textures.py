#!/usr/bin/env python3
"""Paints the textures our own models use (no third-party images):

- assets/models/own/textures/roulette_ring.png: the number ring on the roulette rotor (European
  order, the zero at the top = the ring's -z, numbers clockwise seen from above). Radii are
  fractions of RouletteWheelFx.RING_R: transparent inside 0.62, pocket floors 0.62..0.9 with a
  gold rule, numbers on their colour 0.9..1.0.
- assets/models/own/textures/painting_*.png: the oil paintings in our picture frames, painted
  procedurally (layered hills, sky, trees, brush strokes) in the warm casino palette.

Usage: python3 tools/models/make_textures.py   (needs numpy, pillow)
"""
from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/own/textures"
FONT = ROOT / "assets/fonts/BarlowCondensed-Black.ttf"

WHEEL_ORDER = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1,
               20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
RED = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
CASINO_RED = (184, 46, 46)
BLACK = (26, 24, 24)
GREEN = (39, 94, 73)
GOLD = (214, 168, 75)
CREAM = (242, 230, 201)


def ring(size: int = 1024) -> Image.Image:
	ss = 2  # supersample
	S = size * ss
	c = S / 2
	img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	n = len(WHEEL_ORDER)
	step = 360.0 / n
	r_out, r_num, r_in = c * 0.995, c * 0.9, c * 0.62

	def col(num: int):
		return GREEN if num == 0 else (CASINO_RED if num in RED else BLACK)

	# PIL angles: 0 = +x (right), clockwise (y down). Pocket i is centred at the top, i * step
	# clockwise -> PIL angle -90 + i * step.
	for i, num in enumerate(WHEEL_ORDER):
		a0 = -90 + (i - 0.5) * step
		a1 = -90 + (i + 0.5) * step
		d.pieslice([c - r_out, c - r_out, c + r_out, c + r_out], a0, a1, fill=col(num))
	# Pocket floors a little darker than the number band.
	for i, num in enumerate(WHEEL_ORDER):
		a0 = -90 + (i - 0.5) * step
		a1 = -90 + (i + 0.5) * step
		base = np.array(col(num), dtype=float)
		d.pieslice([c - r_num, c - r_num, c + r_num, c + r_num], a0, a1, fill=tuple(int(v) for v in base * 0.72))
	# Gold rules: between number band and pockets, and the outer edge.
	for r, w in ((r_num, 5 * ss), (r_out - 2 * ss, 6 * ss)):
		d.ellipse([c - r, c - r, c + r, c + r], outline=GOLD, width=w)
	# Pocket dividers in the number band.
	for i in range(n):
		a = math.radians(-90 + (i + 0.5) * step)
		d.line([(c + math.cos(a) * r_num, c + math.sin(a) * r_num), (c + math.cos(a) * r_out, c + math.sin(a) * r_out)], fill=GOLD, width=3 * ss)
	# Hole in the middle (the rotor cone shows through).
	mask = Image.new("L", (S, S), 0)
	md = ImageDraw.Draw(mask)
	md.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], fill=255)
	md.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=0)
	img.putalpha(mask)
	# Numbers, upright when read from outside the wheel (top of the digits outward).
	font = ImageFont.truetype(str(FONT), int(c * 0.085))
	r_txt = (r_num + r_out) / 2
	for i, num in enumerate(WHEEL_ORDER):
		ang = -90 + i * step
		txt = str(num)
		tw = int(c * 0.2)
		tile = Image.new("RGBA", (tw, tw), (0, 0, 0, 0))
		td = ImageDraw.Draw(tile)
		td.text((tw / 2, tw / 2), txt, font=font, fill=CREAM, anchor="mm")
		# Rotate so the text's up points outward: at the top (ang -90) no rotation.
		tile = tile.rotate(-(ang + 90), resample=Image.BICUBIC)
		x = c + math.cos(math.radians(ang)) * r_txt - tw / 2
		y = c + math.sin(math.radians(ang)) * r_txt - tw / 2
		img.alpha_composite(tile, (int(x), int(y)))
	return img.resize((size, size), Image.LANCZOS)


def _hill(w: int, base: float, amp: float, waves: list[tuple[float, float]], rng: random.Random) -> np.ndarray:
	x = np.linspace(0, 1, w)
	y = np.full(w, base)
	for f, a in waves:
		y += np.sin(x * f * math.tau + rng.random() * 6.28) * a * amp
	return y


def painting(seed: int, w: int = 1024, h: int = 768, mood: str = "dusk") -> Image.Image:
	rng = random.Random(seed)
	npr = np.random.default_rng(seed)
	yy, xx = np.mgrid[0:h, 0:w] / np.array([h, w]).reshape(2, 1, 1)
	if mood == "dusk":
		top, horizon = np.array([58, 44, 62]), np.array([236, 170, 96])
	else:
		top, horizon = np.array([92, 112, 128]), np.array([238, 214, 166])
	t = np.clip(yy / 0.62, 0, 1)[..., None]
	img = top * (1 - t) ** 1.4 + horizon * (1 - (1 - t) ** 1.4)
	# Sun glow.
	sx, sy = rng.uniform(0.3, 0.7), rng.uniform(0.42, 0.52)
	dist = np.sqrt(((xx - sx) * w / h) ** 2 + (yy - sy) ** 2)
	glow = np.exp(-(dist / 0.18) ** 2)[..., None]
	img = img * (1 - glow * 0.6) + np.array([255, 226, 160]) * glow * 0.6
	img[dist < 0.045] = np.array([255, 236, 190])
	# Hills, far to near.
	layers = [
		(0.58, 0.05, np.array([120, 98, 110]) if mood == "dusk" else np.array([128, 140, 150])),
		(0.66, 0.06, np.array([88, 84, 70])),
		(0.76, 0.07, np.array([62, 72, 44])),
		(0.88, 0.06, np.array([44, 52, 30])),
	]
	for base, amp, colr in layers:
		ridge = _hill(w, base, 1.0, [(1.3, amp), (3.1, amp * 0.45), (7.3, amp * 0.15)], rng) * h
		mask = (np.arange(h)[:, None] > ridge[None, :])
		shade = np.clip((np.arange(h)[:, None] - ridge[None, :]) / (h * 0.25), 0, 1)[..., None]
		layer = colr * (1 - shade * 0.35)
		img = np.where(mask[..., None], layer, img)
	out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
	d = ImageDraw.Draw(out)
	# A few cypress trees and a little villa on the middle hill.
	for _ in range(rng.randint(3, 6)):
		tx = rng.uniform(0.05, 0.95) * w
		ty = rng.uniform(0.7, 0.86) * h
		th = rng.uniform(0.12, 0.22) * h
		d.ellipse([tx - th * 0.13, ty - th, tx + th * 0.13, ty], fill=(30, 40, 24))
	vx, vy = rng.uniform(0.25, 0.75) * w, 0.7 * h
	d.rectangle([vx - 40, vy - 34, vx + 40, vy], fill=(222, 200, 160))
	d.polygon([(vx - 48, vy - 34), (vx, vy - 62), (vx + 48, vy - 34)], fill=(150, 64, 44))
	for k in (-22, 0, 22):
		d.rectangle([vx + k - 6, vy - 24, vx + k + 6, vy - 8], fill=(70, 50, 40))
	# Brush strokes: short oriented smears of nearby colour.
	arr = np.asarray(out).astype(np.float32)
	strokes = Image.new("RGBA", out.size, (0, 0, 0, 0))
	sd = ImageDraw.Draw(strokes)
	for _ in range(5200):
		x, y = npr.integers(0, w), npr.integers(0, h)
		cl = arr[y, x] * npr.uniform(0.88, 1.12)
		ang = npr.normal(0, 0.35) + (0 if y < h * 0.55 else npr.normal(0, 0.4))
		ln = npr.uniform(6, 22)
		dx, dy = math.cos(ang) * ln, math.sin(ang) * ln
		sd.line([(x - dx, y - dy), (x + dx, y + dy)], fill=tuple(int(v) for v in np.clip(cl, 0, 255)) + (150,), width=int(npr.uniform(3, 7)))
	out = out.convert("RGBA")
	out.alpha_composite(strokes)
	out = out.filter(ImageFilter.SMOOTH)
	# Old varnish: warm it and darken the corners.
	a = np.asarray(out.convert("RGB")).astype(np.float32)
	vign = 1 - 0.35 * (((xx - 0.5) * 1.6) ** 2 + ((yy - 0.5) * 1.6) ** 2)
	a = a * np.clip(vign, 0.5, 1)[..., None] * np.array([1.0, 0.95, 0.84])
	return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def main() -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	ring().save(OUT / "roulette_ring.png")
	painting(7, mood="dusk").save(OUT / "painting_dusk.png")
	print("wrote", OUT)


if __name__ == "__main__":
	main()
