extends Node3D
## Dev: close-ups of what NPCs and beans hold in their hand: the waiter's tray on his palm (one
## standing, one walking) and a bean with the megaphone, plus the megaphone in first person.
## Run with scripts/screenshot.sh res://tools/dev/held_props_shot.tscn <name> 90 --pixel 1
## --view waiter_front|waiter_side|mega_side|mega_front|mega_first.

var _view: String = "waiter_front"
var _walker: Waiter
var _shouter: AvatarVisuals
var _mega: Node3D
var _eye: Camera3D
var _t: float = 0.0


func _ready() -> void:
	process_priority = 10  # after the beans have posed their arms, like CasinoFloor
	_view = Cmdline.parse(OS.get_cmdline_user_args()).get_string("view", "waiter_front")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.WARM_CHARCOAL
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	fcs.shape = box
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	fm.mesh = plane
	fm.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.3))
	floor_body.add_child(fm)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50
	if _view.begins_with("waiter"):
		var standing := Waiter.new()
		add_child(standing)
		standing.global_position = Vector3(0, 0, 0)
		_walker = Waiter.new()
		_walker.puppet = true
		add_child(_walker)
		_walker.global_position = Vector3(-1.6, 0, 0)
		if _view == "waiter_side":
			cam.position = Vector3(2.6, 1.1, -0.3)
			cam.look_at(Vector3(0.0, 0.8, -0.3))
		else:
			cam.position = Vector3(-0.8, 1.3, -3.4)
			cam.look_at(Vector3(-0.8, 0.75, 0.0))
		return
	_shouter = AvatarVisuals.new()
	add_child(_shouter)
	_shouter.set_color(Palette.player_color(1))
	_shouter.mouth_open = 1.0
	_shouter.hold_right_arm(CasinoFloor.HOLD_ARM)
	_mega = CasinoFloor.make_megaphone()
	_mega.top_level = true
	add_child(_mega)
	match _view:
		"mega_side":
			cam.position = Vector3(2.4, 1.1, -0.4)
			cam.look_at(Vector3(0.0, 0.8, -0.3))
		"mega_front":
			cam.position = Vector3(1.0, 1.2, -2.6)
			cam.look_at(Vector3(0.1, 0.8, -0.2))
		_:
			# First person: the bean is hidden and the camera sits at its eyes.
			_shouter.visible = false
			cam.fov = 75
			cam.position = Vector3(0, AvatarVisuals.EYE_Y + 0.35, -0.2)
			cam.rotation.x = -0.1
			_eye = cam
			var ahead := AvatarVisuals.new()
			add_child(ahead)
			ahead.set_color(Palette.player_color(3))
			ahead.position = Vector3(0.6, 0, -3.5)


func _process(delta: float) -> void:
	_t += delta
	if _walker != null:
		# A puppet walking on the spot (forward and back again), to show the tray riding the arm.
		var p: Vector3 = Vector3(-1.6, 0, 0.6 - fposmod(_t * 2.0, 1.2))
		_walker.apply_net(p, 0.0, false)
	if _mega == null:
		return
	if _eye != null:
		_mega.global_transform = _eye.global_transform * CasinoFloor.view_grip()
		_mega.scale = Vector3.ONE * CasinoFloor.VIEW_SCALE
	else:
		_mega.global_transform = _shouter.hand_node().global_transform.orthonormalized() * CasinoFloor.hand_grip()
