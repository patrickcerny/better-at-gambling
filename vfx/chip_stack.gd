class_name ChipStack
extends Node3D
## A little stack of casino chips on the felt (presentation only). Slides along a low arc between
## spots: from a seat onto the layout when a bet is placed, then to the winner or to the house.

const CHIP_RADIUS: float = 0.055
const CHIP_HEIGHT: float = 0.015
## Colour by size of the stack for chips that belong to nobody (the house's winnings): cream, red,
## green, black, gold.
const TIERS: Array[int] = [25, 100, 500, 2000]
const TIER_COLORS: Array[Color] = [Color("#F2E6C9"), Color("#C83D3D"), Color("#275E49"), Color("#24211F"), Color("#E3B95C")]
## Most chips a stack shows, and the most in one column: a bigger bet starts a second column
## beside the first instead of a taller tower (cards behind stay visible).
const MAX_CHIPS: int = 20
const COLUMN_CHIPS: int = 10
## Above this luminance a player colour gets a dark edge band and rim instead of the cream one.
const LIGHT_LUMA: float = 0.6
## Transparent = no owner colour given (house chips use the tier colours).
const NO_COLOR: Color = Color(0, 0, 0, 0)

## Colour html -> [face, edge band, rim] materials, shared by every stack in that colour.
static var _materials: Dictionary[String, Array] = {}
## "skin|colour html" -> the same for chips in an animated skin.
static var _skin_materials: Dictionary[String, Array] = {}
## Alternate chips in a skin stack are this much darker, so the chip count still reads.
const SKIN_BAND_SHADE: float = 0.72

var amount: int = 0
## The table minimum one chip stands for (0 = unknown, a fixed size scale is used).
var unit: int = 0
var color: Color = NO_COLOR
## The owner's animated skin (`CosmeticDef.KIND_SKIN` id, &"" = none): the chips wear its pattern
## (Patrick 2026-11-16: "the chips you have mirror the skin you use"), the rim stays `color`.
var skin: StringName = &""
var _from: Vector3


## Builds a stack for `amount` dollars in its owner's `p_color` (and skin `p_skin`, see `skin`);
## one chip per `p_unit` (the table minimum at the current limits), see `chip_count`.
static func make(p_amount: int, p_color: Color = NO_COLOR, p_unit: int = 0, p_skin: StringName = &"") -> ChipStack:
	var s := ChipStack.new()
	s.name = "ChipStack"
	s.amount = p_amount
	s.unit = p_unit
	s.color = p_color if p_color.a > 0.0 else tier_color(p_amount)
	s.skin = p_skin if ToonMaterial.skin_flat(p_skin).a > 0.0 else &""
	s._build()
	return s


## Chips shown for a bet: one per table minimum `p_unit`, at least one, at most MAX_CHIPS. Without
## a unit the old size scale is used.
static func chip_count(p_amount: int, p_unit: int = 0) -> int:
	if p_unit <= 0:
		return clampi(int(log(maxf(p_amount, 1.0)) / log(1.7)) - 3, 1, 12)
	return clampi(ceili(float(p_amount) / float(p_unit)), 1, MAX_CHIPS)


## Number of side-by-side columns for `count` chips.
static func columns(count: int) -> int:
	return maxi(ceili(float(count) / float(COLUMN_CHIPS)), 1)


static func tier_color(p_amount: int) -> Color:
	for i: int in TIERS.size():
		if p_amount < TIERS[i]:
			return TIER_COLORS[i]
	return TIER_COLORS[TIER_COLORS.size() - 1]


## True when `c` is light enough that a cream rim would not read on it.
static func is_light(c: Color) -> bool:
	return c.get_luminance() > LIGHT_LUMA


## [face, edge band, rim] for chips in `c` (cached per colour).
static func materials_for(c: Color) -> Array:
	var key: String = c.to_html(false)
	if not _materials.has(key):
		var light: bool = is_light(c)
		var rim: Color = Palette.WARM_CHARCOAL if light else (Palette.CREAM if not c.is_equal_approx(Palette.CREAM) else Palette.CASINO_RED)
		_materials[key] = [
			GreyboxKit.material(c, 0.0, 0.6),
			GreyboxKit.material(c.darkened(0.4 if light else 0.25), 0.0, 0.6),
			GreyboxKit.material(rim, 0.0, 0.6),
		]
	return _materials[key]


## [face, darker band, rim] for chips in skin `p_skin` with a rim in the owner's colour `c`
## (cached; falls back to `materials_for(c)` for unknown skins).
static func skin_materials_for(p_skin: StringName, c: Color) -> Array:
	var flat: Color = ToonMaterial.skin_flat(p_skin)
	if flat.a <= 0.0:
		return materials_for(c)
	var key: String = String(p_skin) + "|" + c.to_html(false) + ("" if Vfx.enabled() and ToonMaterial.enabled else "|flat")
	if not _skin_materials.has(key):
		# The rim is the owner's colour, so two players in the same skin still tell their chips
		# apart; when it would vanish on the pattern it falls back to cream / charcoal.
		var rim: Color = c
		if absf(c.get_luminance() - flat.get_luminance()) < 0.12:
			rim = Palette.WARM_CHARCOAL if is_light(flat) else Palette.CREAM
		_skin_materials[key] = [
			ToonMaterial.make_chip_skin(p_skin, CHIP_RADIUS),
			ToonMaterial.make_chip_skin(p_skin, CHIP_RADIUS, false, SKIN_BAND_SHADE),
			GreyboxKit.material(rim, 0.0, 0.6),
		]
	return _skin_materials[key]


func _build() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = CHIP_RADIUS
	mesh.bottom_radius = CHIP_RADIUS
	mesh.height = CHIP_HEIGHT
	mesh.radial_segments = 14
	mesh.rings = 1
	var edge := TorusMesh.new()
	edge.inner_radius = CHIP_RADIUS * 0.78
	edge.outer_radius = CHIP_RADIUS * 0.9
	edge.rings = 14
	edge.ring_segments = 4
	var mats: Array = skin_materials_for(skin, color) if skin != &"" else materials_for(color)
	var n: int = chip_count(amount, unit)
	for i: int in n:
		var col: int = i / COLUMN_CHIPS
		var level: int = i % COLUMN_CHIPS
		var chip := MeshInstance3D.new()
		chip.mesh = mesh
		chip.material_override = mats[i % 2]
		chip.position = Vector3(randf_range(-0.004, 0.004), CHIP_HEIGHT * (level + 0.5), randf_range(-0.004, 0.004) - col * CHIP_RADIUS * 2.05)
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(chip)
		if level == COLUMN_CHIPS - 1 or i == n - 1:  # the rim on top of each column
			var rim := MeshInstance3D.new()
			rim.mesh = edge
			rim.material_override = mats[2]
			rim.position = Vector3(0, CHIP_HEIGHT * 0.5 + 0.001, 0)
			rim.scale = Vector3(1, 0.3, 1)
			chip.add_child(rim)


## Slides to `to` (global) over a small hop. Returns the tween.
func slide_to(to: Vector3, seconds: float = 0.45, arc: float = 0.12) -> Tween:
	var from: Vector3 = global_position
	var t: Tween = create_tween()
	t.tween_method(func(f: float) -> void:
		global_position = from.lerp(to, f) + Vector3(0, sin(f * PI) * arc, 0), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t


## Slides to `to` and disappears there (paid out to a player, or raked in by the house).
func collect(to: Vector3, seconds: float = 0.5, delay: float = 0.0) -> void:
	var t: Tween = create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(func() -> void: _from = global_position)
	t.tween_method(func(f: float) -> void:
		global_position = _from.lerp(to, f) + Vector3(0, sin(f * PI) * 0.15, 0), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "scale", Vector3.ONE * 0.05, 0.15)
	t.tween_callback(queue_free)


## Winnings: a house stack slides over from `house` and joins this one, then everything goes to
## `winner`.
func pay_out(winnings: int, house: Vector3, winner: Vector3) -> void:
	if winnings > 0 and get_parent() != null:
		var extra: ChipStack = ChipStack.make(winnings, NO_COLOR, unit)  # the house's chips
		get_parent().add_child(extra)
		extra.global_position = house
		var spot: Vector3 = global_position + Vector3(CHIP_RADIUS * 2.1, 0, 0)
		extra.slide_to(spot, 0.4, 0.18)
		extra.collect(winner, 0.5, 0.55)
	collect(winner, 0.5, 0.55 if winnings > 0 else 0.1)
