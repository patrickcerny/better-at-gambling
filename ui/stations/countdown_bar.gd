class_name CountdownBar
extends Control
## A thin brass bar that drains with the table's clock (bets close, your move). It runs smoothly
## between state updates, turns red for the last seconds and hides when no clock runs.

const LOW: float = 3.5

var total: float = 1.0
var left: float = -1.0
var _key: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(0, 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## The clock now: `seconds` left (< 0 = none), `key` names the phase (a new phase or a clock that
## went up starts a new bar).
func feed(seconds: float, key: String) -> void:
	if seconds <= 0.05:
		left = -1.0
		visible = false
		_key = key
		return
	if key != _key or seconds > left + 0.75 or left < 0.0:
		total = maxf(seconds, 0.5)
	_key = key
	left = seconds
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if left > 0.0:
		left = maxf(left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.45))
	var f: float = clampf(left / total, 0.0, 1.0)
	var c: Color = Palette.LOSS_RED if left < LOW else Palette.VIP_GOLD
	if left < LOW:
		c = c.lerp(Palette.CREAM, 0.25 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)))
	var w: float = r.size.x * f
	draw_rect(Rect2(Vector2(r.size.x - w, 0) * 0.5, Vector2(w, r.size.y)), c)
	draw_rect(Rect2(Vector2(r.size.x - w, 0) * 0.5, Vector2(w, 1)), Color(1, 1, 1, 0.35))
