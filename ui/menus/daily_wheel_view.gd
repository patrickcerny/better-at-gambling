class_name DailyWheelView
extends Control
## The Daily Spin's prize wheel, drawn in code (`DailySpinPanel`): twelve slices (`DailyWheel`) in
## the casino's burgundy, cream and felt, gold dividers with pegs, a lacquered rim of warm marquee
## bulbs, a Gold Coin hub and a gold pointer at the top that flicks back on every peg
## (docs/ART_DIRECTION.md: warm and luxurious, no neon). Bulbs chase slowly while it waits, race
## while it turns and blink together on a win, when the winning slice glows and confetti and coins
## burst out.
##
## `rev` starts the wheel turning before the result is known (Steam answers in a moment);
## `stop_at` eases it out onto a slice from whatever speed it has, so the spin is one smooth motion;
## `stop_anywhere` stops it on no prize (Steam said not yet). `landed` fires when it rests.

signal landed(index: int)
## The wheel itself was clicked (Patrick 2026-11-16: "be able to click the wheel to spin it").
signal clicked

enum State { IDLE, REVVING, STOPPING, WON }

const SLICE_BURGUNDY := Color("#681F2C")
const SLICE_CREAM := Color("#F2E6C9")
const SLICE_FELT := Color("#275E49")
const SLICE_CHARCOAL := Color("#3A2A22")
const SLICE_JACKPOT := Color("#16100E")
const LACQUER := Color("#2A1012")
const GOLD := Color("#D6A84B")
const GOLD_LIGHT := Color("#F6E3A1")
const BULB_ON := Color("#FFD98A")
const BULB_OFF := Color("#5A4030")
const RUBY := Color("#B3283A")
const BULBS: int = 24
## Top speed while waiting for the result (rad/s) and how fast it gets there.
const REV_SPEED: float = 9.0
const REV_ACCEL: float = 14.0
## Full turns at least between the result and the stop.
const STOP_TURNS: int = 2
## The ease-out power of the stop (higher = longer crawl at the end).
const EASE_POWER: float = 4.0

## The wheel's turn (radians, clockwise); slice i spans [angle + i*step, angle + (i+1)*step] from
## the top.
var angle: float = 0.0
var state: State = State.IDLE
var speed: float = 0.0
## The slice it is stopping on (or rests on after a win), -1 = none.
var target: int = -1
var _from: float = 0.0
var _dist: float = 0.0
var _dur: float = 1.0
var _t: float = 0.0
var _clock: float = 0.0
## The pointer's flick (radians) and the last peg it passed.
var _flick: float = 0.0
var _peg: int = 0
var _tick_cool: float = 0.0
## Confetti and coins: {p, v, rot, spin, color, coin, life}.
var _bits: Array[Dictionary] = []
var _win_t: float = 0.0
## Slices that can't be won here (no Steam): drawn a little dimmed.
var dimmed: Array[int] = []
## Whether a click on the wheel spins it (set by the panel while a spin is free): the hand cursor.
var clickable: bool = false:
	set(v):
		clickable = v
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(560, 560)


static func step() -> float:
	return TAU / float(DailyWheel.count())


## The wheel turn that puts slice `i`'s middle (plus `offset` of a slice) under the pointer.
static func angle_for(i: int, offset: float = 0.0) -> float:
	return fposmod(-(float(i) + 0.5 + offset) * step(), TAU)


## Which slice is under the pointer at turn `a`.
static func index_at(a: float) -> int:
	return posmod(int(floor(fposmod(-a, TAU) / step())), DailyWheel.count())


## Starts turning: the result isn't known yet.
func rev() -> void:
	state = State.REVVING
	target = -1
	_bits.clear()


## Eases out onto slice `i` from the current speed (lands a little off its middle, like a real
## wheel).
func stop_at(i: int, jitter: float = randf_range(-0.32, 0.32)) -> void:
	target = i
	var goal: float = angle_for(i, jitter)
	var delta: float = fposmod(goal - angle, TAU)
	_begin_stop(float(STOP_TURNS) * TAU + delta)


## Slows to a stop wherever it is (no prize).
func stop_anywhere() -> void:
	target = -1
	_begin_stop(TAU + randf() * TAU)


func _begin_stop(dist: float) -> void:
	_from = angle
	_dist = dist
	var v: float = maxf(speed, 3.0)
	_dur = clampf(EASE_POWER * dist / v, 2.5, 7.5)
	_t = 0.0
	state = State.STOPPING


## Whether it is turning.
func busy() -> bool:
	return state == State.REVVING or state == State.STOPPING


func _process(delta: float) -> void:
	_clock += delta
	_tick_cool = maxf(_tick_cool - delta, 0.0)
	var before: float = angle
	match state:
		State.IDLE, State.WON:
			speed = 0.0
			if state == State.IDLE:
				angle += delta * 0.06  # a slow drift, so it looks alive
		State.REVVING:
			speed = minf(speed + REV_ACCEL * delta, REV_SPEED)
			angle += speed * delta
		State.STOPPING:
			_t += delta
			var p: float = clampf(_t / _dur, 0.0, 1.0)
			angle = _from + _dist * (1.0 - pow(1.0 - p, EASE_POWER))
			speed = _dist * EASE_POWER * pow(1.0 - p, EASE_POWER - 1.0) / _dur
			if p >= 1.0:
				speed = 0.0
				if target >= 0:
					state = State.WON
					_win_t = 0.0
					_burst(target)
				else:
					state = State.IDLE
				landed.emit(target)
	angle = fmod(angle, TAU * 64.0)
	# Pegs passing the pointer flick it and click.
	var peg: int = int(floor(angle / step()))
	if peg != _peg and absf(angle - before) < PI:
		_peg = peg
		_flick = minf(_flick + 0.32, 0.55)
		if _tick_cool <= 0.0:
			Audio.play(&"chip_clack", &"UI", -16.0 + minf(speed, 6.0), randf_range(1.15, 1.35))
			_tick_cool = 0.045
	_flick = move_toward(_flick, 0.0, delta * (3.0 + speed * 0.6))
	if state == State.WON:
		_win_t += delta
	_move_bits(delta)
	queue_redraw()


# --- Confetti and coins ---------------------------------------------------------------------------

func _burst(i: int) -> void:
	var r: float = _radius()
	var c: Vector2 = size * 0.5
	var top := Vector2(c.x, c.y - r * 0.7)
	var kind: StringName = DailyWheel.segment(i)["kind"]
	var n: int = 90 if kind == DailyWheel.KIND_SKIN else 46
	var colors: Array[Color] = [GOLD, GOLD_LIGHT, SLICE_CREAM, SLICE_BURGUNDY, Color("#C83D3D")]
	for k: int in n:
		var a: float = randf_range(-PI * 0.95, -PI * 0.05)
		var v: float = randf_range(r * 0.9, r * 2.4)
		var coin: bool = kind != DailyWheel.KIND_PIECE and k % 3 == 0
		_bits.append({
			"p": top + Vector2(randf_range(-r * 0.15, r * 0.15), 0.0),
			"v": Vector2(cos(a), sin(a)) * v,
			"rot": randf() * TAU,
			"spin": randf_range(-9.0, 9.0),
			"color": colors[k % colors.size()],
			"coin": coin,
			"gold": kind == DailyWheel.KIND_GOLD or kind == DailyWheel.KIND_SKIN,
			"life": randf_range(1.6, 2.8),
		})


func _move_bits(delta: float) -> void:
	var g: float = _radius() * 2.2
	for b: Dictionary in _bits:
		var v: Vector2 = b["v"]
		v.y += g * delta
		v *= 1.0 - 0.9 * delta
		b["v"] = v
		b["p"] = (b["p"] as Vector2) + v * delta
		b["rot"] = float(b["rot"]) + float(b["spin"]) * delta
		b["life"] = float(b["life"]) - delta
	_bits = _bits.filter(func(b: Dictionary) -> bool: return float(b["life"]) > 0.0)


# --- Drawing ----------------------------------------------------------------------------------------

func _radius() -> float:
	return minf(size.x, size.y) * 0.40


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if hits(mb.position):
		accept_event()
		clicked.emit()


## Whether `p` (local) is on the wheel, rim included.
func hits(p: Vector2) -> bool:
	var c: Vector2 = size * 0.5 + Vector2(0, minf(size.x, size.y) * 0.03)
	return p.distance_to(c) <= _radius() * 1.17


func _draw() -> void:
	var c: Vector2 = size * 0.5 + Vector2(0, minf(size.x, size.y) * 0.03)
	var r: float = _radius()
	var stp: float = step()
	var n: int = DailyWheel.count()
	# Shadow and the lacquered rim with its gold edges.
	draw_circle(c + Vector2(0, r * 0.06), r * 1.2, Color(0, 0, 0, 0.45))
	draw_circle(c, r * 1.17, LACQUER)
	draw_arc(c, r * 1.17, 0.0, TAU, 96, GOLD, maxf(r * 0.02, 2.0), true)
	draw_arc(c, r * 1.01, 0.0, TAU, 96, GOLD.darkened(0.25), maxf(r * 0.025, 2.0), true)
	# Bulbs: chase while idle or turning (faster with the speed), all blink on a win.
	for k: int in BULBS:
		var a: float = TAU * float(k) / float(BULBS)
		var bp: Vector2 = c + Vector2(cos(a), sin(a)) * r * 1.09
		var lit: bool
		if state == State.WON:
			lit = fmod(_win_t * 4.0, 1.0) < 0.55 if _win_t < 3.5 else (k + int(_clock * 3.0)) % 2 == 0
		else:
			var run: float = _clock * (2.5 + speed * 1.6)
			lit = (k + int(run)) % 3 == 0
		if lit:
			draw_circle(bp, r * 0.05, Color(BULB_ON, 0.18))
			draw_circle(bp, r * 0.033, Color(BULB_ON, 0.35))
			draw_circle(bp, r * 0.024, BULB_ON)
			draw_circle(bp - Vector2(r * 0.007, r * 0.007), r * 0.009, Color.WHITE)
		else:
			draw_circle(bp, r * 0.024, BULB_OFF)
			draw_circle(bp - Vector2(r * 0.007, r * 0.007), r * 0.008, Color(BULB_ON, 0.25))
	# Slices.
	var coin_alt: int = 0
	for i: int in n:
		var a0: float = -PI * 0.5 + angle + float(i) * stp
		var col: Color = _slice_color(i, coin_alt)
		if DailyWheel.segment(i)["kind"] == DailyWheel.KIND_COINS:
			coin_alt += 1
		var pts := PackedVector2Array([c])
		for s: int in 13:
			var a: float = a0 + stp * float(s) / 12.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, col)
		# Soft shading towards the hub (a few faint rings, so no hard edge shows).
		for ring: int in 4:
			var rr: float = r * (0.62 - 0.1 * float(ring))
			var inner := PackedVector2Array([c])
			for s: int in 13:
				var a: float = a0 + stp * float(s) / 12.0
				inner.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(inner, Color(0, 0, 0, 0.035))
		# A sheen across the outer edge.
		var outer := PackedVector2Array()
		for s: int in 13:
			var a: float = a0 + stp * float(s) / 12.0
			outer.append(c + Vector2(cos(a), sin(a)) * r)
		for s: int in range(12, -1, -1):
			var a: float = a0 + stp * float(s) / 12.0
			outer.append(c + Vector2(cos(a), sin(a)) * r * 0.9)
		draw_colored_polygon(outer, Color(1, 0.95, 0.8, 0.06))
		if i in dimmed:
			draw_colored_polygon(pts, Color(0.05, 0.03, 0.03, 0.3))
		if state == State.WON and i == target:
			var pulse: float = 0.25 + 0.2 * sin(_win_t * 8.0)
			draw_colored_polygon(pts, Color(GOLD_LIGHT, pulse))
	# Gold dividers and pegs.
	for i: int in n:
		var a: float = -PI * 0.5 + angle + float(i) * stp
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.17, c + d * r, GOLD, maxf(r * 0.012, 1.5), true)
		draw_circle(c + d * r * 0.95, r * 0.022, GOLD_LIGHT.darkened(0.1))
		draw_circle(c + d * r * 0.95, r * 0.012, GOLD.darkened(0.3))
	# What each slice holds, upright towards the rim.
	for i: int in n:
		var mid: float = -PI * 0.5 + angle + (float(i) + 0.5) * stp
		draw_set_transform(c, mid + PI * 0.5, Vector2.ONE)
		_draw_prize(i, r)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Hub: a Gold Coin in a gold ring.
	draw_circle(c, r * 0.2, GOLD.darkened(0.35))
	draw_arc(c, r * 0.2, 0.0, TAU, 48, GOLD_LIGHT, maxf(r * 0.012, 1.5), true)
	CoinIcon.draw_coin(self, c, r * 0.16, true)
	# Pointer: a gold wedge at the top with a ruby, flicked back by the pegs.
	var pc := Vector2(c.x, c.y - r * 1.13)
	draw_set_transform(pc, -_flick, Vector2.ONE)
	var tip := Vector2(0, r * 0.2)
	var wedge := PackedVector2Array([Vector2(-r * 0.075, -r * 0.03), Vector2(r * 0.075, -r * 0.03), tip])
	draw_colored_polygon(PackedVector2Array([wedge[0] + Vector2(0, r * 0.015), wedge[1] + Vector2(0, r * 0.015), tip + Vector2(0, r * 0.015)]), Color(0, 0, 0, 0.4))
	draw_colored_polygon(wedge, GOLD)
	draw_polyline(PackedVector2Array([wedge[0], wedge[1], tip, wedge[0]]), GOLD_LIGHT, maxf(r * 0.008, 1.0), true)
	draw_circle(Vector2.ZERO, r * 0.065, GOLD.darkened(0.2))
	draw_circle(Vector2.ZERO, r * 0.042, RUBY)
	draw_circle(Vector2(-r * 0.012, -r * 0.012), r * 0.012, Color(1, 1, 1, 0.7))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Confetti and coins.
	for b: Dictionary in _bits:
		var alpha: float = clampf(float(b["life"]) / 0.6, 0.0, 1.0)
		var bp: Vector2 = b["p"]
		if bool(b["coin"]):
			draw_set_transform(bp, 0.0, Vector2(absf(cos(float(b["rot"]))) * 0.85 + 0.15, 1.0))
			CoinIcon.draw_coin(self, Vector2.ZERO, r * 0.045, bool(b["gold"]))
		else:
			draw_set_transform(bp, float(b["rot"]), Vector2.ONE)
			var col: Color = b["color"]
			draw_rect(Rect2(-r * 0.018, -r * 0.009, r * 0.036, r * 0.018), Color(col, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _slice_color(i: int, coin_alt: int) -> Color:
	match DailyWheel.segment(i)["kind"]:
		DailyWheel.KIND_COINS:
			return SLICE_CREAM if coin_alt % 2 == 0 else SLICE_BURGUNDY
		DailyWheel.KIND_GOLD:
			return SLICE_FELT
		DailyWheel.KIND_PIECE:
			return SLICE_CHARCOAL
		_:
			return SLICE_JACKPOT


## One slice's prize in its own frame (the rim is up, -y): an icon near the rim, the amount under it.
func _draw_prize(i: int, r: float) -> void:
	var seg: Dictionary = DailyWheel.segment(i)
	var kind: StringName = seg["kind"]
	var font: Font = get_theme_font(&"font", &"HeadingLabel")
	if font == null:
		font = get_theme_default_font()
	var on_dark: bool = _slice_color(i, _coin_index(i)) != SLICE_CREAM
	var ink: Color = SLICE_CREAM if on_dark else SLICE_BURGUNDY
	var icon_y: float = -r * 0.76
	var text_y: float = -r * 0.5
	match kind:
		DailyWheel.KIND_COINS, DailyWheel.KIND_GOLD:
			CoinIcon.draw_coin(self, Vector2(0, icon_y), r * 0.085, kind == DailyWheel.KIND_GOLD)
			var txt: String = DailyWheel.thousands(int(seg["amount"]))
			_text(font, txt, Vector2(0, text_y), int(r * (0.11 if txt.length() <= 3 else 0.085)), GOLD_LIGHT if kind == DailyWheel.KIND_GOLD else ink)
			if kind == DailyWheel.KIND_GOLD:
				_text(font, "GOLD", Vector2(0, text_y + r * 0.1), int(r * 0.055), GOLD)
		DailyWheel.KIND_PIECE:
			draw_circle(Vector2(0, icon_y), r * 0.085, Color(GOLD, 0.25))
			draw_arc(Vector2(0, icon_y), r * 0.085, 0.0, TAU, 32, GOLD, maxf(r * 0.01, 1.0), true)
			_text(font, "?", Vector2(0, icon_y + r * 0.04), int(r * 0.12), GOLD_LIGHT)
			_text(font, "PIECE", Vector2(0, text_y), int(r * 0.06), ink)
		_:
			# The jackpot: a little bean in Fortune burgundy with a gold wheel on its belly,
			# gold sparkles circling it.
			var bc := Vector2(0, icon_y + r * 0.01)
			var glow: float = 0.5 + 0.5 * sin(_clock * 3.0)
			draw_circle(bc, r * 0.11, Color(GOLD, 0.12 + 0.1 * glow))
			_bean(bc, r * 0.075)
			for k: int in 6:
				var a: float = _clock * 1.3 + float(k) * TAU / 6.0
				var sp: Vector2 = bc + Vector2(cos(a), sin(a) * 0.8) * r * 0.12
				var tw: float = 0.5 + 0.5 * sin(_clock * 5.0 + float(k) * 2.0)
				_sparkle(sp, r * 0.022 * (0.4 + tw), Color(GOLD_LIGHT, 0.4 + 0.6 * tw))
			_text(font, "JACKPOT", Vector2(0, text_y), int(r * 0.052), GOLD_LIGHT)
			_text(font, "SKIN", Vector2(0, text_y + r * 0.08), int(r * 0.05), GOLD)


## A jelly bean (`h` half its height) in burgundy and gold, a tiny prize wheel on its belly.
func _bean(at: Vector2, h: float) -> void:
	var body := PackedVector2Array()
	for k: int in 28:
		var a: float = TAU * float(k) / 28.0
		var y: float = sin(a)
		var w: float = h * (0.62 + 0.1 * y)
		body.append(at + Vector2(cos(a) * w, y * h))
	draw_colored_polygon(body, SLICE_BURGUNDY)
	body.append(body[0])
	draw_polyline(body, GOLD, maxf(h * 0.08, 1.0), true)
	var wc: Vector2 = at + Vector2(0, h * 0.3)
	for k: int in 6:
		var a0: float = _clock * 2.0 + TAU * float(k) / 6.0
		draw_colored_polygon(PackedVector2Array([wc, wc + Vector2(cos(a0), sin(a0)) * h * 0.38, wc + Vector2(cos(a0 + TAU / 6.0), sin(a0 + TAU / 6.0)) * h * 0.38]), SLICE_CREAM if k % 2 == 0 else SLICE_FELT)
	draw_arc(wc, h * 0.38, 0.0, TAU, 20, GOLD, maxf(h * 0.06, 1.0), true)
	draw_circle(at + Vector2(-h * 0.2, -h * 0.45), h * 0.12, Color.WHITE)
	draw_circle(at + Vector2(h * 0.2, -h * 0.45), h * 0.12, Color.WHITE)
	draw_circle(at + Vector2(-h * 0.18, -h * 0.43), h * 0.06, SLICE_JACKPOT)
	draw_circle(at + Vector2(h * 0.22, -h * 0.43), h * 0.06, SLICE_JACKPOT)


## A four-pointed glint.
func _sparkle(at: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 2.0), at + Vector2(s * 0.4, 0), at + Vector2(0, s * 2.0), at + Vector2(-s * 0.4, 0)]), col)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 2.0, 0), at + Vector2(0, s * 0.4), at + Vector2(s * 2.0, 0), at + Vector2(0, -s * 0.4)]), col)


func _coin_index(i: int) -> int:
	var k: int = 0
	for j: int in i:
		if DailyWheel.segment(j)["kind"] == DailyWheel.KIND_COINS:
			k += 1
	return k


func _text(font: Font, txt: String, at: Vector2, px: int, col: Color) -> void:
	var px2: int = maxi(px, 8)
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px2).x
	draw_string(font, at - Vector2(w * 0.5, 0) + Vector2(0, r_shadow()), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px2, Color(0, 0, 0, 0.35))
	draw_string(font, at - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px2, col)


func r_shadow() -> float:
	return maxf(_radius() * 0.006, 1.0)
