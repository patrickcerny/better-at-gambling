#!/usr/bin/env python3
"""Builds the 3D "BETTER AT GAMBLING" title logo as a .glb.

The layout follows Patrick's pixel-art reference: gold chunky letters with a dark outline, on an
arched burgundy banner with a raised, bevelled gold trim and rivets. Letters and banner are real
extruded geometry with chamfered fronts, and the whole sign is bent around a vertical cylinder so
the ends fall back slightly.

Units while building are reference-image pixels (the reference is 1536x1024, centred on 768,512,
y up, z toward the viewer); the .glb is written at 1/100 of that (about 13.5 m wide).

Usage: python3 tools/logo/build_logo3d.py [out.glb]
Needs: numpy, shapely>=2, fonttools, mapbox_earcut.
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import mapbox_earcut as earcut
import numpy as np
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from shapely import affinity
from shapely.geometry import MultiPolygon, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "assets/fonts/LuckiestGuy-Regular.ttf"
OUT = ROOT / "assets/models/logo/logo_3d.glb"
SCALE = 0.01
BEND_RADIUS = 1800.0


def hexcol(h: str) -> tuple[float, float, float]:
	h = h.lstrip("#")
	return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def lerp(a, b, t):
	return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# Palette (sRGB, tuned against the reference and docs/ART_DIRECTION.md).
GOLD_TOP = hexcol("#FFE45C")
GOLD_BOTTOM = hexcol("#F7B32B")
GOLD_SIDE = hexcol("#D9831C")
OUTLINE = hexcol("#4E150A")
BANNER = hexcol("#86131F")
BANNER_DARK = hexcol("#560B17")
TRIM = hexcol("#F5C445")
TRIM_SIDE = hexcol("#C98A26")


class Mesh:
	"""Flat-shaded triangle soup; normals are computed after the bend."""

	def __init__(self, name: str):
		self.name = name
		self.tris: list[tuple] = []  # ((p0,p1,p2),(c0,c1,c2))

	def add(self, pts, cols, smooth: float = 0.0):
		self.tris.append((tuple(pts), tuple(cols), smooth))

	def extend(self, other: "Mesh"):
		self.tris.extend(other.tris)

	def transformed(self, fn) -> "Mesh":
		m = Mesh(self.name)
		for pts, cols, smooth in self.tris:
			m.tris.append((tuple(fn(p) for p in pts), cols, smooth))
		return m


def _norm(p0, p1, p2):
	a = np.subtract(p1, p0)
	b = np.subtract(p2, p0)
	return np.cross(a, b)


def _add_oriented(mesh: Mesh, pts, cols, want_z_sign: float | None = None, want_dir=None, smooth: float = 0.0):
	n = _norm(*pts)
	flip = False
	if want_z_sign is not None and n[2] * want_z_sign < 0:
		flip = True
	if want_dir is not None and np.dot(n, want_dir) < 0:
		flip = True
	if flip:
		pts = (pts[0], pts[2], pts[1])
		cols = (cols[0], cols[2], cols[1])
	if np.linalg.norm(n) > 1e-9:
		mesh.add(pts, cols, smooth)


def _rings(poly: Polygon):
	poly = orient(poly, 1.0)  # exterior CCW, holes CW
	rings = [list(poly.exterior.coords)[:-1]]
	rings += [list(r.coords)[:-1] for r in poly.interiors]
	return rings


STRIP = 36.0


def _cap(mesh: Mesh, poly: Polygon, z: float, color_fn, up: bool):
	minx, miny, maxx, maxy = poly.bounds
	if maxx - minx > STRIP * 1.5:
		x = math.floor(minx / STRIP) * STRIP
		while x < maxx:
			for part in _polys(poly.intersection(box(x, miny - 1, x + STRIP, maxy + 1))):
				_cap_one(mesh, orient(part, 1.0), z, color_fn, up)
			x += STRIP
	else:
		_cap_one(mesh, poly, z, color_fn, up)


def _cap_one(mesh: Mesh, poly: Polygon, z: float, color_fn, up: bool):
	rings = _rings(poly)
	verts = np.array([p for r in rings for p in r], dtype=np.float64)
	ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
	idx = earcut.triangulate_float64(verts, ends)
	for i in range(0, len(idx), 3):
		tri = [verts[idx[i + k]] for k in range(3)]
		pts = [(float(p[0]), float(p[1]), z) for p in tri]
		cols = [color_fn(p[0], p[1]) for p in tri]
		_add_oriented(mesh, pts, cols, want_z_sign=1.0 if up else -1.0, smooth=1.0 if up else -1.0)


def _wall(mesh: Mesh, ring, z0: float, z1: float, color):
	n = len(ring)
	for i in range(n):
		a = ring[i]
		b = ring[(i + 1) % n]
		p0, p1 = (a[0], a[1], z0), (b[0], b[1], z0)
		p2, p3 = (b[0], b[1], z1), (a[0], a[1], z1)
		# Outward = right of the edge direction for CCW exteriors / CW holes.
		d = (b[0] - a[0], b[1] - a[1])
		out = np.array([d[1], -d[0], 0.0])
		_add_oriented(mesh, (p0, p1, p2), (color,) * 3, want_dir=out)
		_add_oriented(mesh, (p0, p2, p3), (color,) * 3, want_dir=out)


def _arclen(ring):
	pts = np.array(ring + [ring[0]])
	seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
	t = np.concatenate([[0.0], np.cumsum(seg)])
	return t / t[-1]


def _stitch(mesh: Mesh, outer, inner, z0: float, z1: float, col_o, col_i):
	"""Chamfer band from ring `outer` at z0 to the (same-orientation) inset ring `inner` at z1."""
	o0 = np.array(outer[0])
	k = int(np.argmin([np.sum((np.array(p) - o0) ** 2) for p in inner]))
	inner = inner[k:] + inner[:k]
	ta, tb = _arclen(outer), _arclen(inner)
	na, nb = len(outer), len(inner)
	i = j = 0
	A = lambda q: (outer[q % na][0], outer[q % na][1], z0)
	B = lambda q: (inner[q % nb][0], inner[q % nb][1], z1)
	ca = lambda q: col_o(outer[q % na][0], outer[q % na][1])
	cb = lambda q: col_i(inner[q % nb][0], inner[q % nb][1])
	while i < na or j < nb:
		adv_a = j >= nb or (i < na and ta[i + 1] <= tb[j + 1])
		if adv_a:
			_add_oriented(mesh, (A(i), A(i + 1), B(j)), (ca(i), ca(i + 1), cb(j)), want_z_sign=1.0)
			i += 1
		else:
			_add_oriented(mesh, (A(i), B(j + 1), B(j)), (ca(i), cb(j + 1), cb(j)), want_z_sign=1.0)
			j += 1


def _polys(geom):
	if geom.is_empty:
		return []
	if isinstance(geom, Polygon):
		return [geom]
	if isinstance(geom, MultiPolygon):
		return list(geom.geoms)
	return [g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon)]


def extrude(mesh: Mesh, geom, z0: float, z1: float, *, bevel: float = 0.0, bevel_h: float = 0.0,
		front=None, chamfer=None, side=(0.5, 0.5, 0.5), back=True):
	"""Extrudes polygons from z0 to z1; with `bevel`, the front edge is chamfered inward."""
	front = front or (lambda x, y: side)
	chamfer = chamfer or front
	for poly in _polys(geom):
		poly = orient(poly.simplify(0.4), 1.0)
		inset = None
		if bevel > 0:
			ins = poly.buffer(-bevel, join_style="mitre", mitre_limit=2.5)
			ip = _polys(ins)
			if len(ip) == 1 and len(ip[0].interiors) == len(poly.interiors):
				inset = orient(ip[0].simplify(0.4), 1.0)
		zw = z1 - bevel_h if inset is not None else z1
		outer_rings = _rings(poly)
		for r in outer_rings:
			_wall(mesh, r, z0, zw, side)
		if inset is not None:
			inner_rings = _rings(inset)
			# Match holes by nearest centroid (exterior is always first).
			used = set()
			for oi, r in enumerate(outer_rings):
				if oi == 0:
					match = 0
				else:
					c = np.mean(r, axis=0)
					cands = [(np.sum((np.mean(ir, axis=0) - c) ** 2), ii) for ii, ir in enumerate(inner_rings) if ii and ii not in used]
					match = min(cands)[1]
				used.add(match)
				_stitch(mesh, r, inner_rings[match], zw, z1, chamfer, chamfer)
			_cap(mesh, inset, z1, front, up=True)
		else:
			_cap(mesh, poly, z1, front, up=True)
		if back:
			_cap(mesh, poly, z0, lambda x, y: side, up=False)


def dome(mesh: Mesh, cx: float, cy: float, z: float, r: float, h: float, color, side):
	seg, rings = 12, 4
	def pt(ri, si):
		a = ri / rings * math.pi / 2
		ang = si / seg * 2 * math.pi
		rr = r * math.cos(a)
		return (cx + rr * math.cos(ang), cy + rr * math.sin(ang), z + h * math.sin(a))
	for ri in range(rings):
		for si in range(seg):
			p00, p01 = pt(ri, si), pt(ri, si + 1)
			p10, p11 = pt(ri + 1, si), pt(ri + 1, si + 1)
			c = lerp(side, color, (ri + 0.5) / rings)
			_add_oriented(mesh, (p00, p01, p11), (c,) * 3, want_z_sign=1.0)
			if ri < rings - 1:
				_add_oriented(mesh, (p00, p11, p10), (c,) * 3, want_z_sign=1.0)


# ---------------------------------------------------------------- glyphs

class FlatPen(BasePen):
	def __init__(self, glyphset):
		super().__init__(glyphset)
		self.contours: list[list[tuple[float, float]]] = []
		self.cur: list[tuple[float, float]] = []

	def _moveTo(self, p):
		self.cur = [p]

	def _lineTo(self, p):
		self.cur.append(p)

	def _curveToOne(self, p1, p2, p3):
		p0 = self.cur[-1]
		for k in range(1, 9):
			t = k / 8
			mt = 1 - t
			self.cur.append(tuple(mt ** 3 * p0[i] + 3 * mt * mt * t * p1[i] + 3 * mt * t * t * p2[i] + t ** 3 * p3[i] for i in range(2)))

	def _qCurveToOne(self, p1, p2):
		p0 = self.cur[-1]
		for k in range(1, 7):
			t = k / 6
			mt = 1 - t
			self.cur.append(tuple(mt * mt * p0[i] + 2 * mt * t * p1[i] + t * t * p2[i] for i in range(2)))

	def _closePath(self):
		if len(self.cur) >= 3:
			self.contours.append(self.cur)
		self.cur = []

	_endPath = _closePath


class Font:
	def __init__(self, path: Path):
		self.tt = TTFont(str(path))
		self.gs = self.tt.getGlyphSet()
		self.cmap = self.tt.getBestCmap()
		self.cap = float(self.tt["OS/2"].sCapHeight or self.tt["head"].unitsPerEm * 0.7)

	def glyph(self, ch: str, cap_px: float):
		name = self.cmap[ord(ch)]
		pen = FlatPen(self.gs)
		self.gs[name].draw(pen)
		s = cap_px / self.cap
		geom = Polygon()
		for c in pen.contours:
			geom = geom.symmetric_difference(Polygon(c).buffer(0))
		geom = affinity.scale(geom, s, s, origin=(0, 0))
		return geom, self.gs[name].width * s


def place_word(font: Font, text: str, cap_px: float, width_px: float, apex_y: float, radius: float,
		tilt_deg: list[float], dy: list[float]):
	"""Lays `text` along an arch whose baseline apex is at (0, apex_y). Returns placed glyphs."""
	glyphs = []
	for ch in text:
		if ch == " ":
			glyphs.append((None, cap_px * 0.32))
			continue
		g, adv = font.glyph(ch, cap_px)
		minx, _, maxx, _ = g.bounds
		g = affinity.translate(g, -(minx + maxx) / 2, 0)  # centre each glyph on its own ink
		glyphs.append((g, maxx - minx))
	ink = sum(w for _, w in glyphs)
	n_gaps = len(glyphs) - 1
	sx = 1.0
	gap = (width_px - ink) / n_gaps
	if gap < cap_px * 0.03:  # too wide: condense letters slightly instead of overlapping
		gap = cap_px * 0.03
		sx = (width_px - gap * n_gaps) / ink
	total = ink * sx + gap * n_gaps
	s = -total / 2
	out = []
	li = 0
	for g, w in glyphs:
		w *= sx
		mid = s + w / 2
		s += w + gap
		if g is None:
			continue
		g = affinity.scale(g, sx, 1.0, origin=(0, 0))
		theta = mid / radius
		bx = radius * math.sin(theta)
		by = apex_y - radius + radius * math.cos(theta) + dy[li % len(dy)]
		rot = -math.degrees(theta) + tilt_deg[li % len(tilt_deg)]
		li += 1
		out.append((g, bx, by, rot))
	return out


def letter_mesh(placed, cap_px: float, z0: float, z1: float, bevel: float, bevel_h: float) -> Mesh:
	mesh = Mesh("Letters")
	for g, bx, by, rot in placed:
		local = Mesh("tmp")
		def front(x, y, cap=cap_px):
			t = max(0.0, min(1.0, y / cap))
			return lerp(GOLD_BOTTOM, GOLD_TOP, t ** 0.8)
		def cham(x, y, cap=cap_px):
			c = front(x, y, cap)
			return lerp(c, GOLD_SIDE, 0.25)
		extrude(local, g, z0, z1, bevel=bevel, bevel_h=bevel_h, front=front, chamfer=cham, side=GOLD_SIDE, back=False)
		r = math.radians(rot)
		cr, sr = math.cos(r), math.sin(r)
		mesh.extend(local.transformed(lambda p: (p[0] * cr - p[1] * sr + bx, p[0] * sr + p[1] * cr + by, p[2])))
	return mesh


def placed_union(placed):
	geoms = []
	for g, bx, by, rot in placed:
		geoms.append(affinity.translate(affinity.rotate(g, rot, origin=(0, 0)), bx, by))
	return unary_union(geoms)


# ---------------------------------------------------------------- banner

def ref(x: float, y: float):
	"""Reference-image pixel -> design coords (centred, y up)."""
	return (x - 768.0, 512.0 - y)


def banner_polygon() -> Polygon:
	half = 680.0
	r_top, top_c = 1060.0, 215.0
	r_bot, bot_c = 2913.0, 722.0
	def y_top(dx):
		y = top_c + (r_top - math.sqrt(r_top * r_top - dx * dx))
		if abs(dx) < 185:
			y = min(y, 200.0)  # flat raised tab in the centre
		if abs(dx) > 470:
			y -= 14.0  # stepped shoulders near the ends
		return y
	def y_bot(dx):
		return bot_c + (r_bot - math.sqrt(r_bot * r_bot - dx * dx))
	pts = []
	n = 120
	for i in range(n + 1):  # top edge, left to right
		dx = -half + 2 * half * i / n
		pts.append(ref(768 + dx, y_top(dx)))
	# right end cap with a small outward notch
	yt, yb = y_top(half), y_bot(half)
	for (ox, oy) in [(0, 46), (16, 58), (16, yb - yt - 50), (0, yb - yt - 38)]:
		pts.append(ref(768 + half + ox, yt + oy))
	for i in range(n + 1):  # bottom edge, right to left
		dx = half - 2 * half * i / n
		pts.append(ref(768 + dx, y_bot(dx)))
	for (ox, oy) in [(0, yb - yt - 38), (16, yb - yt - 50), (16, 58), (0, 46)]:
		pts.append(ref(768 - half - ox, yt + oy))
	return Polygon(pts).buffer(0)


def build() -> list[Mesh]:
	font = Font(FONT)
	big = place_word(font, "GAMBLING", 222.0, 1240.0, ref(0, 688)[1], 3600.0,
		[-4, 3, -2, 2, -3, 2, -2, 4], [4, -6, 2, -4, 3, -5, 2, 6])
	small = place_word(font, "BETTER AT", 108.0, 840.0, ref(0, 418)[1], 2400.0,
		[-3, 2, -2, 3, -2, 2, -3, 2], [2, -3, 3, -2, 2, -3, 3, -2])

	z_banner, z_outline, z_letters = 0.0, 22.0, 64.0

	banner = banner_polygon()
	body = banner.buffer(-14.0, join_style="mitre")
	trim_ring = banner.difference(banner.buffer(-22.0, join_style="mitre"))
	shadow_ring = banner.buffer(-22.0, join_style="mitre").difference(banner.buffer(-30.0, join_style="mitre"))

	ymin, ymax = banner.bounds[1], banner.bounds[3]
	def banner_col(x, y):
		t = (y - ymin) / (ymax - ymin)
		return lerp(BANNER_DARK, BANNER, 0.55 + 0.45 * math.sin(math.pi * t))

	m_banner = Mesh("Banner")
	extrude(m_banner, body, -40.0, z_banner, front=banner_col, side=BANNER_DARK)
	extrude(m_banner, shadow_ring, z_banner, z_banner + 1.5, front=lambda x, y: BANNER_DARK, side=BANNER_DARK, back=False)

	m_trim = Mesh("Trim")
	extrude(m_trim, trim_ring, -44.0, 16.0, bevel=7.0, bevel_h=8.0,
		front=lambda x, y: TRIM, chamfer=lambda x, y: lerp(TRIM, TRIM_SIDE, 0.3), side=TRIM_SIDE)
	rivets = [ref(290, 372), ref(1246, 372), ref(124, 512), ref(1412, 512), ref(124, 742), ref(1412, 742)]
	for (rx, ry) in rivets:
		extrude(m_trim, Polygon([(rx + 15 * math.cos(a), ry + 15 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 12, endpoint=False)]),
			z_banner, z_banner + 4.0, front=lambda x, y: TRIM_SIDE, side=TRIM_SIDE, back=False)
		dome(m_trim, rx, ry, z_banner + 4.0, 12.0, 10.0, TRIM, TRIM_SIDE)

	m_outline = Mesh("Outline")
	for placed in (big, small):
		ol = placed_union(placed).buffer(13.0, join_style="round", quad_segs=4)
		extrude(m_outline, ol, z_banner, z_outline, bevel=4.0, bevel_h=4.0,
			front=lambda x, y: OUTLINE, side=OUTLINE, back=False)

	m_letters = letter_mesh(big, 222.0, z_outline, z_letters, 8.0, 9.0)
	m_letters.extend(letter_mesh(small, 108.0, z_outline, z_letters - 10.0, 5.0, 6.0))

	return [m_letters, m_outline, m_banner, m_trim]


# ---------------------------------------------------------------- output

def bend(p):
	x, y, z = p
	r = BEND_RADIUS + z
	th = x / BEND_RADIUS
	return (r * math.sin(th) * SCALE, y * SCALE, (r * math.cos(th) - BEND_RADIUS) * SCALE)


def srgb_to_linear(c):
	return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


MATERIALS = {
	"Letters": {"metallic": 0.35, "roughness": 0.38},
	"Outline": {"metallic": 0.0, "roughness": 0.7},
	"Banner": {"metallic": 0.0, "roughness": 0.75},
	"Trim": {"metallic": 0.55, "roughness": 0.32},
}


SMOOTH_COS = math.cos(math.radians(40.0))


def _key(q):
	return (round(float(q[0]), 4), round(float(q[1]), 4), round(float(q[2]), 4))


def write_glb(meshes: list[Mesh], path: Path):
	bent = [m.transformed(bend) for m in meshes]
	allp = np.array([p for m in bent for t in m.tris for p in t[0]])
	centre = (allp.min(axis=0) + allp.max(axis=0)) / 2
	centre[2] = 0.0
	bin_parts: list[bytes] = []
	offset = 0
	views, accessors, prims, mats = [], [], [], []

	def push(data: bytes, target: int):
		nonlocal offset
		pad = (-len(data)) % 4
		bin_parts.append(data + b"\0" * pad)
		views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
		offset += len(data) + pad
		return len(views) - 1

	for mi, m in enumerate(bent):
		pos, nrm, col = [], [], []
		# Auto-smooth walls and chamfers: average face normals that meet within SMOOTH_DEG.
		face_n = []
		shared: dict[tuple, list] = {}
		for pts, _cols, smooth in m.tris:
			raw = np.array(pts)
			n = np.cross(raw[1] - raw[0], raw[2] - raw[0])
			n = n / (np.linalg.norm(n) or 1.0)
			face_n.append(n)
			if not smooth:
				for q in raw:
					shared.setdefault(_key(q), []).append(n)
		for (pts, cols, smooth), n in zip(m.tris, face_n):
			raw = np.array(pts)
			p = raw - centre
			for k in range(3):
				pos.append(p[k])
				if smooth:  # cap faces follow the bend cylinder smoothly
					cn = np.array([raw[k][0], 0.0, raw[k][2] + BEND_RADIUS * SCALE])
					nrm.append(smooth * cn / np.linalg.norm(cn))
				else:
					acc = sum((f for f in shared[_key(raw[k])] if np.dot(f, n) > SMOOTH_COS), np.zeros(3))
					nrm.append(acc / (np.linalg.norm(acc) or 1.0))
				col.append(cols[k])  # Godot linearises COLOR_0 itself
		pos = np.array(pos, dtype=np.float32)
		nrm = np.array(nrm, dtype=np.float32)
		col = np.array(col, dtype=np.float32)
		idx = np.arange(len(pos), dtype=np.uint32)
		va = push(pos.tobytes(), 34962)
		accessors.append({"bufferView": va, "componentType": 5126, "count": len(pos), "type": "VEC3",
			"min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()})
		a_pos = len(accessors) - 1
		accessors.append({"bufferView": push(nrm.tobytes(), 34962), "componentType": 5126, "count": len(nrm), "type": "VEC3"})
		a_nrm = len(accessors) - 1
		accessors.append({"bufferView": push(col.tobytes(), 34962), "componentType": 5126, "count": len(col), "type": "VEC3"})
		a_col = len(accessors) - 1
		accessors.append({"bufferView": push(idx.tobytes(), 34963), "componentType": 5125, "count": len(idx), "type": "SCALAR"})
		a_idx = len(accessors) - 1
		prims.append({"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "COLOR_0": a_col}, "indices": a_idx, "material": mi})
		spec = MATERIALS[m.name]
		mats.append({"name": "Logo" + m.name, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
			"metallicFactor": spec["metallic"], "roughnessFactor": spec["roughness"]}})
		print(f"[logo] {m.name}: {len(m.tris)} triangles")

	gltf = {
		"asset": {"version": "2.0", "generator": "tools/logo/build_logo3d.py"},
		"scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [{"name": "Logo3D", "mesh": 0}],
		"meshes": [{"name": "Logo3D", "primitives": prims}],
		"materials": mats,
		"buffers": [{"byteLength": offset}],
		"bufferViews": views, "accessors": accessors,
	}
	js = json.dumps(gltf, separators=(",", ":")).encode()
	js += b" " * ((-len(js)) % 4)
	binary = b"".join(bin_parts)
	path.parent.mkdir(parents=True, exist_ok=True)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
		f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
		f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)
	size = allp.max(axis=0) - allp.min(axis=0)
	print(f"[logo] wrote {path} ({path.stat().st_size // 1024} KB, {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m)")


if __name__ == "__main__":
	write_glb(build(), Path(sys.argv[1]) if len(sys.argv) > 1 else OUT)
