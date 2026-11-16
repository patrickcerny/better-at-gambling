class_name CoinPile
extends Node3D
## Money on the floor: a few big casino chips that float above the carpet, turning slowly and
## bobbing with a soft warm glow, so a pile reads from across the room (Patrick 2026-11-16: "really
## big chips spinning around and hovering and glowing slightly else its really hard to see").
##
## Feel: the chips arc out of whoever dropped them (`SETTLE_SECONDS`, not collectable in the air),
## then hover in a slow little carousel with the value floating above. They fly into whoever
## collects them (`fly_to`) and shrink away when they expire (`fade_out`). The money itself is the
## server's business: this node only shows it, with no physics at all.

## Time from the drop until the pile can be picked up (the arc out of the victim).
const SETTLE_SECONDS: float = 0.45
## Flight time into the collector.
const FLY_SECONDS: float = 0.28
## Chip radius and thickness (a table chip is 5.5 cm across; these are deliberately oversized).
const CHIP_RADIUS: float = 0.24
const CHIP_THICKNESS: float = 0.065
## Height of the chips' centre above the floor, and how far they bob.
const HOVER_HEIGHT: float = 0.6
const BOB_HEIGHT: float = 0.07
const BOB_SPEED: float = 2.2
## Each chip turns about its own upright axis at this rate (rad/s): slow, like a pickup in a shop.
const SPIN_SPEED: float = 1.5
## Several chips circle the pile's centre at this radius and rate.
const ORBIT_RADIUS: float = 0.32
const ORBIT_SPEED: float = 0.7
## Most chips one pile shows.
const MAX_CHIPS: int = 4
## Warm gold of the glow (ART_DIRECTION: warm and luxurious, no neon).
const GLOW_COLOR: Color = Color("#E3B95C")
## Height of the value label above the floor.
const LABEL_HEIGHT: float = 1.2

## Shared glow materials (the same for every pile).
static var _rim_material: ShaderMaterial
static var _halo_material: ShaderMaterial

var pile_id: int = -1
var amount: int = 0
## Scene clock when the pile landed (set by the match scene; pickups wait for it).
var settles_at: float = 0.0
## Our own pickup is predicted: the chips are flying to us while the server confirms.
var predicted_until: float = -INF
var _label: Label3D
## Turns the chips round the centre and bobs them; the chips hang off it.
var _carousel: Node3D
var _chips: Array[Node3D] = []
var _halo: MeshInstance3D
var _time: float = 0.0
## False while the chips are still arcing out of the victim (no hovering yet).
var _hovering: bool = true
var _gone: bool = false
var _tween: Tween


## Chips shown for `p_amount` dollars: one per $50, at least one, at most MAX_CHIPS.
static func chip_count(p_amount: int) -> int:
	return clampi(p_amount / 50, 1, MAX_CHIPS)


func _ready() -> void:
	_time = randf() * TAU  # piles side by side don't bob in step
	_carousel = Node3D.new()
	_carousel.name = "Carousel"
	_carousel.position.y = HOVER_HEIGHT
	add_child(_carousel)
	_halo = _make_halo()
	add_child(_halo)
	_label = Label3D.new()
	_label.text = "$%d" % amount
	_label.font_size = 52
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Palette.MONEY_GREEN
	_label.outline_modulate = Palette.CASINO_BLACK
	_label.outline_size = 10
	_label.position.y = LABEL_HEIGHT
	add_child(_label)
	add_to_group(&"chip_piles")  # the old ChipPile's group, still looked up by name


func _process(delta: float) -> void:
	_time += delta
	if _label != null:
		_label.position.y = LABEL_HEIGHT + sin(_time * BOB_SPEED) * 0.04
	if _gone or not _hovering or _carousel == null:
		return
	_carousel.position.y = HOVER_HEIGHT + sin(_time * BOB_SPEED) * BOB_HEIGHT
	_carousel.rotation.y += delta * ORBIT_SPEED
	for chip: Node3D in _chips:
		chip.rotation.y += delta * SPIN_SPEED
	if _halo != null:
		# The glow on the carpet breathes with the bob: brightest when the chips dip lowest.
		var k: float = 0.5 - 0.5 * sin(_time * BOB_SPEED)
		_halo.scale = Vector3.ONE * lerpf(0.88, 1.0, k)


## True once the pile has landed and nobody has taken it yet.
func is_collectable(now: float) -> bool:
	return not _gone and now >= settles_at and visible


## True while the chips fly into someone (predicted or confirmed).
func is_leaving() -> bool:
	return _gone


## Makes the chips. With `from_pos` (world) away from the pile they arc out of it first (someone
## got shaken); otherwise (a late join) they are hovering already.
func spawn_chips(from_pos: Vector3) -> void:
	var count: int = chip_count(amount)
	var color: Color = ChipStack.tier_color(amount)
	for i: int in count:
		var chip: Node3D = _make_chip(color)
		chip.name = "Chip%d" % i
		var slot: Vector3 = Vector3.ZERO
		if count > 1:
			var a: float = TAU * float(i) / float(count)
			slot = Vector3(cos(a), 0.0, sin(a)) * ORBIT_RADIUS
		chip.position = slot
		chip.rotation.y = TAU * float(i) / float(count) + randf_range(-0.4, 0.4)
		chip.set_meta(&"slot", slot)
		_carousel.add_child(chip)
		_chips.append(chip)
	var start: Vector3 = from_pos - global_position
	if not Vfx.enabled() or not is_inside_tree() or start.length() < 0.05:
		return
	# Arc from the victim to the hover spot; the carousel waits until the chips are there.
	_hovering = false
	_label.visible = false
	_halo.visible = false
	var t: Tween = create_tween()
	_tween = t
	t.tween_method(func(k: float) -> void:
		var p: Vector3 = start.lerp(Vector3(0.0, HOVER_HEIGHT, 0.0), k)
		p.y += sin(k * PI) * 0.9
		_carousel.position = p
		for chip: Node3D in _chips:
			chip.position = (chip.get_meta(&"slot") as Vector3) * k
			chip.rotation.y += 0.35
	, 0.0, 1.0, SETTLE_SECONDS * 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(func() -> void:
		_hovering = true
		_label.visible = true
		_halo.visible = true
		_time = -PI * 0.5 / BOB_SPEED  # pick the bob up at its centre, no jump
		_carousel.position = Vector3(0.0, HOVER_HEIGHT, 0.0))


## The chips fly into the collector; with `keep` they only hide (for prediction).
func fly_to(who: Node3D, keep: bool = false) -> void:
	_gone = true
	_label.visible = false
	_halo.visible = false
	_kill_tween()
	if not Vfx.enabled() or who == null or not is_instance_valid(who) or not who.is_inside_tree():
		if keep:
			visible = false
		else:
			queue_free()
		return
	visible = true
	var start: Vector3 = _carousel.global_position
	var t: Tween = create_tween()
	_tween = t
	t.tween_method(func(k: float) -> void:
		if not is_instance_valid(who) or not who.is_inside_tree():
			return
		var end: Vector3 = who.global_position + Vector3(0.0, 1.0, 0.0)
		var p: Vector3 = start.lerp(end, k * k)
		p.y += sin(k * PI) * 0.4
		_carousel.global_position = p
		_carousel.scale = Vector3.ONE * lerpf(1.0, 0.3, k)
	, 0.0, 1.0, FLY_SECONDS)
	if keep:
		t.tween_callback(func() -> void: _carousel.visible = false)
	else:
		t.tween_callback(queue_free)


## A predicted pickup was refused: the chips are back where they hovered.
func restore() -> void:
	_kill_tween()
	_gone = false
	_hovering = true
	predicted_until = -INF
	visible = true
	_label.visible = true
	_halo.visible = true
	_carousel.visible = true
	_carousel.scale = Vector3.ONE
	_carousel.position = Vector3(0.0, HOVER_HEIGHT, 0.0)


## Expired: the chips shrink away.
func fade_out() -> void:
	_gone = true
	if not Vfx.enabled():
		queue_free()
		return
	_label.visible = false
	_kill_tween()
	var t: Tween = create_tween()
	_tween = t
	t.set_parallel(true)
	t.tween_property(_carousel, "scale", Vector3(0.05, 0.05, 0.05), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(_halo, "scale", Vector3(0.05, 1.0, 0.05), 0.35)
	t.chain().tween_callback(queue_free)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## One big chip standing on its edge (faces sideways, so its turning shows), with a warm rim glow.
func _make_chip(color: Color) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = ChipTowers.chip_mesh(color, 6)
	mi.scale = Vector3(CHIP_RADIUS, CHIP_THICKNESS, CHIP_RADIUS)
	mi.rotation.x = PI * 0.5
	mi.material_overlay = _rim()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	return holder


## A soft warm pool of light on the carpet under the chips.
func _make_halo() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Halo"
	var q := PlaneMesh.new()
	q.size = Vector2(1.7, 1.7)
	mi.mesh = q
	mi.position.y = 0.02
	mi.material_override = _halo_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Additive fresnel rim over the chip's own material: a slight warm gold glow at its edges.
static func _rim() -> ShaderMaterial:
	if _rim_material == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 glow : source_color;
uniform float power = 2.2;
uniform float intensity = 0.7;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = glow.rgb * (0.12 + rim) * intensity;
}
"""
		_rim_material = ShaderMaterial.new()
		_rim_material.shader = sh
		_rim_material.set_shader_parameter(&"glow", GLOW_COLOR)
	return _rim_material


## Radial warm glow fading out to nothing at the edge (no hard disc).
static func _halo_mat() -> ShaderMaterial:
	if _halo_material == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 glow : source_color;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	ALBEDO = glow.rgb * a * 0.6;
}
"""
		_halo_material = ShaderMaterial.new()
		_halo_material.shader = sh
		_halo_material.set_shader_parameter(&"glow", GLOW_COLOR)
	return _halo_material
