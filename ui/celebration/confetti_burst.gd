class_name ConfettiBurst
extends CPUParticles3D
## Palette confetti for the quiz show and the results podium: `burst` pops one shower out of a
## point and frees itself, `rain` keeps a gentle fall going over an area. Nothing is created on a
## headless server or test run.

const COLORS: Array[Color] = [Palette.VIP_GOLD, Palette.CASINO_RED, Palette.MONEY_GREEN, Palette.CREAM, Palette.WARM_GOLD]


## One shower of `amount` pieces shooting up from `pos` (local to `parent`) and fluttering down.
static func burst(parent: Node3D, pos: Vector3, amount: int = 90, power: float = 1.0) -> ConfettiBurst:
	if DisplayServer.get_name() == "headless" or parent == null or not parent.is_inside_tree():
		return null
	var c := ConfettiBurst.new()
	c._setup(amount, 3.2)
	c.position = pos
	c.one_shot = true
	c.explosiveness = 0.92
	c.direction = Vector3.UP
	c.spread = 55.0
	c.initial_velocity_min = 3.5 * power
	c.initial_velocity_max = 6.5 * power
	c.gravity = Vector3(0, -5.5, 0)
	c.damping_min = 2.2
	c.damping_max = 3.5
	parent.add_child(c)
	c.emitting = true
	c.finished.connect(c.queue_free)
	return c


## A steady fall of confetti over a `size` box centred on `pos`.
static func rain(parent: Node3D, pos: Vector3, size: Vector3, amount: int = 140) -> ConfettiBurst:
	if DisplayServer.get_name() == "headless" or parent == null:
		return null
	var c := ConfettiBurst.new()
	c._setup(amount, 4.5)
	c.position = pos
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	c.emission_box_extents = size * 0.5
	c.direction = Vector3.DOWN
	c.spread = 20.0
	c.initial_velocity_min = 0.4
	c.initial_velocity_max = 1.2
	c.gravity = Vector3(0, -1.6, 0)
	parent.add_child(c)
	return c


func _setup(p_amount: int, p_lifetime: float) -> void:
	amount = p_amount
	lifetime = p_lifetime
	local_coords = false
	angular_velocity_min = -360.0
	angular_velocity_max = 360.0
	angle_min = 0.0
	angle_max = 360.0
	scale_amount_min = 0.7
	scale_amount_max = 1.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.14)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	quad.material = m
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i: int in COLORS.size():
		offsets.append(float(i) / COLORS.size())
		colors.append(COLORS[i])
	grad.offsets = offsets
	grad.colors = colors
	color_initial_ramp = grad
