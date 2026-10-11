class_name HandFan
extends Node3D
## The cards a bean carries in Grab Your Hand, fanned over their head like a hand of poker (hands
## are public: that's the fun). It turns to face the camera every frame, the fan opens a little
## wider per card, and the hand's name ("TWO PAIR") floats under it. `set_big(true)` is the
## showdown: the fan grows, rises and the name turns gold. Purely visual; the stage positions it.

const CARD: Vector2 = Vector2(0.3, 0.42)
const SPREAD_DEG: float = 11.0

var cards: Array[int] = []
var big: bool = false
var _fan: Node3D
var _name: Label3D
var _scale_now: float = 1.0
var _pop: float = 0.0


func _init() -> void:
	name = "HandFan"
	_fan = Node3D.new()
	_fan.name = "Fan"
	add_child(_fan)
	_name = Label3D.new()
	_name.font = Vfx.font()
	_name.font_size = 64
	_name.pixel_size = 0.0024
	_name.outline_size = 18
	_name.modulate = Palette.CREAM
	_name.outline_modulate = Palette.CASINO_BLACK
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.no_depth_test = true
	_name.render_priority = 4
	_name.outline_render_priority = 3
	_name.position = Vector3(0, -0.12, 0)
	add_child(_name)


## Shows `p_cards` (pickup order) and the hand's name.
func set_cards(p_cards: Array, hand_name: String) -> void:
	var next: Array[int] = []
	for c: Variant in p_cards:
		next.append(int(c))
	if next != cards:
		_pop = 1.0
	cards = next
	for ch: Node in _fan.get_children():
		_fan.remove_child(ch)
		ch.queue_free()
	var n: int = cards.size()
	for i: int in n:
		var pivot := Node3D.new()
		var off: float = float(i) - float(n - 1) * 0.5
		pivot.rotation.z = deg_to_rad(-SPREAD_DEG * off)
		pivot.position = Vector3(0, 0, 0.004 * float(i))
		_fan.add_child(pivot)
		var c: TableCard3D = TableCard3D.make(cards[i], CARD, true)
		c.rotation.x = PI * 0.5
		c.position.y = CARD.y * 0.5 + 0.02
		pivot.add_child(c)
	_name.text = hand_name if n > 0 else ""
	visible = n > 0


func set_big(on: bool) -> void:
	big = on
	_name.modulate = Palette.VIP_GOLD if on else Palette.CREAM
	_name.font_size = 80 if on else 64


func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var d: Vector3 = cam.global_position - global_position
		_fan.rotation.y = atan2(d.x, d.z)
	_pop = maxf(_pop - delta * 3.0, 0.0)
	var goal: float = (2.2 if big else 1.0) + 0.25 * _pop * _pop
	_scale_now = lerpf(_scale_now, goal, 1.0 - exp(-8.0 * delta))
	scale = Vector3.ONE * _scale_now
