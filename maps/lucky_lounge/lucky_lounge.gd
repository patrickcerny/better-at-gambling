class_name LuckyLounge
extends Node3D
## Greybox of "The Lucky Lounge" (§2.3, docs/ART_DIRECTION.md). Three rooms on one floor:
## - the start room (entrance hall, south): front entrance, the ready pedestals and the party
##   settings board, shut off from the casino by the lobby doors until the match starts;
## - the casino floor: blackjack lounge, roulette pit, slot rows, Plinko wall, bar, gift shop and
##   the barred jail cell where security locks people up;
## - the VIP lounge (north), its own room behind the north door, where the bouncer checks you.
## Built procedurally from the tables below so it is easy to tune.

const SIZE_X: float = 44.0
const SIZE_Z: float = 32.0
const WALL_H: float = 7.0

## station id → [station kind, position, yaw degrees]
const STATIONS: Dictionary = {
	&"slot_1": [&"slots", Vector3(-20, 0, -13.5), 180], &"slot_2": [&"slots", Vector3(-17.5, 0, -13.5), 180],
	&"slot_3": [&"slots", Vector3(-15, 0, -13.5), 180], &"slot_4": [&"slots", Vector3(-12.5, 0, -13.5), 180],
	&"slot_5": [&"slots", Vector3(-10, 0, -13.5), 180], &"slot_6": [&"slots", Vector3(-7.5, 0, -13.5), 180],
	&"slot_7": [&"slots", Vector3(-20, 0, -8.5), 0], &"slot_8": [&"slots", Vector3(-17.5, 0, -8.5), 0],
	&"slot_9": [&"slots", Vector3(-15, 0, -8.5), 0], &"slot_10": [&"slots", Vector3(-12.5, 0, -8.5), 0],
	&"slot_11": [&"slots", Vector3(-10, 0, -8.5), 0], &"slot_12": [&"slots", Vector3(-7.5, 0, -8.5), 0],
	&"plinko_1": [&"plinko", Vector3(11, 0, -14.5), 0], &"plinko_2": [&"plinko", Vector3(17.5, 0, -14.5), 0],
	&"roulette_1": [&"roulette", Vector3(-6, 0, -3), 0], &"roulette_2": [&"roulette", Vector3(6, 0, -3), 180],
	&"blackjack_1": [&"blackjack", Vector3(-16, 0, 4), 0], &"blackjack_2": [&"blackjack", Vector3(-9, 0, 4), 0],
	&"blackjack_3": [&"blackjack", Vector3(-2, 0, 4), 0],
	# VIP lounge (ground floor, behind the north door): the tables either side of the aisle from
	# the door, the two slots against its back wall.
	&"vip_blackjack_1": [&"blackjack", Vector3(-4.3, 0, -20.5), 0], &"vip_roulette_1": [&"roulette", Vector3(4.0, 0, -20.5), 0],
	&"vip_slot_1": [&"slots", Vector3(-6.5, 0, -24.9), 0], &"vip_slot_2": [&"slots", Vector3(6.5, 0, -24.9), 0],
}
const SPAWNS: Array[Vector3] = [  # start-room spots: in front of the pedestal stairs (z ≥ 12.95)
	Vector3(-6, 0, 12.3), Vector3(-4, 0, 11.8), Vector3(-2, 0, 12.3), Vector3(2, 0, 12.3),
	Vector3(4, 0, 11.8), Vector3(6, 0, 12.3), Vector3(-8, 0, 12.3), Vector3(8, 0, 12.3),
]
const GUARD_ROUTES: Array = [
	[Vector3(-12, 0, 0), Vector3(-12, 0, -11), Vector3(0, 0, -11), Vector3(0, 0, 0)],
	[Vector3(12, 0, 0.5), Vector3(18, 0, -8), Vector3(8, 0, -8), Vector3(2, 0, 7)],
]
## The VIP lounge: its own room north of the casino, inner faces x −9..9, z −26..−16 (the casino's
## north wall is its south wall). One door in the middle of that wall.
const VIP_X: float = 9.0
const VIP_Z_FAR: float = -26.0
const VIP_DOOR_HALF: float = 1.75
const VIP_DOOR_H: float = 3.2
## Middle of the VIP door, where the bouncer checks you (the gate area fills the doorway).
const VIP_GATE_POS: Vector3 = Vector3(0.0, 0.0, -SIZE_Z * 0.5)
## Which way the bouncer pushes someone without access: back out onto the casino floor.
const VIP_GATE_PUSH: Vector3 = Vector3(0.0, 0.0, 1.0)
## Pillars: the west pair stands in the roulette pit, the east pair frames the casino side of the
## lobby doors (half set into the start-room wall).
const PILLARS: Array[Vector3] = [Vector3(-9.6, 0, -1), Vector3(9.6, 0, -1), Vector3(-3.75, 0, 8.4), Vector3(3.75, 0, 8.4)]
const ENTRANCE_POS: Vector3 = Vector3(0, 0, 15.0)
const RESPAWN_POS: Vector3 = Vector3(0, 0, 13.0)
## Where online players appear in the start room (off the ready pads).
const LOBBY_SPAWNS: Array[Vector3] = [
	Vector3(-7, 0, 10.0), Vector3(7, 0, 10.0), Vector3(-5, 0, 10.8), Vector3(5, 0, 10.8),
	Vector3(-9, 0, 11.0), Vector3(9, 0, 11.0), Vector3(-7, 0, 11.6), Vector3(7, 0, 11.6),
]
## Where players stand to shop at the Gift Shop kiosk (east wall, next to the bar).
const SHOP_POS: Vector3 = Vector3(19.6, 0, 1.5)
## The Odd Jobs cabinet (button smash for broke players) against the east wall on the Gift Shop's
## north side, away from the bar: its centre, and where players stand to use it.
const ODD_JOBS_CABINET: Vector3 = Vector3(21.35, 0, -0.95)
const ODD_JOBS_POS: Vector3 = Vector3(20.3, 0, -0.95)
const BAR_X: float = 17.7
const BAR_W: float = 7.0
const SETTINGS_BOARD_POS: Vector3 = Vector3(12.5, 0, 14.6)
## Radius around a ready pedestal's centre that counts as standing on it, and how high its top is
## (you have to be up on it, not beside it).
const PAD_RADIUS: float = 0.75
const PEDESTAL_TOP: float = 0.8
## Floor layers (y): carpet 0.01, area rugs 0.02, station rugs 0.03. Keep 1 cm apart.
const AREA_RUG_Y: float = 0.02
const STATION_RUG_Y: float = 0.03
## The ready pedestals (0.8.15, Patrick: "Podeste"): Greek marble column pedestals along the
## south wall of the start room, one per player colour, nearest the door first, each with a
## marble stair up to its top. The revolving door gap runs x −2..2.
const PEDESTALS: Array[Vector3] = [
	Vector3(-3.0, 0, 15.1), Vector3(3.0, 0, 15.1), Vector3(-5.2, 0, 15.1), Vector3(5.2, 0, 15.1),
	Vector3(-7.4, 0, 15.1), Vector3(7.4, 0, 15.1), Vector3(-9.6, 0, 15.1), Vector3(9.6, 0, 15.1),
]
## The glow from above a ready pedestal: warm gold spotlight, how bright, how long it fades.
const PEDESTAL_GLOW: Color = Color(1.0, 0.8, 0.45)
const PEDESTAL_LIGHT_ENERGY: float = 6.0
const PEDESTAL_GLOW_FADE: float = 0.3
## A pedestal's name plate when nobody has its colour.
const PEDESTAL_FREE: String = "FREE"
## How high the name plate's centre sits (on its post behind the column): above the name tag of a
## player standing on the pedestal (feet 0.8 + tag 2.15 = 2.95), so the two never overlap.
const PEDESTAL_PLATE_Y: float = 3.5
const PEDESTAL_NAME_SIZE: int = 44
const MARBLE: Color = Color("#E6DFD2")
const MARBLE_DARK: Color = Color("#B9AE9C")
## The wall between the start room and the casino (centre line) and its doorway: the lobby
## doors fill x −LOBBY_DOOR_HALF..LOBBY_DOOR_HALF, LOBBY_DOOR_H high.
const LOBBY_DOORS_Z: float = 8.4
const LOBBY_WALL_T: float = 0.5
const LOBBY_DOOR_HALF: float = 2.75
const LOBBY_DOOR_H: float = 4.0
## The barrier in the doorway while the doors are shut: thicker than the wall so a body thrown at
## it full speed can't tunnel through in one physics step.
const LOBBY_BARRIER_T: float = 0.9
## Jail (Patrick: "an own room where the security puts you", "just bars"; 0.9.4: "in the wall, on
## the right side of the room"): a cell recessed into the casino's east wall (on your right as you
## come in through the lobby doors), between the Plinko corner and the Odd Jobs cabinet. Its gold
## bars are the front face, flush with the wall line (x = SIZE_X / 2 − 0.25); the cell itself lies
## behind the wall plane. Inner volume, gate in the middle of the bars, where the bouncer delivers
## people (outside the gate), spots inside, and where they walk out when the time is up (at the
## lobby doors, on the casino side).
const JAIL_AREA: AABB = AABB(Vector3(21.75, -1.0, -9.3), Vector3(2.75, 5.0, 3.6))
const JAIL_H: float = 3.0
const JAIL_GATE_Z: float = -7.5
const JAIL_GATE_W: float = 1.2
const JAIL_DOOR: Vector3 = Vector3(20.85, 0, -7.5)
const JAIL_SPOTS: Array[Vector3] = [Vector3(22.75, 0, -8.3), Vector3(22.75, 0, -6.7), Vector3(22.45, 0, -7.5), Vector3(23.25, 0, -7.5)]
const JAIL_EXITS: Array[Vector3] = [Vector3(0.6, 0, 7.2), Vector3(1.4, 0, 7.2), Vector3(-0.2, 0, 7.2), Vector3(2.2, 0, 7.2)]
## The jailed player's view: on the wall over the cell, looking out over the floor.
const JAIL_CAM_POS: Vector3 = Vector3(21.1, 4.4, -7.5)
const JAIL_CAM_LOOK: Vector3 = Vector3(3.0, 0.4, -4.0)

var stations: Dictionary[StringName, StationBase] = {}
## Per ready pedestal: the name on its brass plate, the top slab (never changes), and the warm
## spotlight from the ceiling that comes on while its player is ready (with its light cone and the
## pool of light on the top, `pedestal_glows`).
var pedestal_labels: Array[Label3D] = []
var pedestal_tops: Array[MeshInstance3D] = []
var pedestal_lights: Array[SpotLight3D] = []
var pedestal_glows: Array[Node3D] = []
var _pedestal_state: Array = []
## 0..1 per pedestal: how far its glow has faded in, and the fade under way.
var _glow_level: Array[float] = []
var _glow_tweens: Array[Tween] = []
## Bobbing arrow over the local player's own pedestal (built on first use, client only).
var pedestal_marker: Node3D
var _marker_base_y: float = 0.0
var _marker_time: float = 0.0
var vip_gate_area: Area3D
var nav_region: NavigationRegion3D
var props_parent: Node3D
## The Odd Jobs cabinet's red button cap (dips on the local player's presses).
var odd_jobs_button: Node3D
var navmesh_ready: bool = false
## The lobby doors between the start room and the casino (§2.2): a solid barrier filling the
## doorway while shut, two swinging leaves to look at, the sign above and the countdown on them.
var lobby_doors: StaticBody3D
var lobby_open: bool = true
var _door_leaves: Array[Node3D] = []
var _door_tween: Tween = null
var door_sign: Label3D
var door_countdown_label: Label3D
## Seconds left on the countdown shown on the doors (while `door_counting`).
var door_countdown: float = 0.0
var door_counting: bool = false
## The jail cell's gate (hinge node; the collider never opens) and the jailed player's camera spot.
var jail_gate: Node3D
var jail_camera: Node3D
## False for decorative copies (the menu and loading panorama): no navmesh bake.
var bake_navmesh: bool = true


func _ready() -> void:
	_build_floor_and_walls()
	_build_lobby()
	_build_floor_areas()
	_build_vip_room()
	_build_jail()
	_build_stations()
	_build_props()
	_build_lights()
	if Vfx.enabled():
		add_child(LoungeDecor.new(self))  # client-only art pass; never on the headless server
	if bake_navmesh:
		_build_navmesh()


## Station id → world position of the station origin.
func station_positions() -> Dictionary:
	var out: Dictionary = {}
	for sid: StringName in stations:
		out[sid] = stations[sid].global_position
	return out


## Station id → the table's rotation about y (radians).
func station_yaws() -> Dictionary:
	var out: Dictionary = {}
	for sid: StringName in stations:
		out[sid] = (stations[sid] as Node3D).rotation.y
	return out


## Station id → world positions of its seats, in seat order.
func station_seats() -> Dictionary:
	var out: Dictionary = {}
	for sid: StringName in stations:
		var st: StationBase = stations[sid]
		var seats: Array = []
		for i: int in st.seats.size():
			seats.append(st.seat_position(i))
		out[sid] = seats
	return out


## Spawn points (world).
func spawn_points() -> Array[Vector3]:
	return SPAWNS.duplicate()


## Lobby spawn for a player (online rooms).
func lobby_spawn(player_id: int) -> Vector3:
	return LOBBY_SPAWNS[(player_id - 1) % LOBBY_SPAWNS.size()]


## Fills in the room rules the server needs from this map: the lobby door line, the jail cell, the
## spots inside it and where jailed players come out.
static func describe_rooms(def: MapDefinition) -> void:
	def.lobby_door_z = LOBBY_DOORS_Z - LOBBY_WALL_T * 0.5
	def.jail_area = JAIL_AREA
	def.jail_spots = JAIL_SPOTS.duplicate()
	def.jail_exits = JAIL_EXITS.duplicate()


## Centre (floor level) of the ready pedestal in a player colour.
func ready_pad(color_index: int) -> Vector3:
	return PEDESTALS[clampi(color_index, 0, PEDESTALS.size() - 1)]


## Writes the player's name on the pedestal's brass plate ("" = nobody has this colour: the plate
## reads FREE) and fades the glow from above in while they are ready, out when they are not.
func set_pedestal(color_index: int, player_name: String, ready: bool) -> void:
	if color_index < 0 or color_index >= pedestal_labels.size():
		return
	var state: Array = [player_name, ready]
	if _pedestal_state[color_index] == state:
		return
	_pedestal_state[color_index] = state
	var label: Label3D = pedestal_labels[color_index]
	label.text = player_name.to_upper() if player_name != "" else PEDESTAL_FREE
	label.font_size = PEDESTAL_NAME_SIZE if label.text.length() <= 8 else maxi(20, PEDESTAL_NAME_SIZE * 8 / label.text.length())  # long names fit the plate
	label.modulate = Palette.player_color(color_index).lightened(0.35) if player_name != "" else Palette.CREAM.darkened(0.35)
	var to: float = 1.0 if ready and player_name != "" else 0.0
	var tw: Tween = _glow_tweens[color_index]
	if tw != null and tw.is_valid():
		tw.kill()
	if not is_inside_tree():
		_set_glow(to, color_index)
		return
	tw = create_tween()
	tw.tween_method(_set_glow.bind(color_index), _glow_level[color_index], to, PEDESTAL_GLOW_FADE * absf(to - _glow_level[color_index]))
	_glow_tweens[color_index] = tw


## The glow over pedestal `i` at `level` (0 = off: the light is hidden, so it costs nothing).
func _set_glow(level: float, i: int) -> void:
	_glow_level[i] = level
	var light: SpotLight3D = pedestal_lights[i]
	light.visible = level > 0.001
	light.light_energy = PEDESTAL_LIGHT_ENERGY * level
	var glow: Node3D = pedestal_glows[i]
	glow.visible = level > 0.001
	for mi: MeshInstance3D in [glow.get_node(^"Cone") as MeshInstance3D, glow.get_node(^"Pool") as MeshInstance3D]:
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		mat.albedo_color.a = float(mi.get_meta(&"alpha")) * level


## Shows (or hides) the arrow that points the local player to their own pedestal, in their colour.
## Hidden again once they are ready. One marker: it follows whichever colour is passed.
func set_pedestal_marker(color_index: int, shown: bool) -> void:
	if not shown or color_index < 0 or color_index >= PEDESTALS.size():
		if pedestal_marker != null:
			pedestal_marker.visible = false
		_update_processing()
		return
	if pedestal_marker == null:
		pedestal_marker = Node3D.new()
		pedestal_marker.name = "PedestalMarker"
		add_child(pedestal_marker)
		# Downward cone with a short shaft: reads as an arrow from every side.
		var head := MeshInstance3D.new()
		head.name = "Head"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.28
		cone.bottom_radius = 0.0
		cone.height = 0.4
		cone.radial_segments = 8
		head.mesh = cone
		head.position.y = 0.2
		pedestal_marker.add_child(head)
		var shaft := MeshInstance3D.new()
		shaft.name = "Shaft"
		var bar := BoxMesh.new()
		bar.size = Vector3(0.16, 0.3, 0.16)
		shaft.mesh = bar
		shaft.position.y = 0.55
		pedestal_marker.add_child(shaft)
	var color: Color = Palette.player_color(color_index)
	var mat := StandardMaterial3D.new()  # own material: the kit caches one per colour
	mat.albedo_color = color
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	for child: Node in pedestal_marker.get_children():
		(child as MeshInstance3D).material_override = mat
	var pos: Vector3 = PEDESTALS[color_index]
	_marker_base_y = PEDESTAL_TOP + 1.3
	pedestal_marker.position = Vector3(pos.x, _marker_base_y, pos.z)
	pedestal_marker.visible = true
	set_process(true)


func _process(delta: float) -> void:
	if door_counting:
		door_countdown -= delta
		door_counting = door_countdown > -1.5  # "GO!" for a moment if the doors are late
		_show_door_countdown()
	if pedestal_marker == null or not pedestal_marker.visible:
		_update_processing()
		return
	_marker_time += delta
	pedestal_marker.position.y = _marker_base_y + sin(_marker_time * 3.0) * 0.12
	pedestal_marker.rotation.y = _marker_time * 1.2


func _update_processing() -> void:
	set_process(door_counting or (pedestal_marker != null and pedestal_marker.visible))


## Opens (casino reachable) or closes the lobby doors. Shut, a solid barrier fills the doorway;
## opening swings both leaves into the start room and drops the barrier.
func set_lobby_open(open: bool) -> void:
	if lobby_doors == null or open == lobby_open:
		return
	lobby_open = open
	var shape: CollisionShape3D = lobby_doors.get_node("Shape")
	shape.set_deferred(&"disabled", open)
	if door_sign != null:
		door_sign.visible = not open
	if open:
		set_door_countdown(-1.0)
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()  # shut again while still swinging open
	_door_tween = create_tween().set_parallel() if open and is_inside_tree() else null
	for i: int in _door_leaves.size():
		var hinge: Node3D = _door_leaves[i]
		var angle: float = (-PI * 0.5 if i == 0 else PI * 0.5) if open else 0.0
		if _door_tween != null:
			_door_tween.tween_property(hinge, ^"rotation:y", angle, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			hinge.rotation.y = angle


## The 3-2-1 on the lobby doors: counts down from `seconds` on its own (−1 hides it). The doors
## open when the server says so (`set_lobby_open`), not when this reaches zero.
func set_door_countdown(seconds: float) -> void:
	door_counting = seconds > 0.0
	door_countdown = maxf(seconds, 0.0)
	_show_door_countdown()
	_update_processing()


func _show_door_countdown() -> void:
	if door_countdown_label == null:
		return
	door_countdown_label.visible = door_counting and not lobby_open
	if door_countdown_label.visible:
		var n: int = ceili(door_countdown)
		door_countdown_label.text = str(n) if n > 0 else "GO!"


func _build_floor_and_walls() -> void:
	GreyboxKit.box(self, Vector3(SIZE_X, 0.5, SIZE_Z), Vector3(0, -0.25, 0), Color("#8C7F78"), "Floor")  # marble grey
	var carpet: Color = Palette.CASINO_RED.darkened(0.45)
	_plane(Vector2(SIZE_X - 2, SIZE_Z - 2), Vector3(0, 0.01, 0), carpet, "Carpet")
	var wall: Color = Color("#4A2F2A")
	var hx: float = SIZE_X * 0.5
	var hz: float = SIZE_Z * 0.5
	# North wall with the VIP door in the middle.
	var north_w: float = hx - VIP_DOOR_HALF
	GreyboxKit.box(self, Vector3(north_w, WALL_H, 0.5), Vector3(-hx + north_w * 0.5, WALL_H * 0.5, -hz), wall, "WallN")
	GreyboxKit.box(self, Vector3(north_w, WALL_H, 0.5), Vector3(hx - north_w * 0.5, WALL_H * 0.5, -hz), wall, "WallN")
	GreyboxKit.box(self, Vector3(VIP_DOOR_HALF * 2.0, WALL_H - VIP_DOOR_H, 0.5), Vector3(0, (WALL_H + VIP_DOOR_H) * 0.5, -hz), wall, "WallNTop")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, SIZE_Z), Vector3(-hx, WALL_H * 0.5, 0), wall, "WallW")
	# East wall, with the jail cell's opening cut into it (the cell is `_build_jail`).
	var jz0: float = JAIL_AREA.position.z
	var jz1: float = JAIL_AREA.end.z
	GreyboxKit.box(self, Vector3(0.5, WALL_H, jz0 + hz), Vector3(hx, WALL_H * 0.5, (jz0 - hz) * 0.5), wall, "WallE")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, hz - jz1), Vector3(hx, WALL_H * 0.5, (jz1 + hz) * 0.5), wall, "WallE")
	GreyboxKit.box(self, Vector3(0.5, WALL_H - JAIL_H, jz1 - jz0), Vector3(hx, (WALL_H + JAIL_H) * 0.5, (jz0 + jz1) * 0.5), wall, "WallE")
	# South wall with the entrance gap.
	GreyboxKit.box(self, Vector3(hx - 2.0, WALL_H, 0.5), Vector3(-SIZE_X * 0.25 - 1.0, WALL_H * 0.5, hz), wall, "WallS1")
	GreyboxKit.box(self, Vector3(hx - 2.0, WALL_H, 0.5), Vector3(SIZE_X * 0.25 + 1.0, WALL_H * 0.5, hz), wall, "WallS2")
	GreyboxKit.box(self, Vector3(4.5, WALL_H - 3.2, 0.5), Vector3(0, WALL_H - 1.6, hz), wall, "WallSTop")
	# The start-room wall: wall to the ceiling across the whole building, the lobby doorway in
	# the middle (the doors themselves are `_build_lobby_doors`).
	var mid_w: float = hx - LOBBY_DOOR_HALF
	GreyboxKit.box(self, Vector3(mid_w, WALL_H, LOBBY_WALL_T), Vector3(-hx + mid_w * 0.5, WALL_H * 0.5, LOBBY_DOORS_Z), wall, "WallLobby")
	GreyboxKit.box(self, Vector3(mid_w, WALL_H, LOBBY_WALL_T), Vector3(hx - mid_w * 0.5, WALL_H * 0.5, LOBBY_DOORS_Z), wall, "WallLobby")
	GreyboxKit.box(self, Vector3(LOBBY_DOOR_HALF * 2.0, WALL_H - LOBBY_DOOR_H, LOBBY_WALL_T), Vector3(0, (WALL_H + LOBBY_DOOR_H) * 0.5, LOBBY_DOORS_Z), wall, "WallLobbyTop")
	# Porch outside the entrance, closed off: nobody leaves the building on foot.
	GreyboxKit.box(self, Vector3(8.0, 0.5, 5.0), Vector3(0, -0.25, hz + 2.5), Color("#8C7F78"), "Porch")
	GreyboxKit.box(self, Vector3(8.0, WALL_H, 0.5), Vector3(0, WALL_H * 0.5, hz + 5.0), wall, "PorchWall")
	for x: float in [-4.0, 4.0]:
		GreyboxKit.box(self, Vector3(0.5, WALL_H, 5.0), Vector3(x, WALL_H * 0.5, hz + 2.5), wall, "PorchSide")
	# Ceiling (dark, keeps the lighting warm and cosy).
	GreyboxKit.box(self, Vector3(SIZE_X, 0.3, SIZE_Z), Vector3(0, WALL_H + 0.15, 0), Palette.CASINO_BLACK, "Ceiling")
	# Gold trim along the long walls (the north one stops at the VIP door).
	for x: float in [-1.0, 1.0]:
		GreyboxKit.box(self, Vector3(north_w, 0.15, 0.1), Vector3(x * (hx - north_w * 0.5), 1.0, -hz + 0.3), Palette.WARM_GOLD, "Trim", false)
	GreyboxKit.box(self, Vector3(SIZE_X, 0.15, 0.1), Vector3(0, 1.0, hz - 0.3), Palette.WARM_GOLD, "Trim", false)
	# Pillars (the doorway pair stands half in the start-room wall).
	for p: Vector3 in PILLARS:
		var col: Node3D = GreyboxKit.cylinder(self, 0.45, WALL_H, p + Vector3(0, WALL_H * 0.5, 0), Color("#B8A890"), "Pillar")
		GreyboxKit.cylinder(col, 0.55, 0.3, Vector3(0, -WALL_H * 0.5 + 0.15, 0), Palette.WARM_GOLD, "Base", false, 0.7)


## The start room (entrance hall): checker floor, couches, potted palms, the
## ready pedestals along the south wall, the party settings board and the lobby doors north.
func _build_lobby() -> void:
	var hall_z0: float = LOBBY_DOORS_Z + LOBBY_WALL_T * 0.5
	var hall_z1: float = SIZE_Z * 0.5 - 0.25
	_plane(Vector2(SIZE_X - 0.5, hall_z1 - hall_z0), Vector3(0, 0.015, (hall_z0 + hall_z1) * 0.5), Palette.CASINO_RED.darkened(0.3), "LobbyCarpet")
	# Plants either side of the doors (start-room side), one where the reception desk stood and one
	# where the wardrobe mirror was (the skin picker lives in the main menu now).
	for p: Vector3 in [Vector3(-5.4, 0, hall_z0 + 0.7), Vector3(5.4, 0, hall_z0 + 0.7), Vector3(-13.2, 0, 15.1), Vector3(-21.0, 0, 12.0)]:
		var pot: Node3D = GreyboxKit.cylinder(self, 0.35, 0.6, p + Vector3(0, 0.3, 0), Color("#5A3A22"), "Pot")
		PropModels.dress(pot, &"plant_2" if p.x < 0.0 else &"plant_1", 0.3, 1.7).rotation.y = p.x * 0.7
	# Ready pedestals along the south wall: stand on yours and you're ready.
	for i: int in PEDESTALS.size():
		_build_pedestal(i, PEDESTALS[i])
	# Couches against the back wall of the start room, facing the doors.
	for x: float in [-16.5, 18.0]:
		var couch: Node3D = GreyboxKit.box(self, Vector3(2.4, 0.9, 1.0), Vector3(x, 0.45, SIZE_Z * 0.5 - 0.8), Color("#24304A"), "Couch")
		PropModels.dress(couch, &"couch", 0.45, 0.0, 2.5).rotation.y = PI
	_build_settings_board()
	_build_lobby_doors()


func _build_settings_board() -> void:
	var p: Vector3 = SETTINGS_BOARD_POS
	for x: float in [-1.0, 1.0]:
		GreyboxKit.cylinder(self, 0.07, 1.6, p + Vector3(x, 0.8, 0), Palette.WARM_GOLD, "BoardPost", true, 0.8)
	GreyboxKit.box(self, Vector3(2.4, 1.5, 0.12), p + Vector3(0, 2.2, 0), Palette.FELT_GREEN.darkened(0.3), "SettingsBoard")
	GreyboxKit.box(self, Vector3(2.6, 0.1, 0.16), p + Vector3(0, 3.0, 0), Palette.WARM_GOLD, "BoardTrim", false)
	_sign_label(p + Vector3(0, 2.55, -0.08), PI, "PARTY SETTINGS", 52)
	_sign_label(p + Vector3(0, 2.05, -0.08), PI, "leader: press E", 34)


func _build_lobby_doors() -> void:
	# Built by hand (not GreyboxKit) so the barrier never enters the navmesh: the doorway stays
	# walkable for guards once the doors open. Layer 1 like every wall, so standing players,
	# ragdolls, thrown bodies and props all hit it; it fills the whole doorway and is thicker than
	# the wall so nothing tunnels through it at throw speed.
	lobby_doors = StaticBody3D.new()
	lobby_doors.name = "LobbyDoors"
	lobby_doors.collision_layer = 1
	lobby_doors.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sh := BoxShape3D.new()
	sh.size = Vector3(LOBBY_DOOR_HALF * 2.0, LOBBY_DOOR_H, LOBBY_BARRIER_T)
	cs.shape = sh
	cs.position = Vector3(0, LOBBY_DOOR_H * 0.5, LOBBY_DOORS_Z)
	lobby_doors.add_child(cs)
	add_child(lobby_doors)
	# Two dark-wood leaves with gold panels, hinged at the jambs, swinging into the start room.
	var wood: StandardMaterial3D = GreyboxKit.material(Color("#3A2318"), 0.0, 0.6)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "DoorLeaf%s" % ("L" if side < 0.0 else "R")
		hinge.position = Vector3(side * LOBBY_DOOR_HALF, 0.0, LOBBY_DOORS_Z + LOBBY_WALL_T * 0.5 - 0.08)
		add_child(hinge)
		_door_leaves.append(hinge)
		var w: float = LOBBY_DOOR_HALF - 0.02
		_mesh_box(hinge, Vector3(w, LOBBY_DOOR_H - 0.04, 0.12), Vector3(-side * w * 0.5, LOBBY_DOOR_H * 0.5, 0), wood)
		for y: float in [1.15, 2.85]:
			_mesh_box(hinge, Vector3(w - 0.5, 1.3, 0.03), Vector3(-side * w * 0.5, y, 0.07), gold)
			_mesh_box(hinge, Vector3(w - 0.64, 1.16, 0.035), Vector3(-side * w * 0.5, y, 0.075), wood)
		_mesh_box(hinge, Vector3(0.08, 0.5, 0.06), Vector3(-side * (w - 0.18), 2.0, 0.1), gold)  # handle
	# Gold casing round the doorway on both faces.
	for face: float in [-1.0, 1.0]:
		var z: float = LOBBY_DOORS_Z + face * (LOBBY_WALL_T * 0.5 + 0.03)
		for x: float in [-1.0, 1.0]:
			GreyboxKit.box(self, Vector3(0.18, LOBBY_DOOR_H + 0.1, 0.06), Vector3(x * (LOBBY_DOOR_HALF + 0.09), (LOBBY_DOOR_H + 0.1) * 0.5, z), Palette.WARM_GOLD, "DoorCasing", false)
		GreyboxKit.box(self, Vector3(LOBBY_DOOR_HALF * 2.0 + 0.36, 0.2, 0.08), Vector3(0, LOBBY_DOOR_H + 0.1, z), Palette.WARM_GOLD, "DoorCasing", false)
	# The board over the doors (start-room side), between the doorway pillars, and the big
	# countdown numbers on the doors.
	var board_y: float = LOBBY_DOOR_H + 0.95
	var board_z: float = LOBBY_DOORS_Z + LOBBY_WALL_T * 0.5
	GreyboxKit.box(self, Vector3(5.6, 1.3, 0.08), Vector3(0, board_y, board_z + 0.04), Palette.CASINO_BLACK.lightened(0.06), "DoorBoard", false)
	GreyboxKit.box(self, Vector3(5.8, 0.08, 0.1), Vector3(0, board_y + 0.66, board_z + 0.05), Palette.WARM_GOLD, "DoorBoardTrim", false)
	GreyboxKit.box(self, Vector3(5.8, 0.08, 0.1), Vector3(0, board_y - 0.66, board_z + 0.05), Palette.WARM_GOLD, "DoorBoardTrim", false)
	_sign_label(Vector3(0, board_y + 0.28, board_z + 0.1), 0.0, "THE CASINO", 76).modulate = Palette.VIP_GOLD
	door_sign = _sign_label(Vector3(0, board_y - 0.22, board_z + 0.1), 0.0, "OPENS WHEN EVERYONE IS READY", 46)
	door_sign.visible = false
	door_countdown_label = _sign_label(Vector3(0, 2.2, board_z + 0.25), 0.0, "3", 260)
	door_countdown_label.modulate = Palette.VIP_GOLD
	door_countdown_label.outline_size = 28
	door_countdown_label.visible = false
	# Open until a room's lobby shuts them (Practice and the menu never do).
	cs.disabled = true
	for i: int in _door_leaves.size():
		_door_leaves[i].rotation.y = -PI * 0.5 if i == 0 else PI * 0.5


## A visual-only box under `parent` (door leaves, bars) with a shared material.
func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A Greek marble column pedestal (plinth, fluted drum with a band in the player's colour,
## echinus and abacus, 0.8 m high) with a four-step marble stair in front of it. The stair's
## collision is one smooth wedge (no step lips to catch on); the column is a plain block.
func _build_pedestal(i: int, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Pedestal%d" % i
	root.position = pos
	root.add_to_group(&"ready_pads")
	add_child(root)
	var marble: StandardMaterial3D = GreyboxKit.material(MARBLE, 0.0, 0.45)
	var marble_dark: StandardMaterial3D = GreyboxKit.material(MARBLE_DARK, 0.0, 0.5)
	# The block you stand on (collision only; the column's looks are the visuals below).
	var body := StaticBody3D.new()
	body.name = "Block"
	body.add_to_group(&"navsource")
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, PEDESTAL_TOP, 0.9)
	var cs := CollisionShape3D.new()
	cs.shape = bs
	cs.position.y = PEDESTAL_TOP * 0.5
	body.add_child(cs)
	root.add_child(body)
	# Plinth, drum with 16 flutes, colour band, echinus and abacus.
	(GreyboxKit.box(root, Vector3(1.0, 0.16, 1.0), Vector3(0, 0.08, 0), MARBLE, "Plinth", false).get_node("Mesh") as MeshInstance3D).material_override = marble
	GreyboxKit.cylinder(root, 0.40, 0.03, Vector3(0, 0.175, 0), Palette.player_color(i), "Band", false)
	(GreyboxKit.cylinder(root, 0.36, 0.5, Vector3(0, 0.44, 0), MARBLE, "Drum", false).get_node("Mesh") as MeshInstance3D).material_override = marble
	for f: int in 16:
		var a: float = TAU * f / 16.0
		var flute: Node3D = GreyboxKit.box(root, Vector3(0.05, 0.46, 0.04), Vector3(cos(a) * 0.36, 0.44, sin(a) * 0.36), MARBLE_DARK, "Flute%d" % f, false)
		flute.rotation.y = -a
		(flute.get_node("Mesh") as MeshInstance3D).material_override = marble_dark
	(GreyboxKit.cylinder(root, 0.44, 0.05, Vector3(0, 0.715, 0), MARBLE_DARK, "Echinus", false).get_node("Mesh") as MeshInstance3D).material_override = marble_dark
	GreyboxKit.box(root, Vector3(0.94, 0.012, 0.94), Vector3(0, 0.745, 0), Palette.WARM_GOLD, "Trim", false)
	var top: Node3D = GreyboxKit.box(root, Vector3(0.9, 0.06, 0.9), Vector3(0, PEDESTAL_TOP - 0.03, 0), MARBLE, "Abacus", false)
	var top_mesh: MeshInstance3D = top.get_node("Mesh") as MeshInstance3D
	top_mesh.material_override = marble
	# Stair up from the room side (−z): a smooth wedge to walk on, dressed as four marble steps.
	var stair_len: float = 1.7
	GreyboxKit.ramp(root, Vector3(0, 0, -0.45 - stair_len), Vector3(0, PEDESTAL_TOP, -0.45), 0.9, MARBLE, "Stair")
	for k: int in 4:
		var rise: float = PEDESTAL_TOP / 4.0
		var run: float = stair_len / 4.0
		# Step k climbs from the room side: lowest tread farthest from the column.
		var step: Node3D = GreyboxKit.box(root, Vector3(0.96, rise, run), Vector3(0, rise * (k + 0.5), -0.45 - stair_len + run * (k + 0.5)), MARBLE if k % 2 == 0 else MARBLE_DARK, "Step%d" % k, false)
		(step.get_node("Mesh") as MeshInstance3D).material_override = marble if k % 2 == 0 else marble_dark
	pedestal_labels.append(_build_name_plate(root, i))
	pedestal_tops.append(top_mesh)
	_build_glow(root)
	_pedestal_state.append(["", false])
	_glow_level.append(0.0)
	_glow_tweens.append(null)
	_set_glow(0.0, i)


## The brass name plate on a slim post behind the column (between it and the wall), facing the
## room; high enough to read over the head of whoever stands on the pedestal.
func _build_name_plate(root: Node3D, i: int) -> Label3D:
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	var back_z: float = SIZE_Z * 0.5 - 0.25 - root.position.z - 0.1  # just off the wall
	var plate_h: float = 0.36
	GreyboxKit.cylinder(root, 0.025, PEDESTAL_PLATE_Y, Vector3(0, PEDESTAL_PLATE_Y * 0.5, back_z), Palette.WARM_GOLD, "PlatePost", false, 0.85)
	var plate: MeshInstance3D = _mesh_box(root, Vector3(1.0, plate_h, 0.04), Vector3(0, PEDESTAL_PLATE_Y, back_z - 0.02), brass)
	plate.name = "NamePlate"
	var inset: MeshInstance3D = _mesh_box(root, Vector3(0.92, plate_h - 0.08, 0.01), Vector3(0, PEDESTAL_PLATE_Y, back_z - 0.045), GreyboxKit.material(Palette.CASINO_BLACK.lightened(0.04), 0.0, 0.6))
	inset.name = "NamePlateInset"
	var label := Label3D.new()
	label.name = "Name"
	label.text = PEDESTAL_FREE
	label.font_size = PEDESTAL_NAME_SIZE
	label.pixel_size = 0.004
	label.modulate = Palette.CREAM.darkened(0.35)
	label.outline_modulate = Palette.CASINO_BLACK
	label.outline_size = 8
	label.position = Vector3(0, PEDESTAL_PLATE_Y, back_z - 0.055)
	label.rotation.y = PI
	root.add_child(label)
	return label


## The glow from above (off until the pedestal's player is ready): a warm spotlight straight down
## from a brass can in the ceiling, a faint cone of light and a soft pool on the top.
func _build_glow(root: Node3D) -> void:
	var ceiling_y: float = WALL_H - 0.05
	GreyboxKit.cylinder(root, 0.16, 0.14, Vector3(0, ceiling_y - 0.07, 0), Palette.WARM_GOLD, "SpotCan", false, 0.85)
	var light := SpotLight3D.new()
	light.name = "Spot"
	light.light_color = PEDESTAL_GLOW
	light.spot_range = ceiling_y - 0.1 + 0.5
	light.spot_angle = 6.5
	light.spot_angle_attenuation = 2.2  # soft edge
	light.spot_attenuation = 0.4
	light.shadow_enabled = false
	light.position = Vector3(0, ceiling_y - 0.15, 0)
	light.rotation.x = -PI * 0.5  # straight down
	root.add_child(light)
	pedestal_lights.append(light)
	var glow := Node3D.new()
	glow.name = "Glow"
	root.add_child(glow)
	pedestal_glows.append(glow)
	var cone_h: float = ceiling_y - 0.15 - PEDESTAL_TOP
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = 0.62
	cone.height = cone_h
	cone.radial_segments = 20
	cone.cap_top = false
	cone.cap_bottom = false
	var cone_mi := MeshInstance3D.new()
	cone_mi.name = "Cone"
	cone_mi.mesh = cone
	cone_mi.position.y = PEDESTAL_TOP + cone_h * 0.5
	cone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone_mi.material_override = _glow_material(null)
	cone_mi.set_meta(&"alpha", 0.07)
	glow.add_child(cone_mi)
	var pool := PlaneMesh.new()
	pool.size = Vector2(1.3, 1.3)
	var pool_mi := MeshInstance3D.new()
	pool_mi.name = "Pool"
	pool_mi.mesh = pool
	pool_mi.position.y = PEDESTAL_TOP + 0.004
	pool_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spot := GradientTexture2D.new()
	spot.fill = GradientTexture2D.FILL_RADIAL
	spot.fill_from = Vector2(0.5, 0.5)
	spot.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	spot.gradient = g
	pool_mi.material_override = _glow_material(spot)
	pool_mi.set_meta(&"alpha", 0.55)
	glow.add_child(pool_mi)


## Own unshaded, additive material per glow piece (each pedestal fades on its own).
static func _glow_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(PEDESTAL_GLOW, 0.0)
	m.albedo_texture = tex
	return m


func _sign_label(pos: Vector3, yaw: float, text: String, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = Palette.CREAM
	l.outline_modulate = Palette.CASINO_BLACK
	l.outline_size = 10
	l.position = pos
	l.rotation.y = yaw
	add_child(l)
	return l


func _build_floor_areas() -> void:
	# Coloured rugs identify game areas (readable from a distance). They sit 1 cm above the
	# carpet (0.01) and 1 cm below the station rugs (0.03): closer layers z-fight at distance.
	# LoungeDecor turns them into patterned, brass-edged carpets on clients.
	_plane(Vector2(16.6, 5), Vector3(-10.3, AREA_RUG_Y, 4), Palette.FELT_GREEN.darkened(0.6), "BlackjackRug")
	_plane(Vector2(18, 8), Vector3(0, AREA_RUG_Y, -3), Palette.CASINO_RED.darkened(0.5), "RouletteRug")
	_plane(Vector2(16, 9), Vector3(-13.5, AREA_RUG_Y, -11), Palette.WARM_GOLD.darkened(0.6), "SlotsRug")
	_plane(Vector2(12, 5), Vector3(14, AREA_RUG_Y, -13), Palette.VIP_BURGUNDY.darkened(0.3), "PlinkoRug")
	# Bar (south-east, against the start-room wall; decoration, also the quiz entry area later).
	GreyboxKit.box(self, Vector3(BAR_W, 1.1, 1.2), Vector3(BAR_X, 0.55, 5.0), Color("#3A2A1E"), "Bar")
	GreyboxKit.box(self, Vector3(BAR_W, 0.08, 1.3), Vector3(BAR_X, 1.14, 5.0), Palette.WARM_GOLD, "BarTop", false)
	GreyboxKit.box(self, Vector3(BAR_W, 2.5, 0.4), Vector3(BAR_X, 1.25, 7.0), Color("#2A1E18"), "BackBar")
	for i: int in 6:
		GreyboxKit.box(self, Vector3(0.25, 0.4, 0.25), Vector3(BAR_X - BAR_W * 0.5 + 0.5 + i * 1.3, 1.6, 6.9), [Palette.CASINO_RED, Palette.WARM_GOLD, Palette.FELT_GREEN][i % 3], "Bottle", false)
	_build_gift_shop()
	_build_odd_jobs()
	# Plants and a few obstacles for lanes.
	for p: Vector3 in [Vector3(-20, 0, 14), Vector3(20, 0, 14), Vector3(-20, 0, -1), Vector3(21.2, 0, -2.5)]:
		var pot: Node3D = GreyboxKit.cylinder(self, 0.35, 0.6, p + Vector3(0, 0.3, 0), Color("#5A3A22"), "Pot")
		var plant: Node3D = PropModels.dress(pot, [&"plant_1", &"plant_2", &"plant_3"][absi(int(p.x + p.z)) % 3], 0.3, 1.7)
		plant.rotation.y = p.x * 0.7


## Gift Shop kiosk: a counter with a striped awning and a sign, four items on sale each round.
func _build_gift_shop() -> void:
	var c: Vector3 = SHOP_POS + Vector3(1.3, 0, 0)
	GreyboxKit.box(self, Vector3(1.0, 1.1, 2.2), c + Vector3(0, 0.55, 0), Palette.VIP_BURGUNDY, "ShopCounter")
	GreyboxKit.box(self, Vector3(1.1, 0.08, 2.3), c + Vector3(0, 1.14, 0), Palette.WARM_GOLD, "ShopCounterTop", false)
	for z: float in [-1.0, 1.0]:
		GreyboxKit.box(self, Vector3(0.1, 2.6, 0.1), c + Vector3(-0.5, 1.3, z), Palette.WARM_GOLD, "ShopPost")
	for i: int in 4:
		GreyboxKit.box(self, Vector3(1.4, 0.12, 0.58), c + Vector3(-0.2, 2.65, -0.87 + i * 0.58), Palette.CASINO_RED if i % 2 == 0 else Palette.CREAM, "ShopAwning", false)
	for i: int in 4:
		GreyboxKit.box(self, Vector3(0.3, 0.3, 0.3), c + Vector3(0.1, 1.33, -0.75 + i * 0.5), [Palette.FELT_GREEN, Palette.WARM_GOLD, Palette.CASINO_RED, Palette.CREAM][i], "ShopGoods", false)
	_sign_label(c + Vector3(-0.56, 2.15, 0), -PI / 2.0, "GIFT SHOP", 64)
	var kiosk: Node3D = ItemModels.make_kiosk(1.9)  # Patrick's ATM next to the counter
	kiosk.position = c + Vector3(0.1, 0, 1.75)
	kiosk.rotation.y = -PI / 2.0
	add_child(kiosk)


## The Odd Jobs cabinet: a low wooden arcade cabinet with one big red button on its deck and an
## "ODD JOBS" marquee, its front to the room (−x). Solid like the shop counter.
func _build_odd_jobs() -> void:
	var c: Vector3 = ODD_JOBS_CABINET
	var wood := Color("#3A2A1E")
	GreyboxKit.box(self, Vector3(0.7, 1.0, 0.9), c + Vector3(0, 0.5, 0), wood, "OddJobsCabinet")
	GreyboxKit.box(self, Vector3(0.04, 0.6, 0.7), c + Vector3(-0.37, 0.5, 0), Palette.VIP_BURGUNDY, "OddJobsPanel", false)
	GreyboxKit.box(self, Vector3(0.05, 0.05, 0.92), c + Vector3(-0.36, 0.98, 0), Palette.WARM_GOLD, "OddJobsTrim", false)
	GreyboxKit.box(self, Vector3(0.05, 0.05, 0.92), c + Vector3(-0.36, 0.06, 0), Palette.WARM_GOLD, "OddJobsTrim", false)
	GreyboxKit.box(self, Vector3(0.78, 0.08, 0.98), c + Vector3(-0.02, 1.04, 0), Palette.CASINO_BLACK, "OddJobsDeck", false)
	# The button: gold bezel, red cap (the cap dips when the local player smashes it).
	GreyboxKit.cylinder(self, 0.24, 0.06, c + Vector3(-0.08, 1.11, 0), Palette.WARM_GOLD, "OddJobsBezel", false, 0.8)
	odd_jobs_button = GreyboxKit.cylinder(self, 0.19, 0.12, c + Vector3(-0.08, 1.17, 0), Palette.CASINO_RED, "OddJobsButton", false)
	# Marquee on the back, with its sign facing the room.
	GreyboxKit.box(self, Vector3(0.16, 1.2, 0.9), c + Vector3(0.24, 1.68, 0), wood, "OddJobsBack")
	GreyboxKit.box(self, Vector3(0.04, 0.5, 0.84), c + Vector3(0.14, 1.95, 0), Palette.VIP_BURGUNDY, "OddJobsMarquee", false)
	for y: float in [1.69, 2.21]:
		GreyboxKit.box(self, Vector3(0.05, 0.04, 0.9), c + Vector3(0.13, y, 0), Palette.WARM_GOLD, "OddJobsTrim", false)
	for i: int in 5:
		GreyboxKit.sphere(self, 0.035, c + Vector3(0.12, 2.28, -0.36 + i * 0.18), Palette.CREAM, "OddJobsBulb")
	var l: Label3D = _sign_label(c + Vector3(0.11, 2.0, 0), -PI / 2.0, "ODD JOBS", 32)
	l.modulate = Palette.VIP_GOLD
	_sign_label(c + Vector3(0.11, 1.8, 0), -PI / 2.0, "$50 A BAR", 22)


## The VIP lounge: its own room behind the north door, on the casino's floor level. Parquet,
## gold damask, its own chandelier and lamps, gold statues by the door; the bouncer's gate area
## fills the doorway (no access: pushed back out onto the casino floor).
func _build_vip_room() -> void:
	var wall: Color = Color("#4A2F2A")
	var z0: float = -SIZE_Z * 0.5
	var depth: float = z0 - VIP_Z_FAR
	var mid_z: float = (z0 + VIP_Z_FAR) * 0.5
	GreyboxKit.box(self, Vector3(VIP_X * 2.0 + 1.0, 0.5, depth + 0.5), Vector3(0, -0.25, mid_z - 0.25), Color("#8C7F78"), "FloorVip")
	_plane(Vector2(VIP_X * 2.0, depth), Vector3(0, 0.012, mid_z), Palette.VIP_BURGUNDY, "VipCarpet")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, depth + 0.5), Vector3(-VIP_X - 0.25, WALL_H * 0.5, mid_z - 0.25), wall, "WallVip")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, depth + 0.5), Vector3(VIP_X + 0.25, WALL_H * 0.5, mid_z - 0.25), wall, "WallVip")
	GreyboxKit.box(self, Vector3(VIP_X * 2.0 + 1.0, WALL_H, 0.5), Vector3(0, WALL_H * 0.5, VIP_Z_FAR - 0.25), wall, "WallVip")
	GreyboxKit.box(self, Vector3(VIP_X * 2.0 + 1.0, 0.3, depth + 0.5), Vector3(0, WALL_H + 0.15, mid_z - 0.25), Palette.CASINO_BLACK, "CeilingVip")
	# The bouncer's gate: the whole doorway.
	vip_gate_area = Area3D.new()
	vip_gate_area.name = "VipGate"
	vip_gate_area.collision_layer = 0
	vip_gate_area.collision_mask = 2
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(VIP_DOOR_HALF * 2.0, 2.5, 1.2)
	gcs.shape = gsh
	gcs.position.y = 1.25
	vip_gate_area.add_child(gcs)
	vip_gate_area.position = VIP_GATE_POS
	vip_gate_area.set_meta(&"hazard", &"vip_gate")
	add_child(vip_gate_area)
	# Gold door casing on both faces, velvet-rope posts either side on the casino side.
	for face: float in [-1.0, 1.0]:
		var z: float = z0 + face * 0.28
		for x: float in [-1.0, 1.0]:
			GreyboxKit.box(self, Vector3(0.18, VIP_DOOR_H + 0.1, 0.06), Vector3(x * (VIP_DOOR_HALF + 0.09), (VIP_DOOR_H + 0.1) * 0.5, z), Palette.WARM_GOLD, "VipCasing", false)
		GreyboxKit.box(self, Vector3(VIP_DOOR_HALF * 2.0 + 0.36, 0.2, 0.08), Vector3(0, VIP_DOOR_H + 0.1, z), Palette.WARM_GOLD, "VipCasing", false)
	for x: float in [-1.0, 1.0]:
		var post: Node3D = GreyboxKit.cylinder(self, 0.06, 1.0, Vector3(x * (VIP_DOOR_HALF + 0.45), 0.5, z0 + 0.7), Palette.WARM_GOLD, "GatePost", true, 0.8)
		GreyboxKit.sphere(post, 0.1, Vector3(0, 0.55, 0), Palette.WARM_GOLD, "Knob")
	# The VIP sign over the door, facing the casino floor.
	var sign_pos := Vector3(0, VIP_DOOR_H + 1.05, z0 + 0.3)
	GreyboxKit.box(self, Vector3(4.2, 1.2, 0.08), sign_pos, Palette.VIP_BURGUNDY, "VipSign", false)
	GreyboxKit.box(self, Vector3(4.4, 0.08, 0.1), sign_pos + Vector3(0, 0.62, 0.01), Palette.VIP_GOLD, "VipSignTrim", false)
	GreyboxKit.box(self, Vector3(4.4, 0.08, 0.1), sign_pos + Vector3(0, -0.62, 0.01), Palette.VIP_GOLD, "VipSignTrim", false)
	_sign_label(sign_pos + Vector3(0, 0.12, 0.06), 0.0, "VIP LOUNGE", 96).modulate = Palette.VIP_GOLD
	_sign_label(sign_pos + Vector3(0, -0.32, 0.06), 0.0, "MEMBERS & HIGH ROLLERS ONLY", 38)
	# Gold statues inside the door: the VIP lounge is intentionally excessive.
	for x: float in [-7.6, 7.6]:
		var plinth: Node3D = GreyboxKit.box(self, Vector3(0.8, 0.8, 0.8), Vector3(x, 0.4, z0 - 1.3), Color("#D8D0C4"), "Plinth")
		GreyboxKit.capsule(plinth, 0.3, 1.2, Vector3(0, 1.1, 0), GreyboxKit.gold(), "Statue")


## The jail cell (Patrick: "just bars where the bouncer brings you", "in the wall"): an alcove cut
## into the east wall, stone walls on three sides and a ceiling, gold bars across its open front
## (flush with the wall line) with the gate in the middle, a bench, a caged lamp and a JAIL sign
## over the opening. The bars and the gate are solid (layer 1, like the walls): nobody walks, falls
## or gets thrown out. The gate's collider never opens; its leaf swings for show when the bouncer
## puts someone in or lets them out (`swing_jail_gate`).
func _build_jail() -> void:
	var a: AABB = JAIL_AREA
	var x0: float = a.position.x  # the bars, with the gate (the wall's inner face)
	var x1: float = a.end.x  # the back wall's face
	var z0: float = a.position.z
	var z1: float = a.end.z
	var zc: float = (z0 + z1) * 0.5
	var stone := Color("#4A4440")
	# The alcove behind the wall: floor slab, side walls, back wall, ceiling.
	var back: float = x1 + 0.5
	var wx0: float = x0 + 0.5  # the outside face of the casino wall
	GreyboxKit.box(self, Vector3(back - x0, 0.5, z1 - z0 + 1.0), Vector3((x0 + back) * 0.5, -0.25, zc), Color("#8C7F78"), "JailSlab")
	for z: float in [z0 - 0.25, z1 + 0.25]:
		GreyboxKit.box(self, Vector3(back - wx0, WALL_H, 0.5), Vector3((wx0 + back) * 0.5, WALL_H * 0.5, z), stone, "JailWall")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, z1 - z0 + 1.0), Vector3(x1 + 0.25, WALL_H * 0.5, zc), stone, "JailWall")
	GreyboxKit.box(self, Vector3(back - wx0, WALL_H - JAIL_H, z1 - z0 + 1.0), Vector3((wx0 + back) * 0.5, (WALL_H + JAIL_H) * 0.5, zc), stone, "JailWall")
	GreyboxKit.box(self, Vector3(x1 - x0, 0.06, z1 - z0), Vector3((x0 + x1) * 0.5, JAIL_H - 0.03, zc), Palette.CASINO_BLACK, "JailCeiling", false)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	var bars := StaticBody3D.new()
	bars.name = "JailCell"
	bars.collision_layer = 1
	bars.collision_mask = 0
	bars.add_to_group(&"navsource")
	add_child(bars)
	var t: float = 0.3  # collision thickness (the bars themselves are thin)
	var gate_z0: float = JAIL_GATE_Z - JAIL_GATE_W * 0.5
	var gate_z1: float = JAIL_GATE_Z + JAIL_GATE_W * 0.5
	_jail_wall(bars, Vector3(t, JAIL_H, gate_z0 - z0), Vector3(x0, JAIL_H * 0.5, (z0 + gate_z0) * 0.5))
	_jail_wall(bars, Vector3(t, JAIL_H, z1 - gate_z1), Vector3(x0, JAIL_H * 0.5, (gate_z1 + z1) * 0.5))
	var bar := CylinderMesh.new()
	bar.top_radius = 0.035
	bar.bottom_radius = 0.035
	bar.height = JAIL_H
	bar.radial_segments = 8
	var spacing: float = 0.24
	for span: Vector2 in [Vector2(z0, gate_z0), Vector2(gate_z1, z1)]:
		var n: int = maxi(1, int((span.y - span.x) / spacing))
		for i: int in n + 1:
			_bar(bars, bar, Vector3(x0, JAIL_H * 0.5, span.x + i * (span.y - span.x) / n), gold)
	# Cross bands, and a gold frame round the opening.
	for y: float in [0.12, JAIL_H * 0.5, JAIL_H - 0.04]:
		_mesh_box(bars, Vector3(0.07, 0.07, z1 - z0), Vector3(x0, y, zc), gold)
	_mesh_box(bars, Vector3(0.1, 0.18, z1 - z0 + 0.36), Vector3(x0 - 0.04, JAIL_H + 0.09, zc), gold)
	for z: float in [z0 - 0.09, z1 + 0.09]:
		_mesh_box(bars, Vector3(0.1, JAIL_H + 0.18, 0.18), Vector3(x0 - 0.04, (JAIL_H + 0.18) * 0.5, z), gold)
	# The gate: a solid collider in the gap; the barred leaf on a hinge at its north post.
	var cell_door := StaticBody3D.new()
	cell_door.name = "JailGate"
	cell_door.collision_layer = 1
	cell_door.collision_mask = 0
	cell_door.add_to_group(&"navsource")
	var dcs := CollisionShape3D.new()
	var dsh := BoxShape3D.new()
	dsh.size = Vector3(t, JAIL_H, JAIL_GATE_W)
	dcs.shape = dsh
	dcs.position = Vector3(x0, JAIL_H * 0.5, JAIL_GATE_Z)
	cell_door.add_child(dcs)
	add_child(cell_door)
	jail_gate = Node3D.new()
	jail_gate.name = "JailGateLeaf"
	jail_gate.position = Vector3(x0, 0.0, gate_z0)
	add_child(jail_gate)
	for i: int in 5:
		_bar(jail_gate, bar, Vector3(0, JAIL_H * 0.5, 0.12 + i * (JAIL_GATE_W - 0.24) / 4.0), gold)
	for y: float in [0.12, JAIL_H * 0.5, JAIL_H - 0.04]:
		_mesh_box(jail_gate, Vector3(0.08, 0.08, JAIL_GATE_W), Vector3(0, y, JAIL_GATE_W * 0.5), gold)
	_mesh_box(jail_gate, Vector3(0.14, 0.24, 0.16), Vector3(0.0, 1.3, JAIL_GATE_W - 0.12), GreyboxKit.material(Palette.CASINO_BLACK, 0.6, 0.4))  # lock
	# A bench against the back wall, a stone floor, a caged lamp, the sign over the opening.
	GreyboxKit.box(self, Vector3(0.5, 0.45, 2.4), Vector3(x1 - 0.3, 0.225, zc), Color("#4A3426"), "JailBench")
	_plane(Vector2(x1 - x0, z1 - z0), Vector3((x0 + x1) * 0.5, AREA_RUG_Y, zc), Color("#5B5550"), "JailFloor")
	var bulb: MeshInstance3D = GreyboxKit.sphere(self, 0.1, Vector3((x0 + x1) * 0.5 + 0.4, JAIL_H - 0.2, zc), Palette.CREAM, "JailBulb")
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Palette.CREAM
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.8, 0.5)
	bulb_mat.emission_energy_multiplier = 2.0
	bulb.material_override = bulb_mat
	var lamp: OmniLight3D = GreyboxKit.lamp(self, bulb.position + Vector3(0, -0.15, 0), 0.9, 4.0)
	lamp.name = "JailLamp"
	var sign_pos := Vector3(x0 - 0.1, JAIL_H + 0.6, JAIL_GATE_Z)
	GreyboxKit.box(self, Vector3(0.08, 0.7, 1.9), sign_pos, Palette.CASINO_BLACK.lightened(0.06), "JailSign", false)
	GreyboxKit.box(self, Vector3(0.1, 0.08, 2.0), sign_pos + Vector3(0, 0.37, 0), Palette.WARM_GOLD, "JailSignTrim", false)
	GreyboxKit.box(self, Vector3(0.1, 0.08, 2.0), sign_pos + Vector3(0, -0.37, 0), Palette.WARM_GOLD, "JailSignTrim", false)
	_sign_label(sign_pos + Vector3(-0.06, 0.0, 0), -PI * 0.5, "JAIL", 110).modulate = Palette.LOSS_RED.lightened(0.15)
	# Where a jailed player looks from: on the wall over the cell, out over the floor.
	jail_camera = Node3D.new()
	jail_camera.name = "JailCamera"
	jail_camera.set_meta(&"yaw_limit", deg_to_rad(80.0))
	add_child(jail_camera)
	jail_camera.position = JAIL_CAM_POS
	jail_camera.basis = Basis.looking_at(JAIL_CAM_LOOK - JAIL_CAM_POS, Vector3.UP)


func _jail_wall(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)


func _bar(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


## The jail gate swings open and shut again (someone is put in or let out). Looks only.
func swing_jail_gate() -> void:
	if jail_gate == null or not is_inside_tree():
		return
	var tw: Tween = jail_gate.create_tween()
	tw.tween_property(jail_gate, ^"rotation:y", -PI * 0.55, 0.35)  # out into the casino (−x).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(jail_gate, ^"rotation:y", 0.0, 0.3).set_ease(Tween.EASE_IN)


func _build_stations() -> void:
	for sid: StringName in STATIONS:
		var entry: Array = STATIONS[sid]
		var st: StationBase = _make_station(entry[0])
		st.name = String(sid)
		st.station_id = sid
		st.is_vip = String(sid).begins_with("vip_")
		st.position = entry[1]
		st.rotation.y = deg_to_rad(float(entry[2]))
		add_child(st)
		stations[sid] = st


func _make_station(kind: StringName) -> StationBase:
	match kind:
		&"slots":
			return SlotsStation.new()
		&"plinko":
			return PlinkoStation.new()
		&"roulette":
			return RouletteStation.new()
		&"blackjack":
			return BlackjackStation.new()
	Log.error(&"map", "unknown station kind %s" % kind)
	return StationBase.new()


func _build_props() -> void:
	props_parent = Node3D.new()
	props_parent.name = "Props"
	add_child(props_parent)
	for i: int in 5:
		_stool(Vector3(BAR_X - BAR_W * 0.5 + 0.3 + i * 1.5, 0.0, 3.6))


func _stool(pos: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Stool"
	body.mass = 6.0
	body.collision_layer = 8  # props
	body.collision_mask = 1 | 2 | 4 | 8
	body.add_to_group(&"props")
	body.set_meta(&"prop", &"stool")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.22
	mesh.height = 0.6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.3))
	mi.visible = false
	body.add_child(mi)
	var model: Node3D = PropModels.shade(PropModels.make(&"seat", 0.6), 0.7)
	model.position.y = -0.3
	body.add_child(model)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.22
	sh.height = 0.6
	cs.shape = sh
	body.add_child(cs)
	body.position = pos + Vector3(0, 0.3, 0)
	props_parent.add_child(body)
	return body


func _build_lights() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Palette.CASINO_BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.85, 0.65)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_bloom = 0.1
	env.environment = e
	add_child(env)
	# Chandeliers (start room, centre, VIP lounge) and lamps over each area: warm, with dark
	# corners between.
	for p: Vector3 in [Vector3(0, 6.0, 11), Vector3(0, 6.5, -3), Vector3(-13, 6.0, 4), Vector3(-13, 6.0, -11), Vector3(14, 6.0, -12), Vector3(16, 6.0, 4), Vector3(0, 5.8, -21), Vector3(-13, 6.0, 12), Vector3(13, 6.0, 12)]:
		GreyboxKit.lamp(self, p, 3.0, 16.0)  # the chandelier itself is LoungeDecor (client only)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.25
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = false
	add_child(sun)


func _build_navmesh() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25  # one cell_height: stools (0.5 m) are obstacles, not steps
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nm.geometry_source_group_name = &"navsource"
	nm.geometry_collision_mask = 1
	nm.filter_baking_aabb = AABB(Vector3(-SIZE_X * 0.5, -1, VIP_Z_FAR), Vector3(SIZE_X, 7.0, SIZE_Z * 0.5 - VIP_Z_FAR))
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	# Static colliders register with the physics server a frame later; bake once they exist.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return  # freed while waiting (short-lived test scenes)
	nav_region.bake_finished.connect(_on_bake_finished)
	nav_region.bake_navigation_mesh(false)


## The bake fills the resource in place, which never reaches the NavigationServer (queries stay
## empty). Copying the polygons into a fresh mesh once the bake is done does.
func _on_bake_finished() -> void:
	# Hand the data over from the main loop, not from inside the physics step the bake ran in.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var baked: NavigationMesh = nav_region.navigation_mesh
	var fresh := NavigationMesh.new()
	fresh.cell_size = baked.cell_size
	fresh.cell_height = baked.cell_height
	fresh.vertices = baked.get_vertices()
	for i: int in baked.get_polygon_count():
		fresh.add_polygon(baked.get_polygon(i))
	nav_region.navigation_mesh = fresh
	await get_tree().physics_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	navmesh_ready = true
	Log.debug(&"map", "navmesh ready: %d polygons" % fresh.get_polygon_count())


## Line-of-sight query for the server (walls, pillars, tables block; players don't).
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.2, 0), to + Vector3(0, 1.2, 0), 1)
	return space.intersect_ray(q).is_empty()


func _plane(size: Vector2, pos: Vector3, color: Color, name: String) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = GreyboxKit.material(color)
	mi.position = pos
	add_child(mi)
	return mi


## Dev summary for tools/scene_probe.gd.
func probe() -> String:
	return "stations=%d navmesh_polys=%d los_pillar=%s los_open=%s" % [stations.size(), nav_region.navigation_mesh.get_polygon_count(), has_line_of_sight(Vector3(-13, 0, -1), Vector3(-9, 0, -1)), has_line_of_sight(Vector3(-5, 0, 12), Vector3(5, 0, 12))]
