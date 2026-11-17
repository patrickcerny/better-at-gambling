class_name AchievementMeshes
extends RefCounted
## The models of the achievement rewards (CosmeticDef.achievement, Patrick 2026-11-16: "Each
## achievement should also unlock something", "the harder the achievement, the better the
## price"): one piece per achievement, never sold, not on the pass or the wheel. Built like every
## other outfit piece (`OutfitMeshes`, `OutfitMeshKit`: low-poly parts in vertex colours, warm casino
## colours, no neon); `OutfitMeshes` asks here for every id it doesn't know. Same spaces as there:
## hats upright around the brim (then tipped onto the head), shirts/trousers/capes/faces in body
## space, boots around the foot's centre.


const PAPER := Color("#EFE6D2")
const INK := Color("#3A3533")
const BANANA := Color("#E8C547")
const BRONZE := Color("#9C6A35")
const ICE := Color("#8FB6D9")
const CHERRY := Color("#A8202C")
const WOOD := Color("#7A4A2A")
const HOOP := Color("#5E5A55")
const AMBER := Color("#E89A2E")
const PLUM := Color("#6E3A5E")
const TEAR := Color("#9CC8E0")
const MONEY := Color("#4E7A4A")
const VARSITY := Color("#6A1F2A")

## Shirts' sleeve colours (the arms wear them), like `OutfitMeshes.SLEEVES`.
const FROST := Color("#F2F9FC")
const SLEEVES: Dictionary = {
	&"shirt_varsity": Color("#E9DCBC"), &"shirt_harlequin": Color("#681F2C"), &"shirt_gold_chain": Color("#1C1A19"),
}
## Mouth pieces drawn by the mouth shader (`OutfitMeshes.MOUTH_STYLES`): 7 a sly grin, 8 a gap tooth.
const MOUTH_STYLES: Dictionary = {&"mouth_smirk": 7, &"mouth_gap": 8}
## Eye pieces that change the pupils (`OutfitMeshes.PUPILS`).
const PUPILS: Dictionary = {&"eyes_clover": 0.0, &"eyes_steel": 0.0, &"eyes_cards": 0.0}


## Hats built a little small, scaled up about the top of the head (and their spinners with them).
const BIGGER: Dictionary = {&"hat_banana": 1.3, &"hat_card_house": 1.4, &"hat_beacon": 1.35}


static func hat(k: OutfitMeshKit, id: StringName) -> void:
	const D: float = 0.9
	if id in BIGGER:
		k.xf = k.xf * Transform3D(Basis.from_scale(Vector3.ONE * BIGGER[id]), Vector3(0, 0.2 * (1.0 - BIGGER[id]), 0))
	match id:
		&"hat_banana":
			# A peel flopped on the head: the stalk end up, four flaps hanging down over the crown.
			k.sphere(Vector3(0, 0.2, 0.02), Vector3(0.12, 0.1, 0.11), BANANA, 12, 6)
			k.cylinder(Vector3(0.0, 0.33, 0.02), 0.025, 0.035, 0.08, Color("#6B5A2A"), 8, Basis(Vector3.BACK, 0.25))
			for i: int in 4:
				var a: float = PI * 0.25 + TAU * float(i) / 4.0
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 1.95)  # hanging out and down
				var dir: Vector3 = b * Vector3.UP
				var root := Vector3(0, 0.24, 0.02)
				k.sphere(root + dir * 0.19, Vector3(0.1, 0.22, 0.028), BANANA, 12, 6, b)
				k.sphere(root + dir * 0.19 + b * Vector3(0, 0, -0.014), Vector3(0.082, 0.19, 0.02), CREAM_INSIDE, 10, 5, b)
				k.sphere(root + dir * 0.38, Vector3(0.035, 0.035, 0.03), Color("#5A4A2A"), 6, 3, b)
		&"hat_duel_band":
			# The duel champion's headband: red cloth tied round the head, the knot and its tails at
			# the back, three gold badges on the front: rock, paper, scissors.
			var band := Color("#B8322E")
			k.cylinder(Vector3(0, 0.06, 0), 0.352, 0.356, 0.085, band, 28, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.03, 0), 0.357, 0.357, 0.012, band.darkened(0.25), 28, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.09, 0), 0.355, 0.355, 0.012, band.darkened(0.25), 28, Basis.IDENTITY, D)
			var knot := Vector3(0.0, 0.07, 0.335)
			k.sphere(knot, Vector3(0.055, 0.05, 0.04), band.darkened(0.1), 10, 5)
			for side: float in [-1.0, 1.0]:
				var b := Basis(Vector3.BACK, side * 0.5) * Basis(Vector3.RIGHT, 0.5)
				k.sphere(knot + Vector3(side * 0.05, -0.1, 0.04), Vector3(0.04, 0.13, 0.012), band, 10, 5, b)
				k.sphere(knot + Vector3(side * 0.06, 0.02, 0.0), Vector3(0.06, 0.035, 0.02), band, 10, 5, Basis(Vector3.BACK, side * 0.4))
			for i: int in 3:
				var a: float = PI + (float(i) - 1.0) * 0.42
				var at := Vector3(sin(a) * 0.362, 0.06, cos(a) * 0.362 * D)
				var face := Transform3D(Basis(Vector3.UP, a), at)
				k.prism(OutfitMeshKit.circle_poly(0.045, 18), 0.01, face, OutfitMeshes.GOLD)
				var mark := face.translated_local(Vector3(0, 0, 0.008))
				match i:
					0:  # rock: a round fist-sized pebble
						k.sphere(mark.origin, Vector3(0.026, 0.022, 0.012), OutfitMeshes.BURGUNDY, 10, 5, mark.basis)
					1:  # paper: a sheet
						k.prism(OutfitMeshKit.rect_poly(0.02, 0.027), 0.006, mark, OutfitMeshes.CREAM)
					2:  # scissors: two blades crossed
						for s: float in [-1.0, 1.0]:
							k.prism(OutfitMeshKit.rect_poly(0.006, 0.03), 0.006, mark.rotated_local(Vector3.BACK, s * 0.5), OutfitMeshes.BURGUNDY)
		&"hat_tray":
			# A silver tray balanced on the head, two coupes and a folded napkin on it.
			k.cylinder(Vector3(0, 0.235, 0.0), 0.33, 0.33, 0.018, OutfitMeshes.SILVER, 22)
			k.torus(Vector3(0, 0.248, 0.0), 0.31, 0.345, OutfitMeshes.SILVER.darkened(0.12), 22)
			for g: int in 2:
				var at := Vector3(-0.12 + 0.22 * float(g), 0.25, -0.05 + 0.12 * float(g))
				k.cylinder(at + Vector3(0, 0.01, 0), 0.045, 0.05, 0.012, OutfitMeshes.WHITE, 12)
				k.cylinder(at + Vector3(0, 0.08, 0), 0.008, 0.008, 0.13, OutfitMeshes.WHITE, 6)
				k.cylinder(at + Vector3(0, 0.165, 0), 0.085, 0.02, 0.05, OutfitMeshes.WHITE.darkened(0.06), 14)
				k.cylinder(at + Vector3(0, 0.178, 0), 0.075, 0.06, 0.02, OutfitMeshes.GOLD.lightened(0.25), 14)
			k.prism(PackedVector2Array([Vector2(-0.07, -0.05), Vector2(0.07, -0.05), Vector2(0.0, 0.08)]), 0.04, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.12, 0.25, -0.17)), OutfitMeshes.WHITE)
		&"hat_blast":
			# Hair blown up by the bomb: a frizzy charred mop, embers glowing in it; smoke puffs and
			# sparks keep rising out of it and fade (`spinners`).
			var n: int = 46
			for i: int in n:
				var h: float = OutfitMeshes._hash(i, 1, 41)
				var a: float = TAU * float(i) / float(n) * 7.3
				var el: float = lerpf(0.05, 1.45, sqrt(float(i) / float(n)))
				var r: float = 0.33
				var p := Vector3(sin(a) * cos(el) * r, 0.02 + sin(el) * 0.27, cos(a) * cos(el) * r * D)
				if p.z < -0.24 and p.y < 0.12:
					continue  # keep the forehead clear
				var s: float = lerpf(0.07, 0.11, h)
				k.sphere(p, Vector3(s, s * 0.9, s), INK.darkened(0.35 * h) if h > 0.12 else OutfitMeshes._glow(OutfitMeshes.ORANGE, 0.55), 8, 4)
		&"hat_consolation_crown":
			# Last place still gets a crown: a gold one, a bit crooked, a red velvet cap inside and a
			# big blue participation rosette pinned to the front.
			var crooked := Basis(Vector3.BACK, 0.12)
			var gold := OutfitMeshes.GOLD
			k.dome(crooked * Vector3(0, 0.04, 0), Vector3(0.31, 0.2, 0.28), OutfitMeshes.BURGUNDY, 14, crooked)
			k.cylinder(crooked * Vector3(0, 0.07, 0), 0.35, 0.345, 0.12, gold, 24, crooked, D)
			k.torus(crooked * Vector3(0, 0.015, 0), 0.34, 0.37, gold.darkened(0.2), 24, crooked * Basis.from_scale(Vector3(1, 0.6, D)))
			for i: int in 6:
				var a: float = TAU * float(i) / 6.0
				var base: Vector3 = crooked * Vector3(sin(a) * 0.345, 0.13, cos(a) * 0.345 * D)
				k.cylinder(base + crooked * Vector3(0, 0.07, 0), 0.0, 0.07, 0.15, gold, 4, crooked * Basis(Vector3.UP, a + PI * 0.25))
				k.sphere(base + crooked * Vector3(0, 0.155, 0), Vector3.ONE * 0.026, gold.lightened(0.15), 8, 4)
				k.sphere(crooked * Vector3(sin(a + PI / 6.0) * 0.352, 0.07, cos(a + PI / 6.0) * 0.352 * D), Vector3(0.022, 0.022, 0.012), [OutfitMeshes.RED, OutfitMeshes.TEAL, OutfitMeshes.CREAM][i % 3], 8, 4, crooked * Basis(Vector3.UP, a + PI / 6.0))
			var ros := Transform3D(crooked * Basis(Vector3.UP, PI), crooked * Vector3(-0.12, 0.08, -0.36))
			for side: float in [-1.0, 1.0]:  # the ribbon tails
				k.prism(PackedVector2Array([Vector2(-0.025, 0.0), Vector2(0.025, 0.0), Vector2(0.03, -0.17), Vector2(0.0, -0.14), Vector2(-0.03, -0.17)]), 0.006, ros.rotated_local(Vector3.BACK, side * 0.25).translated_local(Vector3(0, 0, -0.004)), OutfitMeshes.BLUE.darkened(0.15))
			for i: int in 14:  # the pleated ring
				var a: float = TAU * float(i) / 14.0
				k.prism(PackedVector2Array([Vector2(0, 0), Vector2(0.03, -0.018), Vector2(0.075, 0.0), Vector2(0.03, 0.018)]), 0.008, ros.rotated_local(Vector3.BACK, a), OutfitMeshes.BLUE.lightened(0.12 * float(i % 2)))
			k.prism(OutfitMeshKit.circle_poly(0.042, 18), 0.014, ros, OutfitMeshes.GOLD)
			k.prism(OutfitMeshKit.star_poly(5, 0.03, 0.013), 0.02, ros, OutfitMeshes.CREAM)
		&"hat_ice_pack":
			# A rubber ice bag slumped over the head: full of ice on top, flopping down the left side
			# in soft folds, the screw cap sticking up.
			# Built on the head itself (body space), so it lies on the skin with no gap anywhere.
			var keep: Transform3D = k.xf
			k.xf = Transform3D.IDENTITY
			var rim := func(a: float) -> float:  # how far down the head the rim reaches (body t)
				return _ice_rim(a)
			for side: int in 2:
				var at := func(u: float, v: float) -> Vector3:
					var a: float = u * TAU
					var t: float = lerpf(1.0, rim.call(a), v)
					var fold: float = 0.01 * sin(a * 9.0) * v * v
					var full: float = 0.05 * sin(clampf(v * 1.6, 0.0, 1.0) * PI) * (0.6 + 0.4 * cos(a - 2.4))  # the lump of ice
					var r: float = AvatarVisuals.radius_at(t) + (0.014 + fold + (full if side == 0 else 0.0) - (0.0 if side == 0 else 0.008)) * smoothstep(0.0, 0.08, v)
					return Vector3(sin(a) * r, (t - 0.5) * AvatarVisuals.BODY_HEIGHT + 0.012, AvatarVisuals.bend_at(t) - cos(a) * r * AvatarVisuals.BODY_DEPTH)
				var col: Color = ICE if side == 0 else ICE.darkened(0.35)
				k.surface(at, 48, 14, func(u: float, v: float) -> Color:
					if side == 0 and v > 0.15 and OutfitMeshes._hash(int(u * 24.0), int(v * 7.0), 7) > 0.9:
						return ICE.lightened(0.45)  # a few frosted patches
					return col.darkened(0.08) if side == 0 and v > 0.1 and fposmod(v * 6.0, 1.0) < 0.12 else col,
					func(p: Vector3) -> Vector3: return (p - Vector3(0, 0.45, 0)) * (1.0 if side == 0 else -1.0), true)
			# The screw cap where the bag bulges with ice, standing off the bag's surface.
			var ca: float = 2.4
			var ct: float = 0.955
			var cr: float = AvatarVisuals.radius_at(ct) + 0.014 + 0.05 * sin(clampf((1.0 - ct) / (1.0 - rim.call(ca)) * 1.6, 0.0, 1.0) * PI)
			var cp := Vector3(sin(ca) * cr, (ct - 0.5) * AvatarVisuals.BODY_HEIGHT + 0.012, AvatarVisuals.bend_at(ct) - cos(ca) * cr * AvatarVisuals.BODY_DEPTH)
			var cn: Vector3 = (cp - Vector3(0, 0.45, 0)).normalized()
			var cb := Basis(Quaternion(Vector3.UP, cn))
			var cap: Vector3 = cp + cn * 0.01
			k.cylinder(cap, 0.07, 0.075, 0.05, OutfitMeshes.SILVER, 16, cb)
			k.cylinder(cap + cb * Vector3(0, 0.04, 0), 0.06, 0.06, 0.035, OutfitMeshes.SILVER.darkened(0.18), 16, cb)
			for i: int in 3:  # ice cubes showing through the neck
				k.box(cap + cb * Vector3(-0.02 + 0.02 * float(i), 0.065, 0.0), Vector3.ONE * 0.025, OutfitMeshes._glow(Color("#E4F0F7"), 0.2), cb * Basis(Vector3.UP, float(i)))
			# Ice effects: twinkling frost crystals on the bag, meltwater drops along the rim (cold
			# mist sinks from it: `spinners`).
			for i: int in 11:
				var a: float = TAU * float(i) / 11.0 + 0.3 * OutfitMeshes._hash(i, 2, 9)
				var v: float = lerpf(0.25, 0.8, OutfitMeshes._hash(i, 3, 9))
				var p: Vector3 = _ice_point(a, v, 0.004)
				var n: Vector3 = (p - Vector3(0, 0.45, 0)).normalized()
				var b := Basis(Quaternion(Vector3.BACK, n)) * Basis(Vector3.BACK, float(i))
				var sz: float = lerpf(0.02, 0.034, OutfitMeshes._hash(i, 4, 9))
				k.prism(OutfitMeshKit.star_poly(6, sz, sz * 0.32), 0.004, Transform3D(b, p), OutfitMeshes._glow(FROST, 0.7))
			for i: int in 7:
				var a: float = TAU * float(i) / 7.0 + 0.5
				var p: Vector3 = _ice_point(a, 1.0, 0.004) + Vector3(0, -0.012, 0)
				k.sphere(p, Vector3(0.011, 0.016, 0.011), OutfitMeshes._glow(TEAR, 0.35), 6, 4)
			k.xf = keep
		&"hat_star":
			# A gold star floating over the head (it turns: `spinners`), sparkles round it.
			for i: int in 3:
				var a: float = TAU * float(i) / 3.0 + 0.4
				k.sphere(Vector3(sin(a) * 0.2, 0.36 + 0.05 * float(i), cos(a) * 0.2), Vector3.ONE * 0.022, OutfitMeshes._glow(OutfitMeshes.CREAM, 0.6), 6, 3)
		&"hat_trophy":
			var gold := OutfitMeshes.GOLD
			k.cylinder(Vector3(0, 0.2, 0), 0.16, 0.2, 0.07, Color("#2A1E16"), 16)
			k.cylinder(Vector3(0, 0.255, 0), 0.12, 0.14, 0.04, gold.darkened(0.1), 16)
			k.cylinder(Vector3(0, 0.31, 0), 0.03, 0.06, 0.08, gold, 10)
			k.sphere(Vector3(0, 0.36, 0), Vector3(0.05, 0.03, 0.05), gold, 10, 4)
			k.cylinder(Vector3(0, 0.46, 0), 0.19, 0.08, 0.2, gold, 18)
			k.torus(Vector3(0, 0.56, 0), 0.17, 0.2, gold.lightened(0.1), 18)
			for side: float in [-1.0, 1.0]:  # the handles
				k.torus(Vector3(side * 0.18, 0.47, 0), 0.05, 0.08, gold, 12, Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.8, 0.3, 1.2)))
			k.prism(OutfitMeshKit.star_poly(5, 0.05, 0.022), 0.012, Transform3D(Basis(Vector3.RIGHT, -0.2).rotated(Vector3.UP, PI), Vector3(0, 0.45, -0.15)), OutfitMeshes._glow(OutfitMeshes.CREAM, 0.4))
		&"hat_card_house":
			# A house of cards stacked like a real one: pairs of cards leaning on each other in
			# A-frames, a flat card across them, a third A-frame on top. Turned an eighth round so
			# the A-frames and the card backs both show from the front.
			var turn := Basis(Vector3.UP, PI * 0.25)
			var place := func(at: Vector3, lean: float) -> void:
				var b: Basis = turn * Basis(Vector3.BACK, lean)
				var p: Vector3 = turn * at
				k.box(p, Vector3(0.01, 0.2, 0.14), OutfitMeshes.CREAM, b)
				for side: float in [-1.0, 1.0]:  # the card's back pattern shows on both faces
					var out: Vector3 = b * Vector3(side * 0.006, 0, 0)
					k.box(p + out, Vector3(0.004, 0.176, 0.118), OutfitMeshes.BURGUNDY, b)
					k.box(p + out * 1.3, Vector3(0.004, 0.036, 0.036), OutfitMeshes.GOLD, b * Basis(Vector3.RIGHT, PI * 0.25))
			var frame := func(at: Vector3) -> void:  # two cards whose tops meet
				place.call(at + Vector3(-0.038, 0, 0), -0.36)
				place.call(at + Vector3(0.038, 0, 0), 0.36)
			for x: float in [-0.085, 0.085]:
				frame.call(Vector3(x, 0.29, 0))
			k.box(Vector3(0, 0.395, 0), Vector3(0.33, 0.01, 0.15), OutfitMeshes.CREAM, turn)
			k.box(Vector3(0, 0.4005, 0), Vector3(0.3, 0.004, 0.125), OutfitMeshes.BURGUNDY, turn)
			frame.call(Vector3(0, 0.495, 0))
		&"hat_cherries":
			# The slot machine's cherries: two on stalks that meet in a leaf.
			for side: float in [-1.0, 1.0]:
				var c := Vector3(side * 0.1, 0.27, -0.02 + side * 0.03)
				k.sphere(c, Vector3(0.1, 0.095, 0.1), CHERRY, 14, 7)
				k.sphere(c + Vector3(-0.03, 0.04, -0.06), Vector3(0.025, 0.02, 0.012), OutfitMeshes._glow(OutfitMeshes.WHITE, 0.3), 6, 3)
				OutfitMeshes._tube(k, PackedVector3Array([c + Vector3(0, 0.08, 0), c + Vector3(-side * 0.03, 0.18, 0.0), Vector3(0, 0.46, 0.02)]), 0.012, OutfitMeshes.GREEN.darkened(0.2))
			k.sphere(Vector3(0.07, 0.47, 0.02), Vector3(0.09, 0.012, 0.045), OutfitMeshes.GREEN, 10, 3, Basis(Vector3.BACK, -0.4))
		&"hat_plinko":
			# A little Plinko board standing on the head: a wooden triangle full of gold pegs; a chip
			# keeps dropping through them into the slots (`spinners`).
			var face := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.17, 0.0))
			k.prism(PackedVector2Array([Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.0, 0.48)]), 0.05, face, OutfitMeshes.BURGUNDY)
			k.prism(PackedVector2Array([Vector2(-0.33, -0.01), Vector2(0.33, -0.01), Vector2(0.0, 0.52)]), 0.04, face.translated_local(Vector3(0, 0, -0.012)), OutfitMeshes.GOLD.darkened(0.25))
			k.box(Vector3(0, 0.18, 0), Vector3(0.66, 0.035, 0.08), WOOD)
			for row: int in PLINKO_ROWS:
				for j: int in row + 1:
					k.cylinder(_plinko_peg(row, j) + Vector3(0, 0, -0.005), 0.011, 0.011, 0.06, OutfitMeshes.GOLD, 6, Basis(Vector3.RIGHT, PI * 0.5))
			for j: int in 6:  # the slots at the bottom, the middle ones lit
				k.box(Vector3(-0.25 + float(j) * 0.1, 0.22, -0.035), Vector3(0.012, 0.05, 0.035), OutfitMeshes.GOLD.darkened(0.2))
			for j: int in 5:
				k.box(Vector3(-0.2 + float(j) * 0.1, 0.205, -0.03), Vector3(0.08, 0.016, 0.02), OutfitMeshes._glow([OutfitMeshes.RED, OutfitMeshes.GOLD, OutfitMeshes.CREAM, OutfitMeshes.GOLD, OutfitMeshes.RED][j], 0.4))
		&"hat_full_house":
			# A tiny house: cream walls, a red roof, a chimney, a door and lit windows.
			k.box(Vector3(0, 0.29, 0), Vector3(0.36, 0.2, 0.3), OutfitMeshes.CREAM)
			for side: float in [-1.0, 1.0]:
				k.box(Vector3(side * 0.1, 0.45, 0), Vector3(0.26, 0.03, 0.36), OutfitMeshes.RED.darkened(0.1), Basis(Vector3.BACK, -side * 0.62))
			k.box(Vector3(0.1, 0.5, 0.06), Vector3(0.05, 0.12, 0.05), OutfitMeshes.BROWN)
			k.box(Vector3(0, 0.25, -0.152), Vector3(0.07, 0.12, 0.01), OutfitMeshes.BROWN)
			for side: float in [-1.0, 1.0]:
				k.box(Vector3(side * 0.11, 0.31, -0.152), Vector3(0.06, 0.06, 0.01), OutfitMeshes._glow(OutfitMeshes.YELLOW, 0.5))
			k.box(Vector3(0, 0.19, 0), Vector3(0.4, 0.02, 0.34), OutfitMeshes.GREEN.darkened(0.1))
		&"hat_beacon":
			# The amber light on top of a slot machine that pays the jackpot (its lamp turns: `spinners`).
			k.cylinder(Vector3(0, 0.21, 0), 0.15, 0.17, 0.05, OutfitMeshes.BLACK, 16)
			k.cylinder(Vector3(0, 0.3, 0), 0.12, 0.12, 0.14, OutfitMeshes._glow(AMBER, 0.35), 16)
			k.dome(Vector3(0, 0.37, 0), Vector3(0.12, 0.08, 0.12), OutfitMeshes._glow(AMBER, 0.35), 16)
			k.torus(Vector3(0, 0.235, 0), 0.12, 0.15, OutfitMeshes.SILVER, 16)
		&"hat_logo":
			# A twinkle of gold dust where the logo hovers (the logo and its chips move: `spinners`).
			for i: int in 7:
				var a: float = TAU * float(i) / 7.0
				k.sphere(Vector3(sin(a) * 0.18, 0.36 + 0.05 * sin(a * 3.0), cos(a) * 0.18), Vector3.ONE * 0.014, OutfitMeshes._glow(OutfitMeshes.CREAM, 0.7), 6, 3)


## Plinko pegs: rows from the top, in hat space.
const PLINKO_ROWS: int = 4


static func _plinko_peg(row: int, j: int) -> Vector3:
	return Vector3((float(j) - float(row) * 0.5) * 0.12, 0.56 - float(row) * 0.085, -0.04)


## A moving part on a hat (`OutfitMeshes._hat_spinner` plus a looped path, hat space).
static func _hat_mover(k: OutfitMeshKit, at: Vector3, axis_local: Vector3, speed: float, path_local: PackedVector3Array, period: float) -> Dictionary:
	var hat := Transform3D(Basis(Vector3.RIGHT, OutfitMeshes.HAT_TILT), OutfitMeshes.HAT_BASE)
	var path := PackedVector3Array()
	for q: Vector3 in path_local:
		path.append(hat.basis * q)
	return {"mesh": k.commit(), "origin": hat * at, "axis": (hat.basis * axis_local).normalized(), "speed": speed, "path": path, "period": period}


## Where greedy eyes look, in turn (x sideways, y up), each glance held a moment: ahead, one way,
## the other, down at the money, up, and back.
const GREEDY_LOOKS: Array[Vector2] = [Vector2(0, 0), Vector2(0, 0), Vector2(0.32, 0.04), Vector2(0.32, 0.04), Vector2(0.32, 0.04),
	Vector2(-0.32, 0.04), Vector2(-0.32, 0.04), Vector2(-0.32, 0.04), Vector2(0.08, -0.3), Vector2(0.08, -0.3), Vector2(0.08, -0.3),
	Vector2(-0.22, 0.22), Vector2(-0.22, 0.22), Vector2(0, 0)]


## The ice pack's rim, as body height t, and a point on its outer side (body space): `v` 0 at
## the top of the head to 1 at the rim, `lift` off the bag.
static func _ice_rim(a: float) -> float:
	return lerpf(0.9, 0.8, smoothstep(-0.2, 1.0, sin(a))) + 0.012 * sin(a * 3.0 + 1.0)


static func _ice_point(a: float, v: float, lift: float) -> Vector3:
	var t: float = lerpf(1.0, _ice_rim(a), v)
	var fold: float = 0.01 * sin(a * 9.0) * v * v
	var full: float = 0.05 * sin(clampf(v * 1.6, 0.0, 1.0) * PI) * (0.6 + 0.4 * cos(a - 2.4))
	var r: float = AvatarVisuals.radius_at(t) + (0.014 + fold + full) * smoothstep(0.0, 0.08, v) + lift
	return Vector3(sin(a) * r, (t - 0.5) * AvatarVisuals.BODY_HEIGHT + 0.012, AvatarVisuals.bend_at(t) - cos(a) * r * AvatarVisuals.BODY_DEPTH)


## Where the party horn's mouthpiece sits (body space).
static func _horn_mouth() -> Vector3:
	var my: float = OutfitMeshes._mouth_y()
	return Vector3(0.0, my, AvatarVisuals.face_z(my, 0.0) + 0.01)


## The party horn's tube: segment `i` of `n` when it is rolled up by `curl` (0 straight out, 1 a
## full roll), from the mouthpiece forward, curling downward and back under (body space).
static func _horn_point(i: int, n: int, curl: float) -> Vector3:
	const LENGTH: float = 0.42
	var ds: float = LENGTH / float(n)
	var p: Vector3 = _horn_mouth() + Vector3(0, 0, -0.07)
	var theta: float = 0.0
	for j: int in i:
		var s: float = (float(j) + 0.5) / float(n)
		theta += curl * lerpf(2.0, 34.0, s * s) * ds
		p += Vector3(0, -sin(theta), -cos(theta)) * ds
	return p


## A tear's way down the cheek under eye `side` at `s` (0 under the eye .. 1 the jaw), `lift` off
## the skin (body space).
static func _tear_point(side: float, s: float, lift: float) -> Vector3:
	var r: float = AvatarVisuals.EYE_RADIUS
	var e: Vector3 = OutfitMeshes._eye_center(side)
	var x: float = e.x + side * (r * 0.5 + s * 0.03)
	var y: float = e.y - r * 0.85 - s * 0.22
	return Vector3(x, y, AvatarVisuals.face_z(y, x) - lift)


static func spinners(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match id:
		&"mouth_party_horn":
			# Every 10 s the tube rolls out straight, holds, and rolls back in (keys every 0.5 s).
			const N: int = 22
			var curls: PackedFloat32Array = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0.55, 0.12, 0, 0, 0, 0.3, 0.7, 1, 1]
			for i: int in N:
				var k := OutfitMeshKit.new()
				k.sphere(Vector3.ZERO, Vector3.ONE * 0.03, [OutfitMeshes.RED, OutfitMeshes.GOLD, OutfitMeshes.CREAM][(i / 2) % 3], 8, 4)
				if i == N - 1:
					k.sphere(Vector3.ZERO, Vector3.ONE * 0.034, OutfitMeshes.GOLD, 8, 4)
				var origin: Vector3 = _horn_point(i + 1, N, 1.0)
				var path := PackedVector3Array()
				for c: float in curls:
					path.append(_horn_point(i + 1, N, c) - origin)
				out.append({"mesh": k.commit(), "origin": origin, "axis": Vector3.UP, "speed": 0.0, "path": path, "period": 10.0})
		&"eyes_tears":
			# Tears well up under each eye, roll down the cheek and drop off at the jaw.
			for side: float in [-1.0, 1.0]:
				for i: int in 3:
					var k := OutfitMeshKit.new()
					k.sphere(Vector3.ZERO, Vector3(0.02, 0.027, 0.014), OutfitMeshes._glow(TEAR, 0.3), 8, 5)
					var origin: Vector3 = _tear_point(side, 0.0, 0.01)
					var path := PackedVector3Array()
					for j: int in 9:
						path.append(_tear_point(side, float(j) / 8.0, 0.01) - origin)
					path.append(path[path.size() - 1] + Vector3(0, -0.08, -0.02))  # falls off
					out.append({"mesh": k.commit(), "origin": origin, "axis": Vector3.UP, "speed": 0.0, "path": path,
							"period": 2.4, "scales": PackedFloat32Array([0.2, 0.9, 1, 1, 1, 1, 1, 1, 1, 0.0]), "phase": float(i) / 3.0 + (0.15 if side > 0.0 else 0.0)})
		&"hat_ice_pack":
			# Cold mist rolls off the ice bag's rim, sinks along the head and fades (body space).
			for i: int in 5:
				var a: float = TAU * float(i) / 5.0 + 0.9
				var k := OutfitMeshKit.new()
				k.sphere(Vector3.ZERO, Vector3(0.034, 0.02, 0.034), OutfitMeshes._glow(ICE.lightened(0.55), 0.3), 8, 4)
				k.sphere(Vector3(0.022, 0.004, 0.008), Vector3(0.022, 0.014, 0.022), OutfitMeshes._glow(ICE.lightened(0.7), 0.3), 6, 3)
				var start: Vector3 = _ice_point(a, 1.0, 0.012)
				var outward := Vector3(sin(a), 0, -cos(a)) * 0.02
				var path := PackedVector3Array([Vector3.ZERO, outward * 0.5 + Vector3(0, -0.05, 0), outward + Vector3(0, -0.11, 0), outward * 1.3 + Vector3(0, -0.16, 0)])
				out.append({"mesh": k.commit(), "origin": start, "axis": Vector3.UP, "speed": 0.4, "path": path, "period": 3.2,
						"scales": PackedFloat32Array([0.2, 0.9, 1.0, 0.0]), "phase": float(i) / 5.0})
		&"eyes_bulging":
			# The pupils dart round the bulging eyeballs (body space, like `eyes`).
			var r: float = AvatarVisuals.EYE_RADIUS
			for side: float in [-1.0, 1.0]:
				var e: Vector3 = OutfitMeshes._eye_center(side)
				var c := Vector3(e.x * 1.12, e.y + 0.01, e.z - r * 0.55)
				var k := OutfitMeshKit.new()
				k.sphere(Vector3.ZERO, Vector3(r * 0.55, r * 0.55, r * 0.2), OutfitMeshes.BLACK, 12, 6)
				k.sphere(Vector3(0, 0, -r * 0.1), Vector3(r * 0.32, r * 0.32, r * 0.1), OutfitMeshes._glow(OutfitMeshes.GOLD, 0.4), 10, 5)
				k.sphere(Vector3(r * 0.25, r * 0.26, -r * 0.15), Vector3.ONE * r * 0.1, OutfitMeshes.WHITE, 6, 3)
				var origin: Vector3 = c + Vector3(0, -0.01, -r * 1.15)
				var path := PackedVector3Array()
				for look: Vector2 in GREEDY_LOOKS:
					var dir := Vector3(look.x, look.y - 0.01 / (r * 1.15), -1.0).normalized()
					path.append(c + dir * r * 1.15 - origin)
				out.append({"mesh": k.commit(), "origin": origin, "axis": Vector3.UP, "speed": 0.0, "path": path, "period": 5.2})
		&"hat_blast":
			# Smoke puffs rise out of the singed hair, swell and fade; sparks fly up with them.
			for i: int in 3:
				var k := OutfitMeshKit.new()
				k.sphere(Vector3.ZERO, Vector3.ONE * 0.08, Color("#8A8580"), 10, 5)
				k.sphere(Vector3(0.05, 0.03, 0.02), Vector3.ONE * 0.055, Color("#9C978F"), 8, 4)
				var x: float = -0.12 + float(i) * 0.12
				var path := PackedVector3Array([Vector3.ZERO, Vector3(x * 0.3, 0.12, 0.0), Vector3(x * 0.6, 0.26, 0.02), Vector3(x * 0.8, 0.36, 0.03)])
				var sp: Dictionary = _hat_mover(k, Vector3(x, 0.36, 0.04), Vector3.UP, 0.8 - 0.5 * float(i), path, 2.4)
				sp["scales"] = PackedFloat32Array([0.3, 1.0, 1.15, 0.0])
				sp["phase"] = float(i) / 3.0
				out.append(sp)
			for i: int in 4:
				var k := OutfitMeshKit.new()
				k.sphere(Vector3.ZERO, Vector3.ONE * 0.022, OutfitMeshes._glow(OutfitMeshes.ORANGE, 0.9), 6, 3)
				var a: float = TAU * float(i) / 4.0 + 0.4
				var path := PackedVector3Array([Vector3.ZERO, Vector3(sin(a) * 0.06, 0.1, cos(a) * 0.06), Vector3(sin(a) * 0.14, 0.17, cos(a) * 0.14)])
				var sp: Dictionary = _hat_mover(k, Vector3(sin(a) * 0.12, 0.3, cos(a) * 0.1), Vector3.UP, 0.0, path, 1.3)
				sp["scales"] = PackedFloat32Array([1.0, 0.8, 0.0])
				sp["phase"] = float(i) / 4.0
				out.append(sp)
		&"hat_star":
			var k := OutfitMeshKit.new()
			k.prism(OutfitMeshKit.star_poly(5, 0.16, 0.07), 0.06, Transform3D.IDENTITY, OutfitMeshes.GOLD)
			k.prism(OutfitMeshKit.star_poly(5, 0.11, 0.05), 0.07, Transform3D.IDENTITY, OutfitMeshes._glow(OutfitMeshes.YELLOW, 0.5))
			out.append(OutfitMeshes._hat_spinner(k, Vector3(0, 0.45, 0), 1.6))
		&"hat_beacon":
			var k := OutfitMeshKit.new()
			k.xf = Transform3D(Basis.from_scale(Vector3.ONE * BIGGER[id]), Vector3.ZERO)
			for side: float in [-1.0, 1.0]:  # two bright lamp faces sweeping round inside the dome
				k.box(Vector3(side * 0.08, 0.0, 0), Vector3(0.06, 0.1, 0.12), OutfitMeshes._glow(Color("#FFD27A"), 0.95))
			out.append(OutfitMeshes._hat_spinner(k, Vector3(0, 0.2 + 0.1 * BIGGER[id], 0), 6.0))
		&"hat_plinko":
			var k := OutfitMeshKit.new()
			k.cylinder(Vector3.ZERO, 0.04, 0.04, 0.016, OutfitMeshes.RED, 16, Basis(Vector3.RIGHT, PI * 0.5))
			for i: int in 6:  # the chip's edge spots
				var a: float = TAU * float(i) / 6.0
				k.box(Vector3(cos(a) * 0.036, sin(a) * 0.036, 0), Vector3(0.012, 0.012, 0.018), OutfitMeshes.CREAM, Basis(Vector3.BACK, a))
			# Bounce off a peg in every row (left, right, right, left), land in a slot, wait, again.
			var path := PackedVector3Array()
			var top := Vector3(0, 0.66, -0.07)
			path.append(top)
			var x: float = 0.0
			var turns: Array[float] = [-1.0, 1.0, 1.0, -1.0]
			for row: int in PLINKO_ROWS:
				var y: float = _plinko_peg(row, 0).y
				path.append(Vector3(x, y + 0.045, -0.07))
				x += turns[row] * 0.06
				path.append(Vector3(x, y - 0.02, -0.07))
			path.append(Vector3(x, 0.24, -0.07))
			for i: int in 4:
				path.append(Vector3(x, 0.24, -0.07))
			var rel := PackedVector3Array()
			for q: Vector3 in path:
				rel.append(q - top)
			out.append(_hat_mover(k, top, Vector3.BACK, 7.0, rel, 2.6))
		&"hat_logo":
			# The menu logo in miniature: a gold coin with the burgundy banner, hovering and turning
			# over the head, three chips circling it the other way.
			var k := OutfitMeshKit.new()
			k.cylinder(Vector3.ZERO, 0.2, 0.2, 0.045, OutfitMeshes.GOLD, 28, Basis(Vector3.RIGHT, PI * 0.5))
			k.torus(Vector3.ZERO, 0.175, 0.205, OutfitMeshes.GOLD.darkened(0.25), 28, Basis(Vector3.RIGHT, PI * 0.5))
			for i: int in 12:  # notches round the coin's edge
				var a: float = TAU * float(i) / 12.0
				k.box(Vector3(cos(a) * 0.2, sin(a) * 0.2, 0), Vector3(0.026, 0.026, 0.05), OutfitMeshes.GOLD.lightened(0.15), Basis(Vector3.BACK, a))
			k.box(Vector3(0, 0.0, 0), Vector3(0.5, 0.12, 0.07), OutfitMeshes.BURGUNDY)
			for side: float in [-1.0, 1.0]:  # the banner's folded ends
				k.prism(PackedVector2Array([Vector2(0, 0.045), Vector2(side * 0.06, 0.045), Vector2(side * 0.035, 0.0), Vector2(side * 0.06, -0.045), Vector2(0, -0.045)]), 0.045, Transform3D(Basis.IDENTITY, Vector3(side * 0.25, -0.015, -0.02)), OutfitMeshes.BURGUNDY.darkened(0.25))
			for s: float in [-1.0, 1.0]:
				var face := Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(0, -0.03, 0.038 * s))
				OutfitMeshes._glyph(k, "BETTER AT GAMBLING", face, OutfitMeshes.CREAM, 0.056)
			var bob := PackedVector3Array()
			for i: int in 17:
				bob.append(Vector3(0, 0.03 * sin(TAU * float(i) / 16.0), 0))
			out.append(_hat_mover(k, Vector3(0, 0.6, 0), Vector3.UP, 2.2, bob, 2.4))
			var ring := OutfitMeshKit.new()
			for i: int in 3:
				var a: float = TAU * float(i) / 3.0
				var c := Vector3(sin(a) * 0.36, 0.0, cos(a) * 0.36)
				ring.cylinder(c, 0.06, 0.06, 0.018, [OutfitMeshes.RED, OutfitMeshes.CREAM, OutfitMeshes.BLUE][i], 14, Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI * 0.5))
				ring.sphere(c * 0.8, Vector3.ONE * 0.012, OutfitMeshes._glow(OutfitMeshes.GOLD, 0.6), 6, 3)
			out.append(OutfitMeshes._hat_spinner(ring, Vector3(0, 0.58, 0), -1.4))
	return out


const CREAM_INSIDE := Color("#F3E9C2")


static func shirt(k: OutfitMeshKit, id: StringName) -> void:
	var top: Callable = OutfitMeshes._shirt_top()
	var b: float = OutfitMeshes.SHIRT_BOTTOM
	var inf: float = OutfitMeshes.SHIRT_INFLATE
	match id:
		&"shirt_varsity":
			# A letterman jacket: burgundy wool, cream sleeves (`SLEEVES`), striped rib knit, a chip patch.
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if t < b + 0.03 or top.call(a) - t < 0.022:
					return OutfitMeshes.CREAM if int(floor(t / 0.008)) % 3 == 0 else VARSITY.darkened(0.2)
				if OutfitMeshes._front(a) < 0.012:
					return VARSITY.darkened(0.25)
				return VARSITY, 0.03)
			for t: float in [0.22, 0.27, 0.32, 0.37]:
				OutfitMeshes._button(k, t, 0.0, inf + 0.004, OutfitMeshes.CREAM, 0.013)
			var f: Transform3D = OutfitMeshKit.body_frame(0.33, -0.55, inf + 0.004)
			k.prism(OutfitMeshKit.circle_poly(0.07, 20), 0.008, f, OutfitMeshes.CREAM)
			k.prism(OutfitMeshKit.circle_poly(0.055, 20), 0.012, f, OutfitMeshes.RED)
			for i: int in 6:
				var a: float = TAU * float(i) / 6.0
				k.prism(OutfitMeshKit.rect_poly(0.008, 0.012), 0.014, f.translated_local(Vector3(cos(a) * 0.045, sin(a) * 0.045, 0)).rotated_local(Vector3.BACK, a), OutfitMeshes.CREAM)
			OutfitMeshes._glyph(k, "W", f.translated_local(Vector3(0, -0.02, 0.012)), OutfitMeshes.GOLD, 0.075)
			OutfitMeshes._glyph(k, "10", OutfitMeshKit.body_frame(0.3, PI, inf + 0.004).translated_local(Vector3(0, -0.02, 0.03)), OutfitMeshes.CREAM, 0.2)
		&"shirt_cash_vest":
			# A waistcoat sewn from banknotes over a white shirt, notes sticking out of the pockets.
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if OutfitMeshes._in_v(t, a, 0.45, 0.24):
					return OutfitMeshes.WHITE
				# Banknotes laid in brick rows: a dark edge, a pale band with the portrait in the middle.
				var i: int = int(floor(t / 0.06))
				var sh: float = 0.2 * float(i % 2)
				var j: int = int(floor((a + PI + sh) / 0.4))
				var lt: float = fposmod(t, 0.06) / 0.06
				var la: float = fposmod(a + PI + sh, 0.4) / 0.4
				if lt < 0.08 or la < 0.04:
					return MONEY.darkened(0.45)
				if lt < 0.18 or lt > 0.9 or la < 0.1 or la > 0.94:
					return MONEY.darkened(0.15)
				if Vector2((la - 0.5) * 2.2, (lt - 0.52) * 1.3).length() < 0.3:
					return OutfitMeshes.CREAM.darkened(0.1)
				return MONEY.lightened(0.06 * OutfitMeshes._hash(i, j, 5)), 0.03)
			OutfitMeshes._bow_tie(k, OutfitMeshes.BLACK)
			for t: float in [0.2, 0.25]:
				OutfitMeshes._button(k, t, 0.0, inf + 0.004, OutfitMeshes.GOLD)
			for side: float in [-1.0, 1.0]:
				var f: Transform3D = OutfitMeshKit.body_frame(0.23, side * 0.55, inf + 0.01)
				for n: int in 3:
					k.box(f * Vector3((float(n) - 1.0) * 0.02, 0.03 + 0.008 * float(n), 0.004 * float(n)), Vector3(0.07, 0.05, 0.004), MONEY.lightened(0.1 * float(n)), f.basis * Basis(Vector3.BACK, (float(n) - 1.0) * 0.2))
			OutfitMeshes._glyph(k, "$", OutfitMeshKit.body_frame(0.3, PI, inf + 0.004).translated_local(Vector3(0, -0.02, 0.03)), OutfitMeshes.GOLD, 0.22)
		&"shirt_harlequin":
			# A harlequin's diamonds in burgundy, gold and cream, a pleated ruff at the neck.
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				var u: float = (a + PI) / (TAU / 10.0)
				var v: float = t / 0.06
				var i: int = int(floor(u + v))
				var j: int = int(floor(u - v))
				var lu: float = fposmod(u + v, 1.0)
				var lv: float = fposmod(u - v, 1.0)
				if lu < 0.06 or lv < 0.06:
					return OutfitMeshes.BLACK
				return [OutfitMeshes.BURGUNDY, OutfitMeshes.GOLD, OutfitMeshes.CREAM][posmod(i + j * 2, 3)], 0.0, 40, 24)
			for i: int in 20:
				var a: float = TAU * float(i) / 20.0
				var p: Vector3 = OutfitMeshKit.body_point(OutfitMeshes._shirt_top().call(a) - 0.008, a, inf + 0.012)
				k.sphere(p, Vector3(0.046, 0.024, 0.046), OutfitMeshes.WHITE.darkened(0.06 * float(i % 2)), 7, 4, Basis(Vector3.UP, a))
		&"shirt_gold_chain":
			# The high roller's black silk shirt, open to the chest, a heavy gold chain.
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if OutfitMeshes._in_v(t, a, 0.42, 0.27):
					return Color(0, 0, 0, 0)  # open
				if OutfitMeshes._in_v(t, a, 0.5, 0.265):
					return Color("#3A3330")  # the collar's edge
				return Color("#1C1A19").lightened(0.06 * pow(maxf(sin(a * 3.0 + t * 20.0), 0.0), 4.0)))
			OutfitMeshes._collar_points(k, Color("#3A3330"))
			for i: int in 26:
				var s: float = float(i) / 25.0
				var a: float = lerpf(-0.75, 0.75, s)
				var t: float = 0.38 - 0.09 * (1.0 - pow((s - 0.5) * 2.0, 2.0))
				var f: Transform3D = OutfitMeshKit.body_frame(t, a, inf + 0.012)
				k.torus(f.origin, 0.008, 0.02, OutfitMeshes.GOLD, 8, f.basis * Basis(Vector3.UP, PI * 0.5 * float(i % 2)) * Basis(Vector3.RIGHT, PI * 0.5))
			var pend: Transform3D = OutfitMeshKit.body_frame(0.285, 0.0, inf + 0.02)
			k.prism(OutfitMeshKit.circle_poly(0.04, 18), 0.012, pend, OutfitMeshes.GOLD)
			OutfitMeshes._glyph(k, "$", pend.translated_local(Vector3(0, -0.012, 0.008)), OutfitMeshes.BURGUNDY, 0.06)


static func pants(k: OutfitMeshKit, id: StringName) -> void:
	var inf: float = OutfitMeshes.PANTS_INFLATE
	match id:
		&"pants_barrel":
			# Lost it all: a wooden barrel held up by rope straps over the shoulders.
			var at := func(u: float, v: float) -> Vector3:
				var a: float = (u - 0.5) * TAU
				var t: float = lerpf(-0.02, 0.33, v)
				var bulge: float = 0.06 * sin(PI * v)
				var r: float = 0.5 + bulge
				return Vector3(sin(a) * r, (OutfitMeshKit.body_t(t) - 0.5) * AvatarVisuals.BODY_HEIGHT, AvatarVisuals.bend_at(OutfitMeshKit.body_t(t)) - cos(a) * r * 0.92)
			var paint := func(u: float, v: float) -> Color:
				if absf(v - 0.12) < 0.03 or absf(v - 0.88) < 0.03:
					return HOOP
				var stave: int = int(floor(u * 22.0))
				if fposmod(u * 22.0, 1.0) < 0.07:
					return WOOD.darkened(0.35)
				return WOOD.lightened(0.08 * OutfitMeshes._hash(stave, 1, 77))
			k.surface(at, 44, 12, paint, func(p: Vector3) -> Vector3: return Vector3(p.x, 0.0, p.z + 0.03), true)
			k.surface(at, 44, 2, func(_u: float, _v: float) -> Color: return WOOD.darkened(0.5), func(p: Vector3) -> Vector3: return -Vector3(p.x, 0.0, p.z + 0.03), true, false)
			OutfitMeshes._suspenders(k, Color("#B39B6E"), 0.35)
		&"pants_green_zero":
			# Felt-green trousers with a gold side stripe and a big zero on each leg.
			k.band(0.0, OutfitMeshKit.level(OutfitMeshes.PANTS_TOP), inf, func(t: float, a: float) -> Color:
				if t > 0.178:
					return OutfitMeshes.GOLD.darkened(0.15)
				if absf(OutfitMeshes._front(a) - PI * 0.5) < 0.05:
					return OutfitMeshes.GOLD
				return OutfitMeshes.FELT)
			for side: float in [-1.0, 1.0]:
				var f: Transform3D = OutfitMeshKit.body_frame(0.12, side * 0.45, inf + 0.004)
				k.prism(OutfitMeshKit.circle_poly(0.085, 22), 0.006, f, OutfitMeshes.CREAM)
				OutfitMeshes._glyph(k, "0", f.translated_local(Vector3(0, -0.05, 0.004)), OutfitMeshes.FELT.darkened(0.2), 0.16)
			OutfitMeshes._buckle(k, OutfitMeshes.GOLD)


static func cape(k: OutfitMeshKit, id: StringName) -> void:
	match id:
		&"cape_carpet":
			# Fifty matches on the floor: the casino's own carpet. An even field of gold diamonds with
			# teal hearts, small gold diamonds where their corners meet, inside a clean gold-and-dark
			# border; symmetric left to right, whole motifs only.
			OutfitMeshes._cape_sheet(k, -0.78, func(u: float, v: float) -> Color:
				var e: float = minf(minf(u, 1.0 - u), 1.0 - v)  # distance to the sides and the hem
				if e < 0.03:
					return OutfitMeshes.GOLD.darkened(0.1)
				if e < 0.065:
					return OutfitMeshes.BURGUNDY.darkened(0.35)
				if e < 0.08:
					return OutfitMeshes.GOLD.darkened(0.2)
				var fu: float = (u - 0.08) / 0.84 * 5.0
				var fv: float = (v - 0.02) / 0.9 * 6.0
				var x: float = fposmod(fu, 1.0) - 0.5
				var y: float = fposmod(fv, 1.0) - 0.5
				var d: float = absf(x) + absf(y)
				if absf(d - 0.36) < 0.045:
					return OutfitMeshes.GOLD
				if d < 0.13:
					return OutfitMeshes.TEAL.darkened(0.15)
				if d < 0.19:
					return OutfitMeshes.GOLD.darkened(0.2)
				if d > 0.88:
					return OutfitMeshes.GOLD.darkened(0.1)  # where four tiles meet
				return OutfitMeshes.BURGUNDY, OutfitMeshes.BURGUNDY.darkened(0.4), 42, 30)
			OutfitMeshes._clasps(k, OutfitMeshes.GOLD)
		&"cape_suited_trips":
			# The cape ends in three identical seven of hearts fanned out (the cloth itself is cut
			# into the cards), midnight velvet above.
			_card_fan_cape(k, ["7", "7", "7"], true, Color("#1A2235"), 0.32)
		&"cape_royal_flush":
			# The best hand there is: the cape ends in ten to ace of spades fanned out, black satin
			# with a gold collar above.
			OutfitMeshes._cape_collar(k, OutfitMeshes.GOLD, OutfitMeshes.BLACK, 0.12)
			_card_fan_cape(k, ["10", "J", "Q", "K", "A"], false, OutfitMeshes.BLACK, 0.22)


## A cape whose lower part is a fan of playing cards cut out of the cloth: `ranks` left to right
## (seen from behind), hearts or spades, `spread` radians between cards; the cloth above in `top`.
static func _card_fan_cape(k: OutfitMeshKit, ranks: Array, hearts: bool, top: Color, spread: float) -> void:
	const BOTTOM: float = -0.8
	const W: float = 1.15  # metres-ish across the cape (u) and down it (v), for the card shapes
	const H: float = 1.0
	const CW: float = 0.15  # half a card
	const CH: float = 0.24
	var n: int = ranks.size()
	var pivot := Vector2(0.0, 1.0)  # below the hem: the cards turn about the hand that holds them
	var pip_col: Color = OutfitMeshes.RED if hearts else OutfitMeshes.BLACK
	# Card i's own coordinates at cape point (x, y): x right (seen from behind), y down the card.
	var local := func(i: int, x: float, y: float) -> Vector2:
		var a: float = (float(i) - float(n - 1) * 0.5) * spread
		var centre: Vector2 = pivot + Vector2(sin(a), -cos(a)) * 0.42
		var d := Vector2(x, y) - centre
		return Vector2(d.x * cos(a) + d.y * sin(a), -d.x * sin(a) + d.y * cos(a))
	var pip := func(q: Vector2, s: float) -> bool:  # a heart or spade, `s` across, at q
		var p := q / s
		if not hearts:
			p.y = -p.y + 0.35  # a little higher: the stem hangs below
			if p.y < -0.55 and p.y > -1.3 and absf(p.x) < 0.07 + (-0.55 - p.y) * 0.45:
				return true  # the spade's stem, flaring at its foot
		var x: float = p.x * 1.15
		var y: float = -p.y * 1.15 + 0.2
		return pow(x * x + y * y - 1.0, 3.0) - x * x * y * y * y <= 0.0
	var paint := func(u: float, v: float) -> Color:
		var x: float = (0.5 - u) * W
		var y: float = v * H
		for i: int in range(n - 1, -1, -1):  # the last card lies on top
			var q: Vector2 = local.call(i, x, y)
			if absf(q.x) > CW or absf(q.y) > CH:
				continue
			if absf(q.x) > CW - 0.012 or absf(q.y) > CH - 0.012:
				return OutfitMeshes.GOLD  # the gold edge
			if pip.call(q - Vector2(0.0, 0.03), 0.075):
				return pip_col
			for corner: float in [-1.0, 1.0]:  # small pips under the corner index
				if pip.call(q - Vector2(corner * (CW - 0.04), corner * (CH - 0.1)), 0.022):
					return pip_col
			return OutfitMeshes.WHITE
		if y < 0.42:
			return OutfitMeshes.GOLD if y > 0.39 or v < 0.03 else top
		return Color(0, 0, 0, 0)  # cut away round the cards
	OutfitMeshes._cape_sheet(k, BOTTOM, paint, OutfitMeshes.BURGUNDY, 72, 48)
	# The corner indices, standing on the cloth where each card's corner is, like on real cards:
	# top left upright, bottom right turned half round. Only where no card above covers them.
	var top_card := func(at: Vector2) -> int:
		for j: int in range(n - 1, -1, -1):
			var qq: Vector2 = local.call(j, at.x, at.y)
			if absf(qq.x) <= CW and absf(qq.y) <= CH:
				return j
		return -1
	for i: int in n:
		for corner: float in [-1.0, 1.0]:
			var q := Vector2(corner * (CW - 0.04), corner * (CH - 0.045))
			var a: float = (float(i) - float(n - 1) * 0.5) * spread
			var centre: Vector2 = pivot + Vector2(sin(a), -cos(a)) * 0.42
			var cp: Vector2 = centre + Vector2(q.x * cos(a) - q.y * sin(a), q.x * sin(a) + q.y * cos(a))
			var hidden: bool = false
			for o: Vector2 in [Vector2(-0.03, -0.035), Vector2(0.03, -0.035), Vector2(-0.03, 0.035), Vector2(0.03, 0.035), Vector2.ZERO]:
				var oq: Vector2 = q + o
				if top_card.call(centre + Vector2(oq.x * cos(a) - oq.y * sin(a), oq.x * sin(a) + oq.y * cos(a))) != i:
					hidden = true
			if hidden:
				continue
			var u: float = 0.5 - cp.x / W
			var v: float = cp.y / H
			var p: Vector3 = OutfitMeshes._cape_at(u, v, BOTTOM, 0.012)
			var below: Vector3 = OutfitMeshes._cape_at(u, minf(v + 0.02, 1.0), BOTTOM, 0.012)
			var above: Vector3 = OutfitMeshes._cape_at(u, maxf(v - 0.02, 0.0), BOTTOM, 0.012)
			var up: Vector3 = (above - below).normalized()
			var out := Vector3(p.x, 0.0, p.z + 0.03).normalized()
			out = (out - up * out.dot(up)).normalized()
			var right: Vector3 = up.cross(out).normalized()
			# Text reads from behind: +X to the viewer's right, turned with the card.
			# The card turns by `a` with y down the cloth: seen with y up that is -a.
			var b := Basis(right, up, out) * Basis(Vector3.BACK, -a + (PI if corner > 0.0 else 0.0))
			k.uv2 = Vector2(u, v)
			OutfitMeshes._glyph(k, str(ranks[i]), Transform3D(b, p), OutfitMeshes.RED if hearts else OutfitMeshes.BLACK, 0.055)
	k.uv2 = Vector2.ZERO


static func boots(k: OutfitMeshKit, id: StringName) -> void:
	match id:
		&"boots_rain":
			k.sphere(Vector3(0, -0.005, -0.02), Vector3(0.12, 0.08, 0.18), OutfitMeshes.YELLOW, 12, 6)
			OutfitMeshes._sole(k, Vector3(0, -0.058, -0.02), Vector3(0.21, 0.022, 0.31), Color("#3A3533"))
			k.cylinder(Vector3(0, 0.13, 0.03), 0.105, 0.098, 0.22, OutfitMeshes.YELLOW, 12)
			k.torus(Vector3(0, 0.24, 0.03), 0.095, 0.115, OutfitMeshes.YELLOW.darkened(0.12), 12)
			for i: int in 3:  # puddle splashes
				var a: float = 0.8 + float(i) * 0.9
				k.sphere(Vector3(sin(a) * 0.16, -0.04, cos(a) * 0.2), Vector3(0.02, 0.03, 0.02), OutfitMeshes._glow(TEAR, 0.3), 6, 3)
		&"boots_ball_chain":
			_shoe_plain(k, Color("#6E6A64"), Color("#3A3533"))
			k.torus(Vector3(0, 0.07, 0.03), 0.09, 0.115, OutfitMeshes.STEEL.darkened(0.2), 14)
			k.torus(Vector3(0.0, 0.07, 0.125), 0.012, 0.024, OutfitMeshes.STEEL.darkened(0.3), 8, Basis(Vector3.BACK, PI * 0.5))
		&"boots_springs":
			# Coil springs under the shoes (the shoe sits up on them; nothing goes through the floor).
			k.sphere(Vector3(0, 0.035, -0.01), Vector3(0.115, 0.06, 0.17), OutfitMeshes.RED, 12, 6)
			OutfitMeshes._sole(k, Vector3(0, -0.012, -0.01), Vector3(0.2, 0.02, 0.29), OutfitMeshes.CREAM.darkened(0.2))
			for i: int in 3:
				k.torus(Vector3(0, -0.03 - float(i) * 0.012, -0.01), 0.04, 0.055, OutfitMeshes.SILVER, 12, Basis.from_scale(Vector3(1, 0.5, 1)))
			OutfitMeshes._sole(k, Vector3(0, -0.062, -0.01), Vector3(0.14, 0.008, 0.18), OutfitMeshes.SILVER.darkened(0.2))
		&"boots_hilo":
			# Cream sneakers, a green up-arrow on the toe and a red down-arrow at the heel.
			_shoe_plain(k, OutfitMeshes.CREAM, OutfitMeshes.GOLD.darkened(0.3))
			k.cylinder(Vector3(0, 0.07, 0.04), 0.085, 0.09, 0.07, OutfitMeshes.CREAM, 10)
			var up := PackedVector2Array([Vector2(0, 0.04), Vector2(-0.035, 0.0), Vector2(-0.014, 0.0), Vector2(-0.014, -0.035), Vector2(0.014, -0.035), Vector2(0.014, 0.0), Vector2(0.035, 0.0)])
			var down := PackedVector2Array()
			for q: Vector2 in up:
				down.append(Vector2(q.x, -q.y))
			down.reverse()
			k.prism(up, 0.008, OutfitMeshes._facing(Vector3(1, 0, 0), Vector3(0.112, 0.01, -0.07)), OutfitMeshes.GREEN)
			k.prism(down, 0.008, OutfitMeshes._facing(Vector3(1, 0, 0), Vector3(0.112, 0.01, 0.07)), OutfitMeshes.RED)


## The right foot's extra parts (the ball and chain trail behind one foot only).
static func right_boot_extra(_k: OutfitMeshKit, _id: StringName) -> void:
	pass  # the ball and chain swings loose: `BallChain`, added by `AvatarVisuals`


static func _shoe_plain(k: OutfitMeshKit, upper: Color, sole: Color) -> void:
	k.sphere(Vector3(0, 0.0, -0.01), Vector3(0.12, 0.085, 0.175), upper, 12, 6)
	OutfitMeshes._sole(k, Vector3(0, -0.058, -0.01), Vector3(0.21, 0.022, 0.31), sole)


# --- Faces --------------------------------------------------------------------------------------

static func beard(k: OutfitMeshKit, id: StringName) -> void:
	match id:
		&"beard_pencil":
			# A thin, sharply trimmed pencil moustache.
			var my: float = OutfitMeshes._mouth_y()
			var c := Color("#2A1E16")
			for side: float in [-1.0, 1.0]:
				for i: int in 12:
					var s: float = float(i) / 11.0
					var x: float = side * (0.03 + s * 0.12)
					var y: float = my + OutfitMeshes.MOUSTACHE_LIFT * 0.75 + s * 0.012
					k.sphere(Vector3(x, y, AvatarVisuals.face_z(y, x) - 0.006), Vector3(0.016, 0.007, 0.007), c, 6, 3)


## Eye pieces in front of the face (glasses-like), body space.
static func eyes(k: OutfitMeshKit, id: StringName) -> void:
	var r: float = AvatarVisuals.EYE_RADIUS
	var face := Basis(Vector3.RIGHT, PI * 0.5)
	match id:
		&"eyes_black_eye":
			# A purple shiner painted flat on the skin round the left eye (outside the eyeball):
			# dark next to the eye, paler and ragged towards its edge, bigger below than above; a
			# sticking plaster on the other cheek.
			var e: Vector3 = OutfitMeshes._eye_center(1.0)
			var spot := func(u: float, v: float) -> Vector3:
				var a: float = u * TAU
				var reach: float = r * (1.32 + 0.42 * maxf(-sin(a), 0.0) + 0.06 * sin(a * 3.0 + 1.0))
				var rad: float = lerpf(r * 0.93, reach, v)
				var x: float = e.x + cos(a) * rad
				var y: float = e.y + sin(a) * rad * 0.92
				return Vector3(x, y, AvatarVisuals.face_z(y, x) - 0.0025)
			k.surface(spot, 40, 6, func(u: float, v: float) -> Color:
				if v > 0.84 and sin(u * TAU * 9.0) + 0.6 * sin(u * TAU * 4.0) > 0.4:
					return Color(0, 0, 0, 0)  # a ragged edge
				if v < 0.34:
					return Color("#4A2F55")
				if v < 0.67:
					return Color("#6B4C7C")
				return Color("#8C6E86"), func(_p: Vector3) -> Vector3: return Vector3(0, 0, -1), true)
			var o: Vector3 = OutfitMeshes._eye_center(-1.0)
			var y: float = o.y - r * 1.6
			var x: float = o.x - 0.04
			var place := OutfitMeshes._facing(Vector3(-0.3, 0, -1), Vector3(x, y, AvatarVisuals.face_z(y, x) - 0.008))
			for a: float in [0.6, -0.6]:
				k.prism(OutfitMeshKit.rect_poly(0.06, 0.016), 0.006, place.rotated_local(Vector3.BACK, a), Color("#E3B48C"))
		&"eyes_bulging":
			# Greedy goggle eyes popping out, gold glints in the pupils, darting about after money.
			for side: float in [-1.0, 1.0]:
				var e: Vector3 = OutfitMeshes._eye_center(side)
				var c := Vector3(e.x * 1.12, e.y + 0.01, e.z - r * 0.55)
				k.sphere(c, Vector3.ONE * r * 1.25, OutfitMeshes.WHITE, 16, 10)  # the pupils move: `spinners`
		&"eyes_loupe":
			# A jeweller's loupe screwed into the right eye: a black rubber cup pressed onto the skin
			# round the eye, the barrel standing straight out of it, the gold-rimmed lens in front.
			var e: Vector3 = OutfitMeshes._eye_center(-1.0)
			var cup := func(u: float, v: float) -> Vector3:
				var a: float = u * TAU
				var rad: float = lerpf(r * 1.0, r * 1.38, v)
				var x: float = e.x + cos(a) * rad
				var y: float = e.y + sin(a) * rad
				return Vector3(x, y, AvatarVisuals.face_z(y, x) - 0.004 - 0.01 * (1.0 - v))
			k.surface(cup, 32, 3, func(_u: float, _v: float) -> Color: return Color("#24211F"),
				func(_p: Vector3) -> Vector3: return Vector3(0, 0, -1), true)
			var skin_z: float = AvatarVisuals.face_z(e.y, e.x)
			const L: float = 0.11
			var p := Vector3(e.x, e.y, skin_z - L * 0.5)  # the barrel's middle: its back end on the skin
			k.cylinder(p, r * 1.0, r * 1.12, L, OutfitMeshes.BLACK, 20, face)
			k.torus(p + Vector3(0, 0, -L * 0.5), r * 0.86, r * 1.02, OutfitMeshes.GOLD, 20, face)
			k.cylinder(p + Vector3(0, 0, -L * 0.5 - 0.002), r * 0.86, r * 0.86, 0.004, Color("#2E3A44"), 20, face)
			k.sphere(p + Vector3(r * 0.35, r * 0.35, -L * 0.5 - 0.006), Vector3(r * 0.22, r * 0.12, 0.004), OutfitMeshes.WHITE, 8, 3, Basis(Vector3.BACK, 0.7))
		&"eyes_tears":
			# Wet trails down the cheeks; the tears themselves roll down them (`spinners`).
			for side: float in [-1.0, 1.0]:
				for i: int in 8:
					var p: Vector3 = _tear_point(side, float(i) / 7.0, 0.003)
					k.sphere(p, Vector3(0.012, 0.016, 0.004), OutfitMeshes._glow(TEAR.lightened(0.2), 0.15), 6, 3)


## Pupils of eye pieces in `PUPILS` (the pupil's own space, like `OutfitMeshes.pupil_mesh`).
static func pupil(k: OutfitMeshKit, id: StringName) -> void:
	var front := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.35))
	var dark := Color("#1C1A19")
	match id:
		&"eyes_clover":
			k.prism(OutfitMeshKit.circle_poly(1.35, 22), 0.5, front.translated_local(Vector3(0, 0, -0.1)), dark)
			for i: int in 4:
				var a: float = PI * 0.25 + TAU * float(i) / 4.0
				k.prism(OutfitMeshKit.heart_poly(1.25), 0.6, front.rotated_local(Vector3.BACK, a + PI * 0.5).translated_local(Vector3(0, 0.45, 0)), OutfitMeshes.GREEN.lightened(0.15))
			k.prism(OutfitMeshKit.circle_poly(0.18, 10), 0.7, front, OutfitMeshes._glow(OutfitMeshes.GOLD, 0.4))
		&"eyes_steel":
			k.prism(OutfitMeshKit.circle_poly(1.3, 22), 0.5, front.translated_local(Vector3(0, 0, -0.1)), Color("#7D8A99"))
			k.prism(OutfitMeshKit.circle_poly(1.0, 22), 0.55, front.translated_local(Vector3(0, 0, -0.05)), Color("#9AA7B5"))
			k.prism(OutfitMeshKit.circle_poly(0.5, 16), 0.65, front, dark)
			k.prism(OutfitMeshKit.rect_poly(0.55, 0.12), 0.7, front.translated_local(Vector3(0.25, 0.45, 0)).rotated_local(Vector3.BACK, 0.5), OutfitMeshes.WHITE)
		&"eyes_cards":
			k.prism(OutfitMeshKit.rect_poly(0.68, 0.92), 0.5, front.translated_local(Vector3(0, 0, -0.1)), dark)
			k.prism(OutfitMeshKit.rect_poly(0.6, 0.84), 0.6, front, OutfitMeshes.WHITE)
			k.prism(OutfitMeshKit.spade_poly(0.85), 0.7, front.translated_local(Vector3(0, -0.05, 0)), dark)


## Mouth pieces that are objects (the shader draws the rest): in body space at the mouth.
static func mouth(k: OutfitMeshKit, id: StringName) -> void:
	var my: float = OutfitMeshes._mouth_y()
	var mouth_at := Vector3(0.04, my, AvatarVisuals.face_z(my, 0.04) + 0.01)
	match id:
		&"mouth_party_horn":
			# A party blower straight out of the mouth: the gold mouthpiece here, the striped paper
			# tube rolls out and back in (`spinners`).
			var at: Vector3 = _horn_mouth()
			k.cylinder(at + Vector3(0, 0, -0.035), 0.028, 0.034, 0.07, OutfitMeshes.GOLD, 10, Basis(Vector3.RIGHT, PI * 0.5))

		&"mouth_straw":
			# A striped straw in the corner of the mouth, a paper umbrella tied to it.
			var dir := Vector3(0.75, -0.3, -0.6).normalized()
			var len: float = 0.34
			for i: int in 6:
				var s0: float = float(i) / 6.0
				var c: Vector3 = mouth_at + Vector3(0.04, 0, 0) + dir * len * (s0 + 1.0 / 12.0)
				k.cylinder(c, 0.019, 0.019, len / 6.0, OutfitMeshes.RED if i % 2 == 0 else OutfitMeshes.WHITE, 8, Basis(Quaternion(Vector3.UP, dir)))
			var tip: Vector3 = mouth_at + Vector3(0.04, 0, 0) + dir * len * 0.75
			k.cylinder(tip + Vector3(0, 0.07, 0), 0.007, 0.007, 0.14, OutfitMeshes.TAN, 5)
			k.cylinder(tip + Vector3(0, 0.16, 0), 0.0, 0.12, 0.055, OutfitMeshes.TEAL, 10)
			k.cylinder(tip + Vector3(0, 0.133, 0), 0.12, 0.12, 0.006, OutfitMeshes.TEAL.darkened(0.2), 10)
