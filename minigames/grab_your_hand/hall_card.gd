class_name HallCard
extends Node3D
## One giant playing card on the card hall floor (Grab Your Hand): two `TableCard3D` faces back to
## back so it reads from every side, standing upright, hovering a little over the marble, bobbing
## and turning slowly, with a pulsing gold glow on the floor and a soft shadow under it. It lands
## with a deal (`deal_in`: falls in spinning) or flies from a bean's hand (`land_from`), and goes
## with `fly_to` (shrinks into the picker's hand). Purely visual; the server owns every card.

const SIZE: Vector2 = Vector2(0.78, 1.1)
const HOVER: float = 0.18
const SPIN: float = 0.7

static var _ring_tex: Texture2D = null

var floor_id: int = -1
var card: int = TableCard3D.FACE_DOWN
var _body: Node3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _t: float = 0.0
var _phase: float = 0.0
## Flying out of the scene (picked up): the per-frame bob stops touching the body.
var _leaving: bool = false


static func make(p_id: int, p_card: int, yaw: float) -> HallCard:
	var h := HallCard.new()
	h.name = "HallCard%d" % p_id
	h.floor_id = p_id
	h.card = p_card
	h._phase = float(p_id) * 1.37
	h._build(yaw)
	return h


func _build(yaw: float) -> void:
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	var gm := QuadMesh.new()
	gm.size = Vector2(1.5, 1.5)
	gm.orientation = PlaneMesh.FACE_Y
	_glow.mesh = gm
	_glow.position.y = 0.012
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_texture = _ring_texture()
	_glow_mat.albedo_color = Color(Palette.VIP_GOLD, 0.6)
	_glow.material_override = _glow_mat
	add_child(_glow)
	_body = Node3D.new()
	_body.name = "Body"
	_body.rotation.y = yaw
	add_child(_body)
	for side: float in [0.0, PI]:
		var face: TableCard3D = TableCard3D.make(card, SIZE, true)
		face.rotation = Vector3(PI * 0.5, side, 0.0)
		face.position = Vector3(0, SIZE.y * 0.5, 0.006 if side == 0.0 else -0.006)
		_body.add_child(face)
	_body.position.y = HOVER


## Falls in from above, spinning, and settles (a fresh card from the deck).
func deal_in(delay: float = 0.0) -> void:
	_body.position.y = 3.5
	_body.scale = Vector3.ONE * 0.4
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(_body, "position:y", HOVER, 0.55).set_delay(delay).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_property(_body, "scale", Vector3.ONE, 0.4).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_body, "rotation:y", _body.rotation.y + TAU * 2.0, 0.6).set_delay(delay).set_ease(Tween.EASE_OUT)


## Arcs from `from` (world: a bean's hand) to where it lies now.
func land_from(from: Vector3) -> void:
	var to: Vector3 = global_position
	var start_local: Vector3 = from - to
	_leaving = true
	_body.position = start_local + Vector3(0, 0.6, 0)
	_body.scale = Vector3.ONE * 0.35
	var t: Tween = create_tween().set_parallel(true)
	t.tween_method(func(k: float) -> void:
		var p: Vector3 = (start_local + Vector3(0, 0.6, 0)).lerp(Vector3(0, HOVER, 0), k)
		p.y += sin(k * PI) * 1.2
		_body.position = p, 0.0, 1.0, 0.45)
	t.tween_property(_body, "scale", Vector3.ONE, 0.45)
	t.tween_property(_body, "rotation:y", _body.rotation.y + TAU, 0.45)
	t.chain().tween_callback(func() -> void: _leaving = false)


## Shrinks into `target` (a node: the picker) and frees itself.
func fly_to(target: Node3D) -> void:
	_leaving = true
	_glow.visible = false
	var start: Vector3 = _body.global_position
	var t: Tween = create_tween().set_parallel(true)
	t.tween_method(func(k: float) -> void:
		if not is_instance_valid(target):
			return
		var goal: Vector3 = target.global_position + Vector3(0, 1.6, 0)
		var p: Vector3 = start.lerp(goal, k)
		p.y += sin(k * PI) * 0.8
		_body.global_position = p, 0.0, 1.0, 0.32).set_ease(Tween.EASE_IN)
	t.tween_property(_body, "scale", Vector3.ONE * 0.15, 0.32).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	if _leaving:
		return
	_body.position.y = HOVER + 0.08 * sin(_t * 2.2 + _phase)
	_body.rotation.y += SPIN * delta
	var k: float = 0.5 + 0.5 * sin(_t * 3.0 + _phase)
	_glow_mat.albedo_color = Color(Palette.VIP_GOLD, 0.35 + 0.35 * k)
	_glow.scale = Vector3.ONE * (0.95 + 0.1 * k)



## A soft gold ring with a filled centre (the light pool under the card).
static func _ring_texture() -> Texture2D:
	if _ring_tex != null:
		return _ring_tex
	var n: int = 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y: int in n:
		for x: int in n:
			var d: float = Vector2(float(x) + 0.5 - n * 0.5, float(y) + 0.5 - n * 0.5).length() / (n * 0.5)
			var ring: float = clampf(1.0 - absf(d - 0.78) / 0.12, 0.0, 1.0)
			var pool: float = clampf(1.0 - d / 0.8, 0.0, 1.0) * 0.35
			img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(ring, pool), 0.0, 1.0)))
	_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex
