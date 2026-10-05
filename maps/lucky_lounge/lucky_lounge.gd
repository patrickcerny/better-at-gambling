class_name LuckyLounge
extends Node3D
## Greybox of "The Lucky Lounge" (§2.3, docs/ART_DIRECTION.md): entrance lobby with fountain,
## revolving door, reception, staircase to the VIP mezzanine; blackjack lounge, roulette pit,
## slot rows, Plinko wall, bar. Built procedurally from the tables below so it is easy to tune.

const SIZE_X: float = 44.0
const SIZE_Z: float = 32.0
const WALL_H: float = 7.0
const MEZZ_Y: float = 4.0

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
	&"vip_blackjack_1": [&"blackjack", Vector3(-4.5, MEZZ_Y, -4), 0], &"vip_roulette_1": [&"roulette", Vector3(3.5, MEZZ_Y, -4), 0],
	&"vip_slot_1": [&"slots", Vector3(-6.5, MEZZ_Y, -7.5), 0], &"vip_slot_2": [&"slots", Vector3(6.5, MEZZ_Y, -7.5), 0],
}
const SPAWNS: Array[Vector3] = [
	Vector3(-6, 0, 12.5), Vector3(-4, 0, 13.5), Vector3(-2, 0, 12.5), Vector3(2, 0, 12.5),
	Vector3(4, 0, 13.5), Vector3(6, 0, 12.5), Vector3(-3, 0, 14.5), Vector3(3, 0, 14.5),
]
const GUARD_ROUTES: Array = [
	[Vector3(-12, 0, 0), Vector3(-12, 0, -11), Vector3(0, 0, -11), Vector3(0, 0, 0)],
	[Vector3(12, 0, 2), Vector3(18, 0, -8), Vector3(8, 0, -8), Vector3(2, 0, 7)],
]
const VIP_GATE_POS: Vector3 = Vector3(9.0, MEZZ_Y, -0.5)
const ENTRANCE_POS: Vector3 = Vector3(0, 0, 15.0)
const RESPAWN_POS: Vector3 = Vector3(0, 0, 13.0)
const FOUNTAIN_POS: Vector3 = Vector3(0, 0, 10.0)
## Where online players appear in the entrance hall (off the ready pads, clear of the fountain).
const LOBBY_SPAWNS: Array[Vector3] = [
	Vector3(-7, 0, 10.0), Vector3(7, 0, 10.0), Vector3(-5, 0, 10.8), Vector3(5, 0, 10.8),
	Vector3(-9, 0, 11.0), Vector3(9, 0, 11.0), Vector3(-7, 0, 11.6), Vector3(7, 0, 11.6),
]
## Where players stand to shop at the Gift Shop kiosk (east wall, next to the bar).
const SHOP_POS: Vector3 = Vector3(19.6, 0, 1.5)
const MIRROR_POS: Vector3 = Vector3(-21.3, 0, 12.0)
const SETTINGS_BOARD_POS: Vector3 = Vector3(12.5, 0, 14.6)
## Radius around a ready pad's centre that counts as standing on it.
const PAD_RADIUS: float = 0.75
const LOBBY_DOORS_Z: float = 8.2

var stations: Dictionary[StringName, StationBase] = {}
var fountain_area: Area3D
var vip_gate_area: Area3D
var revolving_door: Node3D
var nav_region: NavigationRegion3D
var props_parent: Node3D
var navmesh_ready: bool = false
## Wall between the entrance hall and the casino while the online lobby waits (§2.2).
var lobby_doors: StaticBody3D
var lobby_open: bool = true


func _ready() -> void:
	_build_floor_and_walls()
	_build_lobby()
	_build_floor_areas()
	_build_mezzanine()
	_build_stations()
	_build_props()
	_build_lights()
	_build_navmesh()


## Station id → world position of the station origin.
func station_positions() -> Dictionary:
	var out: Dictionary = {}
	for sid: StringName in stations:
		out[sid] = stations[sid].global_position
	return out


## Spawn points (world).
func spawn_points() -> Array[Vector3]:
	return SPAWNS.duplicate()


## Lobby spawn for a player (online rooms).
func lobby_spawn(player_id: int) -> Vector3:
	return LOBBY_SPAWNS[(player_id - 1) % LOBBY_SPAWNS.size()]


## Centre of the ready pad in a player colour.
func ready_pad(color_index: int) -> Vector3:
	return SPAWNS[clampi(color_index, 0, SPAWNS.size() - 1)]


## Opens (casino reachable) or closes the lobby doors. Opening slides them into the floor.
func set_lobby_open(open: bool) -> void:
	if lobby_doors == null or open == lobby_open:
		return
	lobby_open = open
	var shape: CollisionShape3D = lobby_doors.get_node("Shape")
	shape.set_deferred(&"disabled", open)
	if open and is_inside_tree():
		var tw: Tween = create_tween()
		tw.tween_property(lobby_doors, "position:y", -4.2, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: lobby_doors.visible = false)
	else:
		lobby_doors.position.y = 0.0
		lobby_doors.visible = not open


func _build_floor_and_walls() -> void:
	GreyboxKit.box(self, Vector3(SIZE_X, 0.5, SIZE_Z), Vector3(0, -0.25, 0), Color("#8C7F78"), "Floor")  # marble grey
	var carpet: Color = Palette.CASINO_RED.darkened(0.45)
	_plane(Vector2(SIZE_X - 2, SIZE_Z - 2), Vector3(0, 0.01, 0), carpet, "Carpet")
	var wall: Color = Color("#4A2F2A")
	GreyboxKit.box(self, Vector3(SIZE_X, WALL_H, 0.5), Vector3(0, WALL_H * 0.5, -SIZE_Z * 0.5), wall, "WallN")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, SIZE_Z), Vector3(-SIZE_X * 0.5, WALL_H * 0.5, 0), wall, "WallW")
	GreyboxKit.box(self, Vector3(0.5, WALL_H, SIZE_Z), Vector3(SIZE_X * 0.5, WALL_H * 0.5, 0), wall, "WallE")
	# South wall with a gap for the revolving door.
	GreyboxKit.box(self, Vector3(SIZE_X * 0.5 - 2.0, WALL_H, 0.5), Vector3(-SIZE_X * 0.25 - 1.0, WALL_H * 0.5, SIZE_Z * 0.5), wall, "WallS1")
	GreyboxKit.box(self, Vector3(SIZE_X * 0.5 - 2.0, WALL_H, 0.5), Vector3(SIZE_X * 0.25 + 1.0, WALL_H * 0.5, SIZE_Z * 0.5), wall, "WallS2")
	GreyboxKit.box(self, Vector3(4.5, WALL_H - 3.2, 0.5), Vector3(0, WALL_H - 1.6, SIZE_Z * 0.5), wall, "WallSTop")
	# Porch outside the revolving door, closed off: nobody leaves the building on foot.
	GreyboxKit.box(self, Vector3(8.0, 0.5, 5.0), Vector3(0, -0.25, SIZE_Z * 0.5 + 2.5), Color("#8C7F78"), "Porch")
	GreyboxKit.box(self, Vector3(8.0, WALL_H, 0.5), Vector3(0, WALL_H * 0.5, SIZE_Z * 0.5 + 5.0), wall, "PorchWall")
	for x: float in [-4.0, 4.0]:
		GreyboxKit.box(self, Vector3(0.5, WALL_H, 5.0), Vector3(x, WALL_H * 0.5, SIZE_Z * 0.5 + 2.5), wall, "PorchSide")
	# Ceiling (dark, keeps the lighting warm and cosy).
	GreyboxKit.box(self, Vector3(SIZE_X, 0.3, SIZE_Z), Vector3(0, WALL_H + 0.15, 0), Palette.CASINO_BLACK, "Ceiling")
	# Gold trim along the walls.
	for z: float in [-SIZE_Z * 0.5 + 0.3, SIZE_Z * 0.5 - 0.3]:
		GreyboxKit.box(self, Vector3(SIZE_X, 0.15, 0.1), Vector3(0, 1.0, z), Palette.WARM_GOLD, "Trim", false)
	# Pillars.
	for p: Vector3 in [Vector3(-11, 0, -1), Vector3(11, 0, -1), Vector3(-11, 0, 8), Vector3(11, 0, 8)]:
		var col: Node3D = GreyboxKit.cylinder(self, 0.45, WALL_H, p + Vector3(0, WALL_H * 0.5, 0), Color("#B8A890"), "Pillar")
		GreyboxKit.cylinder(col, 0.55, 0.3, Vector3(0, -WALL_H * 0.5 + 0.15, 0), Palette.WARM_GOLD, "Base", false, 0.7)


func _build_lobby() -> void:
	_plane(Vector2(26, 7.5), Vector3(0, 0.015, 12.25), Palette.CASINO_RED.darkened(0.3), "LobbyCarpet")
	# Fountain: marble basin, water (hazard area), gold bean statue.
	var basin: Node3D = GreyboxKit.cylinder(self, 2.6, 0.7, FOUNTAIN_POS + Vector3(0, 0.35, 0), Color("#D8D0C4"), "FountainBasin")
	GreyboxKit.cylinder(basin, 2.3, 0.05, Vector3(0, 0.36, 0), Color("#4FA3C7"), "Water", false)
	GreyboxKit.cylinder(basin, 0.6, 1.6, Vector3(0, 1.1, 0), Color("#D8D0C4"), "Pedestal")
	GreyboxKit.capsule(basin, 0.5, 1.8, Vector3(0, 2.6, 0), GreyboxKit.gold(), "Statue")
	fountain_area = Area3D.new()
	fountain_area.name = "FountainArea"
	fountain_area.collision_layer = 0
	fountain_area.collision_mask = 2 | 4  # players and ragdolls
	var fcs := CollisionShape3D.new()
	var fshape := CylinderShape3D.new()
	fshape.radius = 2.2
	fshape.height = 1.5
	fcs.shape = fshape
	fountain_area.add_child(fcs)
	fountain_area.position = FOUNTAIN_POS + Vector3(0, 1.0, 0)
	fountain_area.set_meta(&"hazard", &"fountain")
	add_child(fountain_area)
	# Reception desk and velvet ropes.
	GreyboxKit.box(self, Vector3(4.0, 1.1, 1.0), Vector3(-9.5, 0.55, 14.0), Color("#3A2A1E"), "Reception")
	GreyboxKit.box(self, Vector3(4.0, 0.08, 1.1), Vector3(-9.5, 1.14, 14.0), Palette.WARM_GOLD, "ReceptionTop", false)
	for i: int in 5:
		var x: float = -7.0 + i * 3.5
		var post: Node3D = GreyboxKit.cylinder(self, 0.06, 1.0, Vector3(x, 0.5, 8.6), Palette.WARM_GOLD, "RopePost", true, 0.8)
		GreyboxKit.sphere(post, 0.1, Vector3(0, 0.55, 0), Palette.WARM_GOLD, "Knob")
		if i == 0 or i == 3:  # ropes at the sides only: the middle stays open for the stampede
			GreyboxKit.box(self, Vector3(3.3, 0.08, 0.08), Vector3(x + 1.75, 0.85, 8.6), Palette.CASINO_RED, "Rope", false)
	# Casino sign above the entrance (inside).
	GreyboxKit.box(self, Vector3(7.0, 1.2, 0.2), Vector3(0, 5.0, SIZE_Z * 0.5 - 0.5), Palette.CASINO_RED, "Sign", false)
	# Ready pads for the physical lobby (M3 uses them; placed now for layout).
	for i: int in SPAWNS.size():
		var pad: Node3D = GreyboxKit.cylinder(self, 0.6, 0.06, SPAWNS[i] + Vector3(0, 0.03, 0), Palette.player_color(i).darkened(0.2), "ReadyPad%d" % i, false)
		pad.add_to_group(&"ready_pads")
	# Wardrobe mirror: pick a skin in the lobby.
	GreyboxKit.box(self, Vector3(0.2, 2.4, 1.6), Vector3(-SIZE_X * 0.5 + 0.6, 1.2, 12.0), Color("#9AC4D8"), "Mirror")
	GreyboxKit.box(self, Vector3(0.3, 2.7, 1.9), Vector3(-SIZE_X * 0.5 + 0.45, 1.3, 12.0), Palette.WARM_GOLD, "MirrorFrame", false)
	_sign_label(Vector3(-SIZE_X * 0.5 + 0.8, 2.85, 12.0), PI * 0.5, "WARDROBE", 56)
	# Couches against the back wall of the entrance hall, facing the doors.
	for x: float in [-16.5, 18.0]:
		var couch: Node3D = GreyboxKit.box(self, Vector3(2.4, 0.9, 1.0), Vector3(x, 0.45, SIZE_Z * 0.5 - 0.8), Color("#24304A"), "Couch")
		PropModels.dress(couch, &"couch", 0.45, 0.0, 2.5).rotation.y = PI
	_build_settings_board()
	_build_lobby_doors()
	# Revolving door: rotating 4-panel cylinder in the south wall gap.
	revolving_door = Node3D.new()
	revolving_door.name = "RevolvingDoor"
	revolving_door.position = ENTRANCE_POS + Vector3(0, 0, 1.0)
	add_child(revolving_door)
	var spinner := AnimatableBody3D.new()
	spinner.name = "Spinner"
	spinner.sync_to_physics = true
	for i: int in 4:
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.1, 3.0, 2.0)
		panel.mesh = pm
		panel.material_override = GreyboxKit.material(Color("#9AC4D8", ))
		panel.position = Vector3(0, 1.5, 1.0)
		var pivot := Node3D.new()
		pivot.rotation.y = i * PI * 0.5
		pivot.add_child(panel)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = pm.size
		cs.shape = sh
		cs.position = panel.position
		pivot.add_child(cs)
		spinner.add_child(pivot)
	revolving_door.add_child(spinner)
	var drum: Node3D = GreyboxKit.cylinder(revolving_door, 2.2, 0.2, Vector3(0, 3.1, 0), Palette.WARM_GOLD, "DrumTop", false, 0.7)
	drum.visible = true
	var door_area := Area3D.new()
	door_area.name = "DoorArea"
	door_area.collision_layer = 0
	door_area.collision_mask = 2
	var dcs := CollisionShape3D.new()
	var dsh := CylinderShape3D.new()
	dsh.radius = 2.1
	dsh.height = 3.0
	dcs.shape = dsh
	dcs.position.y = 1.5
	door_area.add_child(dcs)
	door_area.set_meta(&"hazard", &"revolving_door")
	revolving_door.add_child(door_area)
	# Stairs (two ramps with a landing) up to the mezzanine on the east side of the lobby.
	GreyboxKit.ramp(self, Vector3(12.0, 0.0, 9.0), Vector3(12.0, MEZZ_Y * 0.5, 4.5), 2.4, Palette.CASINO_RED.darkened(0.2), "Stairs1")
	GreyboxKit.box(self, Vector3(2.6, 0.3, 2.4), Vector3(12.0, MEZZ_Y * 0.5 - 0.15, 3.0), Palette.CASINO_RED.darkened(0.2), "Landing")
	GreyboxKit.ramp(self, Vector3(12.0, MEZZ_Y * 0.5, 1.5), Vector3(12.0, MEZZ_Y, -1.5), 2.4, Palette.CASINO_RED.darkened(0.2), "Stairs2")
	for side: float in [-1.3, 1.3]:
		GreyboxKit.box(self, Vector3(0.1, 1.0, 11.0), Vector3(12.0 + side, MEZZ_Y * 0.5 + 0.5, 3.75), Palette.WARM_GOLD, "StairRail", true)


func _build_settings_board() -> void:
	var p: Vector3 = SETTINGS_BOARD_POS
	for x: float in [-1.0, 1.0]:
		GreyboxKit.cylinder(self, 0.07, 1.6, p + Vector3(x, 0.8, 0), Palette.WARM_GOLD, "BoardPost", true, 0.8)
	GreyboxKit.box(self, Vector3(2.4, 1.5, 0.12), p + Vector3(0, 2.2, 0), Palette.FELT_GREEN.darkened(0.3), "SettingsBoard")
	GreyboxKit.box(self, Vector3(2.6, 0.1, 0.16), p + Vector3(0, 3.0, 0), Palette.WARM_GOLD, "BoardTrim", false)
	_sign_label(p + Vector3(0, 2.55, -0.08), PI, "PARTY SETTINGS", 52)
	_sign_label(p + Vector3(0, 2.05, -0.08), PI, "leader: press E", 34)


func _build_lobby_doors() -> void:
	# Built by hand (not GreyboxKit) so it never enters the navmesh: the casino floor stays
	# walkable for guards once the doors sink away.
	lobby_doors = StaticBody3D.new()
	lobby_doors.name = "LobbyDoors"
	lobby_doors.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sh := BoxShape3D.new()
	sh.size = Vector3(SIZE_X, 4.0, 0.4)
	cs.shape = sh
	cs.position = Vector3(0, 2.0, LOBBY_DOORS_Z)
	lobby_doors.add_child(cs)
	for x: float in [-14.0, 14.0]:
		var curtain := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(16.0, 4.0, 0.2)
		curtain.mesh = cm
		curtain.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.35))
		curtain.position = Vector3(x, 2.0, LOBBY_DOORS_Z)
		lobby_doors.add_child(curtain)
	for x: float in [-3.0, 3.0]:
		var door := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(6.0, 4.0, 0.3)
		door.mesh = dm
		door.material_override = GreyboxKit.material(Color("#3A2A1E"))
		door.position = Vector3(x, 2.0, LOBBY_DOORS_Z)
		lobby_doors.add_child(door)
		var trim := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(5.4, 3.4, 0.05)
		trim.mesh = tm
		trim.material_override = GreyboxKit.material(Palette.WARM_GOLD)
		trim.position = Vector3(x, 2.0, LOBBY_DOORS_Z + 0.17)
		lobby_doors.add_child(trim)
	var label := Label3D.new()
	label.text = "THE CASINO OPENS WHEN EVERYONE IS ON A READY PAD"
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = Palette.CREAM
	label.outline_modulate = Palette.CASINO_BLACK
	label.outline_size = 12
	label.position = Vector3(0, 3.3, LOBBY_DOORS_Z + 0.25)
	lobby_doors.add_child(label)
	lobby_doors.visible = false
	cs.disabled = true
	add_child(lobby_doors)


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
	# Coloured rugs identify game areas (readable from a distance).
	_plane(Vector2(22, 5), Vector3(-13, 0.012, 4), Palette.FELT_GREEN.darkened(0.6), "BlackjackRug")
	_plane(Vector2(18, 8), Vector3(0, 0.012, -3), Palette.CASINO_RED.darkened(0.5), "RouletteRug")
	_plane(Vector2(16, 9), Vector3(-13.5, 0.012, -11), Palette.WARM_GOLD.darkened(0.6), "SlotsRug")
	_plane(Vector2(12, 5), Vector3(14, 0.012, -13), Palette.VIP_BURGUNDY.darkened(0.3), "PlinkoRug")
	# Bar (south-east, decoration; also the quiz entry area later).
	GreyboxKit.box(self, Vector3(8.0, 1.1, 1.2), Vector3(16.0, 0.55, 5.0), Color("#3A2A1E"), "Bar")
	GreyboxKit.box(self, Vector3(8.0, 0.08, 1.3), Vector3(16.0, 1.14, 5.0), Palette.WARM_GOLD, "BarTop", false)
	GreyboxKit.box(self, Vector3(8.0, 2.5, 0.4), Vector3(16.0, 1.25, 7.0), Color("#2A1E18"), "BackBar")
	for i: int in 6:
		GreyboxKit.box(self, Vector3(0.25, 0.4, 0.25), Vector3(12.5 + i * 1.4, 1.6, 6.9), [Palette.CASINO_RED, Palette.WARM_GOLD, Palette.FELT_GREEN][i % 3], "Bottle", false)
	_build_gift_shop()
	# Plants and a few obstacles for lanes.
	for p: Vector3 in [Vector3(-20, 0, 14), Vector3(20, 0, 14), Vector3(-20, 0, -1), Vector3(20, 0, -1), Vector3(-5, 0, 8.6), Vector3(5, 0, 8.6)]:
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


func _build_mezzanine() -> void:
	# Platform above the roulette pit, open on the south side with a low railing (shove-able).
	GreyboxKit.box(self, Vector3(18.0, 0.4, 10.0), Vector3(0, MEZZ_Y - 0.2, -5.0), Color("#3A2A1E"), "MezzFloor")
	_plane(Vector2(17.5, 9.5), Vector3(0, MEZZ_Y + 0.01, -5.0), Palette.VIP_BURGUNDY, "VipCarpet")
	for x: float in [-9.0, 9.0]:
		GreyboxKit.box(self, Vector3(0.1, 0.9, 10.0), Vector3(x, MEZZ_Y + 0.45, -5.0), Palette.WARM_GOLD, "MezzRailSide", true)
	# South railing is low: 0.6 m, with a gap where the stairs arrive (x 10.8..13.2 handled by platform extension).
	GreyboxKit.box(self, Vector3(16.0, 0.6, 0.1), Vector3(-1.0, MEZZ_Y + 0.3, 0.0), Palette.WARM_GOLD, "MezzRailSouth", true)
	GreyboxKit.box(self, Vector3(18.0, 0.6, 0.1), Vector3(0.0, MEZZ_Y + 0.3, -10.0), Palette.WARM_GOLD, "MezzRailNorth", true)
	# Stair arrival platform + velvet rope gate with the bouncer.
	GreyboxKit.box(self, Vector3(4.6, 0.4, 3.0), Vector3(11.0, MEZZ_Y - 0.2, -1.5), Color("#3A2A1E"), "MezzLanding")
	vip_gate_area = Area3D.new()
	vip_gate_area.name = "VipGate"
	vip_gate_area.collision_layer = 0
	vip_gate_area.collision_mask = 2
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(1.0, 2.5, 3.0)
	gcs.shape = gsh
	gcs.position.y = 1.25
	vip_gate_area.add_child(gcs)
	vip_gate_area.position = VIP_GATE_POS
	vip_gate_area.set_meta(&"hazard", &"vip_gate")
	add_child(vip_gate_area)
	for z: float in [-2.9, 0.9]:
		GreyboxKit.cylinder(self, 0.06, 1.0, VIP_GATE_POS + Vector3(0, 0.5, z), Palette.WARM_GOLD, "GatePost", true, 0.8)
	# VIP sign.
	GreyboxKit.box(self, Vector3(2.6, 0.8, 0.1), Vector3(9.0, MEZZ_Y + 2.6, -1.0), Palette.VIP_BURGUNDY, "VipSign", false)
	GreyboxKit.box(self, Vector3(2.4, 0.6, 0.12), Vector3(9.0, MEZZ_Y + 2.6, -1.0), Palette.VIP_GOLD, "VipSignFace", false)
	# Gold statues: the VIP floor is intentionally excessive.
	for x: float in [-7.5, 7.5]:
		var plinth: Node3D = GreyboxKit.box(self, Vector3(0.8, 0.8, 0.8), Vector3(x, MEZZ_Y + 0.4, -1.2), Color("#D8D0C4"), "Plinth")
		GreyboxKit.capsule(plinth, 0.3, 1.2, Vector3(0, 1.1, 0), GreyboxKit.gold(), "Statue")


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
		_stool(Vector3(12.5 + i * 1.5, 0.0, 3.6))
	for p: Vector3 in [Vector3(-3, 0, 1), Vector3(3, 0, 1), Vector3(14, 0, -9), Vector3(-19, 0, 2)]:
		_chip_stack(p)


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


func _chip_stack(pos: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "ChipStack"
	body.mass = 1.0
	body.collision_layer = 8
	body.collision_mask = 1 | 2 | 4 | 8
	body.add_to_group(&"props")
	body.set_meta(&"prop", &"chip_stack")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = GreyboxKit.material(Palette.CASINO_RED)
	mi.visible = false
	body.add_child(mi)
	for i: int in 12:
		var chip: Node3D = PropModels.make(&"poker_chip", 0.0, 0.24)
		chip.position = Vector3(randf_range(-0.01, 0.01), -0.15 + i * 0.025, randf_range(-0.01, 0.01))
		chip.rotation.y = randf() * TAU
		body.add_child(chip)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.12
	sh.height = 0.3
	cs.shape = sh
	body.add_child(cs)
	body.position = pos + Vector3(0, 0.15, 0)
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
	# Chandeliers (lobby and centre) and lamps over each area: warm, with dark corners between.
	for p: Vector3 in [Vector3(0, 6.0, 11), Vector3(0, 6.5, -3), Vector3(-13, 6.0, 4), Vector3(-13, 6.0, -11), Vector3(14, 6.0, -12), Vector3(16, 6.0, 4), Vector3(0, MEZZ_Y + 2.5, -5)]:
		GreyboxKit.lamp(self, p, 3.0, 16.0)
		GreyboxKit.cylinder(self, 0.5, 0.15, p + Vector3(0, 0.3, 0), Palette.WARM_GOLD, "Chandelier", false, 0.8)
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
	nm.filter_baking_aabb = AABB(Vector3(-SIZE_X * 0.5, -1, -SIZE_Z * 0.5), Vector3(SIZE_X, MEZZ_Y + 3.0, SIZE_Z))
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
