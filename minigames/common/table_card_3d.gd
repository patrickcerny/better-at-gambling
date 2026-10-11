class_name TableCard3D
extends Node3D
## One big playing card lying on the felt, for the card table minigames (Find the Lady, Forehead
## Poker): the Kenney card art (same files as the blackjack table) on top, the red back underneath,
## a thin cream edge so it reads as a card from a low angle, and a soft gold glow under it for
## "this one" highlights. `face_up_t` turns it over sideways with a little hop (1 = face up), so a
## stage can tween it or drive it from its own clock. Purely visual.

const SIZE: Vector2 = Vector2(0.42, 0.6)
const FACE_DOWN: int = -1
const BACK_TINT: Color = Color("#8E2A33")
const FACE_TINT: Color = Color(0.92, 0.9, 0.86)
const THICKNESS: float = 0.008
const SUIT_FILES: Array[String] = ["spades", "hearts", "diamonds", "clubs"]
const RANK_FILES: Array[String] = ["", "A", "02", "03", "04", "05", "06", "07", "08", "09", "10", "J", "Q", "K"]

static var _textures: Dictionary[int, Texture2D] = {}
static var _glow_tex: Texture2D = null

## The card shown on the face side (Card int, or FACE_DOWN for a blank back on both sides).
var card: int = FACE_DOWN
## 1 = face up, 0 = face down; in between it is mid-flip (turned on its long edge, lifted).
var face_up_t: float = 0.0:
	set(v):
		face_up_t = clampf(v, 0.0, 1.0)
		_apply_flip()
var size: Vector2 = SIZE
var flipper: Node3D
var face: MeshInstance3D
var back: MeshInstance3D
var glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _flip_tween: Tween = null


static func make(p_card: int, p_size: Vector2 = SIZE, p_face_up: bool = false) -> TableCard3D:
	var c := TableCard3D.new()
	c.card = p_card
	c.size = p_size
	c._build()
	c.face_up_t = 1.0 if p_face_up else 0.0
	return c


func _build() -> void:
	if flipper != null:
		return
	glow = MeshInstance3D.new()
	glow.name = "Glow"
	var gm := QuadMesh.new()
	gm.size = size + Vector2(0.14, 0.14)
	gm.orientation = PlaneMesh.FACE_Y
	glow.mesh = gm
	glow.position.y = 0.002
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_texture = _glow_texture()
	_glow_mat.albedo_color = Color(Palette.VIP_GOLD, 0.0)
	glow.material_override = _glow_mat
	glow.visible = false
	add_child(glow)
	flipper = Node3D.new()
	flipper.name = "Flipper"
	add_child(flipper)
	var quad := QuadMesh.new()
	quad.size = size
	quad.orientation = PlaneMesh.FACE_Y
	face = MeshInstance3D.new()
	face.name = "Face"
	face.mesh = quad
	face.position.y = THICKNESS * 0.5
	flipper.add_child(face)
	back = MeshInstance3D.new()
	back.name = "Back"
	back.mesh = quad
	back.position.y = -THICKNESS * 0.5
	back.rotation.z = PI
	back.material_override = _material(texture(FACE_DOWN), BACK_TINT)
	flipper.add_child(back)
	var edge := MeshInstance3D.new()
	edge.name = "Edge"
	var em := BoxMesh.new()
	em.size = Vector3(size.x * 0.96, THICKNESS * 0.9, size.y * 0.97)
	edge.mesh = em
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Palette.CREAM.darkened(0.15)
	edge_mat.roughness = 0.8
	edge.material_override = edge_mat
	flipper.add_child(edge)
	set_card(card)


## Changes the face art (the back stays).
func set_card(c: int) -> void:
	card = c
	if face != null:
		face.material_override = _material(texture(c), FACE_TINT if c != FACE_DOWN else BACK_TINT)


func is_face_up() -> bool:
	return face_up_t >= 0.5


## Turns the card over to `up` in `seconds` (0 = at once). Returns the tween (or null).
func flip_to(up: bool, seconds: float = 0.35, delay: float = 0.0) -> Tween:
	var target: float = 1.0 if up else 0.0
	stop_flip()
	if seconds <= 0.0 or not is_inside_tree():
		face_up_t = target
		return null
	var t: Tween = create_tween()
	_flip_tween = t
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(self, ^"face_up_t", target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t


## Stops a running `flip_to` where it is (the stage takes over the card).
func stop_flip() -> void:
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip_tween = null


## The gold glow under the card (0 = off); `color` defaults to the house gold.
func set_glow(amount: float, color: Color = Palette.VIP_GOLD) -> void:
	if glow == null:
		return
	glow.visible = amount > 0.01
	_glow_mat.albedo_color = Color(color, clampf(amount, 0.0, 1.0))


func _apply_flip() -> void:
	if flipper == null:
		return
	# Turned over sideways (about the long edge), lifted at mid-flip so it clears the felt.
	flipper.rotation.z = PI * (1.0 - face_up_t)
	flipper.position.y = sin(face_up_t * PI) * size.x * 0.55


static func texture(c: int) -> Texture2D:
	if not _textures.has(c):
		var path: String = "res://assets/cards/card_back.png"
		if c != FACE_DOWN:
			path = "res://assets/cards/card_%s_%s.png" % [SUIT_FILES[Card.suit(c)], RANK_FILES[Card.rank(c)]]
		_textures[c] = load(path) as Texture2D
	return _textures[c]


static func _material(tex: Texture2D, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR  # rounded corners
	m.roughness = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## A soft rounded-rectangle falloff for the glow quad.
static func _glow_texture() -> Texture2D:
	if _glow_tex != null:
		return _glow_tex
	var w: int = 48
	var h: int = 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var dx: float = maxf(absf(float(x) + 0.5 - w * 0.5) - (w * 0.5 - 12.0), 0.0)
			var dy: float = maxf(absf(float(y) + 0.5 - h * 0.5) - (h * 0.5 - 12.0), 0.0)
			var d: float = sqrt(dx * dx + dy * dy) / 12.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) * 0.9))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex
