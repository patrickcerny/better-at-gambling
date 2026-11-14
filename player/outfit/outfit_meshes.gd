class_name OutfitMeshes
extends RefCounted
## The low-poly models of every outfit piece in the cosmetics shop (data/progression/
## cosmetics_shop.tres): 15 hats, 15 shirts, 15 trousers, 15 capes and 15 pairs of boots, built in
## code from simple parts (`OutfitMeshKit`), no imported art. Each piece is ONE mesh in vertex
## colours with one shared toon material, built once and shared by every bean that wears it.
## Warm casino colours, no neon (docs/ART_DIRECTION.md).
## Spaces: hats, shirts, trousers and capes are in the bean body's space (`AvatarVisuals.body`,
## front -Z); boots around a foot's centre (`AvatarVisuals` feet), the outer side +X (the other foot
## gets the mirror image).

## Where a hat's brim sits on the head (body space) and how far it is tipped back, so the brim
## clears the eyebrows.
const HAT_BASE: Vector3 = Vector3(0.0, 0.50, -0.02)
const HAT_TILT: float = 0.12
## Capes hang from here (body space, the back of the shoulders): the sway turns them about it.
const CAPE_TOP_T: float = 0.6
## Heights on the body (0 = bottom, 1 = top) the clothes are cut to.
const SHIRT_BOTTOM: float = 0.17
const SHIRT_FRONT: float = 0.40
const SHIRT_BACK: float = 0.60
const PANTS_TOP: float = 0.205
const SHIRT_INFLATE: float = 0.012
const PANTS_INFLATE: float = 0.016

const BLACK := Color("#1C1A19")
const CHARCOAL := Color("#3B3F4A")
const NAVY := Color("#23304A")
const WHITE := Color("#F4EFE4")
const CREAM := Color("#E9DCBC")
const GOLD := Color("#D9AE52")
const SILVER := Color("#B8BCC2")
const STEEL := Color("#8C9198")
const RED := Color("#C23B32")
const DARK_RED := Color("#7A1F22")
const BURGUNDY := Color("#681F2C")
const BROWN := Color("#5A3A24")
const TAN := Color("#B07A45")
const LEATHER := Color("#6B4A2E")
const ORANGE := Color("#D9772B")
const YELLOW := Color("#E2B23A")
const GREEN := Color("#3E6B45")
const FELT := Color("#275E49")
const OLIVE := Color("#5B6340")
const SKY := Color("#7D9CC4")
const BLUE := Color("#2F5DA8")
const DENIM := Color("#3E5C88")
const PURPLE := Color("#4E2A6B")
const PINK := Color("#E39AA6")
const TEAL := Color("#3E8C88")

## A shirt's sleeve colour (the arms wear it); shirts not listed leave the arms bare.
const SLEEVES: Dictionary = {
	&"shirt_police": SKY, &"shirt_business": CHARCOAL, &"shirt_tux": BLACK, &"shirt_dealer": WHITE,
	&"shirt_chef": WHITE, &"shirt_firefighter": Color("#8A6A3A"), &"shirt_hivis": Color("#6B6B6B"),
	&"shirt_sailor": WHITE, &"shirt_jailbird": BLACK, &"shirt_referee": BLACK, &"shirt_hawaiian": Color("#C8503A"),
	&"shirt_knight": STEEL, &"shirt_hero": BLUE, &"shirt_flannel": Color("#A8322C"), &"shirt_sweater": FELT,
}

static var _cache: Dictionary = {}
static var _boot_cache: Dictionary = {}
static var _material: Material = null


## The model of a hat, shirt, pair of trousers or cape (null for unknown ids and boots).
static func mesh(id: StringName) -> ArrayMesh:
	if _cache.has(id):
		return _cache[id]
	var k := OutfitMeshKit.new()
	var s: String = String(id)
	if s.begins_with("hat_"):
		k.xf = Transform3D(Basis(Vector3.RIGHT, HAT_TILT), HAT_BASE)
		_hat(k, id)
	elif s.begins_with("shirt_"):
		_shirt(k, id)
	elif s.begins_with("pants_"):
		_pants(k, id)
	elif s.begins_with("cape_"):
		k.record_uv2 = true  # cloth coordinates for `CapeCloth`
		_cape(k, id)
		_cape_bottoms[id] = _cape_bottom
	var m: ArrayMesh = null if k.is_empty() else k.commit()
	_cache[id] = m
	return m


## A pair of boots: [the right foot's (+X side), the left foot's] (empty for unknown ids).
static func boot_meshes(id: StringName) -> Array[ArrayMesh]:
	if _boot_cache.has(id):
		return _boot_cache[id]
	var k := OutfitMeshKit.new()
	_boots(k, id)
	var out: Array[ArrayMesh] = []
	if not k.is_empty():
		out = [k.commit(), k.mirrored().commit()]
	_boot_cache[id] = out
	return out


## Whether there is a model for `id`.
static func has_model(id: StringName) -> bool:
	if String(id).begins_with("boots_"):
		return not boot_meshes(id).is_empty()
	return mesh(id) != null


## The sleeve colour of a shirt (alpha 0: no sleeves).
static func sleeve_color(id: StringName) -> Color:
	return SLEEVES.get(id, Color(0, 0, 0, 0))


## The shared material: the beans' toon look, coloured by the vertex colours.
static func material() -> Material:
	if _material == null:
		_material = ToonMaterial.make_vertex_colored(0.3)
	return _material


## The cape's hinge (body space).
static func cape_pivot() -> Vector3:
	return OutfitMeshKit.body_point(CAPE_TOP_T, PI, 0.03)


# --- Helpers ------------------------------------------------------------------------------------

## A repeatable 0..1 noise for cell (i, j) (spots, flowers, patches).
static func _hash(i: int, j: int, salt: int = 0) -> float:
	var h: int = (i * 73856093) ^ (j * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 10007) / 10007.0


## Front-centre distance on the body in metres-ish (|angle| from the front).
static func _front(a: float) -> float:
	return absf(wrapf(a, -PI, PI))


static func _back(a: float) -> float:
	return PI - absf(wrapf(a, -PI, PI))


static func _shirt_top() -> Callable:
	return OutfitMeshKit.neckline(SHIRT_FRONT, SHIRT_BACK)


## A V opening at the front from the neckline down to `bottom` (true inside the V).
static func _in_v(t: float, a: float, width: float, bottom: float) -> bool:
	if t < bottom:
		return false
	return _front(a) < width * (t - bottom) / maxf(SHIRT_FRONT - bottom, 0.01)


## A flat emblem on the body surface.
static func _emblem(k: OutfitMeshKit, poly: PackedVector2Array, t: float, a: float, inflate: float, color: Color, thick: float = 0.012) -> void:
	k.prism(poly, thick, OutfitMeshKit.body_frame(t, a, inflate), color)


## A little round button on the body surface.
static func _button(k: OutfitMeshKit, t: float, a: float, inflate: float, color: Color, r: float = 0.016) -> void:
	var f: Transform3D = OutfitMeshKit.body_frame(t, a, inflate)
	k.sphere(f.origin, Vector3(r, r, r * 0.55), color, 8, 4, f.basis)


## Text (a "$") standing on the body surface or a cape.
static func _glyph(k: OutfitMeshKit, text: String, place: Transform3D, color: Color, size: float = 0.13) -> void:
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 32
	tm.pixel_size = size / 32.0
	tm.depth = 0.01
	tm.curve_step = 2.0
	k.add_primitive(tm, place, color)


## A bow tie at the front of the neck.
static func _bow_tie(k: OutfitMeshKit, color: Color) -> void:
	var f: Transform3D = OutfitMeshKit.body_frame(SHIRT_FRONT - 0.01, 0.0, SHIRT_INFLATE + 0.02)
	for side: float in [-1.0, 1.0]:
		var wing := PackedVector2Array([Vector2(0, 0.012), Vector2(side * 0.07, 0.035), Vector2(side * 0.07, -0.035), Vector2(0, -0.012)])
		if side < 0.0:
			wing.reverse()
		k.prism(wing, 0.02, f, color)
	k.sphere(f * Vector3(0, 0, 0.015), Vector3(0.018, 0.018, 0.014), color.darkened(0.15), 8, 4, f.basis)


## A necktie: the knot (the blade is painted on the shirt).
static func _tie_knot(k: OutfitMeshKit, color: Color) -> void:
	var f: Transform3D = OutfitMeshKit.body_frame(SHIRT_FRONT - 0.012, 0.0, SHIRT_INFLATE + 0.008)
	k.sphere(f.origin, Vector3(0.028, 0.022, 0.016), color, 8, 4, f.basis)


# --- Hats ---------------------------------------------------------------------------------------
# Built upright around the brim's centre (y = 0 at the brim; the top of the head is ~0.2 above),
# then tipped back onto the head (`HAT_BASE`, `HAT_TILT`). Crowns are 0.9 deep, like the head.

static func _hat(k: OutfitMeshKit, id: StringName) -> void:
	const D: float = 0.9
	match id:
		&"hat_police":
			k.cylinder(Vector3(0, 0.09, 0), 0.34, 0.33, 0.18, NAVY, 16, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.035, 0), 0.338, 0.338, 0.06, BLACK, 16, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.215, -0.02), 0.41, 0.36, 0.08, NAVY, 16, Basis.IDENTITY, D)
			k.dome(Vector3(0, 0.005, -0.27), Vector3(0.24, 0.035, 0.17), BLACK, 14, Basis(Vector3.RIGHT, -0.3))
			k.prism(OutfitMeshKit.star_poly(5, 0.055, 0.024), 0.015, Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0, 0.12, -0.31)), GOLD)
		&"hat_top":
			k.cylinder(Vector3(0, 0.23, 0), 0.31, 0.33, 0.46, BLACK, 16, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.07, 0), 0.336, 0.338, 0.08, RED, 16, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.015, 0), 0.49, 0.49, 0.03, BLACK, 18, Basis.IDENTITY, D)
		&"hat_bowler":
			k.dome(Vector3(0, 0.0, 0), Vector3(0.34, 0.3, 0.32), CHARCOAL, 14)
			k.cylinder(Vector3(0, 0.035, 0), 0.342, 0.342, 0.06, BLACK, 16, Basis.IDENTITY, D)
			k.torus(Vector3(0, 0.01, 0), 0.32, 0.44, CHARCOAL, 18, Basis.from_scale(Vector3(1, 0.25, 1)), D)
		&"hat_fedora":
			k.cylinder(Vector3(0, 0.13, 0), 0.27, 0.335, 0.26, Color("#5A4A3C"), 14, Basis.IDENTITY, D)
			k.box(Vector3(0, 0.255, 0), Vector3(0.05, 0.03, 0.4), Color("#4A3C30"))
			k.cylinder(Vector3(0, 0.045, 0), 0.338, 0.338, 0.07, BLACK, 14, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.01, 0), 0.5, 0.5, 0.025, Color("#5A4A3C"), 18, Basis(Vector3.RIGHT, -0.08), D)
			k.sphere(Vector3(0.31, 0.1, 0.08), Vector3(0.025, 0.09, 0.02), RED, 8, 4, Basis(Vector3.FORWARD, 0.5))
		&"hat_cowboy":
			k.cylinder(Vector3(0, 0.14, 0), 0.26, 0.335, 0.28, TAN, 14, Basis.IDENTITY, D)
			k.box(Vector3(0, 0.27, 0), Vector3(0.06, 0.04, 0.36), TAN.darkened(0.25))
			k.cylinder(Vector3(0, 0.04, 0), 0.338, 0.338, 0.05, BROWN, 14, Basis.IDENTITY, D)
			k.torus(Vector3(0, 0.0, 0), 0.32, 0.64, TAN, 18, Basis.from_scale(Vector3(1, 0.2, 1)), D)
			for side: float in [-1.0, 1.0]:
				k.sphere(Vector3(side * 0.55, 0.07, 0), Vector3(0.07, 0.08, 0.3), TAN, 10, 5, Basis(Vector3.FORWARD, side * 0.6))
		&"hat_chef":
			k.cylinder(Vector3(0, 0.08, 0), 0.34, 0.335, 0.16, WHITE, 16, Basis.IDENTITY, D)
			k.sphere(Vector3(0, 0.32, 0), Vector3(0.38, 0.22, 0.35), WHITE, 14, 7)
			for i: int in 5:
				var ang: float = TAU * float(i) / 5.0
				k.sphere(Vector3(sin(ang) * 0.22, 0.33, cos(ang) * 0.2), Vector3(0.2, 0.17, 0.2), WHITE.darkened(0.04), 10, 5)
		&"hat_firefighter":
			k.dome(Vector3(0, -0.01, 0.0), Vector3(0.37, 0.33, 0.37), RED, 16)
			k.sphere(Vector3(0, -0.01, 0.07), Vector3(0.5, 0.03, 0.56), RED.darkened(0.15), 16, 4)
			k.box(Vector3(0, 0.3, 0.0), Vector3(0.07, 0.06, 0.62), RED.darkened(0.1))
			k.box(Vector3(0, 0.18, -0.36), Vector3(0.2, 0.2, 0.03), GOLD, Basis(Vector3.RIGHT, -0.35))
			k.prism(OutfitMeshKit.cross_poly(0.06, 0.02), 0.012, Transform3D(Basis(Vector3.RIGHT, -0.35).rotated(Vector3.UP, PI), Vector3(0, 0.185, -0.4)), RED)
		&"hat_hardhat":
			k.dome(Vector3(0, -0.005, 0), Vector3(0.36, 0.31, 0.35), YELLOW, 16)
			k.box(Vector3(0, 0.29, 0), Vector3(0.06, 0.05, 0.5), YELLOW.darkened(0.12))
			k.sphere(Vector3(0, -0.005, -0.3), Vector3(0.3, 0.025, 0.2), YELLOW, 12, 4)
			k.cylinder(Vector3(0, 0.005, 0), 0.37, 0.37, 0.02, YELLOW.darkened(0.12), 16, Basis.IDENTITY, D)
		&"hat_pirate":
			k.dome(Vector3(0, 0.0, 0), Vector3(0.35, 0.26, 0.33), BLACK, 14)
			for i: int in 3:
				var ang: float = PI + TAU * float(i) / 3.0
				var b := Basis(Vector3.UP, ang)
				k.sphere(Vector3(sin(ang) * 0.3, 0.13, cos(ang) * 0.27), Vector3(0.36, 0.16, 0.05), BLACK, 12, 5, b * Basis(Vector3.RIGHT, -0.35))
				k.sphere(Vector3(sin(ang) * 0.34, 0.24, cos(ang) * 0.3), Vector3(0.3, 0.02, 0.06), GOLD, 10, 3, b)
			var front := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0, 0.14, -0.375))
			k.prism(OutfitMeshKit.circle_poly(0.045, 10), 0.012, front, WHITE)
			for side: float in [-1.0, 1.0]:
				k.box(front * Vector3(0, -0.04, -0.004), Vector3(0.14, 0.022, 0.012), WHITE, front.basis * Basis(Vector3.BACK, side * 0.6))
			k.sphere(front * Vector3(-0.016, 0.008, 0.012), Vector3(0.011, 0.011, 0.006), BLACK, 6, 3)
			k.sphere(front * Vector3(0.016, 0.008, 0.012), Vector3(0.011, 0.011, 0.006), BLACK, 6, 3)
		&"hat_crown":
			k.dome(Vector3(0, 0.02, 0), Vector3(0.31, 0.2, 0.28), BURGUNDY, 12)
			k.cylinder(Vector3(0, 0.07, 0), 0.345, 0.34, 0.14, GOLD, 16, Basis.IDENTITY, D)
			for i: int in 8:
				var ang: float = TAU * float(i) / 8.0
				var p := Vector3(sin(ang) * 0.32, 0.2, cos(ang) * 0.29)
				k.cylinder(p, 0.0, 0.06, 0.13, GOLD, 6)
				k.sphere(p + Vector3(0, 0.075, 0), Vector3.ONE * 0.025, GOLD, 6, 3)
			for i: int in 3:
				var ang: float = PI + (float(i) - 1.0) * 0.55
				k.sphere(Vector3(sin(ang) * 0.35, 0.07, cos(ang) * 0.315), Vector3(0.035, 0.035, 0.02), [RED, BLUE, FELT][i], 8, 4, Basis(Vector3.UP, ang))
		&"hat_wizard":
			k.cylinder(Vector3(0, 0.015, 0), 0.52, 0.52, 0.03, Color("#2E3E7A"), 18, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.2, 0), 0.17, 0.33, 0.4, Color("#2E3E7A"), 14, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.5, 0.08), 0.0, 0.17, 0.32, Color("#2E3E7A"), 12, Basis(Vector3.RIGHT, 0.55))
			k.cylinder(Vector3(0, 0.05, 0), 0.335, 0.335, 0.06, GOLD, 14, Basis.IDENTITY, D)
			k.prism(OutfitMeshKit.star_poly(5, 0.05, 0.022), 0.012, Transform3D(Basis(Vector3.RIGHT, 0.2).rotated(Vector3.UP, PI), Vector3(-0.06, 0.2, -0.27)), YELLOW)
			k.prism(OutfitMeshKit.star_poly(5, 0.035, 0.016), 0.012, Transform3D(Basis(Vector3.RIGHT, 0.2).rotated(Vector3.UP, PI * 0.8), Vector3(0.12, 0.3, -0.18)), YELLOW)
		&"hat_party":
			var tilt := Basis(Vector3.BACK, -0.28)
			var cols: Array[Color] = [RED, CREAM, GOLD, RED]
			for i: int in 4:
				var h0: float = 0.08 + float(i) * 0.1
				var r0: float = 0.2 * (1.0 - float(i) / 4.0)
				var r1: float = 0.2 * (1.0 - float(i + 1) / 4.0)
				k.cylinder(Vector3(0.02, 0.0, 0) + tilt * Vector3(0, h0 + 0.05, 0), r1, r0, 0.1, cols[i], 12, tilt)
			k.sphere(Vector3(0.02, 0.0, 0) + tilt * Vector3(0, 0.5, 0), Vector3.ONE * 0.05, GOLD, 8, 4)
		&"hat_propeller":
			k.dome(Vector3(0, -0.01, 0), Vector3(0.35, 0.29, 0.33), RED, 16)
			k.torus(Vector3(0, 0.0, 0), 0.33, 0.37, YELLOW, 16, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.3, 0), 0.02, 0.02, 0.08, YELLOW, 6)
			k.box(Vector3(0, 0.34, 0), Vector3(0.5, 0.015, 0.07), BLUE, Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.15))
			k.sphere(Vector3(0, 0.345, 0), Vector3.ONE * 0.03, RED, 8, 4)
		&"hat_viking":
			k.dome(Vector3(0, -0.01, 0), Vector3(0.36, 0.31, 0.35), STEEL, 16)
			k.torus(Vector3(0, 0.02, 0), 0.33, 0.39, Color("#A0743A"), 16, Basis.IDENTITY, D)
			k.box(Vector3(0, 0.2, -0.3), Vector3(0.05, 0.24, 0.04), Color("#A0743A"), Basis(Vector3.RIGHT, 0.6))
			for side: float in [-1.0, 1.0]:
				k.cylinder(Vector3(side * 0.4, 0.12, 0), 0.055, 0.08, 0.2, CREAM, 8, Basis(Vector3.BACK, -side * 1.15))
				k.cylinder(Vector3(side * 0.51, 0.25, 0), 0.03, 0.055, 0.17, CREAM, 8, Basis(Vector3.BACK, -side * 0.45))
				k.cylinder(Vector3(side * 0.535, 0.37, 0), 0.0, 0.03, 0.1, CREAM.darkened(0.1), 8, Basis(Vector3.BACK, side * 0.1))
		&"hat_cone":
			var lean := Basis(Vector3.BACK, 0.16)
			k.box(Vector3(0, 0.14, 0), Vector3(0.5, 0.04, 0.48), ORANGE.darkened(0.2), lean)
			k.cylinder(lean * Vector3(0, 0.44, 0), 0.035, 0.2, 0.56, ORANGE, 12, lean)
			k.cylinder(lean * Vector3(0, 0.33, 0), 0.142, 0.157, 0.07, WHITE, 12, lean)
			k.cylinder(lean * Vector3(0, 0.52, 0), 0.087, 0.102, 0.06, WHITE, 12, lean)


# --- Shirts -------------------------------------------------------------------------------------
# Cloth bands around the body (`OutfitMeshKit.band`) from `SHIRT_BOTTOM` up to a neckline that
# stays below the mouth at the front and rises to the shoulders at the back. Patterns are painted
# per cell: paint(t, a) with t the height, a the angle from the front.

static func _shirt(k: OutfitMeshKit, id: StringName) -> void:
	var top: Callable = _shirt_top()
	var b: float = SHIRT_BOTTOM
	var inf: float = SHIRT_INFLATE
	match id:
		&"shirt_police":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _front(a) < 0.07 and t > 0.22:
					return NAVY
				if absf(_front(a) - 0.5) < 0.12 and t > 0.29 and t < 0.36:
					return SKY.darkened(0.12)
				return SKY)
			_tie_knot(k, NAVY)
			_emblem(k, OutfitMeshKit.star_poly(6, 0.045, 0.026), 0.355, -0.5, inf + 0.002, GOLD)
			for t: float in [0.24, 0.3]:
				_button(k, t, 0.11, inf, WHITE, 0.012)
		&"shirt_business":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _in_v(t, a, 0.5, 0.2):
					return RED if _front(a) < 0.07 else WHITE
				return CHARCOAL)
			_tie_knot(k, RED)
			_emblem(k, OutfitMeshKit.rect_poly(0.035, 0.012), 0.34, 0.6, inf + 0.002, WHITE)
			for t: float in [0.19, 0.24]:
				_button(k, t, 0.0, inf, BLACK)
		&"shirt_tux":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _in_v(t, a, 0.55, 0.2):
					return WHITE
				if _in_v(t, a, 0.68, 0.22):
					return Color("#2A2828")  # satin lapels
				return BLACK)
			_bow_tie(k, BLACK)
			for t: float in [0.27, 0.32]:
				_button(k, t, 0.0, inf, BLACK, 0.012)
			_emblem(k, OutfitMeshKit.circle_poly(0.025, 8), 0.34, 0.55, inf + 0.002, RED)
		&"shirt_dealer":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _in_v(t, a, 0.42, 0.24):
					return WHITE
				if _back(a) < 0.25 and t > 0.4:
					return WHITE
				return BURGUNDY)
			_bow_tie(k, BLACK)
			for t: float in [0.2, 0.25, 0.3]:
				_button(k, t, 0.0, inf, GOLD)
			_emblem(k, OutfitMeshKit.rect_poly(0.05, 0.016), 0.33, -0.6, inf + 0.002, GOLD)
		&"shirt_chef":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				return BLACK if t > SHIRT_FRONT - 0.02 and _front(a) < 0.8 else WHITE)
			for t: float in [0.21, 0.27, 0.33]:
				for a: float in [-0.2, 0.2]:
					_button(k, t, a, inf, BLACK)
		&"shirt_firefighter":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if t > 0.21 and t < 0.24:
					return YELLOW
				if t >= 0.24 and t < 0.255:
					return SILVER
				if _front(a) < 0.03:
					return BLACK
				return Color("#8A6A3A"))
			for t: float in [0.29, 0.34]:
				_emblem(k, OutfitMeshKit.rect_poly(0.03, 0.008), t, 0.0, inf + 0.002, SILVER)
		&"shirt_hivis":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if (t > 0.23 and t < 0.25) or (t > 0.3 and t < 0.32):
					return SILVER
				if t > 0.32 and absf(_front(a) - 0.35) < 0.06:
					return SILVER
				if _front(a) < 0.06 and t > 0.2:
					return Color("#6B6B6B")
				return ORANGE)
		&"shirt_sailor":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if t > SHIRT_FRONT - 0.04 and _front(a) > 1.2:
					return NAVY  # the square collar at the back
				return NAVY if int(floor(t / 0.03)) % 2 == 0 else WHITE)
		&"shirt_jailbird":
			k.band(b, top, inf, func(t: float, _a: float) -> Color:
				return BLACK if int(floor(t / 0.045)) % 2 == 0 else WHITE)
			_emblem(k, OutfitMeshKit.rect_poly(0.045, 0.022), 0.33, -0.5, inf + 0.002, WHITE)
			_emblem(k, OutfitMeshKit.rect_poly(0.03, 0.006), 0.33, -0.5, inf + 0.014, BLACK, 0.004)
		&"shirt_referee":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if t > SHIRT_FRONT - 0.025 and _front(a) < 1.0:
					return BLACK
				return BLACK if int(floor((a + PI) / (TAU / 18.0))) % 2 == 0 else WHITE)
			var f: Transform3D = OutfitMeshKit.body_frame(0.3, 0.12, inf + 0.02)
			k.cylinder(f.origin, 0.02, 0.02, 0.06, SILVER, 8, f.basis * Basis(Vector3.BACK, PI * 0.5))
		&"shirt_hawaiian":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				var i: int = int(floor(t / 0.035))
				var j: int = int(floor((a + PI) / 0.3))
				var h: float = _hash(i, j, 3)
				if _front(a) < 0.03:
					return Color("#9E3A2A")
				if h < 0.16:
					return CREAM
				if h < 0.24:
					return YELLOW
				if h < 0.3:
					return TEAL
				return Color("#C8503A"))
			for t: float in [0.21, 0.27, 0.33]:
				_button(k, t, 0.05, inf, CREAM, 0.011)
		&"shirt_knight":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				var tabard: bool = _front(a) < 0.55 or _back(a) < 0.55
				if tabard:
					if (_front(a) < 0.1 and t > 0.19) or (_front(a) < 0.45 and t > 0.29 and t < 0.33):
						return RED
					return WHITE
				return STEEL if int(floor(t / 0.03)) % 2 == 0 else STEEL.darkened(0.15))
			for side: float in [-1.0, 1.0]:
				k.sphere(OutfitMeshKit.body_point(0.5, side * PI * 0.5, 0.05), Vector3(0.11, 0.07, 0.13), STEEL.lightened(0.1), 10, 5)
		&"shirt_hero":
			k.band(b, top, inf, func(t: float, _a: float) -> Color:
				return YELLOW if t < 0.205 else BLUE)
			var f: Transform3D = OutfitMeshKit.body_frame(0.3, 0.0, inf + 0.002)
			k.prism(OutfitMeshKit.diamond_poly(0.11, 0.08), 0.012, f, YELLOW)
			k.prism(OutfitMeshKit.diamond_poly(0.075, 0.052), 0.012, f.translated_local(Vector3(0, 0, 0.004)), RED)
		&"shirt_flannel":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				var row: bool = int(floor(t / 0.04)) % 2 == 0
				var col: bool = int(floor((a + PI) / 0.35)) % 2 == 0
				if row and col:
					return Color("#2A1E1E")
				if row or col:
					return Color("#7A2420")
				return Color("#A8322C"))
			for t: float in [0.22, 0.28, 0.34]:
				_button(k, t, 0.0, inf, CREAM, 0.012)
		&"shirt_sweater":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if t > 0.29 and t < 0.33:
					var zig: float = absf(fposmod((a + PI) / 0.18, 2.0) - 1.0)
					return CREAM if absf((t - 0.29) / 0.04 - zig) < 0.35 else RED
				if t > 0.22 and t < 0.25:
					return CREAM if int(floor((a + PI) / 0.22)) % 2 == 0 else FELT
				if t < SHIRT_BOTTOM + 0.025:
					return FELT.darkened(0.2)  # the ribbed hem
				return FELT)


# --- Trousers -----------------------------------------------------------------------------------
# The bottom of the bean up to `PANTS_TOP`, over the shirt's hem; belts, stripes and pockets
# painted on, buckles and pouches added. Suspenders are a second band with holes.

static func _pants(k: OutfitMeshKit, id: StringName) -> void:
	var top: Callable = OutfitMeshKit.level(PANTS_TOP)
	var inf: float = PANTS_INFLATE
	match id:
		&"pants_police":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.175:
					return BLACK
				return GOLD if absf(_front(a) - PI * 0.5) < 0.06 else NAVY)
			_buckle(k, SILVER)
		&"pants_suit":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.175:
					return BROWN
				return CHARCOAL.darkened(0.15) if absf(_front(a) - 0.32) < 0.015 else CHARCOAL)
			_buckle(k, GOLD)
		&"pants_tux":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.165:
					return BURGUNDY if int(floor(t / 0.012)) % 2 == 0 else BURGUNDY.darkened(0.2)
				return Color("#33302E") if absf(_front(a) - PI * 0.5) < 0.05 else BLACK)
		&"pants_jeans":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.178:
					return LEATHER
				if _back(a) < 0.75 and _back(a) > 0.2 and t > 0.09 and t < 0.16:
					if t > 0.155 or absf(_back(a) - 0.475) > 0.25:
						return GOLD.darkened(0.2)  # stitching around the back pockets
					return DENIM.darkened(0.1)
				if _front(a) < 0.015 and t > 0.08:
					return GOLD.darkened(0.2)
				return DENIM)
			_buckle(k, SILVER)
		&"pants_chef":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.18:
					return WHITE
				return BLACK if (int(floor(t / 0.03)) + int(floor((a + PI) / 0.2))) % 2 == 0 else WHITE)
		&"pants_firefighter":
			k.band(0.0, top, inf, func(t: float, _a: float) -> Color:
				if t > 0.07 and t < 0.1:
					return YELLOW
				if t > 0.1 and t < 0.11:
					return SILVER
				return Color("#8A6A3A"))
			_suspenders(k, RED, 0.3)
		&"pants_cargo":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.178:
					return BLACK
				if absf(_front(a) - PI * 0.5) < 0.28 and t > 0.06 and t < 0.15:
					return OLIVE.darkened(0.25) if t > 0.13 else OLIVE.darkened(0.1)
				return OLIVE)
			_buckle(k, STEEL)
		&"pants_pirate":
			k.band(0.0, top, inf, func(t: float, _a: float) -> Color:
				if t > 0.14:
					return RED
				return LEATHER if int(floor(t / 0.035)) % 2 == 0 else CREAM)
			k.sphere(OutfitMeshKit.body_point(0.16, 1.3, inf + 0.03), Vector3(0.06, 0.05, 0.05), RED.darkened(0.1), 8, 4)
			k.sphere(OutfitMeshKit.body_point(0.09, 1.35, inf + 0.03), Vector3(0.04, 0.09, 0.03), RED.darkened(0.1), 8, 4)
		&"pants_jailbird":
			k.band(0.0, top, inf, func(t: float, _a: float) -> Color:
				return BLACK if int(floor(t / 0.045)) % 2 == 1 else WHITE)
		&"pants_lederhosen":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if absf(_front(a) - 1.2) < 0.18 and t > 0.07 and t < 0.15:
					return CREAM if _hash(int(t * 100.0), int(a * 20.0)) < 0.3 else LEATHER.darkened(0.15)
				if _front(a) < 0.12 and t > 0.08 and t < 0.17:
					return LEATHER.darkened(0.15)  # the front flap
				return LEATHER)
			_suspenders(k, LEATHER.darkened(0.1), 0.3)
			var f: Transform3D = OutfitMeshKit.body_frame(0.37, 0.0, SHIRT_INFLATE + 0.012)
			k.box(f.origin, Vector3(0.24, 0.035, 0.012), LEATHER.lightened(0.1), f.basis)
			k.prism(OutfitMeshKit.star_poly(5, 0.022, 0.012), 0.006, f.translated_local(Vector3(0, 0, 0.007)), CREAM)
			for side: float in [-1.0, 1.0]:
				_button(k, 0.14, side * 0.12, inf, Color("#C9B79A"), 0.012)
		&"pants_kilt":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.18:
					return BROWN
				var r: int = int(floor(t / 0.03)) % 3
				var c: int = int(floor((a + PI) / 0.25)) % 3
				if r == 0 and c == 0:
					return Color("#1E3A2A")
				if r == 0 or c == 0:
					return GREEN
				if r == 1 and c == 1:
					return YELLOW.darkened(0.2)
				return RED.darkened(0.15), 0.07)
			var f: Transform3D = OutfitMeshKit.body_frame(0.12, 0.0, inf + 0.05)
			k.sphere(f.origin, Vector3(0.07, 0.06, 0.03), LEATHER, 10, 5, f.basis)
			k.sphere(f * Vector3(0, 0.035, 0.0), Vector3(0.075, 0.025, 0.035), WHITE, 10, 4, f.basis)
			_buckle(k, SILVER)
		&"pants_clown":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				var i: int = int(floor(t / 0.05))
				var j: int = int(floor((a + PI) / 0.45))
				var h: float = _hash(i, j, 7)
				if h < 0.18:
					return RED
				if h < 0.32:
					return BLUE
				if h < 0.44:
					return FELT
				return YELLOW, 0.05)
			_suspenders(k, RED, 0.2)
		&"pants_golf":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.18:
					return WHITE
				var x: float = (a + PI) / 0.4
				var y: float = t / 0.05
				var p: float = fposmod(x + y, 2.0)
				var q: float = fposmod(x - y, 2.0)
				var both: bool = (p < 1.0) == (q < 1.0)
				return PINK if both else Color("#7FA27A"))
		&"pants_hero":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.185:
					return YELLOW
				if t > 0.11 or (t > 0.06 and _front(a) < 0.25):
					return RED
				return BLUE)
		&"pants_boxers":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.175:
					return SKY
				var i: int = int(floor(t / 0.04))
				var j: int = int(floor((a + PI) / 0.3))
				return RED if _hash(i, j, 11) < 0.2 else WHITE)
			for i: int in 5:
				var t: float = 0.05 + float(i) * 0.025
				var a: float = -1.0 + _hash(i, 2, 5) * 2.0
				_emblem(k, OutfitMeshKit.heart_poly(0.05), t + 0.02, a, inf + 0.001, RED, 0.006)


## A belt buckle at the front of the waistband.
static func _buckle(k: OutfitMeshKit, color: Color) -> void:
	var f: Transform3D = OutfitMeshKit.body_frame(0.19, 0.0, PANTS_INFLATE + 0.002)
	k.prism(OutfitMeshKit.rect_poly(0.04, 0.022), 0.012, f, color)


## Two straps from the waistband over the shoulders (`width` = their angle apart at the front).
static func _suspenders(k: OutfitMeshKit, color: Color, spread: float) -> void:
	var top: Callable = OutfitMeshKit.neckline(SHIRT_FRONT + 0.005, SHIRT_BACK + 0.01)
	k.band(PANTS_TOP - 0.02, top, SHIRT_INFLATE + 0.006, func(_t: float, a: float) -> Color:
		var front_strap: bool = absf(_front(a) - spread) < 0.07
		var back_strap: bool = absf(_back(a) - spread * 0.8) < 0.07
		return color if front_strap or back_strap else Color(0, 0, 0, 0), 0.0, 72, 10)


# --- Capes --------------------------------------------------------------------------------------
# A cloth sheet hanging from the back of the shoulders (`CAPE_TOP_T`), wider and further out at the
# bottom; outside and lining in their own colours. paint(u, v): u across (0 = the bean's right
# edge), v down (0 = the top).

static func _cape(k: OutfitMeshKit, id: StringName) -> void:
	match id:
		&"cape_hero":
			_cape_sheet(k, -0.78, func(_u: float, _v: float) -> Color: return RED, RED.darkened(0.3))
			_clasps(k, GOLD)
		&"cape_vampire":
			_cape_sheet(k, -0.78, func(_u: float, _v: float) -> Color: return BLACK, DARK_RED)
			_cape_collar(k, BLACK, DARK_RED, 0.2)
			_clasps(k, RED)
		&"cape_royal":
			_cape_sheet(k, -0.78, func(u: float, v: float) -> Color:
				if v > 0.9:
					return BLACK if _hash(int(u * 30.0), int(v * 60.0), 2) < 0.12 else WHITE
				return PURPLE, GOLD.darkened(0.2))
			_cape_collar(k, WHITE, WHITE.darkened(0.2), 0.08, func(u: float, v: float) -> Color:
				return BLACK if _hash(int(u * 24.0), int(v * 6.0), 4) < 0.14 else WHITE)
			_clasps(k, GOLD)
		&"cape_wizard":
			_cape_sheet(k, -0.78, func(u: float, v: float) -> Color:
				var h: float = _hash(int(u * 14.0), int(v * 12.0), 9)
				return YELLOW if h < 0.07 else (CREAM if h < 0.1 else Color("#2E3E7A")), PURPLE)
			_cape_emblem(k, OutfitMeshKit.star_poly(5, 0.12, 0.05), 0.3, YELLOW)
			_clasps(k, GOLD)
		&"cape_knight":
			_cape_sheet(k, -0.74, func(u: float, v: float) -> Color:
				if absf(u - 0.5) < 0.06 and v > 0.08 and v < 0.75:
					return RED
				if absf(v - 0.32) < 0.05 and absf(u - 0.5) < 0.25:
					return RED
				return WHITE, STEEL)
			_clasps(k, STEEL)
		&"cape_high_roller":
			_cape_sheet(k, -0.78, func(_u: float, v: float) -> Color:
				return GOLD.darkened(0.15) if v > 0.93 else GOLD, BURGUNDY)
			_cape_glyph(k, "$", 0.34, BURGUNDY, 0.3)
			_clasps(k, BURGUNDY)
		&"cape_card_shark":
			_cape_sheet(k, -0.78, func(_u: float, v: float) -> Color:
				return GOLD if v > 0.94 else BLACK, RED.darkened(0.2))
			_cape_emblem(k, OutfitMeshKit.spade_poly(0.24), 0.32, CREAM)
			_clasps(k, GOLD)
		&"cape_money":
			_cape_sheet(k, -0.76, func(u: float, v: float) -> Color:
				if u < 0.06 or u > 0.94 or v > 0.92 or v < 0.05:
					return Color("#9DBF8E")
				return Color("#3F7A4A"), Color("#9DBF8E"))
			_cape_emblem(k, OutfitMeshKit.circle_poly(0.13, 14), 0.36, Color("#9DBF8E"))
			_cape_glyph(k, "$", 0.36, Color("#2C5A35"), 0.22, 0.016)
			_clasps(k, GOLD)
		&"cape_picnic":
			_cape_sheet(k, -0.74, func(u: float, v: float) -> Color:
				var r: bool = int(floor(v * 12.0)) % 2 == 0
				var c: bool = int(floor(u * 10.0)) % 2 == 0
				if r and c:
					return RED
				if r or c:
					return Color("#E08A80")
				return WHITE, WHITE)
			_clasps(k, CREAM)
		&"cape_towel":
			_cape_sheet(k, -0.62, func(u: float, v: float) -> Color:
				if v > 0.96 and int(floor(u * 40.0)) % 2 == 0:
					return Color(0, 0, 0, 0)  # fringe
				if (v > 0.78 and v < 0.82) or (v > 0.85 and v < 0.87):
					return SKY
				return WHITE, WHITE.darkened(0.08), 64, 26)
			k.sphere(OutfitMeshKit.body_point(0.56, 0.0, 0.03), Vector3(0.07, 0.05, 0.04), WHITE, 8, 4)
		&"cape_leopard":
			_cape_sheet(k, -0.78, func(u: float, v: float) -> Color:
				var h: float = _hash(int(u * 22.0), int(v * 18.0), 13)
				if h < 0.1:
					return Color("#3A2A1E")
				if h < 0.16:
					return Color("#8A5A2A")
				return Color("#C9964E"), BLACK)
			_clasps(k, GOLD)
		&"cape_rainbow":
			var bands: Array[Color] = [Color("#B9473E"), Color("#D07C3A"), Color("#D6A84B"), Color("#7FA25A"), Color("#3E8C88"), Color("#3E5C88"), Color("#6B4A8A")]
			_cape_sheet(k, -0.78, func(u: float, _v: float) -> Color:
				return bands[clampi(int(floor(u * bands.size())), 0, bands.size() - 1)], CREAM)
			_clasps(k, GOLD)
		&"cape_detective":
			_cape_sheet(k, -0.3, func(u: float, v: float) -> Color:
				if absf(fposmod(u * 9.0, 1.0) - 0.5) < 0.05 or absf(fposmod(v * 6.0, 1.0) - 0.5) < 0.06:
					return Color("#8A6440")
				return Color("#A07850"), Color("#6B2A26"), 40, 10)
			_cape_collar(k, Color("#A07850"), Color("#8A6440"), 0.12)
			_clasps(k, BROWN)
		&"cape_patchwork":
			_cape_sheet(k, -0.76, func(u: float, v: float) -> Color:
				var i: int = int(floor(u * 4.0))
				var j: int = int(floor(v * 5.0))
				if absf(fposmod(u * 4.0, 1.0) - 0.5) > 0.47 or absf(fposmod(v * 5.0, 1.0) - 0.5) > 0.46:
					return CREAM  # stitches
				var cols: Array[Color] = [RED, TEAL, GOLD, FELT, PINK, DENIM, ORANGE, PURPLE]
				return cols[int(_hash(i, j, 17) * cols.size()) % cols.size()], CREAM.darkened(0.1))
			_clasps(k, BROWN)
		&"cape_matador":
			_cape_sheet(k, -0.32, func(u: float, v: float) -> Color:
				if v > 0.85 or u < 0.05 or u > 0.95:
					return GOLD
				return BLACK, RED, 40, 10)
			_cape_emblem(k, OutfitMeshKit.star_poly(8, 0.07, 0.035), 0.4, GOLD)
			_clasps(k, GOLD)


## The cape's shape: `u` across, `v` down to `bottom_y` (body space), `inflate` off the cloth's
## middle (the outside and the lining sit either side).
static func _cape_at(u: float, v: float, bottom_y: float, inflate: float) -> Vector3:
	var y_top: float = (CAPE_TOP_T - 0.5) * AvatarVisuals.BODY_HEIGHT
	var y: float = lerpf(y_top, bottom_y, v)
	var t: float = clampf(y / AvatarVisuals.BODY_HEIGHT + 0.5, 0.0, 1.0)
	var r: float = maxf(AvatarVisuals.radius_at(t), 0.41) + 0.035 + 0.06 * v + inflate
	# Wrapped round the shoulders at the top, hanging as a flatter sheet behind further down (a
	# cape, not a skirt).
	var w: float = lerpf(1.25, 1.0, v)
	var b: float = (u - 0.5) * 2.0 * w
	var x: float = -sin(b) * r * (1.0 + 0.3 * v)
	var z_round: float = cos(b) * r * AvatarVisuals.BODY_DEPTH
	var z_flat: float = r * AvatarVisuals.BODY_DEPTH * 0.82 + 0.04 * v
	var z: float = lerpf(z_round, maxf(z_round, z_flat), smoothstep(0.0, 0.7, v))
	return Vector3(x, y, AvatarVisuals.bend_at(t) + z)


static var _cape_bottom: float = -0.78
## Cape id -> its hem height (body space), for the cloth.
static var _cape_bottoms: Dictionary = {}


## Where cape `id`'s cloth point (u across, v down) rests, in body space (`CapeCloth`).
static func cape_rest(id: StringName, u: float, v: float) -> Vector3:
	if not _cape_bottoms.has(id):
		mesh(id)
	return _cape_at(u, v, _cape_bottoms.get(id, -0.78), 0.0)


static func _cape_sheet(k: OutfitMeshKit, bottom_y: float, paint: Callable, lining: Color, nu: int = 40, nv: int = 22) -> void:
	_cape_bottom = bottom_y
	var out := func(p: Vector3) -> Vector3:
		return Vector3(p.x, 0.0, p.z + 0.03)
	var inside := func(p: Vector3) -> Vector3:
		return -Vector3(p.x, 0.0, p.z + 0.03)
	k.surface_uv2 = true
	k.surface(func(u: float, v: float) -> Vector3: return _cape_at(u, v, bottom_y, 0.004), nu, nv, paint, out)
	k.surface(func(u: float, v: float) -> Vector3: return _cape_at(u, v, bottom_y, -0.004), nu, nv, func(u: float, v: float) -> Color:
		var c: Color = paint.call(u, v)
		return Color(lining, c.a), inside)
	k.surface_uv2 = false


## A standing collar behind the head (vampire, ermine, a detective's coat).
static func _cape_collar(k: OutfitMeshKit, outside: Color, inside_col: Color, height: float, paint: Callable = Callable()) -> void:
	var at := func(u: float, v: float, off: float) -> Vector3:
		var t: float = CAPE_TOP_T - 0.03 + v * height
		var b: float = (u - 0.5) * 2.0 * 1.35
		var r: float = AvatarVisuals.radius_at(t) + 0.04 + v * 0.1 + off
		return Vector3(-sin(b) * r, (t - 0.5) * AvatarVisuals.BODY_HEIGHT, AvatarVisuals.bend_at(t) + cos(b) * r * AvatarVisuals.BODY_DEPTH)
	var pt: Callable = paint if paint.is_valid() else func(_u: float, _v: float) -> Color: return outside
	k.surface(func(u: float, v: float) -> Vector3: return at.call(u, v, 0.004), 30, 5, pt, func(p: Vector3) -> Vector3: return Vector3(p.x, 0.0, p.z + 0.03))
	k.surface(func(u: float, v: float) -> Vector3: return at.call(u, v, -0.004), 30, 5, func(_u: float, _v: float) -> Color: return inside_col, func(p: Vector3) -> Vector3: return -Vector3(p.x, 0.0, p.z + 0.03))


## Where an emblem sits on the back of the cape (`v` down it): +Z out of the cape, +X to the right
## of someone looking at the back.
static func _cape_frame(v: float, lift: float = 0.006) -> Transform3D:
	var p: Vector3 = _cape_at(0.5, v, _cape_bottom, 0.004 + lift)
	var up: Vector3 = (_cape_at(0.5, v - 0.02, _cape_bottom, 0.0) - _cape_at(0.5, v + 0.02, _cape_bottom, 0.0)).normalized()
	var out := Vector3(0, 0, 1)
	out = (out - up * out.dot(up)).normalized()
	return Transform3D(Basis(up.cross(out).normalized() * -1.0, up, out), p)


static func _cape_emblem(k: OutfitMeshKit, poly: PackedVector2Array, v: float, color: Color) -> void:
	k.uv2 = Vector2(0.5, v)  # moves with the cloth
	k.prism(poly, 0.012, _cape_frame(v), color)
	k.uv2 = Vector2.ZERO


static func _cape_glyph(k: OutfitMeshKit, text: String, v: float, color: Color, size: float, lift: float = 0.006) -> void:
	k.uv2 = Vector2(0.5, v)
	_glyph(k, text, _cape_frame(v, lift), color, size)
	k.uv2 = Vector2.ZERO


## The two clasps at the front of the shoulders where the cape is tied.
static func _clasps(k: OutfitMeshKit, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		k.sphere(OutfitMeshKit.body_point(CAPE_TOP_T - 0.02, side * 1.15, 0.035), Vector3.ONE * 0.035, color, 8, 4)


# --- Boots --------------------------------------------------------------------------------------
# Around the foot's centre (the bean's feet are 0.065 above the floor): sole at y = -0.065, toe at
# -Z, the outer side +X. A shaft rises into the bottom of the body.

static func _boots(k: OutfitMeshKit, id: StringName) -> void:
	match id:
		&"boots_police":
			_shoe(k, BLACK, BLACK.lightened(0.08))
			k.cylinder(Vector3(0, 0.1, 0.03), 0.09, 0.1, 0.15, BLACK, 10)
			k.sphere(Vector3(0.03, 0.05, -0.12), Vector3(0.04, 0.02, 0.03), Color(1, 1, 1, 1).darkened(0.2), 6, 3)
		&"boots_oxford":
			_shoe(k, BROWN, BROWN.darkened(0.4))
			for i: int in 3:
				k.box(Vector3(0, 0.07, -0.04 - float(i) * 0.035), Vector3(0.08, 0.008, 0.008), CREAM)
		&"boots_spats":
			_shoe(k, BLACK, BLACK.lightened(0.1))
			k.dome(Vector3(0, 0.0, 0.01), Vector3(0.122, 0.09, 0.15), WHITE, 12)
			for i: int in 3:
				k.sphere(Vector3(0.12, 0.02 + float(i) * 0.025, 0.02), Vector3.ONE * 0.01, BLACK, 6, 3)
		&"boots_cowboy":
			k.sphere(Vector3(0, -0.005, -0.03), Vector3(0.11, 0.07, 0.19), TAN.darkened(0.2), 12, 6)
			k.cylinder(Vector3(0, -0.005, -0.21), 0.0, 0.05, 0.08, TAN.darkened(0.2), 8, Basis(Vector3.RIGHT, -PI * 0.5))
			k.box(Vector3(0, -0.05, 0.09), Vector3(0.09, 0.05, 0.06), BROWN.darkened(0.3))
			k.cylinder(Vector3(0, 0.12, 0.03), 0.1, 0.095, 0.2, TAN.darkened(0.2), 10)
			k.cylinder(Vector3(0, 0.1, 0.03), 0.101, 0.098, 0.03, CREAM.darkened(0.2), 10)
			k.torus(Vector3(0.0, 0.0, 0.13), 0.025, 0.035, SILVER, 8, Basis(Vector3.RIGHT, PI * 0.5))
			k.prism(OutfitMeshKit.star_poly(6, 0.03, 0.012), 0.006, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.0, 0.16)), SILVER)
		&"boots_clogs":
			k.sphere(Vector3(0, 0.0, -0.02), Vector3(0.13, 0.09, 0.19), WHITE, 12, 6)
			k.box(Vector3(0, -0.055, -0.02), Vector3(0.2, 0.025, 0.32), CREAM.darkened(0.2))
			k.torus(Vector3(0, 0.04, 0.06), 0.11, 0.125, WHITE.darkened(0.1), 12, Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5))
		&"boots_firefighter":
			_shoe(k, BLACK, BLACK.lightened(0.1))
			k.cylinder(Vector3(0, 0.1, 0.02), 0.095, 0.105, 0.17, BLACK, 10)
			k.cylinder(Vector3(0, 0.08, 0.02), 0.107, 0.107, 0.03, YELLOW, 10)
			k.box(Vector3(0, -0.06, -0.02), Vector3(0.2, 0.02, 0.32), YELLOW.darkened(0.2))
		&"boots_work":
			_shoe(k, TAN, BROWN.darkened(0.3))
			k.cylinder(Vector3(0, 0.08, 0.02), 0.09, 0.1, 0.1, TAN, 10)
			k.dome(Vector3(0, -0.03, -0.1), Vector3(0.1, 0.07, 0.09), STEEL, 10)
			for i: int in 3:
				k.box(Vector3(0, 0.07 + float(i) * 0.02, -0.06 + float(i) * 0.02), Vector3(0.08, 0.008, 0.008), ORANGE)
		&"boots_pirate":
			_shoe(k, BLACK, BROWN.darkened(0.4))
			k.cylinder(Vector3(0, 0.1, 0.03), 0.095, 0.1, 0.16, BLACK, 10)
			k.cylinder(Vector3(0, 0.17, 0.03), 0.13, 0.11, 0.06, LEATHER, 10)
			k.box(Vector3(0, 0.04, -0.12), Vector3(0.07, 0.05, 0.02), GOLD, Basis(Vector3.RIGHT, 0.4))
		&"boots_sneakers":
			_shoe(k, WHITE, CREAM.darkened(0.15))
			k.box(Vector3(0.115, 0.0, -0.01), Vector3(0.012, 0.03, 0.16), RED, Basis(Vector3.RIGHT, 0.35))
			k.box(Vector3(-0.115, 0.0, -0.01), Vector3(0.012, 0.03, 0.16), RED, Basis(Vector3.RIGHT, 0.35))
			k.cylinder(Vector3(0, 0.07, 0.04), 0.085, 0.09, 0.07, WHITE, 10)
			k.cylinder(Vector3(0, 0.1, 0.04), 0.087, 0.087, 0.012, RED, 10)
		&"boots_flippers":
			k.sphere(Vector3(0, 0.0, 0.0), Vector3(0.12, 0.08, 0.15), TEAL.darkened(0.2), 10, 5)
			k.sphere(Vector3(0, -0.05, -0.22), Vector3(0.17, 0.018, 0.25), TEAL, 12, 4)
			for i: int in 3:
				k.box(Vector3(-0.08 + float(i) * 0.08, -0.04, -0.25), Vector3(0.012, 0.012, 0.3), TEAL.darkened(0.25))
		&"boots_bunny":
			k.sphere(Vector3(0, 0.0, -0.01), Vector3(0.13, 0.095, 0.19), PINK, 12, 6)
			for side: float in [-1.0, 1.0]:
				k.sphere(Vector3(side * 0.045, 0.12, 0.02), Vector3(0.03, 0.09, 0.02), PINK, 8, 4, Basis(Vector3.BACK, side * 0.25))
				k.sphere(Vector3(side * 0.045, 0.12, 0.012), Vector3(0.016, 0.065, 0.012), WHITE, 6, 3, Basis(Vector3.BACK, side * 0.25))
				k.sphere(Vector3(side * 0.04, 0.05, -0.14), Vector3.ONE * 0.016, BLACK, 6, 3)
			k.sphere(Vector3(0, 0.02, -0.19), Vector3.ONE * 0.02, RED, 6, 3)
		&"boots_skates":
			_shoe(k, WHITE, Color("#B9473E"))
			k.cylinder(Vector3(0, 0.09, 0.02), 0.09, 0.1, 0.13, WHITE, 10)
			for z: float in [-0.11, 0.09]:
				for x: float in [-0.06, 0.06]:
					k.cylinder(Vector3(x, -0.06, z), 0.032, 0.032, 0.03, YELLOW, 10, Basis(Vector3.BACK, PI * 0.5))
			k.sphere(Vector3(0, -0.05, -0.2), Vector3(0.03, 0.03, 0.03), RED, 6, 3)
		&"boots_clown":
			k.sphere(Vector3(0, 0.0, -0.07), Vector3(0.16, 0.095, 0.27), RED, 14, 6)
			k.box(Vector3(0, -0.06, -0.07), Vector3(0.24, 0.02, 0.48), CREAM)
			for side: float in [-1.0, 1.0]:
				k.sphere(Vector3(side * 0.045, 0.09, -0.03), Vector3(0.05, 0.03, 0.03), YELLOW, 8, 4)
		&"boots_knight":
			for i: int in 4:
				var z: float = 0.05 - float(i) * 0.06
				k.sphere(Vector3(0, 0.0 - float(i) * 0.008, z), Vector3(0.12 - float(i) * 0.015, 0.085 - float(i) * 0.01, 0.09), STEEL.lightened(float(i % 2) * 0.12), 10, 5)
			k.cylinder(Vector3(0, -0.02, -0.22), 0.0, 0.045, 0.1, STEEL, 6, Basis(Vector3.RIGHT, -PI * 0.5))
			k.cylinder(Vector3(0, 0.1, 0.03), 0.095, 0.1, 0.14, STEEL.lightened(0.05), 10)
		&"boots_gold":
			_shoe(k, GOLD, WHITE)
			k.cylinder(Vector3(0, 0.09, 0.03), 0.095, 0.1, 0.13, GOLD, 10)
			for i: int in 4:
				k.box(Vector3(0, 0.07 + float(i) * 0.025, -0.06 + float(i) * 0.012), Vector3(0.07, 0.008, 0.008), BURGUNDY)
			k.prism(OutfitMeshKit.star_poly(5, 0.03, 0.013), 0.006, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.115, 0.03, 0.02)), WHITE)


## A plain shoe: the upper and a darker sole.
static func _shoe(k: OutfitMeshKit, upper: Color, sole: Color) -> void:
	k.sphere(Vector3(0, 0.0, -0.01), Vector3(0.12, 0.085, 0.175), upper, 12, 6)
	k.box(Vector3(0, -0.058, -0.01), Vector3(0.21, 0.022, 0.31), sole)
