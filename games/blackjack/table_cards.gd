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
## Card faces are a touch grey so a white card under a spotlight stays below the room's bloom
## threshold (LoungeDecor glow_hdr_threshold 1.1) and never smears over its neighbours.
const FACE_TINT: Color = Color(0.85, 0.85, 0.85)
## Sunglasses x-ray: the hole card's face seen through its back, scan green.
const XRAY_TINT: Color = Color(0.45, 1.0, 0.55, 0.85)
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
## Card spot and facing yaw per seat index, plus the dealer's (key -1); an optional third entry
## is the fan step (sideways per card) for that pile.
var spots: Dictionary[int, Array] = {}
## Where the dealer's cards turn to (local to the table); INF faces them straight down +z.
var viewer: Vector3 = Vector3.INF
## The slanted rack the dealer's cards lean against.
var dealer_rack: MeshInstance3D

## The hand being played after a split: a gold outline around its cards (the aim outline shader on
## a thin card-sized hull with smoothed normals, so it grows sideways into a rim).
const OUTLINE_SHADER: Shader = preload("res://client/aim_outline.gdshader")
const OUTLINE_WIDTH: float = 0.016

## Shown cards per seat (-1 = dealer): {"ids": Array[int], "nodes": Array[Node3D]}.
var _piles: Dictionary[int, Dictionary] = {}

var _textures: Dictionary[int, Texture2D] = {}
## Piles drawn with the gold outline (the hand being played after a split).
var _outlined: Array[int] = []
var _outline_mat: ShaderMaterial
var _outline_mesh: ArrayMesh
## Hole card shown through its back for the local Sunglasses wearer (-1 = none).
var _xray: int = -1
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


## Moves a pile to a new spot (and fan); its cards slide over. A split moves the first hand aside.
func move_pile(key: int, spot: Array) -> void:
	if spots.has(key) and spots[key] == spot:
		return
	spots[key] = spot
	if not _piles.has(key):
		return
	var nodes: Array = _piles[key]["nodes"]
	for i: int in nodes.size():
		var n: Node3D = nodes[i]
		n.create_tween().tween_property(n, ^"position", card_position(key, i), DEAL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A split: the last card of pile `from` (when it is `card`) slides over to start pile `to`
## (instead of going back to the shoe and being dealt again).
func split_pile(from: int, to: int, card: int) -> void:
	if not _piles.has(from) or _piles.has(to) or not spots.has(to):
		return
	var ids: Array = _piles[from]["ids"]
	var nodes: Array = _piles[from]["nodes"]
	if nodes.size() != 2 or int(ids[1]) != card:
		return
	var n: Node3D = nodes.pop_back()
	var c: int = int(ids.pop_back())
	_piles[to] = {"ids": [c] as Array[int], "nodes": [n] as Array[Node3D]}
	_set_outline(n, _outlined.has(to))
	var t: Tween = n.create_tween().set_parallel(true)
	t.tween_property(n, ^"position", card_position(to, 0), DEAL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(n, ^"rotation", card_rotation(to, c != FACE_DOWN), DEAL_TIME)


## Outlines the cards of these piles (and the cards dealt to them later); every other pile loses it.
func set_outlined(keys: Array[int]) -> void:
	_outlined = keys.duplicate()
	for key: int in _piles:
		for n: Node3D in _piles[key]["nodes"]:
			_set_outline(n, _outlined.has(key))


## True when the card node shows the gold outline.
static func is_outlined(card: Node3D) -> bool:
	var o: Node3D = card.get_node_or_null(^"Outline")
	return o != null and o.visible


func _set_outline(card: Node3D, on: bool) -> void:
	var o: MeshInstance3D = card.get_node_or_null(^"Outline")
	if o == null:
		if not on:
			return
		o = MeshInstance3D.new()
		o.name = "Outline"
		o.mesh = _hull_mesh()
		if _outline_mat == null:
			_outline_mat = ShaderMaterial.new()
			_outline_mat.shader = OUTLINE_SHADER
			_outline_mat.set_shader_parameter(&"color", Palette.VIP_GOLD)
			_outline_mat.set_shader_parameter(&"width", OUTLINE_WIDTH)
		o.material_override = _outline_mat
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.add_child(o)
	o.visible = on


## A card-sized slab whose normals point out of its corners (mostly sideways), so the outline
## shader grows it into a rim around the card rather than just pushing each face out.
func _hull_mesh() -> ArrayMesh:
	if _outline_mesh != null:
		return _outline_mesh
	var box := BoxMesh.new()
	box.size = Vector3(CARD_SIZE.x, 0.002, CARD_SIZE.y)
	var arrays: Array = box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	for v: Vector3 in verts:
		normals.append(Vector3(signf(v.x), signf(v.y) * 0.5, signf(v.z)).normalized())
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	_outline_mesh = ArrayMesh.new()
	_outline_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _outline_mesh


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
		_set_outline(node, _outlined.has(key))
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
	if (spots[key] as Array).size() > 2:
		fan.x = float(spots[key][2])
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


## Sunglasses (client only): the dealer's face-down card shows `card` through its back with a
## green x-ray tint for the wearer (-1 turns it back into a plain red back).
func set_xray(card: int) -> void:
	_xray = card
	if not _piles.has(-1):
		return
	var nodes: Array = _piles[-1]["nodes"]
	var ids: Array = _piles[-1]["ids"]
	for i: int in nodes.size():
		var back: MeshInstance3D = (nodes[i] as Node3D).get_node_or_null(^"Back")
		if back == null:
			continue
		var want: int = card if int(ids[i]) == FACE_DOWN and card >= 0 else FACE_DOWN
		if int(back.get_meta(&"xray", FACE_DOWN)) == want:
			continue
		back.set_meta(&"xray", want)
		back.material_override = _material(_texture(FACE_DOWN), BACK_TINT) if want == FACE_DOWN else _xray_material(_texture(want))


## The card currently x-rayed on the dealer's hole card (-1 = none).
func xray_card() -> int:
	return _xray


## See-through scan look: the face in green, glowing a little, slightly transparent.
static func _xray_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = XRAY_TINT
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.1, 0.9, 0.35)
	m.emission_energy_multiplier = 0.35
	m.emission_texture = tex
	m.roughness = 0.3
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


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
	var tint: Color = BACK_TINT if card == FACE_DOWN else FACE_TINT
	(root.get_node(^"Face") as MeshInstance3D).material_override = _material(_texture(card), tint)


static func _material(tex: Texture2D, tint: Color = FACE_TINT) -> StandardMaterial3D:
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
