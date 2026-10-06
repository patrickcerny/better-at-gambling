class_name TableCards
extends Node3D
## Real cards on the blackjack felt: each new card slides out of the shoe and flips onto its
## spot, the dealer's hole card stays face down until the reveal, and the table is swept when a
## new round starts. Cards are tilted up towards whoever reads them so they stay legible from a
## stool: players' hands lean a little towards their own seat, the dealer's stand almost upright
## in a rack turned towards `viewer` (the local player's eye, purely visual). Card art: Kenney playing cards (CC0), via simple-card-pile-ui (MIT).
## Purely visual; it mirrors the station's public state.

const CARD_SIZE: Vector2 = Vector2(0.2, 0.28)  # oversized so you can read them from your stool
const FAN: Vector3 = Vector3(0.1, 0.0, -0.03)
const DEAL_TIME: float = 0.35
const FACE_DOWN: int = -1
## The stock back art is pale blue; casino red makes the hole card obvious.
const BACK_TINT: Color = Color("#C83D3D")
## How far cards lean up from the felt towards their reader (0 = flat, PI/2 = upright).
const HAND_TILT: float = deg_to_rad(28.0)
const DEALER_TILT: float = deg_to_rad(68.0)
## The dealer's cards are read from across the table, so they are a bit bigger.
const DEALER_SCALE: float = 1.3
## The dealer's cards spread wider than a player's fan so the hole card never hides the up card.
const DEALER_FAN: float = 0.2
## Gap between overlapping cards along the card normal (keeps the newest card on top).
const STACK_GAP: float = 0.003
const SUIT_FILES: Array[String] = ["spades", "hearts", "diamonds", "clubs"]
const RANK_FILES: Array[String] = ["", "A", "02", "03", "04", "05", "06", "07", "08", "09", "10", "J", "Q", "K"]

## Where cards come from (local to the table).
var shoe: Vector3 = Vector3.ZERO
## Card spot and facing yaw per seat index, plus the dealer's (key -1).
var spots: Dictionary[int, Array] = {}
## Where the dealer's cards turn to (local to the table); INF faces them straight down +z.
var viewer: Vector3 = Vector3.INF
## The slanted rack the dealer's cards lean against.
var dealer_rack: MeshInstance3D

## Shown cards per seat (-1 = dealer): {"ids": Array[int], "nodes": Array[Node3D]}.
var _piles: Dictionary[int, Dictionary] = {}

var _textures: Dictionary[int, Texture2D] = {}
var _mesh: QuadMesh


## Mirrors one blackjack public state: `hands_by_seat` maps seat index → card ints, `dealer`
## is the dealer's shown cards (a face-down card is appended while the hole card is hidden).
func show_cards(hands_by_seat: Dictionary, dealer: Array) -> void:
	var want: Dictionary[int, Array] = {}
	for seat: int in hands_by_seat:
		want[seat] = hands_by_seat[seat]
	want[-1] = dealer
	for key: int in _piles.keys():
		if not want.has(key):
			_sweep(key)
	var delay: float = 0.0
	for key: int in want:
		delay = _sync(key, want[key], delay)


## The card nodes of one pile (seat index, or -1 for the dealer), in deal order.
func pile_nodes(key: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _piles.has(key):
		for n: Node3D in _piles[key]["nodes"]:
			out.append(n)
	return out


func card_count() -> int:
	var n: int = 0
	for key: int in _piles:
		n += (_piles[key]["nodes"] as Array).size()
	return n


func _sync(key: int, cards: Array, delay: float) -> float:
	if not spots.has(key):
		return delay
	if cards.is_empty():
		if _piles.has(key):
			_sweep(key)
		return delay
	if not _piles.has(key):
		_piles[key] = {"ids": [] as Array[int], "nodes": [] as Array[Node3D]}
	var ids: Array = _piles[key]["ids"]
	var nodes: Array = _piles[key]["nodes"]
	# A shorter or different hand means a new round (or a cut): drop what no longer matches.
	var keep: int = 0
	while keep < mini(ids.size(), cards.size()) and (int(ids[keep]) == int(cards[keep]) or int(ids[keep]) == FACE_DOWN):
		keep += 1
	while nodes.size() > keep:
		(nodes.pop_back() as Node3D).queue_free()
		ids.pop_back()
	for i: int in keep:
		if int(ids[i]) == FACE_DOWN and int(cards[i]) != FACE_DOWN:
			_flip_up(nodes[i], int(cards[i]))
			ids[i] = int(cards[i])
	for i: int in range(keep, cards.size()):
		var c: int = int(cards[i])
		var node: Node3D = _make_card(c)
		add_child(node)
		_deal(node, key, i, delay)
		delay += 0.18
		nodes.append(node)
		ids.append(c)
	return delay


func _sweep(key: int) -> void:
	for n: Node3D in _piles[key]["nodes"]:
		var t: Tween = n.create_tween()
		t.tween_property(n, ^"position", shoe + Vector3(0, 0.05, -0.3), 0.3)
		t.tween_callback(n.queue_free)
	_piles.erase(key)


func _deal(node: Node3D, key: int, index: int, delay: float) -> void:
	var yaw: float = _yaw(key)
	var tilt: float = _tilt(key)
	if key == -1:
		node.scale = Vector3.ONE * DEALER_SCALE
	node.position = shoe
	node.rotation = Vector3(0.0, yaw, PI)  # leaves the shoe face down
	var face_up: bool = bool(node.get_meta(&"face_up"))
	var t: Tween = node.create_tween()
	t.tween_interval(delay)
	t.tween_callback(func() -> void: Audio.play_at(&"card_deal", node, 2.0, randf_range(0.96, 1.04)))
	t.set_parallel(true)
	t.tween_property(node, ^"position", card_position(key, index), DEAL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(node, ^"rotation:x", tilt, DEAL_TIME)
	if face_up:
		t.tween_property(node, ^"rotation:z", 0.0, DEAL_TIME)


## Where card `index` of pile `key` rests (local to the table): fanned to the reader's right,
## each one a hair in front of the last, the lower edge on the felt.
func card_position(key: int, index: int) -> Vector3:
	var spot: Vector3 = spots[key][0]
	var tilt: float = _tilt(key)
	var size: float = CARD_SIZE.y * (DEALER_SCALE if key == -1 else 1.0)
	var lean := Basis(Vector3.UP, _yaw(key)) * Basis(Vector3.RIGHT, tilt)
	var lift := Vector3(0.0, sin(tilt) * size * 0.5 + 0.002, 0.0)
	var fan: Vector3 = Vector3(DEALER_FAN, 0.0, 0.0) if key == -1 else FAN
	return spot + lift + lean * Vector3(fan.x * index, STACK_GAP * index, fan.z * index)


## The rotation a card of pile `key` comes to rest at (z is PI while face down).
func card_rotation(key: int, face_up: bool) -> Vector3:
	return Vector3(_tilt(key), _yaw(key), 0.0 if face_up else PI)


## Turns the dealer's cards (and their rack) towards a new reader; `local_eye` is local to the table.
func set_viewer(local_eye: Vector3) -> void:
	viewer = local_eye
	_place_rack()
	if not _piles.has(-1):
		return
	var nodes: Array = _piles[-1]["nodes"]
	var ids: Array = _piles[-1]["ids"]
	for i: int in nodes.size():
		var n: Node3D = nodes[i]
		n.position = card_position(-1, i)
		n.rotation = card_rotation(-1, int(ids[i]) != FACE_DOWN)


func _yaw(key: int) -> float:
	if key != -1 or viewer == Vector3.INF or not spots.has(-1):
		return float(spots[key][1])
	var to: Vector3 = viewer - (spots[-1][0] as Vector3)
	return atan2(to.x, to.z)


func _tilt(key: int) -> float:
	return DEALER_TILT if key == -1 else HAND_TILT


func _ready() -> void:
	dealer_rack = MeshInstance3D.new()
	dealer_rack.name = "DealerRack"
	var box := BoxMesh.new()
	box.size = Vector3(0.72, 0.01, CARD_SIZE.y * DEALER_SCALE * 0.5)
	dealer_rack.mesh = box
	dealer_rack.material_override = GreyboxKit.material(Palette.FELT_GREEN.darkened(0.45), 0.0, 0.8)
	add_child(dealer_rack)
	_place_rack()


## The rack sits just behind the dealer's first card slot and leans with the cards.
func _place_rack() -> void:
	if dealer_rack == null or not spots.has(-1):
		return
	var yaw: float = _yaw(-1)
	var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, DEALER_TILT)
	var depth: float = (dealer_rack.mesh as BoxMesh).size.z
	var fan_mid: float = DEALER_FAN
	dealer_rack.transform = Transform3D(lean, (spots[-1][0] as Vector3) + Vector3(0, sin(DEALER_TILT) * depth * 0.5, 0) + lean * Vector3(fan_mid, -0.012, 0.0))


func _flip_up(node: Node3D, card: int) -> void:
	_set_face(node, card)
	var t: Tween = node.create_tween()
	t.tween_property(node, ^"rotation:z", 0.0, DEAL_TIME)
	Audio.play_at(&"card_flip", node, -6.0)


## A two-sided card lying flat: face on top (+y), back underneath.
func _make_card(card: int) -> Node3D:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = CARD_SIZE
		_mesh.orientation = PlaneMesh.FACE_Y
	var root := Node3D.new()
	root.name = "Card"
	var face := MeshInstance3D.new()
	face.name = "Face"
	face.mesh = _mesh
	face.position.y = 0.0015
	root.add_child(face)
	var back := MeshInstance3D.new()
	back.name = "Back"
	back.mesh = _mesh
	back.rotation.z = PI
	back.material_override = _material(_texture(FACE_DOWN), BACK_TINT)
	root.add_child(back)
	root.set_meta(&"face_up", card != FACE_DOWN)
	_set_face(root, card)
	return root


func _set_face(root: Node3D, card: int) -> void:
	var tint: Color = BACK_TINT if card == FACE_DOWN else Color.WHITE
	(root.get_node(^"Face") as MeshInstance3D).material_override = _material(_texture(card), tint)


static func _material(tex: Texture2D, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR  # rounded corners
	m.roughness = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func _texture(card: int) -> Texture2D:
	if not _textures.has(card):
		var path: String = "res://assets/cards/card_back.png"
		if card != FACE_DOWN:
			path = "res://assets/cards/card_%s_%s.png" % [SUIT_FILES[Card.suit(card)], RANK_FILES[Card.rank(card)]]
		_textures[card] = load(path) as Texture2D
	return _textures[card]
