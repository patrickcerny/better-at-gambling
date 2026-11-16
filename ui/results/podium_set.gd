class_name PodiumSet
extends Node3D
## The stage the results show plays on (`ResultsStage`, 0.9.72 rework, Patrick: "rework it to look
## nicer"): a polished dark floor with a red carpet up to a round stage with a brass rim, a walnut
## back wall with gold pin-stripe panels, an art-deco sunburst fanning out behind 1st place, pleated
## burgundy curtains with a swagged valance and a gold fringe, and a marquee sign with chasing warm
## bulbs. Code-built low poly (docs/ART_DIRECTION.md: warm luxurious casino, no neon); everything
## in local metres, the camera looks from +z.

## Radius and height of the round stage the podium stands on.
const STAGE_R: float = 3.45
const STAGE_H: float = 0.16
const WALL_Z: float = -4.0
## The marquee: where it hangs, its size and how many bulbs run along each long edge.
const SIGN_Y: float = 6.25
const SIGN_SIZE: Vector2 = Vector2(7.0, 1.2)
const SIGN_BULBS_X: int = 26
const SIGN_BULBS_Y: int = 4
## Sunburst rays behind the podium: count, centre, length.
const RAYS: int = 17
const RAY_CENTER: Vector3 = Vector3(0, 0.4, WALL_Z + 0.2)
const RAY_LEN: float = 7.2
const BULB_WARM := Color("#FFD98A")
const BULB_DIM := Color("#6E4A1E")

var _bulbs: MultiMeshInstance3D
var _ray_mat: StandardMaterial3D
var _ray_glow: float = 0.0
var _t: float = 0.0
## Steps per second the bulb chase runs (slow while the podium fills, fast for the winner).
var _chase_speed: float = 4.0


func _ready() -> void:
	_build_floor()
	_build_stage()
	_build_wall()
	_build_sunburst()
	_build_curtains()
	_build_marquee()


func _process(delta: float) -> void:
	_t += delta
	if _bulbs != null:
		var mm: MultiMesh = _bulbs.multimesh
		var n: int = mm.instance_count
		var head: float = _t * _chase_speed
		for i: int in n:
			# Every third bulb lit, the pattern marching round the sign.
			var lit: bool = (int(floor(head)) + i) % 3 == 0
			mm.set_instance_color(i, BULB_WARM if lit else BULB_DIM)
	if _ray_mat != null:
		var shimmer: float = 0.08 * sin(_t * 1.7)
		_ray_mat.emission_energy_multiplier = 0.05 + _ray_glow * (0.3 + shimmer * 0.5)


## The winner is up: the sunburst lights and the bulbs run.
func celebrate() -> void:
	_chase_speed = 11.0
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		_ray_glow = 1.0
		return
	var tw: Tween = create_tween()
	tw.tween_property(self, ^"_ray_glow", 1.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_floor() -> void:
	# Polished dark parquet with a soft sheen, and a red carpet runner with gold edges.
	_box(Vector3(30, 0.2, 22), Vector3(0, -0.1, 2), _mat(Color("#2A1A14"), 0.0, 0.32))
	var carpet: StandardMaterial3D = _mat(Palette.CASINO_RED.darkened(0.42), 0.0, 0.9)
	_box(Vector3(3.0, 0.02, 12), Vector3(0, 0.01, STAGE_R + 6.0 - 0.3), carpet)
	for x: float in [-1.55, 1.55]:
		_box(Vector3(0.1, 0.025, 12), Vector3(x, 0.012, STAGE_R + 6.0 - 0.3), _mat(Palette.WARM_GOLD, 0.8, 0.35))


func _build_stage() -> void:
	# Two tiers: a brass-rimmed base and a burgundy velvet top.
	var base: MeshInstance3D = _cyl(STAGE_R + 0.25, STAGE_R + 0.32, STAGE_H * 0.5, Vector3(0, STAGE_H * 0.25, 0), _mat(Color("#3A1D16"), 0.0, 0.4), 48)
	base.name = "StageBase"
	_cyl(STAGE_R, STAGE_R + 0.05, STAGE_H * 0.5, Vector3(0, STAGE_H * 0.75, 0), _mat(Palette.VIP_BURGUNDY.darkened(0.15), 0.0, 0.85), 48)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = STAGE_R + 0.01
	tm.outer_radius = STAGE_R + 0.09
	tm.rings = 48
	tm.ring_segments = 6
	rim.mesh = tm
	rim.position = Vector3(0, STAGE_H, 0)
	rim.scale = Vector3(1, 0.5, 1)
	rim.material_override = _mat(Palette.WARM_GOLD, 0.85, 0.3)
	add_child(rim)
	var rim2 := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = STAGE_R + 0.27
	tm2.outer_radius = STAGE_R + 0.34
	tm2.rings = 48
	tm2.ring_segments = 6
	rim2.mesh = tm2
	rim2.position = Vector3(0, STAGE_H * 0.5, 0)
	rim2.scale = Vector3(1, 0.5, 1)
	rim2.material_override = rim.material_override
	add_child(rim2)


func _build_wall() -> void:
	var walnut: StandardMaterial3D = _mat(Color("#1E1310"), 0.0, 0.55)
	_box(Vector3(30, 11, 0.3), Vector3(0, 5.5, WALL_Z - 0.15), walnut)
	# Tall raised panels with gold pin-stripes between them.
	var panel_mat: StandardMaterial3D = _mat(Color("#2A1B15"), 0.0, 0.45)
	var gold: StandardMaterial3D = _mat(Palette.WARM_GOLD, 0.8, 0.35)
	for i: int in range(-6, 7):
		var x: float = i * 1.5
		_box(Vector3(1.3, 7.6, 0.06), Vector3(x, 4.1, WALL_Z + 0.03), panel_mat)
		_box(Vector3(0.035, 7.6, 0.08), Vector3(x + 0.75, 4.1, WALL_Z + 0.04), gold)
	# A gold dado rail and a skirting along the bottom.
	_box(Vector3(30, 0.08, 0.12), Vector3(0, 0.6, WALL_Z + 0.08), gold)
	_box(Vector3(30, 0.3, 0.1), Vector3(0, 0.15, WALL_Z + 0.06), _mat(Color("#140C0A"), 0.0, 0.5))


## Art-deco rays fanning up from behind the podium, alternating gold and deep walnut.
func _build_sunburst() -> void:  # (the rays meet behind the podium, out of sight)
	_ray_mat = _mat(Color("#6E5126"), 0.0, 0.5)
	_ray_mat.emission_enabled = true
	_ray_mat.emission = Color("#C99A4A")
	_ray_mat.emission_energy_multiplier = 0.05
	var dark: StandardMaterial3D = _mat(Color("#24160F"), 0.0, 0.6)
	for i: int in RAYS:
		var a: float = lerpf(-PI * 0.5, PI * 0.5, (i + 0.5) / RAYS)
		var ray := MeshInstance3D.new()
		var pm := PrismMesh.new()  # a long thin wedge: wide at the tip, pointed at the centre
		var w: float = 2.0 * RAY_LEN * tan(PI / RAYS * 0.5) * 0.92
		pm.size = Vector3(w, RAY_LEN, 0.04)
		pm.left_to_right = 0.5
		ray.mesh = pm
		ray.material_override = _ray_mat if i % 2 == 0 else dark
		ray.position = RAY_CENTER + Vector3(sin(a), cos(a), 0) * RAY_LEN * 0.5 + Vector3(0, 0, 0.01 * (i % 2))
		ray.rotation = Vector3(0, 0, -a + PI)  # the prism's point at the centre
		add_child(ray)


func _build_curtains() -> void:
	var velvet: StandardMaterial3D = _mat(Palette.VIP_BURGUNDY, 0.0, 0.85)
	var velvet_dark: StandardMaterial3D = _mat(Palette.VIP_BURGUNDY.darkened(0.3), 0.0, 0.9)
	# Pleats: a row of tall half-overlapping columns each side, gathered towards the edge.
	for side: float in [-1.0, 1.0]:
		for k: int in 9:
			var x: float = side * (6.0 + k * 0.32)
			var c: MeshInstance3D = _cyl(0.2, 0.24, 9.6, Vector3(x, 4.8, WALL_Z + 0.45 + (k % 2) * 0.06), velvet if k % 2 == 0 else velvet_dark, 10)
			c.name = "Pleat"
		# A gold tie-back rope.
		var tie := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.07
		cm.height = 3.2
		tie.mesh = cm
		tie.rotation = Vector3(0, 0, PI * 0.5)
		tie.position = Vector3(side * 7.3, 2.3, WALL_Z + 0.75)
		tie.material_override = _mat(Palette.WARM_GOLD, 0.8, 0.35)
		add_child(tie)
	# The valance: swags (flattened spheres) along the top and a gold fringe under them.
	for i: int in range(-8, 9):
		var swag := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.95
		sm.height = 1.1
		sm.radial_segments = 16
		sm.rings = 8
		swag.mesh = sm
		swag.scale = Vector3(1, 0.62, 0.35)
		swag.position = Vector3(i * 1.75, 9.15, WALL_Z + 0.75)
		swag.material_override = velvet
		add_child(swag)
	_box(Vector3(30, 0.9, 0.5), Vector3(0, 9.75, WALL_Z + 0.7), velvet_dark)
	_box(Vector3(30, 0.07, 0.08), Vector3(0, 8.82, WALL_Z + 1.08), _mat(Palette.WARM_GOLD, 0.8, 0.35))


## A dark plaque in a brass frame with the title and a ring of chasing bulbs.
func _build_marquee() -> void:
	var at := Vector3(0, SIGN_Y, WALL_Z + 0.35)
	_box(Vector3(SIGN_SIZE.x + 0.3, SIGN_SIZE.y + 0.3, 0.12), at, _mat(Palette.WARM_GOLD, 0.85, 0.3))
	_box(Vector3(SIGN_SIZE.x, SIGN_SIZE.y, 0.16), at + Vector3(0, 0, 0.02), _mat(Color("#1A0F0C"), 0.0, 0.5))
	var title := Label3D.new()
	title.name = "Title"
	title.text = "BETTER AT GAMBLING"
	title.font = TableSkin.black_font()
	title.font_size = 120
	title.pixel_size = 0.0068
	title.outline_size = 10
	title.outline_modulate = Color("#5A3A12")
	title.modulate = Palette.VIP_GOLD
	title.position = at + Vector3(0, 0, 0.12)
	add_child(title)
	# Bulbs round the frame (one MultiMesh, recoloured every frame for the chase).
	var spots: Array[Vector3] = []
	var hx: float = SIGN_SIZE.x * 0.5 + 0.05
	var hy: float = SIGN_SIZE.y * 0.5 + 0.05
	for i: int in SIGN_BULBS_X:
		spots.append(at + Vector3(lerpf(-hx, hx, i / float(SIGN_BULBS_X - 1)), hy, 0.12))
	for i: int in range(1, SIGN_BULBS_Y + 1):
		spots.append(at + Vector3(hx, lerpf(hy, -hy, i / float(SIGN_BULBS_Y + 1)), 0.12))
	for i: int in SIGN_BULBS_X:
		spots.append(at + Vector3(lerpf(hx, -hx, i / float(SIGN_BULBS_X - 1)), -hy, 0.12))
	for i: int in range(1, SIGN_BULBS_Y + 1):
		spots.append(at + Vector3(-hx, lerpf(-hy, hy, i / float(SIGN_BULBS_Y + 1)), 0.12))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.065
	sm.height = 0.13
	sm.radial_segments = 8
	sm.rings = 4
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	bm.vertex_color_is_srgb = true
	sm.material = bm
	mm.mesh = sm
	mm.instance_count = spots.size()
	for i: int in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis(), spots[i]))
		mm.set_instance_color(i, BULB_DIM)
	_bulbs = MultiMeshInstance3D.new()
	_bulbs.name = "Bulbs"
	_bulbs.multimesh = mm
	_bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bulbs)
	# The sign casts a little warm glow on the wall round it.
	var glow := OmniLight3D.new()
	glow.position = at + Vector3(0, 0, 1.2)
	glow.omni_range = 6.0
	glow.light_energy = 0.6
	glow.light_color = BULB_WARM
	add_child(glow)


func _box(size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = m
	add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, at: Vector3, m: Material, segments: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = at
	mi.material_override = m
	add_child(mi)
	return mi


static func _mat(c: Color, metallic: float = 0.0, roughness: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m
