class_name OddJobsCabinet
extends Node3D
## The Odd Jobs cabinet's live parts (built by LuckyLounge at `ODD_JOBS_CABINET`, front to the room,
## −x): the big red arcade button you click in the world, the shared bar lit on the riser above it,
## the clicks/notes text, and the warm lamp strip + marquee bulbs that pulse while the local player
## is broke. Pure presentation: OddJobsController feeds it the server's numbers.

## Button cap centre (local) and the radius the aim ray must pass within.
const BUTTON_POS: Vector3 = Vector3(-0.08, 1.17, 0.0)
const BUTTON_RADIUS: float = 0.19
const AIM_RADIUS: float = 0.24
const DIP: float = 0.05
## The bar on the riser's room-facing side (x = 0.16 local), left (−z) to right (+z) as you face it.
const BAR_X: float = 0.145
const BAR_Y: float = 1.57
const BAR_LEN: float = 0.68
const OUTLINE_SHADER: Shader = preload("res://client/aim_outline.gdshader")

var button: Node3D
var bar_fill: MeshInstance3D
var count_label: Label3D
var note_label: Label3D
var lamp_light: OmniLight3D
## True while the cabinet glows for a broke local player.
var glowing: bool = false
var aimed: bool = false
## Displayed fill (eases towards `_target`, so throttled server updates still slide).
var shown_fill: float = 0.0

var _target: float = 0.0
var _button_mesh: MeshInstance3D
var _button_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _outline: ShaderMaterial
var _time: float = 0.0
var _punch: float = 0.0
var _note_until: float = 0.0


func _init() -> void:
	name = "OddJobsLive"
	_build()


func _build() -> void:
	GreyboxKit.cylinder(self, 0.25, 0.06, Vector3(BUTTON_POS.x, 1.11, 0), Palette.WARM_GOLD, "OddJobsBezel", false, 0.8)
	# The button: a red cap with a domed top, its own material (it flashes on a click).
	button = Node3D.new()
	button.name = "OddJobsButton"
	button.position = BUTTON_POS
	add_child(button)
	_button_mat = StandardMaterial3D.new()
	_button_mat.albedo_color = Palette.CASINO_RED
	_button_mat.roughness = 0.35
	_button_mat.emission_enabled = true
	_button_mat.emission = Palette.CASINO_RED
	_button_mat.emission_energy_multiplier = 0.0
	var cap := CylinderMesh.new()
	cap.top_radius = BUTTON_RADIUS
	cap.bottom_radius = BUTTON_RADIUS
	cap.height = 0.1
	_button_mesh = MeshInstance3D.new()
	_button_mesh.name = "Mesh"
	_button_mesh.mesh = cap
	_button_mesh.material_override = _button_mat
	button.add_child(_button_mesh)
	var dome := SphereMesh.new()
	dome.radius = BUTTON_RADIUS
	dome.height = 0.12
	dome.is_hemisphere = true
	var dome_mi := MeshInstance3D.new()
	dome_mi.name = "Dome"
	dome_mi.mesh = dome
	dome_mi.material_override = _button_mat
	dome_mi.position.y = 0.05
	button.add_child(dome_mi)
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE_SHADER
	_outline.set_shader_parameter(&"width", 0.012)
	# The shared bar: a dark slot and a lit gold fill.
	GreyboxKit.box(self, Vector3(0.02, 0.11, BAR_LEN + 0.06), Vector3(BAR_X + 0.005, BAR_Y, 0), Palette.CASINO_BLACK, "OddJobsBarSlot", false)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Palette.WARM_GOLD
	fill_mat.emission_enabled = true
	fill_mat.emission = Palette.WARM_GOLD
	fill_mat.emission_energy_multiplier = 1.2
	var fm := BoxMesh.new()
	fm.size = Vector3(0.02, 0.07, BAR_LEN)
	bar_fill = MeshInstance3D.new()
	bar_fill.name = "OddJobsBarFill"
	bar_fill.mesh = fm
	bar_fill.material_override = fill_mat
	add_child(bar_fill)
	count_label = _label("OddJobsCount", Vector3(BAR_X - 0.01, 1.44, 0), 24, Palette.CREAM)
	note_label = _label("OddJobsNote", Vector3(BAR_X - 0.01, 1.33, 0), 18, Palette.WARM_GOLD)
	# Lamps: a strip under the deck's front edge and the marquee bulbs share one warm material.
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Palette.WARM_GOLD.lerp(Palette.CREAM, 0.4)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Palette.WARM_GOLD
	_lamp_mat.emission_energy_multiplier = 0.0
	var strip := GreyboxKit.box(self, Vector3(0.03, 0.05, 0.84), Vector3(-0.405, 0.88, 0), Palette.CREAM, "OddJobsLamp", false)
	(strip.get_node("Mesh") as MeshInstance3D).material_override = _lamp_mat
	for i: int in 5:
		var b: MeshInstance3D = GreyboxKit.sphere(self, 0.035, Vector3(0.12, 2.28, -0.36 + i * 0.18), Palette.CREAM, "OddJobsBulb")
		b.material_override = _lamp_mat
	lamp_light = OmniLight3D.new()
	lamp_light.name = "OddJobsGlow"
	lamp_light.light_color = Palette.WARM_GOLD
	lamp_light.omni_range = 2.4
	lamp_light.shadow_enabled = false
	lamp_light.position = Vector3(-0.7, 1.2, 0)
	lamp_light.visible = false
	add_child(lamp_light)
	_apply_fill()
	set_counts(0.0, OddJobs.MIN_PRESSES)


func _label(n: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.name = n
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_modulate = Palette.CASINO_BLACK
	l.outline_size = 8
	l.position = pos
	l.rotation.y = -PI / 2.0
	add_child(l)
	return l


## Button cap centre in world space (the aim target).
func button_center() -> Vector3:
	return global_transform * (BUTTON_POS + Vector3(0, 0.08, 0))


## True when the ray from `origin` along `dir` comes down onto the button's top (the horizontal
## plane through `center`) within `radius` of it. Looking straight ahead over the deck is not aiming.
static func ray_hits(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> bool:
	if dir.y >= -0.0001 or origin.y <= center.y:
		return false
	var hit: Vector3 = origin + dir * ((center.y - origin.y) / dir.y)
	return Vector2(hit.x - center.x, hit.z - center.z).length() <= radius


func aimed_by(origin: Vector3, dir: Vector3) -> bool:
	return ray_hits(origin, dir, button_center(), AIM_RADIUS)


## The server's shared bar (0..1).
func set_fill(f: float) -> void:
	_target = clampf(f, 0.0, 1.0)
	if _target < shown_fill - 0.3:
		shown_fill = _target  # a payout reset: no slow slide back down


## "N clicks to $50" for the local player at their own share (`needed` 0 = refused).
func set_counts(f: float, needed: int) -> void:
	if needed <= 0:
		count_label.text = "YOU'VE GOT ENOUGH"
	else:
		count_label.text = "%d CLICKS TO $%d" % [maxi(1, ceili((1.0 - f) * needed - 0.001)), OddJobs.PAYOUT]


func show_note(text: String, seconds: float = 2.5) -> void:
	note_label.text = text
	_note_until = _time + seconds


## A click landed: the cap dips and springs back, and flashes.
func dip() -> void:
	_punch = 1.0


func set_glow(on: bool) -> void:
	glowing = on
	lamp_light.visible = on
	if not on:
		_lamp_mat.emission_energy_multiplier = 0.0
	_update_outline()


func set_aimed(on: bool) -> void:
	if on == aimed:
		return
	aimed = on
	_update_outline()


func _update_outline() -> void:
	if aimed or glowing:
		_outline.set_shader_parameter(&"color", Palette.VIP_GOLD if aimed else Palette.WARM_GOLD.lerp(Palette.CASINO_RED, 0.3))
		_button_mesh.material_overlay = _outline
	else:
		_button_mesh.material_overlay = null


func _process(delta: float) -> void:
	_time += delta
	_punch = maxf(0.0, _punch - delta * 9.0)
	button.position.y = BUTTON_POS.y - DIP * minf(1.0, _punch * 1.6)
	_button_mat.emission_energy_multiplier = 1.4 * _punch
	if absf(shown_fill - _target) > 0.0005:
		shown_fill = lerpf(shown_fill, _target, 1.0 - exp(-14.0 * delta))
		_apply_fill()
	if glowing:
		var pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
		_lamp_mat.emission_energy_multiplier = 0.8 + 1.6 * pulse
		lamp_light.light_energy = 0.4 + 0.5 * pulse
		_outline.set_shader_parameter(&"width", 0.012 + 0.012 * pulse)
	if _note_until > 0.0 and _time >= _note_until:
		_note_until = 0.0
		note_label.text = ""


func _apply_fill() -> void:
	bar_fill.visible = shown_fill > 0.002
	bar_fill.scale = Vector3(1, 1, maxf(shown_fill, 0.001))
	bar_fill.position = Vector3(BAR_X - 0.004, BAR_Y, -BAR_LEN * 0.5 + BAR_LEN * shown_fill * 0.5)
