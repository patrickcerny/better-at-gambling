class_name RouletteStation
extends StationBase
## Roulette table: long red layout, Patrick's wheel model at one end, 6 stools around it.


func _build_visuals() -> void:
	game_id = &"roulette"
	seat_count = 6
	hot_center = Vector3(0.5, 0, 0)
	_rug(Vector2(7.0, 5.0), Palette.CASINO_RED.darkened(0.55))
	GreyboxKit.box(self, Vector3(4.2, 0.9, 1.8), Vector3(0.6, 0.45, 0), Color("#3A2A1E"), "Body")
	GreyboxKit.box(self, Vector3(2.6, 0.04, 1.5), Vector3(1.2, 0.92, 0), Palette.FELT_GREEN, "Layout", false)
	_add_wheel_model(Vector3(-1.3, 0.9, 0))
	if Vfx.enabled():
		_print_layout()
	var spots: Array[Vector3] = [Vector3(-0.2, 0, 1.5), Vector3(1.0, 0, 1.5), Vector3(2.2, 0, 1.5), Vector3(-0.2, 0, -1.5), Vector3(1.0, 0, -1.5), Vector3(2.2, 0, -1.5)]
	for i: int in spots.size():
		_stool(spots[i], "Stool%d" % i)
		_add_seat(spots[i] + Vector3(0, 0.5, 0), 0.0 if spots[i].z > 0 else PI)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0.9, 1.7, 1.9)  # wheel and felt both clear of the panel docked right
	camera_anchor.rotation.x = deg_to_rad(-35.0)
	add_child(camera_anchor)


const WHEEL_MODEL: String = "res://assets/casino/roulette_table.fbx"


## Patrick's roulette wheel (native 4 m across with its own floor plane, camera and lights,
## which are dropped), scaled to 1.6 m and resting on the table at `pos`.
func _add_wheel_model(pos: Vector3) -> void:
	var ps: PackedScene = load(WHEEL_MODEL) as PackedScene
	if ps == null:
		return
	var model: Node3D = ps.instantiate()
	model.name = "Wheel"
	add_child(model)
	for n: Node in model.find_children("*", "", true, false):
		if n is Camera3D or n is Light3D or String(n.name) == "Plane":
			n.queue_free()
	model.scale = Vector3.ONE * 0.4
	model.position = pos + Vector3(0, 0.512 * 0.4, 0)  # its base sits 0.51 m below its origin
	if Vfx.enabled():
		wheel_fx = RouletteWheelFx.new()
		model.add_child(wheel_fx)


## Spinning wheel and ball (client only; null on a headless server).
var wheel_fx: RouletteWheelFx

## Felt height of the layout and where the croupier rakes lost chips (by the wheel).
const FELT_Y: float = 0.95
const HOUSE_SPOT: Vector3 = Vector3(-0.25, FELT_Y, 0.0)
const OUTSIDE_BETS: Array[StringName] = [&"low", &"even", &"red", &"black", &"odd", &"high"]


## The ball starts circling (`roulette_spin_started`).
func start_spin(seconds: float) -> void:
	if wheel_fx != null:
		wheel_fx.start_spin(seconds)


## The spin was called off (bets refunded for a minigame): the ball comes off the wheel.
func reset_table() -> void:
	if wheel_fx != null and wheel_fx.ball != null:
		wheel_fx.ball.visible = false


## The ball drops into `number`'s pocket; returns the seconds until it rests there.
func land(number: int) -> float:
	return wheel_fx.land(number) if wheel_fx != null else 0.0


## The betting layout printed on the felt (client only): numbers 1-36 in red and black, the green
## zero, dozens, columns and the even-money boxes, matching `bet_spot`.
func _print_layout() -> void:
	var root := Node3D.new()
	root.name = "LayoutPrint"
	add_child(root)
	var top: float = 0.941
	_tile(root, Vector3(0.04, top, 0.0), Vector2(0.2, 0.86), Palette.FELT_GREEN.lightened(0.25), "0", 56)
	for n: int in range(1, 37):
		var c: Color = Palette.CASINO_RED if n in RouletteLogic.RED else Palette.CASINO_BLACK
		_tile(root, Vector3(bet_spot(&"straight", n).x, top, bet_spot(&"straight", n).z), Vector2(0.165, 0.28), c, str(n), 44)
	var dozens: Array[String] = ["1st 12", "2nd 12", "3rd 12"]
	for d: int in 3:
		_tile(root, Vector3(bet_spot(&"dozen", d + 1).x, top, 0.56), Vector2(0.705, 0.18), Palette.FELT_GREEN.darkened(0.25), dozens[d], 40)
	for c: int in 3:
		_tile(root, Vector3(2.4, top, bet_spot(&"column", c + 1).z), Vector2(0.13, 0.28), Palette.FELT_GREEN.darkened(0.25), "2:1", 30)
	var outside: Dictionary = {&"low": "1-18", &"even": "EVEN", &"red": "RED", &"black": "BLACK", &"odd": "ODD", &"high": "19-36"}
	for t: StringName in OUTSIDE_BETS:
		var col: Color = Palette.CASINO_RED if t == &"red" else (Palette.CASINO_BLACK if t == &"black" else Palette.FELT_GREEN.darkened(0.25))
		_tile(root, Vector3(bet_spot(t, 0).x, top, -0.56), Vector2(0.345, 0.18), col, outside[t], 36)


func _tile(parent: Node3D, pos: Vector3, size: Vector2, color: Color, text: String, font_size: int) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = GreyboxKit.material(color, 0.0, 0.8)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = font_size
	l.pixel_size = 0.0016
	l.modulate = Palette.CREAM
	l.outline_size = 0
	l.rotation.x = -PI * 0.5
	l.position = pos + Vector3(0, 0.002, 0)
	parent.add_child(l)


## Local spot on the layout where a bet of `type` / `value` goes: numbers in a 12 × 3 grid, the
## zero by the wheel, dozens along the near edge, columns at the far end, even-money bets along
## the other edge.
static func bet_spot(type: StringName, value: int) -> Vector3:
	match type:
		&"straight":
			if value <= 0:
				return Vector3(0.05, FELT_Y, 0.0)
			return Vector3(0.25 + ((value - 1) / 3) * 0.18, FELT_Y, ((value - 1) % 3 - 1) * 0.3)
		&"dozen":
			return Vector3(0.25 + ((value - 1) * 4 + 1.5) * 0.18, FELT_Y, 0.56)
		&"column":
			return Vector3(2.4, FELT_Y, (value - 2) * 0.3)
	var i: int = maxi(OUTSIDE_BETS.find(type), 0)
	return Vector3(0.34 + i * 0.36, FELT_Y, -0.56)
