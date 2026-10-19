extends Node3D
## Dev: close-ups of what NPCs and beans hold in their hand: the waiter's tray on his palm (one
## standing, one walking) and a bean with the megaphone, plus the megaphone in first person.
## Run with scripts/screenshot.sh res://tools/dev/held_props_shot.tscn <name> 90
## --view waiter_front|waiter_side|mega_side|mega_front|mega_first, or --view dealer
## --station blackjack_1 (any blackjack/roulette station: the Lucky Lounge with its dealers, a
## close-up of that table's dealer from the side).

var _view: String = "waiter_front"
var _walker: Waiter
var _shouter: AvatarVisuals
var _mega: Node3D
var _eye: Camera3D
var _t: float = 0.0


func _ready() -> void:
	process_priority = 10  # after the beans have posed their arms, like CasinoFloor
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_view = args.get_string("view", "waiter_front")
	if _view == "dealer":
		_dealers(StringName(args.get_string("station", "blackjack_1")))
		return
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


## The Lucky Lounge with a dealer at every table (as `CasinoFloor` places them), the camera on the
## dealer of `sid` from the side so the gap under the feet would show.
func _dealers(sid: StringName) -> void:
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	add_child(map)
	var target: Dealer = null
	for id: StringName in map.stations:
		var station: StationBase = map.stations[id]
		if not DealerLogic.OFFSETS.has(station.game_id):
			continue
		var dealer := Dealer.new()
		dealer.position_offset = station.global_position + (DealerLogic.OFFSETS[station.game_id] as Vector3).rotated(Vector3.UP, station.global_rotation.y)
		dealer.yaw = wrapf(station.global_rotation.y + float(DealerLogic.FACINGS[station.game_id]), -PI, PI)
		add_child(dealer)
		dealer.global_position = dealer.position_offset
		if id == sid:
			target = dealer
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50
	if target != null:
		var side: Vector3 = target.forward().cross(Vector3.UP)
		cam.global_position = target.position_offset * Vector3(1, 0, 1) + side * 2.8 - target.forward() * 0.6 + Vector3(0, 0.6, 0)
		cam.look_at(target.position_offset * Vector3(1, 0, 1) + target.forward() * 0.5 + Vector3(0, 0.55, 0))


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
