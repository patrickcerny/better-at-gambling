class_name OutfitMeshes
extends RefCounted
## The low-poly models of every outfit piece in the cosmetics shop (data/progression/
## cosmetics_shop.tres): hats, shirts, trousers, capes, boots, beards and glasses, built in code
## from simple parts (`OutfitMeshKit`), no imported art. Parts that move on their own (a propeller,
## stars circling a hat) come separately (`spinners`); vertex alpha below 1 makes a part twinkle
## (`_glow`, toon_vertex_color.gdshader). Each piece is ONE mesh in vertex
## colours with one shared toon material, built once and shared by every bean that wears it.
## Warm casino colours, no neon (docs/ART_DIRECTION.md).
## Spaces: hats, shirts, trousers, capes, beards and glasses are in the bean body's space (`AvatarVisuals.body`,
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
	&"shirt_chef": WHITE, &"shirt_firefighter": Color("#B08A4A"), &"shirt_hivis": Color("#6B6B6B"),
	&"shirt_sailor": WHITE, &"shirt_jailbird": BLACK, &"shirt_referee": BLACK, &"shirt_hawaiian": Color("#C8503A"),
	&"shirt_knight": STEEL, &"shirt_hero": BLUE, &"shirt_flannel": Color("#A8322C"), &"shirt_sweater": FELT,
	&"shirt_pilot": WHITE, &"shirt_doctor": WHITE, &"shirt_captain": Color("#7A1F22"), &"shirt_royal": PURPLE,
	&"shirt_wizard": Color("#2E3E7A"), &"shirt_kid": Color("#C8463A"), &"shirt_bavarian": Color("#C9D6EA"),
	&"shirt_polo": Color("#E39AA6"),
}
const SUIT := Color("#2B3346")
const ROBE := Color("#2E3E7A")
const SCRUBS := Color("#5E9E9A")

static var _cache: Dictionary = {}
static var _spin_cache: Dictionary = {}
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
	elif s.begins_with("beard_"):
		_beard(k, id)
	elif s.begins_with("eyes_"):
		_glasses(k, id)
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


## Parts of piece `id` that turn on their own (a propeller, stars circling a wizard's hat):
## [{mesh, origin (body space), axis (body space), speed (radians a second)}].
static func spinners(id: StringName) -> Array[Dictionary]:
	if _spin_cache.has(id):
		return _spin_cache[id]
	var out: Array[Dictionary] = []
	match id:
		&"hat_propeller":
			var k := OutfitMeshKit.new()
			for side: float in [-1.0, 1.0]:
				k.sphere(Vector3(side * 0.14, 0.0, 0.0), Vector3(0.14, 0.012, 0.045), BLUE, 12, 4, Basis(Vector3.RIGHT, side * 0.3))
			k.sphere(Vector3.ZERO, Vector3.ONE * 0.032, RED, 8, 4)
			out.append(_hat_spinner(k, Vector3(0, 0.345, 0), 14.0))
		&"hat_wizard":
			var k := OutfitMeshKit.new()
			for i: int in 3:
				var ang: float = TAU * float(i) / 3.0
				k.prism(OutfitMeshKit.star_poly(5, 0.055, 0.024), 0.014, Transform3D(Basis(Vector3.UP, ang), Basis(Vector3.UP, ang) * Vector3(0, 0, 0.47)), _glow(YELLOW, 0.6))
				for j: int in 3:  # a little trail of sparkles behind each star
					var back: float = ang - 0.16 * float(j + 1)
					k.sphere(Basis(Vector3.UP, back) * Vector3(0, 0, 0.47), Vector3.ONE * (0.016 - float(j) * 0.004), _glow(CREAM, 0.6), 6, 3)
			out.append(_hat_spinner(k, Vector3(0, 0.3, 0), 1.3))
	_spin_cache[id] = out
	return out


static func _hat_spinner(k: OutfitMeshKit, at: Vector3, speed: float) -> Dictionary:
	var hat := Transform3D(Basis(Vector3.RIGHT, HAT_TILT), HAT_BASE)
	return {"mesh": k.commit(), "origin": hat * at, "axis": (hat.basis * Vector3.UP).normalized(), "speed": speed}


# --- Helpers ------------------------------------------------------------------------------------

## A twinkling colour: the outfit shaders make it glow in its own colour, pulsing.
static func _glow(c: Color, amount: float = 0.5) -> Color:
	return Color(c.r, c.g, c.b, 1.0 - amount)


## A flat thing at `at` facing `n` (+Z along `n`).
static func _facing(n: Vector3, at: Vector3) -> Transform3D:
	var d: Vector3 = n.normalized()
	return Transform3D(Basis.looking_at(-d, Vector3.UP if absf(d.y) < 0.95 else Vector3.BACK), at)


static func _ellipse(w: float, h: float, n: int = 18) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		p.append(Vector2(cos(a) * w, sin(a) * h))
	return p


## A crescent moon (`r` across).
static func _crescent(r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in 13:
		var a: float = lerpf(-PI * 0.75, PI * 0.75, float(i) / 12.0)
		p.append(Vector2(cos(a), sin(a)) * r)
	for i: int in 13:
		var a: float = lerpf(PI * 0.62, -PI * 0.62, float(i) / 12.0)
		p.append(Vector2(cos(a) * 0.8 + 0.42, sin(a) * 0.8) * r)
	return p


## A necktie's blade painted down the shirt front (true inside it): widening down to a point.
static func _in_tie(t: float, a: float, top: float, bottom: float) -> bool:
	if t > top or t < bottom:
		return false
	var w: float = lerpf(0.04, 0.08, (top - t) / (top - bottom))
	return _front(a) < w * clampf((t - bottom) / 0.025, 0.0, 1.0)


## The two points of a shirt collar either side of the neck.
static func _collar_points(k: OutfitMeshKit, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var f: Transform3D = OutfitMeshKit.body_frame(SHIRT_FRONT - 0.012, side * 0.12, SHIRT_INFLATE + 0.006)
		k.prism(PackedVector2Array([Vector2(side * -0.05, 0.02), Vector2(side * 0.04, 0.02), Vector2(side * -0.02, -0.04)]), 0.008, f, color)


## A folded pocket square in the breast pocket.
static func _pocket_square(k: OutfitMeshKit, color: Color) -> void:
	var f: Transform3D = OutfitMeshKit.body_frame(0.335, 0.62, SHIRT_INFLATE + 0.003)
	k.prism(PackedVector2Array([Vector2(-0.042, -0.008), Vector2(0.042, -0.008), Vector2(0.03, 0.028), Vector2(0.008, 0.012), Vector2(-0.012, 0.032), Vector2(-0.032, 0.014)]), 0.008, f, color)


## A tube along `path` (a stethoscope, a cord): cylinders between the points, balls at the joints.
static func _tube(k: OutfitMeshKit, path: PackedVector3Array, r: float, color: Color) -> void:
	for i: int in path.size():
		k.sphere(path[i], Vector3.ONE * r, color, 6, 3)
		if i + 1 < path.size():
			var d: Vector3 = path[i + 1] - path[i]
			if d.length() > 1e-5:
				k.cylinder((path[i] + path[i + 1]) * 0.5, r, r, d.length(), color, 6, Basis(Quaternion(Vector3.UP, d.normalized())))


## Little round dots scattered over the body between heights `t0` and `t1` (twinkles, flecks).
static func _scatter(k: OutfitMeshKit, n: int, t0: float, t1: float, inflate: float, color: Color, r: float, salt: int) -> void:
	for i: int in n:
		var t: float = lerpf(t0, t1, _hash(i, 1, salt))
		var a: float = (_hash(i, 2, salt) - 0.5) * TAU
		k.sphere(OutfitMeshKit.body_point(t, a, inflate), Vector3(r, r, r), color, 6, 3)


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
			k.cylinder(Vector3(0, 0.015, 0), 0.54, 0.54, 0.03, ROBE, 22, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.2, 0), 0.17, 0.33, 0.4, ROBE, 18, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.5, 0.08), 0.0, 0.17, 0.32, ROBE, 14, Basis(Vector3.RIGHT, 0.55))
			k.cylinder(Vector3(0, 0.05, 0), 0.335, 0.335, 0.06, GOLD, 18, Basis.IDENTITY, D)
			k.sphere(Vector3(0, 0.636, 0.164), Vector3.ONE * 0.035, _glow(GOLD, 0.4), 8, 4)
			k.prism(OutfitMeshKit.star_poly(5, 0.055, 0.024), 0.012, Transform3D(Basis(Vector3.RIGHT, 0.2).rotated(Vector3.UP, PI), Vector3(-0.06, 0.2, -0.27)), _glow(YELLOW, 0.45))
			k.prism(OutfitMeshKit.star_poly(5, 0.035, 0.016), 0.012, Transform3D(Basis(Vector3.RIGHT, 0.2).rotated(Vector3.UP, PI * 0.8), Vector3(0.12, 0.3, -0.18)), _glow(YELLOW, 0.45))
			k.prism(_crescent(0.05), 0.012, Transform3D(Basis(Vector3.RIGHT, 0.2).rotated(Vector3.UP, PI * 1.2), Vector3(-0.15, 0.32, -0.17)), _glow(CREAM, 0.35))
			k.prism(OutfitMeshKit.star_poly(5, 0.03, 0.014), 0.012, Transform3D(Basis(Vector3.RIGHT, 0.1).rotated(Vector3.UP, PI * 0.25), Vector3(0.24, 0.16, 0.2)), _glow(YELLOW, 0.45))
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
			# Four panels in turn, a peak, and the propeller on top (it spins: `spinners`).
			for i: int in 4:
				var seg := func(u: float, v: float) -> Vector3:
					var a: float = (float(i) + u) * TAU / 4.0
					var el: float = v * PI * 0.5
					return Vector3(sin(a) * cos(el) * 0.355, -0.01 + sin(el) * 0.29, cos(a) * cos(el) * 0.335)
				k.surface(seg, 8, 6, func(_u: float, _v: float) -> Color: return [RED, YELLOW, BLUE, FELT][i], func(p: Vector3) -> Vector3: return p)
			k.dome(Vector3(0, 0.0, -0.29), Vector3(0.25, 0.03, 0.17), RED.darkened(0.1), 14, Basis(Vector3.RIGHT, -0.2))
			k.cylinder(Vector3(0, 0.3, 0), 0.02, 0.02, 0.08, YELLOW, 6)
		&"hat_viking":
			k.dome(Vector3(0, -0.01, 0), Vector3(0.36, 0.31, 0.35), STEEL, 16)
			k.torus(Vector3(0, 0.02, 0), 0.33, 0.39, Color("#A0743A"), 16, Basis.IDENTITY, D)
			k.box(Vector3(0, 0.2, -0.3), Vector3(0.05, 0.24, 0.04), Color("#A0743A"), Basis(Vector3.RIGHT, 0.6))
			for side: float in [-1.0, 1.0]:
				k.cylinder(Vector3(side * 0.4, 0.12, 0), 0.055, 0.08, 0.2, CREAM, 8, Basis(Vector3.BACK, -side * 1.15))
				k.cylinder(Vector3(side * 0.51, 0.25, 0), 0.03, 0.055, 0.17, CREAM, 8, Basis(Vector3.BACK, -side * 0.45))
				k.cylinder(Vector3(side * 0.535, 0.37, 0), 0.0, 0.03, 0.1, CREAM.darkened(0.1), 8, Basis(Vector3.BACK, side * 0.1))
		&"hat_hair_slick":
			var hair := Color("#3A2A1E")
			k.dome(Vector3(0, -0.07, 0.01), Vector3(0.36, 0.31, 0.355), hair, 18)
			k.sphere(Vector3(-0.08, 0.17, -0.19), Vector3(0.24, 0.11, 0.16), hair.lightened(0.05), 14, 7, Basis(Vector3.BACK, 0.25))
			k.sphere(Vector3(0.12, 0.19, -0.12), Vector3(0.2, 0.09, 0.17), hair, 12, 6, Basis(Vector3.BACK, -0.2))
			k.sphere(Vector3(0.14, 0.235, 0.02), Vector3(0.012, 0.012, 0.25), hair.darkened(0.5), 6, 3)  # the side part
			k.sphere(Vector3(-0.1, 0.26, -0.13), Vector3(0.09, 0.016, 0.05), hair.lightened(0.4), 8, 3, Basis(Vector3.BACK, 0.25))
		&"hat_pilot":
			k.cylinder(Vector3(0, 0.09, 0), 0.34, 0.33, 0.18, NAVY, 18, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.035, 0), 0.338, 0.338, 0.06, BLACK, 18, Basis.IDENTITY, D)
			k.cylinder(Vector3(0, 0.215, -0.02), 0.41, 0.36, 0.08, WHITE, 18, Basis.IDENTITY, D)
			k.dome(Vector3(0, 0.005, -0.27), Vector3(0.24, 0.035, 0.17), BLACK, 14, Basis(Vector3.RIGHT, -0.3))
			for side: float in [-1.0, 1.0]:  # gold oak leaves on the peak
				k.sphere(Vector3(side * 0.08, 0.03, -0.37), Vector3(0.07, 0.01, 0.025), GOLD, 8, 3, Basis(Vector3.UP, side * 0.35) * Basis(Vector3.RIGHT, -0.3))
			var badge := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0, 0.12, -0.315))
			k.prism(OutfitMeshKit.circle_poly(0.03, 12), 0.014, badge, GOLD)
			for side: float in [-1.0, 1.0]:
				k.prism(PackedVector2Array([Vector2(0, 0.015), Vector2(side * 0.11, 0.032), Vector2(side * 0.095, 0.008), Vector2(side * 0.06, -0.016), Vector2(0, -0.012)]), 0.01, badge, GOLD)
		&"hat_surgeon":
			k.dome(Vector3(0, -0.06, 0.0), Vector3(0.362, 0.29, 0.352), SCRUBS, 20)
			k.torus(Vector3(0, -0.035, 0), 0.34, 0.375, SCRUBS.darkened(0.1), 20, Basis.from_scale(Vector3(1, 0.5, 1)), D)
			for side: float in [-1.0, 1.0]:  # the tie at the back
				k.sphere(Vector3(side * 0.045, 0.01, 0.345), Vector3(0.05, 0.028, 0.02), SCRUBS.darkened(0.15), 8, 4, Basis(Vector3.BACK, side * 0.3))
				k.sphere(Vector3(side * 0.03, -0.06, 0.35), Vector3(0.018, 0.07, 0.014), SCRUBS.darkened(0.15), 6, 3, Basis(Vector3.BACK, side * 0.25))
		&"hat_knight":
			var steel := Color("#9AA0A8")
			k.dome(Vector3(0, -0.05, 0), Vector3(0.375, 0.35, 0.365), steel, 20)
			k.cylinder(Vector3(0, -0.02, 0), 0.38, 0.385, 0.07, steel.darkened(0.2), 20, Basis.IDENTITY, D)
			k.sphere(Vector3(0, 0.08, 0), Vector3(0.03, 0.26, 0.37), steel.lightened(0.15), 12, 8)  # the comb
			for side: float in [-1.0, 1.0]:  # cheek plates
				k.sphere(Vector3(side * 0.37, -0.07, -0.02), Vector3(0.035, 0.11, 0.13), steel.darkened(0.1), 12, 6)
			for i: int in 12:
				var ang: float = TAU * float(i) / 12.0
				k.sphere(Vector3(sin(ang) * 0.388, -0.02, cos(ang) * 0.388 * D), Vector3.ONE * 0.017, GOLD.darkened(0.1), 6, 3)
			k.cylinder(Vector3(0, 0.31, 0.03), 0.03, 0.045, 0.07, GOLD, 10)
			for i: int in 6:  # the plume, falling back
				var f: float = float(i)
				k.sphere(Vector3(0, 0.37 + f * 0.02, 0.05 + f * 0.07), Vector3(0.065, 0.1 - f * 0.01, 0.09), RED.darkened(f * 0.05), 10, 5, Basis(Vector3.RIGHT, -0.5 - f * 0.18))
		&"hat_tyrolean":
			var felt := Color("#3E5B3A")
			k.cylinder(Vector3(0, 0.15, 0), 0.24, 0.32, 0.3, felt, 16, Basis.IDENTITY, D)
			k.sphere(Vector3(0, 0.3, 0), Vector3(0.24, 0.035, 0.26), felt.darkened(0.12), 14, 4)
			k.cylinder(Vector3(0, 0.015, 0.03), 0.45, 0.45, 0.025, felt, 22, Basis(Vector3.RIGHT, 0.2), D)
			for i: int in 28:  # the twisted cord
				var ang: float = TAU * float(i) / 28.0
				k.sphere(Vector3(sin(ang) * 0.318, 0.055, cos(ang) * 0.318 * D), Vector3(0.028, 0.022, 0.028), [RED, CREAM][i % 2], 6, 3)
			k.sphere(Vector3(0.29, 0.21, 0.1), Vector3(0.022, 0.2, 0.045), Color("#7A5A3A"), 8, 5, Basis(Vector3.BACK, -0.45) * Basis(Vector3.RIGHT, 0.25))
			k.sphere(Vector3(0.36, 0.33, 0.14), Vector3(0.012, 0.09, 0.03), Color("#C9B79A"), 6, 3, Basis(Vector3.BACK, -0.6))
			for i: int in 7:  # the tuft
				var a: float = -0.6 + float(i) * 0.2
				k.sphere(Vector3(0.28 + sin(a) * 0.04, 0.14 + cos(a) * 0.08, 0.17), Vector3(0.03, 0.09, 0.03), Color("#4A3E34").lightened(_hash(i, 1, 9) * 0.25), 6, 3, Basis(Vector3.BACK, a))
		&"hat_golf":
			var tweed := Color("#9C8A6A")
			k.dome(Vector3(0, -0.03, 0.02), Vector3(0.36, 0.2, 0.37), tweed, 18)
			k.sphere(Vector3(0, 0.1, -0.05), Vector3(0.38, 0.1, 0.41), tweed, 18, 7, Basis(Vector3.RIGHT, 0.16))
			k.dome(Vector3(0, -0.005, -0.31), Vector3(0.26, 0.03, 0.16), tweed.darkened(0.18), 14, Basis(Vector3.RIGHT, -0.15))
			k.sphere(Vector3(0, 0.205, -0.07), Vector3.ONE * 0.028, tweed.darkened(0.3), 8, 4)
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
			var lapel := Color("#3A4560")
			var tie := Color("#7A1F2C")
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _in_v(t, a, 0.5, 0.21):
					if _in_tie(t, a, 0.385, 0.215):
						return tie if fposmod(t * 60.0 + a * 10.0, 2.0) < 1.55 else GOLD.darkened(0.15)
					return WHITE
				if _in_v(t, a, 0.66, 0.215):
					return lapel
				if _front(a) < 0.012 and t < 0.215:
					return lapel  # where the jacket closes
				if absf(_front(a) - 0.95) < 0.11 and absf(t - 0.215) < 0.006:
					return lapel  # pocket flaps
				return SUIT, 0.035)
			_tie_knot(k, tie)
			_collar_points(k, WHITE)
			_pocket_square(k, WHITE)
			k.prism(_ellipse(0.045, 0.006), 0.006, OutfitMeshKit.body_frame(0.325, 0.62, inf + 0.002), lapel)
			_button(k, 0.19, 0.0, inf, Color("#15181F"), 0.018)
		&"shirt_tux":
			var satin := Color("#4A4542")
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _in_v(t, a, 0.52, 0.215):
					return WHITE
				if _in_v(t, a, 0.69, 0.222):
					return satin
				if _front(a) < 0.012 and t < 0.215:
					return satin
				return BLACK, 0.035)
			_bow_tie(k, BLACK)
			for t: float in [0.255, 0.29, 0.325]:
				_button(k, t, 0.0, inf, BLACK, 0.011)
			_button(k, 0.2, 0.0, inf, satin, 0.018)
			_pocket_square(k, WHITE)
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
			var coat := Color("#B08A4A")
			var dark := Color("#2A2420")
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				for t0: float in [0.2, 0.3]:
					if t > t0 and t < t0 + 0.036:
						return SILVER if absf(t - t0 - 0.018) < 0.007 else YELLOW
				if _front(a) < 0.03:
					return dark  # the front closure
				if top.call(a) - t < 0.03 and _front(a) < 1.4:
					return dark  # the collar
				return coat, 0.035)
			for t: float in [0.25, 0.28, 0.345, 0.375]:
				var f: Transform3D = OutfitMeshKit.body_frame(t, 0.0, inf + 0.004)
				k.sphere(f.origin, Vector3(0.03, 0.009, 0.009), SILVER, 8, 4, f.basis)
			var radio: Transform3D = OutfitMeshKit.body_frame(0.35, -0.55, inf + 0.02)
			k.sphere(radio.origin, Vector3(0.035, 0.05, 0.02), dark, 10, 5, radio.basis)
			k.cylinder(radio * Vector3(0.02, 0.07, 0.0), 0.006, 0.006, 0.06, dark, 6, radio.basis)
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
		&"shirt_pilot":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _in_tie(t, a, 0.385, 0.22):
					return NAVY
				if absf(_front(a) - 0.55) < 0.1 and absf(t - 0.335) < 0.004:
					return WHITE.darkened(0.14)  # pocket flaps
				if _front(a) < 0.01 and t < 0.37:
					return WHITE.darkened(0.12)
				return WHITE)
			_tie_knot(k, NAVY)
			_collar_points(k, WHITE)
			for side: float in [-1.0, 1.0]:  # epaulettes with four gold bars
				var p: Vector3 = OutfitMeshKit.body_point(0.5, side * PI * 0.5, 0.03)
				k.sphere(p, Vector3(0.07, 0.022, 0.11), NAVY, 10, 5)
				for j: int in 4:
					k.sphere(p + Vector3(0, 0.017, -0.05 + float(j) * 0.028), Vector3(0.06, 0.008, 0.008), GOLD, 8, 3)
			var wings: Transform3D = OutfitMeshKit.body_frame(0.35, 0.55, inf + 0.002)
			k.prism(OutfitMeshKit.circle_poly(0.018, 10), 0.012, wings, GOLD)
			for side: float in [-1.0, 1.0]:
				k.prism(PackedVector2Array([Vector2(0, 0.01), Vector2(side * 0.075, 0.022), Vector2(side * 0.065, 0.004), Vector2(side * 0.04, -0.012), Vector2(0, -0.008)]), 0.008, wings, GOLD)
			k.prism(_ellipse(0.04, 0.01), 0.008, OutfitMeshKit.body_frame(0.35, -0.55, inf + 0.002), GOLD)
		&"shirt_doctor":
			var seam := WHITE.darkened(0.13)
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				var f: float = _front(a)
				if _in_v(t, a, 0.36, 0.27):
					return SCRUBS
				if _in_v(t, a, 0.52, 0.255):
					return WHITE.darkened(0.06)
				if f < 0.01 and t < 0.27:
					return seam
				if absf(f - 0.75) < 0.12 and t > 0.19 and t < 0.24 and (t > 0.234 or absf(f - 0.75) > 0.11):
					return seam  # side pockets
				if absf(f - 0.5) < 0.08 and absf(t - 0.335) < 0.003:
					return seam
				return WHITE, 0.04)
			for i: int in 2:  # pens in the chest pocket
				var pen: Transform3D = OutfitMeshKit.body_frame(0.345, -0.47 - float(i) * 0.05, inf + 0.01)
				k.cylinder(pen.origin, 0.008, 0.008, 0.07, [BLUE, RED][i], 6, pen.basis)
			# A stethoscope around the neck: down the chest on both sides, the bell on one end.
			var tube := Color("#2A2A2E")
			for side: float in [-1.0, 1.0]:
				var path := PackedVector3Array()
				var end_t: float = 0.27 if side < 0.0 else 0.31
				for i: int in 10:
					path.append(OutfitMeshKit.body_point(lerpf(end_t, top.call(0.42) - 0.012, float(i) / 9.0), side * 0.42, inf + 0.02))
				for i: int in 24:
					var a: float = side * lerpf(0.42, PI, float(i + 1) / 24.0)
					path.append(OutfitMeshKit.body_point(top.call(a) - 0.012, a, inf + 0.02))
				_tube(k, path, 0.011, tube)
			var bell: Transform3D = OutfitMeshKit.body_frame(0.26, -0.42, inf + 0.022)
			k.prism(OutfitMeshKit.circle_poly(0.032, 14), 0.014, bell, SILVER)
			k.sphere(OutfitMeshKit.body_point(0.3, 0.42, inf + 0.03), Vector3.ONE * 0.016, SILVER, 6, 3)
		&"shirt_captain":
			var coat := Color("#7A1F22")
			var opening := func(t: float) -> float: return 0.12 + (SHIRT_FRONT - t) * 0.9
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				var f: float = _front(a)
				if t > 0.205 and t < 0.235:
					return BLACK  # the wide belt
				var o: float = opening.call(t)
				if f < o:
					return WHITE if int(floor(t / 0.02)) % 2 == 0 else CREAM
				if f < o + 0.07 or t < b + 0.018:
					return GOLD  # braid along the opening and the hem
				if top.call(a) - t < 0.03:
					return GOLD.darkened(0.15)
				return coat, 0.05)
			for t: float in [0.26, 0.3, 0.34]:
				for side: float in [-1.0, 1.0]:
					_button(k, t, side * (opening.call(t) + 0.16), inf, GOLD, 0.017)
			var buckle: Transform3D = OutfitMeshKit.body_frame(0.22, 0.0, inf + 0.003)
			k.prism(_ellipse(0.05, 0.034), 0.012, buckle, GOLD)
			k.prism(_ellipse(0.03, 0.017), 0.016, buckle, BLACK)
			for i: int in 4:  # the jabot
				k.sphere(OutfitMeshKit.body_point(0.385 - float(i) * 0.028, 0.0, inf + 0.022), Vector3(0.06 - float(i) * 0.008, 0.024, 0.025), WHITE, 10, 4)
			for side: float in [-1.0, 1.0]:  # fringed epaulettes
				var p: Vector3 = OutfitMeshKit.body_point(0.5, side * PI * 0.5, 0.035)
				k.sphere(p, Vector3(0.08, 0.03, 0.11), GOLD, 12, 5)
				for j: int in 7:
					var z: float = -0.08 + float(j) * 0.027
					k.cylinder(p + Vector3(side * 0.075, -0.035, z), 0.007, 0.007, 0.05, GOLD.darkened(0.1), 5)
		&"shirt_royal":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				var f: float = _front(a)
				if top.call(a) - t < 0.035:
					return BLACK if _hash(int(t * 300.0), int(a * 14.0), 6) < 0.1 else WHITE  # ermine
				if f < 0.05 or t < b + 0.022:
					return GOLD
				if absf(f - 0.42) < 0.02:
					return GOLD.darkened(0.12)
				var x: float = fposmod((a + PI) / 0.22, 1.0) - 0.5
				var y: float = fposmod(t / 0.045, 1.0) - 0.5
				return PURPLE.lightened(0.1) if absf(x) + absf(y) < 0.2 else PURPLE)
			for i: int in 15:  # the chain of office
				var a: float = lerpf(-1.15, 1.15, float(i) / 14.0)
				var t: float = 0.28 + 0.085 * pow(absf(a) / 1.15, 1.6)
				k.sphere(OutfitMeshKit.body_point(t, a, inf + 0.018), Vector3(0.02, 0.016, 0.016), GOLD, 8, 3)
			var medal: Transform3D = OutfitMeshKit.body_frame(0.255, 0.0, inf + 0.02)
			k.prism(OutfitMeshKit.circle_poly(0.045, 16), 0.012, medal, GOLD)
			k.prism(OutfitMeshKit.circle_poly(0.024, 12), 0.016, medal, _glow(RED, 0.3))
			for t: float in [0.2, 0.235]:
				_button(k, t, 0.0, inf, GOLD.lightened(0.15), 0.014)
		&"shirt_wizard":
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _front(a) < 0.05 or top.call(a) - t < 0.022:
					return GOLD
				return ROBE, 0.02)
			for e: Vector3 in [Vector3(0.32, -0.45, 0.045), Vector3(0.25, 0.6, 0.035), Vector3(0.28, 2.3, 0.05), Vector3(0.22, -2.6, 0.04), Vector3(0.36, 3.0, 0.035), Vector3(0.21, -1.4, 0.03)]:
				_emblem(k, OutfitMeshKit.star_poly(5, e.z, e.z * 0.45), e.x, e.y, inf + 0.002, _glow(YELLOW, 0.45))
			_emblem(k, _crescent(0.05), 0.33, 0.5, inf + 0.002, _glow(CREAM, 0.3))
			_scatter(k, 26, 0.19, 0.42, inf + 0.003, _glow(CREAM, 0.6), 0.009, 21)
			for i: int in 44:  # rope belt
				k.sphere(OutfitMeshKit.body_point(0.2, TAU * float(i) / 44.0, inf + 0.012), Vector3.ONE * 0.017, GOLD.darkened(0.15), 6, 3)
			for side: float in [-1.0, 1.0]:
				k.sphere(OutfitMeshKit.body_point(0.17, side * 0.3, inf + 0.022), Vector3(0.016, 0.045, 0.016), GOLD, 6, 3)
				k.sphere(OutfitMeshKit.body_point(0.135, side * 0.3, inf + 0.026), Vector3(0.026, 0.035, 0.022), GOLD.darkened(0.1), 8, 4)
		&"shirt_kid":
			var tee := Color("#C8463A")
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if top.call(a) - t < 0.02:
					return WHITE
				if t > 0.215 and t < 0.25:
					return YELLOW
				return tee)
			var star: Transform3D = OutfitMeshKit.body_frame(0.315, 0.0, inf + 0.002)
			k.prism(OutfitMeshKit.star_poly(5, 0.09, 0.04), 0.012, star, YELLOW)
			k.prism(OutfitMeshKit.star_poly(5, 0.05, 0.022), 0.016, star, WHITE)
		&"shirt_bavarian":
			var vest := Color("#3E5B3A")
			var check := func(t: float, a: float) -> Color:
				var x: bool = int(floor((a + PI) / (TAU / 40.0))) % 2 == 0
				var y: bool = int(floor(t / 0.02)) % 2 == 0
				return Color("#2F5DA8") if x and y else (Color("#8FAAD4") if x or y else WHITE)
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if _in_v(t, a, 0.5, 0.26):
					return check.call(t, a)
				if absf(_front(a) - 0.5) < 0.012 and t > 0.26:
					return vest.lightened(0.25)  # stitched edge of the lapel
				if _front(a) < 0.012:
					return vest.darkened(0.35)
				return vest)
			for t: float in [0.19, 0.215, 0.24]:
				_button(k, t, 0.0, inf, SILVER.lightened(0.1), 0.017)
			for side: float in [-1.0, 1.0]:
				_emblem(k, OutfitMeshKit.star_poly(6, 0.032, 0.013), 0.31, side * 0.75, inf + 0.002, WHITE)
				_button(k, 0.31, side * 0.75, inf + 0.012, YELLOW, 0.009)
		&"shirt_polo":
			var polo := Color("#E39AA6")
			k.band(b, top, inf, func(t: float, a: float) -> Color:
				if top.call(a) - t < 0.03:
					return WHITE
				if _front(a) < 0.035 and t > 0.31:
					return polo.darkened(0.12)
				return polo)
			_collar_points(k, WHITE)
			for t: float in [0.33, 0.36]:
				_button(k, t, 0.0, inf, WHITE, 0.011)
			var flag: Transform3D = OutfitMeshKit.body_frame(0.33, 0.55, inf + 0.002)
			k.cylinder(flag.origin, 0.004, 0.004, 0.06, WHITE, 5, flag.basis)
			k.prism(PackedVector2Array([Vector2(0, 0.03), Vector2(0.035, 0.018), Vector2(0, 0.006)]), 0.006, flag, RED)
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
					return BLACK
				return SUIT.darkened(0.2) if absf(_front(a) - 0.32) < 0.012 else SUIT)
			_buckle(k, SILVER)
		&"pants_tux":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.165:
					return BLACK if int(floor(t / 0.012)) % 2 == 0 else Color("#4A4542")  # pleated cummerbund
				return Color("#4A4542") if absf(_front(a) - PI * 0.5) < 0.05 else BLACK)
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
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.06 and t < 0.096:
					return SILVER if absf(t - 0.078) < 0.007 else YELLOW
				if absf(_front(a) - 0.5) < 0.22 and t > 0.02 and t < 0.055:
					return Color("#8A6A3A")  # knee pads
				return Color("#B08A4A"))
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
		&"pants_breeches":
			k.band(0.0, top, inf, func(t: float, _a: float) -> Color:
				if t < 0.04:
					return CREAM  # stockings
				if t < 0.055:
					return Color("#2E2622").lightened(0.15)
				if t > 0.162:
					return RED if int(floor(t / 0.01)) % 3 != 0 else RED.darkened(0.15)  # the sash
				return Color("#2E2622"))
			k.sphere(OutfitMeshKit.body_point(0.18, 1.2, inf + 0.03), Vector3(0.065, 0.05, 0.05), RED.darkened(0.1), 10, 5)
			k.sphere(OutfitMeshKit.body_point(0.12, 1.15, inf + 0.035), Vector3(0.035, 0.08, 0.025), RED.darkened(0.15), 8, 4)
			k.sphere(OutfitMeshKit.body_point(0.125, 1.3, inf + 0.035), Vector3(0.03, 0.07, 0.022), RED.darkened(0.2), 8, 4)
			for side: float in [-1.0, 1.0]:
				_button(k, 0.047, side * 1.0, inf, GOLD, 0.014)
		&"pants_royal":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t < 0.04:
					return WHITE
				if t < 0.055 or t > 0.18:
					return GOLD.darkened(0.1)
				if absf(fposmod((a + PI) / 0.32, 1.0) - 0.5) < 0.09 and t > 0.07 and t < 0.165:
					return GOLD.darkened(0.15)  # the slashes
				return PURPLE)
			var jewel: Transform3D = OutfitMeshKit.body_frame(0.192, 0.0, inf + 0.004)
			k.prism(_ellipse(0.04, 0.026), 0.012, jewel, GOLD)
			k.prism(_ellipse(0.02, 0.014), 0.016, jewel, _glow(RED, 0.3))
		&"pants_knight":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				var f: float = _front(a)
				if (f < 0.45 or _back(a) < 0.45) and t > 0.085 and t < 0.178:
					if t < 0.103:
						return RED
					return RED if f < 0.07 else WHITE  # the tabard and its cross
				if t > 0.178:
					return BROWN
				var shade: float = fposmod(t, 0.028) / 0.028
				return STEEL.lightened(0.22 * shade) if int(floor(t / 0.028)) % 2 == 0 else SILVER.darkened(0.05 + 0.1 * shade))
			for side: float in [-1.0, 1.0]:
				k.sphere(OutfitMeshKit.body_point(0.055, side * 0.75, inf + 0.02), Vector3(0.075, 0.06, 0.05), SILVER, 12, 6)
				k.sphere(OutfitMeshKit.body_point(0.055, side * 0.98, inf + 0.022), Vector3(0.035, 0.065, 0.05), SILVER.darkened(0.1), 10, 5)
				for i: int in 3:
					_button(k, 0.014 + float(i) * 0.028, side * 1.55, inf, GOLD.darkened(0.15), 0.011)
			_buckle(k, STEEL)
		&"pants_wizard":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if _front(a) < 0.05 or t < 0.03:
					return GOLD
				return ROBE)
			for e: Vector3 in [Vector3(0.09, -0.8, 0.04), Vector3(0.13, 1.3, 0.035), Vector3(0.07, 2.6, 0.045), Vector3(0.12, -2.2, 0.035)]:
				_emblem(k, OutfitMeshKit.star_poly(5, e.z, e.z * 0.45), e.x, e.y, inf + 0.002, _glow(YELLOW, 0.45))
			_scatter(k, 18, 0.04, 0.19, inf + 0.003, _glow(CREAM, 0.6), 0.009, 22)
		&"pants_overalls":
			var denim := Color("#4A6FA5")
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if absf(_front(a) - 1.5) < 0.012:
					return YELLOW.darkened(0.15)  # side seam
				return denim)
			# The bib and straps up over the shirt.
			var neck: Callable = OutfitMeshKit.neckline(SHIRT_FRONT + 0.005, SHIRT_BACK + 0.01)
			k.band(PANTS_TOP - 0.02, neck, SHIRT_INFLATE + 0.008, func(t: float, a: float) -> Color:
				var f: float = _front(a)
				if f < 0.42 and t < 0.31:
					if f < 0.2 and t > 0.25 and t < 0.29:
						return denim.darkened(0.15)  # bib pocket
					return denim
				if absf(f - 0.32) < 0.07 or absf(_back(a) - 0.3) < 0.07:
					return denim
				return Color(0, 0, 0, 0), 0.0, 72, 30)
			for side: float in [-1.0, 1.0]:
				_button(k, 0.302, side * 0.32, SHIRT_INFLATE + 0.012, YELLOW, 0.02)
			var patch: Transform3D = OutfitMeshKit.body_frame(0.08, 0.5, inf + 0.002)
			k.prism(OutfitMeshKit.star_poly(5, 0.045, 0.02), 0.008, patch, ORANGE)
		&"pants_chaps":
			var chaps := Color("#8A5A32")
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				var f: float = _front(a)
				if t > 0.178:
					return LEATHER.darkened(0.15)
				if f > 0.2 and f < 2.2 and t < 0.172:
					if f > 2.12 or f < 0.26:
						return TAN if int(floor(t / 0.01)) % 2 == 0 else chaps.darkened(0.2)  # laced edge
					return chaps
				if f < 0.015 and t > 0.08:
					return GOLD.darkened(0.2)
				return DENIM)
			for i: int in 4:
				for side: float in [-1.0, 1.0]:
					_emblem(k, OutfitMeshKit.circle_poly(0.02, 12), 0.035 + float(i) * 0.04, side * 1.6, inf + 0.003, SILVER)
			for i: int in 7:
				for side: float in [-1.0, 1.0]:
					k.sphere(OutfitMeshKit.body_point(0.02 + float(i) * 0.024, side * 2.24, inf + 0.02), Vector3(0.012, 0.03, 0.012), TAN, 6, 3)
			var buckle: Transform3D = OutfitMeshKit.body_frame(0.19, 0.0, inf + 0.003)
			k.prism(_ellipse(0.055, 0.035), 0.012, buckle, SILVER)
			k.prism(OutfitMeshKit.star_poly(5, 0.022, 0.01), 0.016, buckle, GOLD)
		&"pants_pilot":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.175:
					return BLACK
				return NAVY.darkened(0.25) if absf(_front(a) - 0.32) < 0.012 else NAVY)
			_buckle(k, SILVER)
		&"pants_scrubs":
			k.band(0.0, top, inf, func(t: float, a: float) -> Color:
				if t > 0.18:
					return SCRUBS.darkened(0.1)
				if absf(_front(a) - PI * 0.5) < 0.01:
					return SCRUBS.darkened(0.2)
				return SCRUBS)
			for side: float in [-1.0, 1.0]:
				k.sphere(OutfitMeshKit.body_point(0.17, side * 0.06, inf + 0.012), Vector3(0.008, 0.035, 0.008), WHITE, 6, 3)
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
	k.prism(_ellipse(0.042, 0.025), 0.012, f, color)


## Two straps from the waistband over the shoulders (`width` = their angle apart at the front).
static func _suspenders(k: OutfitMeshKit, color: Color, spread: float) -> void:
	var top: Callable = OutfitMeshKit.neckline(SHIRT_FRONT + 0.005, SHIRT_BACK + 0.01)
	k.band(PANTS_TOP - 0.02, top, SHIRT_INFLATE + 0.006, func(_t: float, a: float) -> Color:
		var front_strap: bool = absf(_front(a) - spread) < 0.07
		var back_strap: bool = absf(_back(a) - spread * 0.8) < 0.07
		return color if front_strap or back_strap else Color(0, 0, 0, 0), 0.0, 72, 16)


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
			_sole(k, Vector3(0, -0.05, 0.09), Vector3(0.09, 0.05, 0.06), BROWN.darkened(0.3))
			k.cylinder(Vector3(0, 0.12, 0.03), 0.1, 0.095, 0.2, TAN.darkened(0.2), 10)
			k.cylinder(Vector3(0, 0.1, 0.03), 0.101, 0.098, 0.03, CREAM.darkened(0.2), 10)
			k.torus(Vector3(0.0, 0.0, 0.13), 0.025, 0.035, SILVER, 8, Basis(Vector3.RIGHT, PI * 0.5))
			k.prism(OutfitMeshKit.star_poly(6, 0.03, 0.012), 0.006, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.0, 0.16)), SILVER)
		&"boots_clogs":
			k.sphere(Vector3(0, 0.0, -0.02), Vector3(0.13, 0.09, 0.19), WHITE, 12, 6)
			_sole(k, Vector3(0, -0.055, -0.02), Vector3(0.2, 0.025, 0.32), CREAM.darkened(0.2))
			k.torus(Vector3(0, 0.04, 0.06), 0.11, 0.125, WHITE.darkened(0.1), 12, Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5))
		&"boots_firefighter":
			_shoe(k, BLACK, BLACK.lightened(0.1))
			k.cylinder(Vector3(0, 0.1, 0.02), 0.095, 0.105, 0.17, BLACK, 10)
			k.cylinder(Vector3(0, 0.08, 0.02), 0.107, 0.107, 0.03, YELLOW, 10)
			_sole(k, Vector3(0, -0.06, -0.02), Vector3(0.2, 0.02, 0.32), YELLOW.darkened(0.2))
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
			_sole(k, Vector3(0, -0.06, -0.07), Vector3(0.24, 0.02, 0.48), CREAM)
			for side: float in [-1.0, 1.0]:
				k.sphere(Vector3(side * 0.045, 0.09, -0.03), Vector3(0.05, 0.03, 0.03), YELLOW, 8, 4)
		&"boots_knight":
			for i: int in 4:
				var z: float = 0.05 - float(i) * 0.06
				k.sphere(Vector3(0, 0.0 - float(i) * 0.008, z), Vector3(0.12 - float(i) * 0.015, 0.085 - float(i) * 0.01, 0.09), STEEL.lightened(float(i % 2) * 0.12), 10, 5)
			k.cylinder(Vector3(0, -0.02, -0.22), 0.0, 0.045, 0.1, STEEL, 6, Basis(Vector3.RIGHT, -PI * 0.5))
			k.cylinder(Vector3(0, 0.1, 0.03), 0.095, 0.1, 0.14, STEEL.lightened(0.05), 10)
		&"boots_pilot":
			_shoe(k, BLACK, BLACK.lightened(0.06))
			k.sphere(Vector3(-0.04, 0.05, -0.12), Vector3(0.03, 0.012, 0.03), WHITE.darkened(0.2), 6, 3)
			for i: int in 3:
				k.sphere(Vector3(0, 0.072, -0.03 - float(i) * 0.03), Vector3(0.04, 0.006, 0.006), CHARCOAL, 6, 3)
		&"boots_royal":
			k.sphere(Vector3(0, 0.0, -0.01), Vector3(0.12, 0.085, 0.175), PURPLE, 14, 7)
			_sole(k, Vector3(0, -0.058, -0.01), Vector3(0.21, 0.022, 0.31), Color("#2A1A30"))
			_sole(k, Vector3(0, -0.07, 0.1), Vector3(0.1, 0.03, 0.08), GOLD.darkened(0.2))  # the heel
			k.cylinder(Vector3(0, 0.1, 0.03), 0.09, 0.1, 0.15, WHITE, 12)
			var buckle: Transform3D = _facing(Vector3(0, 1.0, -0.3), Vector3(0, 0.078, -0.09))
			k.prism(_ellipse(0.05, 0.036), 0.01, buckle, GOLD)
			k.prism(_ellipse(0.03, 0.018), 0.013, buckle, PURPLE.darkened(0.25))
		&"boots_hero":
			k.sphere(Vector3(0, 0.0, -0.01), Vector3(0.12, 0.085, 0.175), RED, 14, 7)
			_sole(k, Vector3(0, -0.058, -0.01), Vector3(0.21, 0.022, 0.31), RED.darkened(0.4))
			k.cylinder(Vector3(0, 0.1, 0.02), 0.096, 0.106, 0.16, RED, 12)
			k.cylinder(Vector3(0, 0.16, 0.02), 0.114, 0.108, 0.05, YELLOW, 12)
			k.prism(OutfitMeshKit.diamond_poly(0.03, 0.024), 0.01, _facing(Vector3(0, 0, -1), Vector3(0, 0.16, -0.093)), RED)
		&"boots_wizard":
			k.sphere(Vector3(0, -0.01, 0.0), Vector3(0.12, 0.08, 0.16), PURPLE, 12, 6)
			_sole(k, Vector3(0, -0.06, 0.0), Vector3(0.2, 0.02, 0.28), PURPLE.darkened(0.4))
			var last := Vector3.ZERO
			for i: int in 8:  # the toe curls up
				var s: float = float(i) / 7.0
				last = Vector3(0, -0.01 + 0.13 * s * s, -0.12 - 0.12 * sin(s * 2.2))
				var r: float = lerpf(0.075, 0.016, s)
				k.sphere(last, Vector3(r, r, r * 1.2), PURPLE, 10, 5)
			k.sphere(last + Vector3(0, 0.025, 0.012), Vector3.ONE * 0.026, _glow(GOLD, 0.45), 8, 4)
			k.torus(Vector3(0, 0.065, 0.03), 0.082, 0.1, GOLD, 14, Basis.IDENTITY)
		&"boots_light":
			_shoe(k, WHITE, WHITE.darkened(0.12))
			var lights: Array[Color] = [RED, YELLOW, TEAL, ORANGE]
			for i: int in 10:
				var ang: float = TAU * float(i) / 10.0
				k.sphere(Vector3(sin(ang) * 0.105, -0.053, -0.01 + cos(ang) * 0.155), Vector3(0.026, 0.014, 0.026), _glow(lights[i % 4], 0.75), 8, 3)
			k.sphere(Vector3(0, 0.065, -0.06), Vector3(0.105, 0.02, 0.05), RED, 10, 4, Basis(Vector3.RIGHT, 0.4))
			k.cylinder(Vector3(0, 0.08, 0.04), 0.085, 0.09, 0.07, WHITE, 10)
		&"boots_haferl":
			var leather := Color("#5A3A24")
			k.sphere(Vector3(0, -0.005, -0.01), Vector3(0.12, 0.082, 0.175), leather, 14, 7)
			_sole(k, Vector3(0, -0.058, -0.01), Vector3(0.21, 0.022, 0.31), Color("#2A1E16"))
			for i: int in 4:  # laces on the outer side
				k.sphere(Vector3(0.105, 0.02 + float(i) * 0.016, -0.06 + float(i) * 0.022), Vector3(0.008, 0.006, 0.03), CREAM, 6, 3)
			k.cylinder(Vector3(0, 0.12, 0.03), 0.1, 0.095, 0.2, CREAM, 14)
			for i: int in 8:  # cable knit
				var ang: float = TAU * float(i) / 8.0
				k.cylinder(Vector3(sin(ang) * 0.097, 0.12, 0.03 + cos(ang) * 0.097), 0.012, 0.012, 0.18, CREAM.darkened(0.08), 6)
			k.cylinder(Vector3(0, 0.205, 0.03), 0.103, 0.103, 0.03, GREEN, 14)
		&"boots_golf":
			_shoe(k, WHITE, Color("#3A2A1E"))
			k.sphere(Vector3(0, 0.0, -0.01), Vector3(0.124, 0.089, 0.07), BROWN, 12, 6)
			k.sphere(Vector3(0, 0.075, -0.1), Vector3(0.06, 0.01, 0.045), TAN, 10, 3, Basis(Vector3.RIGHT, 0.35))
			for i: int in 5:  # the kiltie's fringe
				k.sphere(Vector3(-0.04 + float(i) * 0.02, 0.06, -0.14), Vector3(0.007, 0.022, 0.007), TAN.darkened(0.1), 5, 2, Basis(Vector3.RIGHT, 0.5))
		&"boots_gold":
			_shoe(k, GOLD, WHITE)
			k.cylinder(Vector3(0, 0.09, 0.03), 0.095, 0.1, 0.13, GOLD, 10)
			for i: int in 4:
				k.box(Vector3(0, 0.07 + float(i) * 0.025, -0.06 + float(i) * 0.012), Vector3(0.07, 0.008, 0.008), BURGUNDY)
			k.prism(OutfitMeshKit.star_poly(5, 0.03, 0.013), 0.006, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.115, 0.03, 0.02)), WHITE)


## A plain shoe: the upper and a darker sole.
## A rounded sole (an oval slab): square soles stuck out at the corners under the round shoes.
static func _sole(k: OutfitMeshKit, center: Vector3, size: Vector3, color: Color) -> void:
	var r: float = size.x * 0.5
	k.cylinder(center, r, r * 0.94, size.y, color, 18, Basis.IDENTITY, size.z / size.x)


static func _shoe(k: OutfitMeshKit, upper: Color, sole: Color) -> void:
	k.sphere(Vector3(0, 0.0, -0.01), Vector3(0.12, 0.085, 0.175), upper, 12, 6)
	_sole(k, Vector3(0, -0.058, -0.01), Vector3(0.21, 0.022, 0.31), sole)


# --- Faces --------------------------------------------------------------------------------------
# Beards and glasses in the body's space, around the face (`AvatarVisuals`: the mouth at MOUTH_Y,
# the eyes at EYE_Y). Eye shapes (`pupil_mesh`) replace the pupils and lashes sit on the eye whites;
# mouths are drawn by the mouth shader (`mouth_style`).

const MOUTH_STYLES: Dictionary = {
	&"mouth_tongue": 1, &"mouth_buck": 2, &"mouth_lipstick": 3, &"mouth_gold": 4, &"mouth_fangs": 5, &"mouth_grill": 6,
}
## Eye pieces that change the pupils, and how fast they turn (radians a second).
const PUPILS: Dictionary = {&"eyes_star": 0.0, &"eyes_heart": 0.0, &"eyes_dollar": 0.0, &"eyes_cat": 0.0, &"eyes_spiral": -4.0}


## The mouth shader's style for mouth piece `id` (0: the plain mouth).
static func mouth_style(id: StringName) -> int:
	return MOUTH_STYLES.get(id, 0)


## Whether eye piece `id` has long lashes.
static func has_lashes(id: StringName) -> bool:
	return id == &"eyes_lashes"


static func _mouth_y() -> float:
	return AvatarVisuals.MOUTH_Y - AvatarVisuals._body_center_y()


static func _eye_center(side: float) -> Vector3:
	var y: float = AvatarVisuals.EYE_Y - AvatarVisuals._body_center_y()
	var x: float = side * AvatarVisuals.EYE_SPREAD
	return Vector3(x, y, AvatarVisuals.face_z(y, x) + AvatarVisuals.EYE_RADIUS * 0.45)


## A point on the face: body-space height `y`, angle `a` from the front, `out` off the skin.
static func _face_point(y: float, a: float, out: float) -> Vector3:
	var t: float = y / AvatarVisuals.BODY_HEIGHT + 0.5
	var r: float = AvatarVisuals.radius_at(t) + out
	return Vector3(sin(a) * r, y, AvatarVisuals.bend_at(t) - cos(a) * r * AvatarVisuals.BODY_DEPTH)


## A thick patch of beard across angles -span..span between heights top(a) and bottom(a),
## `thick(u, v)` off the skin (thin at the edges so it meets the skin).
static func _beard_patch(k: OutfitMeshKit, span: float, top: Callable, bottom: Callable, thick: Callable, color: Color, nu: int = 36, nv: int = 16) -> void:
	for side: int in 2:
		var at := func(u: float, v: float) -> Vector3:
			var a: float = (u - 0.5) * 2.0 * span
			var y: float = lerpf(top.call(a), bottom.call(a), v)
			var edge: float = pow(sin(PI * u), 0.4) * pow(sin(PI * clampf(v * 0.5 + 0.08, 0.0, 0.5) * 2.0), 0.3)
			var th: float = 0.006 + (thick.call(u, v) as float) * edge if side == 0 else 0.004
			return _face_point(y, a, th)
		var col: Color = color if side == 0 else color.darkened(0.4)
		k.surface(at, nu, nv, func(_u: float, _v: float) -> Color: return col, func(p: Vector3) -> Vector3:
			return OutfitMeshKit.body_out(p) * (1.0 if side == 0 else -1.0))


## A moustache: two arcs of tufts from under the nose to `reach` sideways, `droop` at the ends.
static func _moustache(k: OutfitMeshKit, color: Color, reach: float, droop: float, thick: float) -> void:
	var my: float = _mouth_y()
	for side: float in [-1.0, 1.0]:
		for i: int in 14:  # densely overlapping lobes read as one tuft, not a bead chain
			var s: float = float(i) / 13.0
			var x: float = side * (0.015 + s * reach)
			var y: float = my + 0.05 - s * s * droop
			var r: float = lerpf(thick * 1.15, thick * 0.5, s)
			k.sphere(Vector3(x, y, AvatarVisuals.face_z(y, x) - r * 0.35), Vector3(r * 1.5, r * 0.9, r * 0.8), color, 10, 5, Basis(Vector3.BACK, side * -s * 0.5))


static func _beard(k: OutfitMeshKit, id: StringName) -> void:
	var my: float = _mouth_y()
	match id:
		&"beard_mustache":
			_moustache(k, Color("#4A3424"), 0.12, 0.05, 0.03)
		&"beard_handlebar":
			var c := Color("#1C1A19")
			_moustache(k, c, 0.14, 0.01, 0.026)
			for side: float in [-1.0, 1.0]:  # the curled-up ends
				var cx: float = side * 0.175
				var cy: float = my + 0.075
				for i: int in 22:  # overlapping, so the curl reads as one twirl
					var ph: float = float(i) / 21.0 * PI * 1.5
					var x: float = cx + side * sin(ph) * 0.032
					var y: float = cy - cos(ph) * 0.032
					var r: float = lerpf(0.017, 0.009, float(i) / 21.0)
					k.sphere(Vector3(x, y, AvatarVisuals.face_z(y, x) - 0.008), Vector3.ONE * r, c, 8, 4)
		&"beard_goatee":
			var c := Color("#5A3B26")
			_moustache(k, c, 0.09, 0.06, 0.022)
			_beard_patch(k, 0.3, func(_a: float) -> float: return my - 0.075, func(a: float) -> float:
				return my - 0.24 + 0.13 * absf(a) / 0.3,
				func(_u: float, v: float) -> float: return 0.02 + 0.012 * v, c, 16, 8)
		&"beard_full", &"beard_viking":
			var c := Color("#A0522D") if id == &"beard_full" else Color("#B5652E")
			_moustache(k, c.darkened(0.08), 0.13, 0.06, 0.03)
			_beard_patch(k, 1.35, func(a: float) -> float:
				return lerpf(my - 0.075, my + 0.15, smoothstep(0.42, 1.3, absf(a))),
				func(a: float) -> float:
					return my - 0.27 + 0.13 * smoothstep(0.3, 1.35, absf(a)) + 0.012 * sin(a * 16.0),
				func(u: float, v: float) -> float:
					return 0.022 + 0.03 * v + 0.006 * sin(u * 60.0) * sin(v * 9.0), c)
			if id == &"beard_viking":
				for side: float in [-1.0, 1.0]:  # two braids with gold rings
					var x0: float = side * 0.1
					for i: int in 9:
						var y: float = my - 0.24 - float(i) * 0.03
						var p: Vector3 = Vector3(x0, y, AvatarVisuals.face_z(y, x0) - 0.05)
						k.sphere(p, Vector3(0.028, 0.022, 0.026) * lerpf(1.0, 0.7, float(i) / 8.0), c.lightened(0.05 * float(i % 2)), 8, 4)
						if i == 3 or i == 7:
							k.torus(p, 0.022, 0.034, GOLD, 10, Basis.IDENTITY)
		&"beard_santa":
			var c := Color("#F4EFE4")
			_moustache(k, c, 0.15, 0.07, 0.036)
			_beard_patch(k, 1.4, func(a: float) -> float:
				return lerpf(my - 0.07, my + 0.26, smoothstep(0.4, 1.3, absf(a))),
				func(a: float) -> float:
					return my - 0.42 + 0.24 * smoothstep(0.2, 1.4, absf(a)) + 0.02 * sin(a * 12.0),
				func(u: float, v: float) -> float:
					return 0.035 + 0.04 * v + 0.012 * sin(u * 50.0) * sin(v * 12.0), c, 40, 18)
		&"beard_wizard":
			var c := Color("#D8D4CC")
			_moustache(k, c.darkened(0.05), 0.15, 0.11, 0.03)
			_beard_patch(k, 1.15, func(a: float) -> float:
				return lerpf(my - 0.075, my + 0.22, smoothstep(0.42, 1.1, absf(a))),
				func(a: float) -> float:
					return my - 0.66 + 0.5 * pow(absf(a) / 1.15, 1.1),
				func(u: float, v: float) -> float:
					return 0.03 + 0.03 * v + 0.007 * sin(u * 40.0 + v * 6.0), c, 36, 24)


## Glasses, a monocle or shades in front of the eyes (nothing for pieces that only change the eyes).
static func _glasses(k: OutfitMeshKit, id: StringName) -> void:
	var r: float = AvatarVisuals.EYE_RADIUS
	var face := Basis(Vector3.RIGHT, PI * 0.5)  # a ring lying flat turned to face forward
	match id:
		&"eyes_glasses":
			var c := Color("#5A3A24")
			for side: float in [-1.0, 1.0]:
				var e: Vector3 = _eye_center(side)
				var p := Vector3(e.x * 1.08, e.y, e.z - r - 0.012)
				k.torus(p, r * 1.0, r * 1.16, c, 22, face)
				k.cylinder(Vector3(side * (absf(p.x) + r * 1.1), e.y + 0.02, p.z + 0.08), 0.01, 0.01, 0.17, c, 6, Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.BACK, side * 0.4))
			var bridge_y: float = _eye_center(1.0).y + 0.045
			k.cylinder(Vector3(0, bridge_y, _eye_center(1.0).z - r - 0.02), 0.011, 0.011, 0.07, c, 6, Basis(Vector3.BACK, PI * 0.5))
		&"eyes_monocle":
			var e: Vector3 = _eye_center(1.0)
			var p := Vector3(e.x * 1.04, e.y, e.z - r - 0.014)
			k.torus(p, r * 1.0, r * 1.15, GOLD, 22, face)
			for i: int in 11:  # the chain down to the chest
				var s: float = float(i) / 10.0
				var y: float = p.y - r * 1.1 - s * 0.32
				var x: float = p.x + 0.04 + s * 0.12
				k.sphere(Vector3(x, y, AvatarVisuals.face_z(y, x) - 0.02), Vector3.ONE * 0.009, GOLD.darkened(0.1), 6, 3)
		&"eyes_shades":
			var lens := Color("#1C1A19")
			for side: float in [-1.0, 1.0]:
				var e: Vector3 = _eye_center(side)
				var p := Vector3(e.x * 1.1, e.y - 0.01, e.z - r - 0.016)
				var drop := PackedVector2Array()
				for i: int in 20:
					var a: float = TAU * float(i) / 20.0
					var y: float = sin(a) * r * 1.0 - (0.02 if sin(a) < 0.0 else 0.0) * absf(sin(a))
					drop.append(Vector2(cos(a) * r * 1.18 + side * 0.01 * maxf(-sin(a), 0.0), y))
				k.prism(drop, 0.012, _facing(Vector3(0, 0, -1), p), lens)
				k.torus(p, r * 1.1, r * 1.2, GOLD, 22, face * Basis.from_scale(Vector3(1.05, 1.0, 0.92)))
				k.cylinder(Vector3(side * (absf(p.x) + r * 1.2), e.y + 0.02, p.z + 0.08), 0.008, 0.008, 0.17, GOLD, 6, Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.BACK, side * 0.4))
			var top_y: float = _eye_center(1.0).y + r * 0.95
			k.cylinder(Vector3(0, top_y, _eye_center(1.0).z - r - 0.02), 0.008, 0.008, 0.12, GOLD, 6, Basis(Vector3.BACK, PI * 0.5))


static var _pupil_cache: Dictionary = {}


## The pupil of eye piece `id` (null: the plain round pupil), in the pupil's own space: a unit
## shape facing -Z, its front at z = -1 (`AvatarVisuals` scales it to the pupil's size).
static func pupil_mesh(id: StringName) -> ArrayMesh:
	if not PUPILS.has(id):
		return null
	if _pupil_cache.has(id):
		return _pupil_cache[id]
	var k := OutfitMeshKit.new()
	var front := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.35))  # +Z out of the eye
	var dark := Color("#1C1A19")
	match id:
		&"eyes_star":
			k.prism(OutfitMeshKit.star_poly(5, 1.35, 0.62), 0.55, front.translated_local(Vector3(0, 0, -0.1)), dark)
			k.prism(OutfitMeshKit.star_poly(5, 1.12, 0.5), 0.65, front, _glow(YELLOW, 0.3))
		&"eyes_heart":
			k.prism(OutfitMeshKit.heart_poly(2.6), 0.55, front.translated_local(Vector3(0, 0.05, -0.1)), dark)
			k.prism(OutfitMeshKit.heart_poly(2.2), 0.65, front.translated_local(Vector3(0, 0.05, 0)), RED)
		&"eyes_dollar":
			k.prism(OutfitMeshKit.circle_poly(1.2, 20), 0.55, front.translated_local(Vector3(0, 0, -0.1)), GOLD.darkened(0.15))
			_glyph(k, "$", front.translated_local(Vector3(0, -0.05, 0.5)), Color("#2C5A35"), 1.9)
		&"eyes_cat":
			k.prism(OutfitMeshKit.circle_poly(1.3, 22), 0.5, front.translated_local(Vector3(0, 0, -0.1)), Color("#9DB04A"))
			k.prism(_ellipse(0.3, 1.05, 18), 0.65, front, dark)
		&"eyes_spiral":
			k.prism(OutfitMeshKit.circle_poly(1.3, 24), 0.5, front.translated_local(Vector3(0, 0, -0.1)), WHITE)
			var n := Vector3(0, 0, -1)
			var z: float = -1.0
			var steps: int = 60
			for i: int in steps:
				var a0: float = float(i) / float(steps) * TAU * 2.5
				var a1: float = float(i + 1) / float(steps) * TAU * 2.5
				var r0: float = 0.06 + a0 / (TAU * 2.5) * 1.15
				var r1: float = 0.06 + a1 / (TAU * 2.5) * 1.15
				var w: float = 0.11
				var p0 := Vector3(cos(a0) * (r0 - w), sin(a0) * (r0 - w), z)
				var p1 := Vector3(cos(a0) * (r0 + w), sin(a0) * (r0 + w), z)
				var p2 := Vector3(cos(a1) * (r1 + w), sin(a1) * (r1 + w), z)
				var p3 := Vector3(cos(a1) * (r1 - w), sin(a1) * (r1 - w), z)
				k.tri(p0, p1, p2, n, PURPLE)
				k.tri(p0, p2, p3, n, PURPLE)
	var m: ArrayMesh = k.commit()
	_pupil_cache[id] = m
	return m


## Three long lashes on top of an eye (the eye's own space, metres; `side` -1 the bean's right).
static func lash_mesh(side: float) -> ArrayMesh:
	var key: StringName = &"lashes_r" if side < 0.0 else &"lashes_l"
	if _cache.has(key):
		return _cache[key]
	var k := OutfitMeshKit.new()
	var r: float = AvatarVisuals.EYE_RADIUS
	for i: int in 3:
		var s: float = float(i) - 1.0
		var base := Vector3(s * 0.45 * r + side * 0.25 * r, r * 0.8, -r * 0.5)
		var dir: Vector3 = (base.normalized() + Vector3(side * 0.35 + s * 0.3, 0.8, -0.3)).normalized()
		var len: float = 0.06 if i != 1 else 0.07
		k.cylinder(base + dir * len * 0.5, 0.005, 0.011, len, Color("#1C1A19"), 6, Basis(Quaternion(Vector3.UP, dir)))
	var m: ArrayMesh = k.commit()
	_cache[key] = m
	return m
