class_name LuckyLounge
extends Node3D
## Greybox of "The Lucky Lounge" (§2.3, docs/ART_DIRECTION.md). Its rooms, all on one floor:
## - the start room (entrance hall, south): front entrance, the ready pedestals and the lobby
##   settings tablet, shut off from the casino by the lobby doors until the match starts;
## - the casino floor: blackjack lounge, roulette pit, slot rows, Plinko wall, bar, gift shop and
##   the barred jail cell where security locks people up, with the Race Hall (the horse race
##   table) opening off its east wall through a wide archway;
## - the VIP lounge (north), its own room behind the north door, where the bouncer checks you;
## - the waiting room (behind the start room, through the door between the pedestals): a blackjack
##   table and four slots on play money while an online room waits in its lobby.
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
	# The Race Hall (east annex): the long horse race table, stools on its south side.
	&"horse_race_1": [&"horse_race", Vector3(29.0, 0, -19.0), 0],
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
## The Race Hall (Patrick: "horse race table: bigger room"): an annex east of the casino floor,
## x 22..ANNEX_X1, z ANNEX_Z0..ANNEX_Z1 (wall centre lines), reaching north past the casino's
## north wall beside the VIP lounge, open to the floor through an archway in the east wall from
## ARCH_Z0 to ARCH_Z1, ARCH_H high (the jail alcove sits in the same wall further south). The jail alcove, the Gift Shop and the
## Odd Jobs cabinet sit in the same east wall south of the annex and stay where they are.
const ANNEX_X1: float = 36.0
const ANNEX_Z0: float = VIP_Z_FAR
const ANNEX_Z1: float = -10.5
const ARCH_Z0: float = -15.5
const ARCH_Z1: float = -11.0
const ARCH_H: float = 4.6
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
## The lobby settings tablet on its brass stand (0.9.4, Patrick: "settings tablet into the lobby
## room"), west of the middle of the start room by the host's spot: walk up and press E for the
## lobby settings. Where it stands, which way its screen faces (yaw), and how close you must be.
const SETTINGS_TABLET_POS: Vector3 = Vector3(-10.6, 0, 9.9)
const SETTINGS_TABLET_YAW: float = -PI * 0.6
const SETTINGS_TABLET_RANGE: float = 1.8
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
## The waiting room (Patrick: "a blackjack table just for fun ... when you're bored"): a
## small room behind the start room's south wall, through the doorway between the pedestals where
## the closed-off porch used to be. One blackjack table and four slot machines on play money only
## (`FunRoom`, server side). Inner faces x −WAIT_X..WAIT_X, z WAIT_Z0..WAIT_Z1, WAIT_H high. Its
## double door fills the entrance gap (x −WAIT_DOOR_HALF..WAIT_DOOR_HALF): open while an online
## room waits in LOBBY, shut and solid from the moment the match starts.
const WAIT_X: float = 5.5
const WAIT_Z0: float = SIZE_Z * 0.5 + 0.25
const WAIT_Z1: float = 23.25
const WAIT_H: float = 4.2
const WAIT_DOOR_HALF: float = 2.0
const WAIT_DOOR_H: float = 3.2
## The room's inner volume (feet inside it = in the waiting room).
const WAITING_AREA: AABB = AABB(Vector3(-WAIT_X, -1.0, WAIT_Z0), Vector3(WAIT_X * 2.0, 5.0, WAIT_Z1 - WAIT_Z0))
## The play-money stations: id → [kind, position, yaw degrees], like STATIONS. The `fun_` prefix
## keeps them out of everything that reads the real ledger (`FunRoom.is_fun`).
const FUN_STATIONS: Dictionary = {
	&"fun_blackjack_1": [&"blackjack", Vector3(0, 0, 20.9), 180],
	&"fun_slot_1": [&"slots", Vector3(-5.1, 0, 18.3), 90], &"fun_slot_2": [&"slots", Vector3(-5.1, 0, 20.3), 90],
	&"fun_slot_3": [&"slots", Vector3(5.1, 0, 18.3), -90], &"fun_slot_4": [&"slots", Vector3(5.1, 0, 20.3), -90],
}
const WAITING_SIGN: String = "WAITING ROOM  ·  PLAY MONEY"
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

## Where the floor plan may stand a table (world x, z rects; docs/FLOOR_PLAN.md): the casino floor,
## the VIP lounge and the west end of the entrance hall (inner wall faces).
const FLOOR_AREAS: Array[Rect2] = [
	Rect2(-21.75, -15.75, 43.5, 23.9), Rect2(-8.75, -25.75, 17.5, 9.5), Rect2(-21.75, 8.65, 10.0, 6.0),
]
## What a drawn table keeps clear of: pillars, the bar and its stools, the megaphone stand, the
## Gift Shop, the Odd Jobs cabinet, the jail's bars and drop-off, the Race Hall archway, the lobby
## and VIP doorways, plants, the VIP lounge's statues, the settings tablet, and a square round every
## guard and waiter route point so the patrols stay walkable.
const FLOOR_KEEP_OUT: Array[Rect2] = [
	Rect2(-10.2, -1.6, 1.2, 1.2), Rect2(9.0, -1.6, 1.2, 1.2),
	Rect2(14.0, 3.1, 7.75, 5.0), Rect2(15.2, 1.7, 1.6, 1.6),
	Rect2(18.9, 0.1, 2.85, 3.6), Rect2(19.6, -1.7, 2.15, 1.5), Rect2(20.6, -3.0, 1.15, 1.0),
	Rect2(20.2, -9.3, 1.55, 3.6), Rect2(19.6, -15.75, 2.15, 5.0),
	Rect2(-3.0, 6.5, 6.0, 1.65), Rect2(-2.7, -16.0, 5.4, 1.6), Rect2(-20.6, -1.6, 1.2, 1.2),
	Rect2(-8.75, -17.8, 1.7, 1.0), Rect2(7.05, -17.8, 1.7, 1.0), Rect2(-8.75, -21.5, 1.0, 1.0), Rect2(7.75, -21.5, 1.0, 1.0),
	Rect2(-2.4, -17.6, 4.8, 1.6), Rect2(-11.4, 9.1, 1.6, 1.6), Rect2(-21.75, 11.3, 1.4, 1.4),
	# Patrol route points (guards, then the waiter).
	Rect2(-12.45, -0.45, 0.9, 0.9), Rect2(-12.45, -11.45, 0.9, 0.9), Rect2(-0.45, -11.45, 0.9, 0.9), Rect2(-0.45, -0.45, 0.9, 0.9),
	Rect2(11.55, 0.05, 0.9, 0.9), Rect2(17.55, -8.45, 0.9, 0.9), Rect2(7.55, -8.45, 0.9, 0.9), Rect2(1.55, 6.55, 0.9, 0.9),
	Rect2(13.55, 1.15, 0.9, 0.9), Rect2(2.05, 1.75, 0.9, 0.9), Rect2(-5.45, 0.15, 0.9, 0.9), Rect2(-12.95, -5.05, 0.9, 0.9),
	Rect2(-1.45, -10.95, 0.9, 0.9), Rect2(8.55, -9.45, 0.9, 0.9), Rect2(12.05, -2.45, 0.9, 0.9),
]

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
## The Odd Jobs cabinet's live parts (button, shared bar, lamps) and its red button.
var odd_jobs: OddJobsCabinet
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
## The waiting room's door: the solid barrier while shut, its two leaves, and whether it is open
## (shut by default: Practice, the menu and a running match never open it).
var waiting_door: StaticBody3D
var waiting_open: bool = false
var _waiting_leaves: Array[Node3D] = []
var _waiting_tween: Tween = null
## The floor plan standing now (docs/FLOOR_PLAN.md), wire form {station id: [game, anchor id]}:
## the full floor (every spot with its usual game, from STATIONS) until `apply_floor_plan`.
var floor_plan: Dictionary = {}
## Closed spots' ropes and plants, and the list on the TONIGHT'S FLOOR board in the entrance hall.
var closed_spots: Node3D
var floor_board: Label3D
## True while a navmesh rebake after a floor change waits for its colliders.
var _rebake_queued: bool = false


func _ready() -> void:
	_build_floor_and_walls()
	_build_lobby()
	_build_floor_areas()
	_build_vip_room()
	_build_race_hall()
	_build_jail()
	_build_waiting_room()
	_build_stations()
	closed_spots = Node3D.new()
	closed_spots.name = "ClosedSpots"
	add_child(closed_spots)
	floor_board = FloorProps.board(self)
	floor_plan = full_floor_plan()
	floor_board.text = FloorProps.board_text(floor_plan, floor_anchors(), fixed_games())
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
	describe_waiting_room(def)


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
	# East wall: the archway into the Race Hall between ARCH_Z0 and ARCH_Z1 (wall above it), then
	# the jail cell's opening cut into it further south (the cell is `_build_jail`).
	var jz0: float = JAIL_AREA.position.z
	var jz1: float = JAIL_AREA.end.z
	GreyboxKit.box(self, Vector3(0.5, WALL_H, ARCH_Z0 + hz), Vector3(hx, WALL_H * 0.5, (-hz + ARCH_Z0) * 0.5), wall, "WallE")
	GreyboxKit.box(self, Vector3(0.5, WALL_H - ARCH_H, ARCH_Z1 - ARCH_Z0), Vector3(hx, (WALL_H + ARCH_H) * 0.5, (ARCH_Z0 + ARCH_Z1) * 0.5), wall, "WallETop")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, jz0 - ARCH_Z1), Vector3(hx, WALL_H * 0.5, (ARCH_Z1 + jz0) * 0.5), wall, "WallE")
	GreyboxKit.box(self, Vector3(0.5, WALL_H - JAIL_H, jz1 - jz0), Vector3(hx, (WALL_H + JAIL_H) * 0.5, (jz0 + jz1) * 0.5), wall, "WallE")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, hz - jz1), Vector3(hx, WALL_H * 0.5, (jz1 + hz) * 0.5), wall, "WallE")
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
	# Behind the entrance gap: the waiting room (`_build_waiting_room`).
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
	_build_settings_tablet()
	_build_lobby_doors()


## The lobby settings tablet: a brass pedestal stand with a tilted black tablet on top, its screen
## lit with the lobby's colours and a "LOBBY SETTINGS / press E" title. The pole is solid.
func _build_settings_tablet() -> void:
	var root := Node3D.new()
	root.name = "SettingsTablet"
	root.position = SETTINGS_TABLET_POS
	root.rotation.y = SETTINGS_TABLET_YAW
	add_child(root)
	GreyboxKit.cylinder(root, 0.26, 0.05, Vector3(0, 0.025, 0), Palette.WARM_GOLD, "TabletFoot", false, 0.85)
	GreyboxKit.cylinder(root, 0.045, 1.0, Vector3(0, 0.5, 0), Palette.WARM_GOLD, "TabletPole", true, 0.85)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.2, -0.1)
	head.rotation.x = deg_to_rad(35.0)  # screen tilted up towards whoever stands in front (−z)
	root.add_child(head)
	_mesh_box(head, Vector3(0.12, 0.12, 0.08), Vector3(0, -0.12, 0.06), GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)).name = "Bracket"
	_mesh_box(head, Vector3(0.66, 0.46, 0.04), Vector3.ZERO, GreyboxKit.material(Palette.CASINO_BLACK, 0.3, 0.4)).name = "Bezel"
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = Palette.FELT_GREEN.darkened(0.45)
	screen_mat.emission_enabled = true
	screen_mat.emission = Palette.FELT_GREEN.darkened(0.2)
	screen_mat.emission_energy_multiplier = 0.6
	_mesh_box(head, Vector3(0.58, 0.38, 0.01), Vector3(0, 0, -0.021), screen_mat).name = "Screen"
	_mesh_box(head, Vector3(0.68, 0.03, 0.05), Vector3(0, -0.245, 0), GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)).name = "Lip"
	for spec: Array in [["LOBBY SETTINGS", 30, 0.08, Palette.VIP_GOLD], ["press E", 22, -0.07, Palette.CREAM]]:
		var l := Label3D.new()
		l.text = spec[0]
		l.font_size = spec[1]
		l.pixel_size = 0.0035
		l.modulate = spec[3]
		l.outline_modulate = Palette.CASINO_BLACK
		l.outline_size = 6
		l.position = Vector3(0, spec[2], -0.03)
		l.rotation.y = PI  # read from the screen side (−z)
		head.add_child(l)


## True when `pos` (feet) is close enough to the settings tablet to use it.
static func near_settings_tablet(pos: Vector3) -> bool:
	return Vector2(pos.x - SETTINGS_TABLET_POS.x, pos.z - SETTINGS_TABLET_POS.z).length() < SETTINGS_TABLET_RANGE


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


## The Odd Jobs cabinet: a low wooden arcade cabinet with one big red button on its deck, the shared
## bar lit on the riser behind it and an "ODD JOBS" marquee, its front to the room (−x). Solid like
## the shop counter. The live parts (button, bar, text, lamps) are an OddJobsCabinet.
func _build_odd_jobs() -> void:
	var c: Vector3 = ODD_JOBS_CABINET
	var wood := Color("#3A2A1E")
	GreyboxKit.box(self, Vector3(0.7, 1.0, 0.9), c + Vector3(0, 0.5, 0), wood, "OddJobsCabinet")
	GreyboxKit.box(self, Vector3(0.04, 0.6, 0.7), c + Vector3(-0.37, 0.5, 0), Palette.VIP_BURGUNDY, "OddJobsPanel", false)
	GreyboxKit.box(self, Vector3(0.05, 0.05, 0.92), c + Vector3(-0.36, 0.98, 0), Palette.WARM_GOLD, "OddJobsTrim", false)
	GreyboxKit.box(self, Vector3(0.05, 0.05, 0.92), c + Vector3(-0.36, 0.06, 0), Palette.WARM_GOLD, "OddJobsTrim", false)
	GreyboxKit.box(self, Vector3(0.78, 0.08, 0.98), c + Vector3(-0.02, 1.04, 0), Palette.CASINO_BLACK, "OddJobsDeck", false)
	# Marquee on the back, with its sign facing the room.
	GreyboxKit.box(self, Vector3(0.16, 1.2, 0.9), c + Vector3(0.24, 1.68, 0), wood, "OddJobsBack")
	GreyboxKit.box(self, Vector3(0.04, 0.5, 0.84), c + Vector3(0.14, 1.95, 0), Palette.VIP_BURGUNDY, "OddJobsMarquee", false)
	for y: float in [1.69, 2.21]:
		GreyboxKit.box(self, Vector3(0.05, 0.04, 0.9), c + Vector3(0.13, y, 0), Palette.WARM_GOLD, "OddJobsTrim", false)
	var l: Label3D = _sign_label(c + Vector3(0.11, 2.0, 0), -PI / 2.0, "ODD JOBS", 32)
	l.modulate = Palette.VIP_GOLD
	_sign_label(c + Vector3(0.11, 1.8, 0), -PI / 2.0, "$50 A BAR", 22)
	odd_jobs = OddJobsCabinet.new()
	odd_jobs.position = c
	add_child(odd_jobs)
	odd_jobs_button = odd_jobs.button


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


## The Race Hall: floor, carpet, walls and ceiling of the east annex, gold casing round the
## archway and a sign over it facing the casino floor. The horse race table is a station.
func _build_race_hall() -> void:
	var wall: Color = Color("#4A2F2A")
	var hx: float = SIZE_X * 0.5
	var x0: float = hx + 0.25  # inner face of the casino's east wall
	var x1: float = ANNEX_X1 + 0.25
	var z0: float = ANNEX_Z0 - 0.25
	var z1: float = ANNEX_Z1 + 0.25
	GreyboxKit.box(self, Vector3(x1 - hx, 0.5, z1 - z0), Vector3((hx + x1) * 0.5, -0.25, (z0 + z1) * 0.5), Color("#8C7F78"), "FloorAnnex")
	var cx0: float = hx - 0.25
	var cx1: float = ANNEX_X1 - 1.0
	var cz0: float = ANNEX_Z0 + 1.0
	var cz1: float = ANNEX_Z1 - 1.0
	_plane(Vector2(cx1 - cx0, cz1 - cz0), Vector3((cx0 + cx1) * 0.5, 0.01, (cz0 + cz1) * 0.5), Palette.CASINO_RED.darkened(0.45), "AnnexCarpet")
	GreyboxKit.box(self, Vector3(x1 - x0, WALL_H, 0.5), Vector3((x0 + x1) * 0.5, WALL_H * 0.5, ANNEX_Z0), wall, "WallAnnex")
	GreyboxKit.box(self, Vector3(x1 - x0, WALL_H, 0.5), Vector3((x0 + x1) * 0.5, WALL_H * 0.5, ANNEX_Z1), wall, "WallAnnex")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, z1 - z0), Vector3(ANNEX_X1, WALL_H * 0.5, (z0 + z1) * 0.5), wall, "WallAnnex")
	# West wall north of the casino's north wall (the casino's east wall covers the rest).
	var wz1: float = -SIZE_Z * 0.5 - 0.25
	GreyboxKit.box(self, Vector3(0.5, WALL_H, wz1 - z0), Vector3(hx, WALL_H * 0.5, (z0 + wz1) * 0.5), wall, "WallAnnex")
	GreyboxKit.box(self, Vector3(x1 - hx, 0.3, z1 - z0), Vector3((hx + x1) * 0.5, WALL_H + 0.15, (z0 + z1) * 0.5), Palette.CASINO_BLACK, "CeilingAnnex")
	# Gold casing round the archway on both faces.
	var mid_z: float = (ARCH_Z0 + ARCH_Z1) * 0.5
	for face: float in [-1.0, 1.0]:
		var x: float = hx + face * 0.28
		for z: float in [ARCH_Z0, ARCH_Z1]:
			GreyboxKit.box(self, Vector3(0.06, ARCH_H + 0.1, 0.18), Vector3(x, (ARCH_H + 0.1) * 0.5, z + (0.09 if z == ARCH_Z0 else -0.09)), Palette.WARM_GOLD, "ArchCasing", false)
		GreyboxKit.box(self, Vector3(0.08, 0.2, ARCH_Z1 - ARCH_Z0 + 0.36), Vector3(x, ARCH_H + 0.1, mid_z), Palette.WARM_GOLD, "ArchCasing", false)
	# The sign over the arch, facing the casino floor (−x).
	var sign_pos := Vector3(hx - 0.3, ARCH_H + 1.15, mid_z)
	GreyboxKit.box(self, Vector3(0.08, 1.3, ARCH_Z1 - ARCH_Z0 + 0.3), sign_pos, Palette.VIP_BURGUNDY, "RaceSign", false)
	for dy: float in [-0.67, 0.67]:
		GreyboxKit.box(self, Vector3(0.1, 0.08, ARCH_Z1 - ARCH_Z0 + 0.5), sign_pos + Vector3(-0.01, dy, 0), Palette.VIP_GOLD, "RaceSignTrim", false)
	_sign_label(sign_pos + Vector3(-0.06, 0.15, 0), -PI * 0.5, "THE BEAN DERBY", 80).modulate = Palette.VIP_GOLD
	_sign_label(sign_pos + Vector3(-0.06, -0.33, 0), -PI * 0.5, "HORSE RACING  ·  PAYS 1:4", 34)


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


# --- The waiting room (play money) -----------------------------------------------------------


## Tells the server about the waiting room: its play-money stations (id → game) and its volume.
static func describe_waiting_room(def: MapDefinition) -> void:
	var games: Dictionary = {}
	for sid: StringName in FUN_STATIONS:
		games[sid] = (FUN_STATIONS[sid] as Array)[0]
	def.fun_stations = games
	def.waiting_area = WAITING_AREA


## True when `pos` (feet) is inside the waiting room.
static func in_waiting_room(pos: Vector3) -> bool:
	return WAITING_AREA.has_point(pos)


## The waiting room behind the entrance gap: parquet floor, wine walls, a low coffered ceiling with
## its own lamp, the blackjack table against the back wall under the "WAITING ROOM · PLAY MONEY"
## board, two slot machines along each side wall, and the double door in the gap.
func _build_waiting_room() -> void:
	var wall: Color = Color("#4A2F2A")
	var hz: float = SIZE_Z * 0.5
	var depth: float = WAIT_Z1 + 0.5 - hz
	var mid_z: float = (hz + WAIT_Z1 + 0.5) * 0.5
	GreyboxKit.box(self, Vector3(WAIT_X * 2.0 + 1.0, 0.5, depth), Vector3(0, -0.25, mid_z), Color("#8C7F78"), "WaitSlab")
	_plane(Vector2(WAIT_X * 2.0, WAIT_Z1 - hz), Vector3(0, 0.012, (hz + WAIT_Z1) * 0.5), Color("#5A3A26"), "WaitFloor")
	for sx: float in [-1.0, 1.0]:
		GreyboxKit.box(self, Vector3(0.5, WALL_H, depth - 0.25), Vector3(sx * (WAIT_X + 0.25), WALL_H * 0.5, mid_z + 0.125), wall, "WaitWall")
	GreyboxKit.box(self, Vector3(WAIT_X * 2.0 + 1.0, WALL_H, 0.5), Vector3(0, WALL_H * 0.5, WAIT_Z1 + 0.25), wall, "WaitWall")
	GreyboxKit.box(self, Vector3(WAIT_X * 2.0, 0.3, WAIT_Z1 - WAIT_Z0), Vector3(0, WAIT_H + 0.15, (WAIT_Z0 + WAIT_Z1) * 0.5), Palette.CASINO_BLACK, "CeilingWaiting")
	GreyboxKit.lamp(self, Vector3(0, WAIT_H - 0.6, 19.6), 2.6, 9.0)
	# The board over the dealer, read from the doorway.
	var board_z: float = WAIT_Z1 - 0.05
	GreyboxKit.box(self, Vector3(5.0, 1.0, 0.08), Vector3(0, 3.05, board_z), Palette.CASINO_BLACK.lightened(0.06), "WaitSignBoard", false)
	for y: float in [3.58, 2.52]:
		GreyboxKit.box(self, Vector3(5.2, 0.07, 0.1), Vector3(0, y, board_z - 0.01), Palette.WARM_GOLD, "WaitSignTrim", false)
	var title: Label3D = _sign_label(Vector3(0, 3.17, board_z - 0.07), PI, WAITING_SIGN, 54)
	title.name = "WaitingSign"
	title.modulate = Palette.VIP_GOLD
	_sign_label(Vector3(0, 2.8, board_z - 0.07), PI, "just for fun: wins and losses never touch your real money", 26).name = "WaitingSignNote"
	for sid: StringName in FUN_STATIONS:
		var entry: Array = FUN_STATIONS[sid]
		var st: StationBase = _make_station(entry[0])
		st.name = String(sid)
		st.station_id = sid
		st.position = entry[1]
		st.rotation.y = deg_to_rad(float(entry[2]))
		add_child(st)
		stations[sid] = st
		var strip: Label3D = st.find_child("JackpotLabel", true, false) as Label3D
		if strip != null:  # no progressive jackpot on play money
			strip.text = "PLAY MONEY"
			strip.font_size = 50
	_build_waiting_door()


## The double door in the entrance gap: a solid barrier filling the gap while shut (built by hand,
## outside the navmesh like the lobby doors), two dark-wood leaves hinged at the jambs on the
## room's inner face, and a gold casing on the start-room side.
func _build_waiting_door() -> void:
	var hz: float = SIZE_Z * 0.5
	waiting_door = StaticBody3D.new()
	waiting_door.name = "WaitingDoor"
	waiting_door.collision_layer = 1
	waiting_door.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sh := BoxShape3D.new()
	sh.size = Vector3(WAIT_DOOR_HALF * 2.0, WAIT_DOOR_H, LOBBY_BARRIER_T)
	cs.shape = sh
	cs.position = Vector3(0, WAIT_DOOR_H * 0.5, hz)
	waiting_door.add_child(cs)
	add_child(waiting_door)
	var wood: StandardMaterial3D = GreyboxKit.material(Color("#3A2318"), 0.0, 0.6)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "WaitLeaf%s" % ("L" if side < 0.0 else "R")
		hinge.position = Vector3(side * WAIT_DOOR_HALF, 0.0, hz + 0.17)
		add_child(hinge)
		_waiting_leaves.append(hinge)
		var w: float = WAIT_DOOR_HALF - 0.02
		_mesh_box(hinge, Vector3(w, WAIT_DOOR_H - 0.04, 0.1), Vector3(-side * w * 0.5, WAIT_DOOR_H * 0.5, 0), wood)
		for y: float in [0.95, 2.35]:
			_mesh_box(hinge, Vector3(w - 0.44, 1.05, 0.02), Vector3(-side * w * 0.5, y, -0.055), gold)
			_mesh_box(hinge, Vector3(w - 0.58, 0.91, 0.025), Vector3(-side * w * 0.5, y, -0.06), wood)
		_mesh_box(hinge, Vector3(0.07, 0.45, 0.05), Vector3(-side * (w - 0.16), 1.6, -0.08), gold)  # handle
		var plate := Label3D.new()
		plate.text = "ROOM" if side < 0.0 else "WAITING"  # read left to right from the start room (−x is on the right)
		plate.font_size = 40
		plate.pixel_size = 0.005
		plate.modulate = Palette.VIP_GOLD
		plate.outline_modulate = Palette.CASINO_BLACK
		plate.outline_size = 8
		plate.position = Vector3(-side * w * 0.5, 1.65, -0.075)
		plate.rotation.y = PI  # read from the start room (−z)
		hinge.add_child(plate)
	var z: float = hz - 0.28
	for x: float in [-1.0, 1.0]:
		GreyboxKit.box(self, Vector3(0.16, WAIT_DOOR_H + 0.08, 0.06), Vector3(x * (WAIT_DOOR_HALF + 0.08), (WAIT_DOOR_H + 0.08) * 0.5, z), Palette.WARM_GOLD, "WaitDoorCasing", false)
	GreyboxKit.box(self, Vector3(WAIT_DOOR_HALF * 2.0 + 0.32, 0.12, 0.07), Vector3(0, WAIT_DOOR_H + 0.04, z), Palette.WARM_GOLD, "WaitDoorCasing", false)


## Opens the waiting room (the room's lobby) or shuts and locks it (the match started): shut, a
## solid barrier fills the doorway; opening swings both leaves through the room until they lie
## flat against its front wall (clear of the pedestals outside and the slots inside) and drops it.
func set_waiting_room_open(open: bool) -> void:
	if waiting_door == null or open == waiting_open:
		return
	waiting_open = open
	(waiting_door.get_node(^"Shape") as CollisionShape3D).set_deferred(&"disabled", open)
	if _waiting_tween != null and _waiting_tween.is_valid():
		_waiting_tween.kill()
	_waiting_tween = create_tween().set_parallel() if is_inside_tree() else null
	for i: int in _waiting_leaves.size():
		var angle: float = (-PI if i == 0 else PI) if open else 0.0  # all the way round, flat to the wall
		if _waiting_tween != null:
			_waiting_tween.tween_property(_waiting_leaves[i], ^"rotation:y", angle, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			_waiting_leaves[i].rotation.y = angle


func _build_stations() -> void:
	var anchor_of: Dictionary = {}
	for a: Dictionary in floor_anchors():
		anchor_of[a["station"]] = a["id"]
	for sid: StringName in STATIONS:
		var entry: Array = STATIONS[sid]
		var st: StationBase = _place_station(sid, entry[0], entry[1], deg_to_rad(float(entry[2])))
		if anchor_of.has(sid):
			st.set_meta(&"anchor", anchor_of[sid])


func _place_station(sid: StringName, kind: StringName, pos: Vector3, yaw: float) -> StationBase:
	var st: StationBase = _make_station(kind)
	st.name = String(sid)
	st.station_id = sid
	st.is_vip = String(sid).begins_with("vip_")
	st.position = pos
	st.rotation.y = yaw
	add_child(st)
	stations[sid] = st
	return st


# --- Per-round floor plan (docs/FLOOR_PLAN.md) -------------------------------------------------

## The floor's spots, from STATIONS: every station whose game isn't `fixed` (the horse race keeps
## the Race Hall) is a spot of its game's size, numbered per area and size in STATIONS order
## (t = table, c = cabinet, b = big; v in front for the VIP lounge): [{id, footprint, vip,
## default (its game on the full floor), station (its id there), pos, yaw (radians)}]. A new
## STATIONS line is a new spot.
static func floor_anchors() -> Array:
	var out: Array = []
	var counts: Dictionary = {}
	for sid: StringName in STATIONS:
		var entry: Array = STATIONS[sid]
		var game: StringName = entry[0]
		var fp: StringName = footprint_of(game)
		if fp == &"fixed":
			continue
		var vip: bool = String(sid).begins_with("vip_")
		var key: String = ("v" if vip else "") + String(fp).left(1)
		counts[key] = int(counts.get(key, 0)) + 1
		out.append({"id": StringName("%s%d" % [key, counts[key]]), "footprint": fp, "vip": vip, "default": game, "station": sid, "pos": entry[1], "yaw": deg_to_rad(float(entry[2]))})
	return out


## A game's size class on the floor (`GameDefinition.floor_footprint`; table when unregistered).
static func footprint_of(game: StringName) -> StringName:
	var def: GameDefinition = Registry.games.get(game, null)
	return def.floor_footprint if def != null else &"table"


## Games that keep their own place whatever the plan (the horse race in the Race Hall).
static func fixed_games() -> Array:
	var out: Array = []
	for sid: StringName in STATIONS:
		var game: StringName = (STATIONS[sid] as Array)[0]
		if footprint_of(game) == &"fixed" and not game in out:
			out.append(game)
	return out


## The full floor in wire form: every spot with its usual game under its usual id.
static func full_floor_plan() -> Dictionary:
	var out: Dictionary = {}
	for a: Dictionary in floor_anchors():
		out[a["station"]] = [a["default"], a["id"]]
	return out


## Tells the server about the floor's spots and the station id stems (slots → slot).
static func describe_floor(def: MapDefinition) -> void:
	def.floor_anchors = floor_anchors()
	var prefixes: Dictionary = {}
	for sid: StringName in STATIONS:
		var game: StringName = (STATIONS[sid] as Array)[0]
		var stem: String = String(sid).trim_prefix("vip_")
		var cut: int = stem.rfind("_")
		if cut > 0 and stem.substr(cut + 1).is_valid_int():
			stem = stem.left(cut)
		if not prefixes.has(game):
			prefixes[game] = stem
	def.floor_prefixes = prefixes
	def.floor_areas = FLOOR_AREAS.duplicate()
	def.floor_keep_out = FLOOR_KEEP_OUT.duplicate()


## Measures how much floor every drawable game takes (table, chairs and dealer, in its own frame)
## by building its station once out of sight: `MapDefinition.floor_rects`. The server's draw then
## only puts a game where it fits (`FloorGeometry`). Needs the map in the tree.
func measure_floor(def: MapDefinition) -> void:
	var rects: Dictionary = {}
	for game: StringName in Registry.games:
		if footprint_of(game) == &"fixed":
			continue
		var st: StationBase = _make_station(game)
		st.position = Vector3(0, -40.0, 0)  # under the floor, for one frame at most
		add_child(st)
		rects[game] = station_rect(st)
		remove_child(st)
		st.free()
	def.floor_rects = rects


## A station's floor in its own frame (x, z): its static colliders, its chairs and its dealer.
static func station_rect(st: StationBase) -> Rect2:
	var inv: Transform3D = st.global_transform.affine_inverse()
	var box := AABB()
	var first: bool = true
	for body: Node in st.find_children("*", "StaticBody3D", true, false):
		for cs: Node in body.find_children("*", "CollisionShape3D", true, false):
			var shape: Shape3D = (cs as CollisionShape3D).shape
			if shape == null:
				continue
			var b: AABB = inv * (cs as CollisionShape3D).global_transform * shape.get_debug_mesh().get_aabb()
			box = b if first else box.merge(b)
			first = false
	var extras: Array[Vector3] = []
	for s: Node3D in st.seats:
		for d: Vector3 in [Vector3(0.3, 0, 0.3), Vector3(-0.3, 0, -0.3)]:
			extras.append(inv * s.global_position + d)
	if DealerLogic.OFFSETS.has(st.game_id):
		var o: Vector3 = DealerLogic.OFFSETS[st.game_id]
		extras.append(o + Vector3(0.35, 0, 0.35))
		extras.append(o - Vector3(0.35, 0, 0.35))
	for p: Vector3 in extras:
		box = AABB(p, Vector3.ZERO) if first else box.expand(p)
		first = false
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## Builds the floor of a plan (wire form; {} = the full floor): stations that stay on their spot
## with the same game are kept, the others are taken down and the new ones built, closed spots get
## their rope or plant, the hall board its list, and the navmesh is baked again (guards and the
## waiter path round the new tables). Returns false when that plan is already standing.
func apply_floor_plan(plan: Dictionary) -> bool:
	var want: Dictionary = plan if not plan.is_empty() else full_floor_plan()
	if want == floor_plan:
		return false
	floor_plan = want.duplicate(true)
	var anchors: Array = floor_anchors()
	var by_id: Dictionary = {}
	for a: Dictionary in anchors:
		by_id[a["id"]] = a
	for sid: StringName in stations.keys():
		var st: StationBase = stations[sid]
		if not st.has_meta(&"anchor"):
			continue  # the horse race and the waiting room's tables never move
		var e: Variant = want.get(sid, null)
		if e != null and StringName((e as Array)[0]) == st.game_id and StringName((e as Array)[1]) == StringName(st.get_meta(&"anchor")):
			continue
		stations.erase(sid)
		st.name = "%s_gone" % sid
		st.remove_from_group(&"stations")
		remove_child(st)
		st.queue_free()
	for sid: Variant in want:
		var entry: Array = want[sid]
		if stations.has(StringName(sid)) or not by_id.has(StringName(entry[1])):
			continue
		var a: Dictionary = by_id[StringName(entry[1])]
		var st: StationBase = _place_station(StringName(sid), StringName(entry[0]), a["pos"], float(a["yaw"]))
		st.set_meta(&"anchor", a["id"])
	var used: Dictionary = {}
	for sid: Variant in want:
		used[StringName((want[sid] as Array)[1])] = true
	for c: Node in closed_spots.get_children():
		closed_spots.remove_child(c)
		c.queue_free()
	for a: Dictionary in anchors:
		if not used.has(a["id"]):
			FloorProps.closed_spot(closed_spots, a)
	floor_board.text = FloorProps.board_text(want, anchors, fixed_games())
	if bake_navmesh and nav_region != null:
		rebake_navmesh()
	return true


## Bakes the navmesh again from the colliders standing now (after the floor changed).
func rebake_navmesh() -> void:
	navmesh_ready = false
	if _rebake_queued or not is_inside_tree():
		return
	_rebake_queued = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	_rebake_queued = false
	if not is_inside_tree():
		return
	nav_region.navigation_mesh = _nav_template()
	nav_region.bake_navigation_mesh(false)


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
		&"horse_race":
			return HorseRaceStation.new()
	# A newer game can bring its own station scene (`GameDefinition.station_scene`).
	var def: GameDefinition = Registry.games.get(kind, null)
	if def != null and def.station_scene != null:
		var node: StationBase = def.station_scene.instantiate() as StationBase
		if node != null:
			return node
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
	# Chandeliers (start room, centre, VIP lounge, Race Hall) and lamps over each area: warm, with dark
	# corners between.
	for p: Vector3 in [Vector3(0, 6.0, 11), Vector3(0, 6.5, -3), Vector3(-13, 6.0, 4), Vector3(-13, 6.0, -11), Vector3(14, 6.0, -12), Vector3(16, 6.0, 4), Vector3(0, 5.8, -21), Vector3(-13, 6.0, 12), Vector3(13, 6.0, 12), Vector3(25.5, 6.0, -18.5), Vector3(32.5, 6.0, -18.5)]:
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
	nav_region.navigation_mesh = _nav_template()
	add_child(nav_region)
	# Static colliders register with the physics server a frame later; bake once they exist.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return  # freed while waiting (short-lived test scenes)
	nav_region.bake_finished.connect(_on_bake_finished)
	if _rebake_queued:
		return  # the floor changed meanwhile: its rebake is on the way
	nav_region.bake_navigation_mesh(false)


## The navmesh's bake settings (a fresh resource for each bake: `_on_bake_finished` swaps in a
## copy without them).
func _nav_template() -> NavigationMesh:
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
	# The casino, start room and VIP lounge, plus the Race Hall to the east.
	nm.filter_baking_aabb = AABB(Vector3(-SIZE_X * 0.5, -1, VIP_Z_FAR), Vector3(ANNEX_X1 + SIZE_X * 0.5, 7.0, SIZE_Z * 0.5 - VIP_Z_FAR))
	return nm


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
