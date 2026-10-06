class_name BlackjackStation
extends StationBase
## Half-moon blackjack table (Patrick's model, flat casino colors since its textures did not come
## along): green felt, padded rail, gold legs, 4 seats on the curved side, dealer on the straight one.


func _build_visuals() -> void:
	game_id = &"blackjack"
	seat_count = 4
	_round_rug(4.8)
	# Collision stays a simple cylinder; Patrick's half-moon table model is what you see.
	var rim: Node3D = GreyboxKit.cylinder(self, 1.7, 0.9, Vector3(0, 0.45, 0), Color("#3A2A1E"), "Rim")
	(rim.get_node(^"Mesh") as Node3D).visible = false
	_add_table_model()
	# Dealer spot (north side, the straight edge), chip rack.
	GreyboxKit.box(self, Vector3(0.7, 0.08, 0.22), Vector3(0.75, 0.96, -0.22), Color("#1E1B19"), "ChipRack", false)
	GreyboxKit.box(self, Vector3(0.2, 0.12, 0.3), Vector3(-0.8, 0.98, -0.2), Color("#1E1B19"), "Shoe", false)
	cards = TableCards.new()
	cards.name = "Cards"
	cards.shoe = Vector3(-0.8, 1.06, -0.2)
	cards.spots[-1] = [Vector3(-0.1, TABLE_TOP, 0.05), 0.0]
	add_child(cards)
	for i: int in seat_count:
		var angle: float = deg_to_rad(-45.0 + 30.0 * i)  # fan on the south side
		var pos: Vector3 = Vector3(sin(angle) * 2.2, 0.0, cos(angle) * 2.2)
		_stool(pos, "Stool%d" % i)
		_add_seat(pos + Vector3(0, 0.5, 0), angle)  # yaw = angle looks at the table centre
		# Your cards land on the felt in front of you; your camera sits at your own stool.
		var to_seat: Vector3 = (pos - ARC_CENTRE).normalized()
		cards.spots[i] = [ARC_CENTRE + to_seat * 1.3 + Vector3(0, TABLE_TOP, 0), angle]
		# A split's second hand: one row closer to the dealer, nudged right, so both stay readable.
		cards.spots[i + SPLIT_KEY] = [ARC_CENTRE + to_seat * 1.3 + Basis(Vector3.UP, angle) * SPLIT_OFFSET + Vector3(0, TABLE_TOP, 0), angle]
		var eye := Node3D.new()
		eye.name = "SeatCamera%d" % i
		# Leaning in over the rail: your own cards low in view, the dealer's rack above them.
		eye.position = pos - to_seat * SEAT_EYE_LEAN + Vector3(0, SEAT_EYE_HEIGHT, 0)
		var look: Vector3 = SEAT_LOOK_AT - eye.position
		eye.rotation = Vector3(SEAT_EYE_PITCH, atan2(-look.x, -look.z), 0.0)
		add_child(eye)
		seat_cameras.append(eye)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0, 1.45, 2.3)
	camera_anchor.rotation.x = deg_to_rad(-25.0)
	add_child(camera_anchor)


## Card height on the felt and the centre of the half-moon's arc.
const TABLE_TOP: float = 0.935
const ARC_CENTRE: Vector3 = Vector3(0, 0, -0.4)
## Card-spot key offset for a seat's second (split) hand, and where that hand lies relative to
## the first one (seat-local: -z is towards the dealer).
const SPLIT_KEY: int = 10
const SPLIT_OFFSET: Vector3 = Vector3(0.14, 0.0, -0.4)
## Seated eye: how far it leans in from the stool towards the table, its height and its pitch.
const SEAT_EYE_LEAN: float = 0.5
const SEAT_EYE_HEIGHT: float = 1.5
const SEAT_EYE_PITCH: float = deg_to_rad(-26.0)
## Every seat's view is turned towards this point (between the dealer's rack and the hands).
const SEAT_LOOK_AT: Vector3 = Vector3(0.0, 0.0, 0.2)

var cards: TableCards


## Turns the dealer's cards towards the local player's seat (-1 = nobody local is seated here).
func set_viewer_seat(index: int) -> void:
	cards.set_viewer(seat_cameras[index].position if index >= 0 and index < seat_cameras.size() else Vector3.INF)


## Mirrors the round onto the felt (see `TableCards`).
func show_round(pub: Dictionary) -> void:
	var seat_ids: Array = pub.get("seats", [])
	var hands: Dictionary = pub.get("hands", {})
	var by_seat: Dictionary = {}
	for i: int in seat_ids.size():
		var pid: int = int(seat_ids[i])
		if pid < 0:
			continue
		for k: Variant in hands:
			if int(k) == pid:
				var h: Dictionary = hands[k]
				by_seat[i] = h.get("cards", [])
				if h.has("split"):
					by_seat[i + SPLIT_KEY] = (h["split"] as Dictionary).get("cards", [])
	var dealer: Array = (pub.get("dealer", []) as Array).duplicate()
	if not bool(pub.get("dealer_revealed", false)) and dealer.size() == 1 and int(pub.get("state", 0)) == BlackjackLogic.State.ACTING:
		dealer.append(TableCards.FACE_DOWN)
	cards.show_cards(by_seat, dealer)


const TABLE_MODEL: String = "res://assets/casino/blackjack_table.dae"
## Flat colors per part of the model (its texture files were not included).
const TABLE_COLORS: Dictionary = {
	"Table top": Color("#275E49"), "arm rest (for players)": Color("#681F2C"), "Rubber pad strip": Color("#151414"),
}


func _add_table_model() -> void:
	var ps: PackedScene = load(TABLE_MODEL) as PackedScene
	if ps == null:
		return
	var model: Node3D = ps.instantiate()
	model.name = "Table"
	# Native: 2.24 m across, straight edge on z = 0, curved side towards +z, top at ~0.97 m.
	model.scale = Vector3(1.7, 0.95, 1.7)
	model.position = Vector3(0, 0, -0.4)
	add_child(model)
	for n: Node in model.find_children("*", "", true, false):
		if n is MeshInstance3D:
			var c: Color = TABLE_COLORS.get(String(n.name), Palette.WARM_GOLD)
			(n as MeshInstance3D).material_override = GreyboxKit.gold() if c == Palette.WARM_GOLD else GreyboxKit.material(c, 0.0, 0.7)
