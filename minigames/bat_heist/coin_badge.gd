class_name CoinBadge
extends Node3D
## Bat Heist's coin count over a bean: the casino's own gold `Coin` turning slowly on its edge next
## to the count, on a dark plaque so it reads against the vault's marble. When the bean is down and
## can be robbed it drops to the body, turns red and says "STEAL!". `bump(delta)` pops it when the
## count changes (green for a gain, red for a loss).

const COIN_SCALE: float = 3.2
const SPIN: float = 2.4

var count: int = 0
var stealable: bool = false
var _coin_spin: Node3D
var _label: Label3D
var _hint: Label3D
var _pop: float = 0.0
var _flash: Color = Palette.VIP_GOLD


func _init(p_count: int = 0) -> void:
	name = "CoinBadge"
	count = p_count
	_coin_spin = Node3D.new()
	_coin_spin.position = Vector3(-0.17, 0.0, 0.0)
	_coin_spin.scale = Vector3.ONE * COIN_SCALE
	add_child(_coin_spin)
	var coin := Coin.new()
	coin.gravity = 0.0
	coin.rotation.x = PI * 0.5  # the face towards the camera, turning around y
	_coin_spin.add_child(coin)
	_label = _make_label(110, Palette.VIP_GOLD)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.position = Vector3(-0.04, 0.0, 0.0)
	add_child(_label)
	_hint = _make_label(70, Palette.CREAM)
	_hint.text = "STEAL!"
	_hint.position = Vector3(0, -0.26, 0)
	_hint.visible = false
	add_child(_hint)
	_refresh()


func set_count(c: int) -> void:
	if c != count:
		bump(c - count)
	count = c
	_refresh()


## Pops the badge: green for a gain, red for a loss.
func bump(delta: int) -> void:
	_pop = 1.0
	_flash = Palette.MONEY_GREEN if delta > 0 else Palette.LOSS_RED


func set_stealable(on: bool) -> void:
	stealable = on
	_hint.visible = on


func _process(delta: float) -> void:
	_coin_spin.rotation.y += SPIN * delta * (3.0 if stealable else 1.0)
	_pop = maxf(_pop - delta * 2.5, 0.0)
	var s: float = 1.0 + 0.45 * _pop * _pop
	_label.scale = Vector3.ONE * s
	_label.modulate = Palette.VIP_GOLD.lerp(_flash, _pop)
	if stealable:
		var k: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		_hint.modulate = Palette.CREAM.lerp(Palette.LOSS_RED, k)


func _refresh() -> void:
	_label.text = str(count)


func _make_label(size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.0022
	l.outline_size = 22
	l.modulate = color
	l.outline_modulate = Palette.CASINO_BLACK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 4
	l.outline_render_priority = 3
	return l
