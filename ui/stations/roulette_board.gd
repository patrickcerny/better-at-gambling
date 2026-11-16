class_name RouletteBoard
extends Control
## The roulette betting layout, drawn: the zero on top, 12 rows of three numbers, the columns'
## 2:1 at the foot and the dozens and even-money boxes in two columns on the left, like the felt
## seen from the chair (RouletteStation lays the 3D felt out the same way, turned a quarter).
##
## Every bet of a real table is here, by where the mouse is: the middle of a number is the number
## (35:1), its side or top line a split of the two numbers it divides (17:1), a cross of lines a
## corner (8:1), the outer left edge of a row its street (11:1) and the edge between two rows a
## six line (5:1); the zero's edge splits it with 1, 2 or 3, and the outer corner by 1 is the
## first four 0-1-2-3 (8:1). Hovering lights the numbers the bet covers and names it with its
## payout; chips show where everybody's bets sit.

signal spot_clicked(type: StringName, value: int)
signal hover_changed(type: StringName, value: int)

const EVEN_W: float = 64.0
const DOZEN_W: float = 46.0
const CELL: Vector2 = Vector2(68.0, 30.0)
const ZERO_H: float = 34.0
## How close to a line (px) the mouse has to be to bet on the line instead of the number.
const EDGE: float = 8.0
const EVEN_SPOTS: Array[StringName] = [&"low", &"even", &"red", &"black", &"odd", &"high"]
const EVEN_TEXT: Array[String] = ["1-18", "EVEN", "RED", "BLACK", "ODD", "19-36"]

const FELT := Color("#1E5A43")
const LINE := Color("#E9DDBF")
const RED_TILE := Color("#B8312F")
const BLACK_TILE := Color("#1B1817")

## Bets on the layout: {player, type, value, amount} (the public state's list).
var bets: Array = []
var local_id: int = -1
## Player id → chip colour for other players' chips.
var color_of: Callable
## The number the ball landed in (lit while the result shows), -1 = none.
var winning: int = -1
## False while bets are closed: no hover, no clicks.
var open: bool = true:
	set(v):
		open = v
		if not open:
			_set_hover(&"", 0)
		queue_redraw()

var hover_type: StringName = &""
var hover_value: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(grid_x() + CELL.x * 3 + 2, ZERO_H + CELL.y * 13 + 2)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func() -> void: _set_hover(&"", 0))


static func grid_x() -> float:
	return EVEN_W + DOZEN_W


## Top-left of the board inside the control (it is centred when the control is wider).
func origin() -> Vector2:
	return Vector2(floorf((size.x - custom_minimum_size.x) * 0.5) + 1.0, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit: Array = spot_at((event as InputEventMouseMotion).position)
		_set_hover(hit[0], hit[1])
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var hit: Array = spot_at((event as InputEventMouseButton).position)
		if open and hit[0] != &"":
			spot_clicked.emit(hit[0], hit[1])
			accept_event()


func _set_hover(type: StringName, value: int) -> void:
	if not open:
		type = &""
	if type == hover_type and value == hover_value:
		return
	hover_type = type
	hover_value = value
	queue_redraw()
	hover_changed.emit(type, value)


## The bet under a point of the control: [type, value], or [&"", 0] off the layout.
func spot_at(p: Vector2) -> Array:
	var q: Vector2 = p - origin()
	var gx: float = grid_x()
	var grid_h: float = CELL.y * 12
	if q.x < 0 or q.y < 0:
		return [&"", 0]
	# The outside columns on the left, beside the numbers.
	if q.x < gx and q.y >= ZERO_H and q.y < ZERO_H + grid_h:
		var row: int = int((q.y - ZERO_H) / CELL.y)
		if q.x < EVEN_W:
			return [EVEN_SPOTS[clampi(row / 2, 0, 5)], 0]
		return [&"dozen", clampi(row / 4, 0, 2) + 1]
	var lx: float = q.x - gx
	if lx < 0 or lx > CELL.x * 3:
		return [&"", 0]
	if q.y < ZERO_H - EDGE:
		return [&"straight", 0]
	if q.y >= ZERO_H + grid_h:
		if q.y > ZERO_H + grid_h + CELL.y:
			return [&"", 0]
		return [&"column", clampi(int(lx / CELL.x), 0, 2) + 1]
	var ly: float = q.y - ZERO_H
	var c: int = clampi(int(lx / CELL.x), 0, 2)
	var r: int = clampi(int(ly / CELL.y), 0, 11)
	var fx: float = lx - c * CELL.x
	var fy: float = ly - r * CELL.y
	var left: bool = fx < EDGE
	var top: bool = fy < EDGE
	if fx > CELL.x - EDGE and c < 2:
		c += 1
		left = true
	if fy > CELL.y - EDGE and r < 11:
		r += 1
		top = true
	if ly < 0:  # the zero's lower edge, just above the first row
		top = true
		r = 0
	if left and top:
		if c > 0 and r > 0:
			return [&"corner", _n(r - 1, c - 1)]
		if c == 0 and r > 0:
			return [&"line", _n(r - 1, 0)]
		if c == 0 and r == 0:
			return [&"corner", 0]
		return [&"split", RouletteLogic.split_value(0, _n(0, c))]
	if left:
		if c > 0:
			return [&"split", RouletteLogic.split_value(_n(r, c - 1), _n(r, c))]
		return [&"street", _n(r, 0)]
	if top:
		if r > 0:
			return [&"split", RouletteLogic.split_value(_n(r - 1, c), _n(r, c))]
		return [&"split", RouletteLogic.split_value(0, _n(0, c))]
	return [&"straight", _n(r, c)]


static func _n(row: int, col: int) -> int:
	return row * 3 + col + 1


## Rect of number `n` (0 = the zero across the top) in control coordinates.
func number_rect(n: int) -> Rect2:
	var o: Vector2 = origin() + Vector2(grid_x(), 0)
	if n == 0:
		return Rect2(o, Vector2(CELL.x * 3, ZERO_H))
	var r: int = (n - 1) / 3
	var c: int = (n - 1) % 3
	return Rect2(o + Vector2(c * CELL.x, ZERO_H + r * CELL.y), CELL)


## Rect of an outside box (dozen, column, even-money).
func outside_rect(type: StringName, value: int) -> Rect2:
	var o: Vector2 = origin()
	match type:
		&"dozen":
			return Rect2(o + Vector2(EVEN_W, ZERO_H + (value - 1) * CELL.y * 4), Vector2(DOZEN_W, CELL.y * 4))
		&"column":
			return Rect2(o + Vector2(grid_x() + (value - 1) * CELL.x, ZERO_H + CELL.y * 12), CELL)
	var i: int = maxi(EVEN_SPOTS.find(type), 0)
	return Rect2(o + Vector2(0, ZERO_H + i * CELL.y * 2), Vector2(EVEN_W, CELL.y * 2))


## Where a bet's chip sits (control coordinates): a number's middle, the line or cross between
## the numbers of a split or corner, the outer edge for a street or six line, a box's middle.
func spot_point(type: StringName, value: int) -> Vector2:
	match type:
		&"straight":
			return number_rect(value).get_center()
		&"split", &"corner", &"street", &"line":
			var nums: Array[int] = RouletteLogic.covered(type, value)
			if nums.is_empty():
				return number_rect(0).get_center()
			var gx: float = origin().x + grid_x()
			if type == &"corner" and value == 0:
				return Vector2(gx, origin().y + ZERO_H)
			if type == &"split" and nums[0] == 0:
				return Vector2(number_rect(nums[1]).get_center().x, origin().y + ZERO_H)
			var sum := Vector2.ZERO
			for n: int in nums:
				sum += number_rect(n).get_center()
			var at: Vector2 = sum / nums.size()
			if type == &"street" or type == &"line":
				at.x = gx
			return at
	return outside_rect(type, value).get_center()


## A spot's point in global (screen) coordinates.
func spot_global(type: StringName, value: int) -> Vector2:
	return get_global_transform() * spot_point(type, value)


## Numbers that win a bet (for the hover light): the inside bet's own, or every number an
## outside bet pays on.
static func winners(type: StringName, value: int) -> Array[int]:
	if type == &"":
		return []
	var out: Array[int] = []
	for n: int in 37:
		if RouletteLogic.wins(type, value, n):
			out.append(n)
	return out


func _draw() -> void:
	var o: Vector2 = origin()
	var full := Rect2(o - Vector2(1, 1), custom_minimum_size)
	var felt := StyleBoxFlat.new()
	felt.bg_color = FELT
	felt.set_corner_radius_all(6)
	felt.shadow_color = Color(0, 0, 0, 0.35)
	felt.shadow_size = 6
	draw_style_box(felt, full.grow(4))
	var lit: Array[int] = winners(hover_type, hover_value)
	var font: Font = TableSkin.black_font()
	# The zero.
	var zr: Rect2 = number_rect(0)
	_tile(zr, FELT.lightened(0.12), "0", font, 22, 0 in lit, winning == 0)
	for n: int in range(1, 37):
		_tile(number_rect(n), RED_TILE if n in RouletteLogic.RED else BLACK_TILE, str(n), font, 19, n in lit, winning == n)
	for d: int in [1, 2, 3]:
		_box(outside_rect(&"dozen", d), ["1st 12", "2nd 12", "3rd 12"][d - 1], hover_type == &"dozen" and hover_value == d, true)
	for c: int in [1, 2, 3]:
		_box(outside_rect(&"column", c), "2 : 1", hover_type == &"column" and hover_value == c, false)
	for i: int in EVEN_SPOTS.size():
		var t: StringName = EVEN_SPOTS[i]
		var r: Rect2 = outside_rect(t, 0)
		var hot: bool = hover_type == t
		if t == &"red" or t == &"black":
			_box(r, "", hot, false)
			var dc: Vector2 = r.get_center()
			var w: float = r.size.x * 0.32
			var hgt: float = r.size.y * 0.3
			draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -hgt), dc + Vector2(w, 0), dc + Vector2(0, hgt), dc + Vector2(-w, 0)]), RED_TILE if t == &"red" else BLACK_TILE)
			draw_polyline(PackedVector2Array([dc + Vector2(0, -hgt), dc + Vector2(w, 0), dc + Vector2(0, hgt), dc + Vector2(-w, 0), dc + Vector2(0, -hgt)]), LINE, 1.0, true)
		else:
			_box(r, EVEN_TEXT[i], hot, true)
	_draw_chips()
	if hover_type != &"" and hover_type != &"straight" and RouletteLogic.MULTI_INSIDE.has(hover_type):
		# A ghost chip where the bet would go.
		var p: Vector2 = spot_point(hover_type, hover_value)
		draw_circle(p, 9.0, Color(Palette.VIP_GOLD, 0.55))
		draw_arc(p, 9.0, 0, TAU, 24, Palette.CREAM, 1.5, true)


func _tile(r: Rect2, color: Color, text: String, font: Font, fs: int, lit: bool, win: bool) -> void:
	var inner: Rect2 = r.grow(-1.5)
	draw_rect(inner, color)
	draw_rect(r, LINE, false, 1.0)
	if lit:
		draw_rect(inner, Color(Palette.VIP_GOLD, 0.42))
	if win:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		draw_rect(inner, Color(Palette.VIP_GOLD, 0.35 + 0.3 * pulse))
		draw_rect(r.grow(1.0), Palette.VIP_GOLD, false, 3.0)
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var ink: Color = Palette.CASINO_BLACK if (lit or win) and color != BLACK_TILE else Palette.CREAM
	draw_string(font, r.get_center() + Vector2(-ts.x * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


func _box(r: Rect2, text: String, hot: bool, vertical: bool) -> void:
	if hot:
		draw_rect(r.grow(-1.5), Color(Palette.VIP_GOLD, 0.38))
	draw_rect(r, LINE, false, 1.0)
	if text == "":
		return
	var font: Font = TableSkin.heavy_font()
	var fs: int = 15
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if vertical and r.size.y > r.size.x * 1.4:
		draw_set_transform(r.get_center(), -PI * 0.5)
		draw_string(font, Vector2(-ts.x * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LINE)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_string(font, r.get_center() + Vector2(-ts.x * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LINE)


## Everybody's chips: yours as a gold chip with your total on that spot, other players' as small
## chips in their colours beside it.
func _draw_chips() -> void:
	var mine: Dictionary = {}
	var others: Dictionary = {}
	var order: Array[String] = []
	for b: Variant in bets:
		if not b is Dictionary:
			continue
		var d: Dictionary = b
		var key: String = "%s:%d" % [d.get("type", ""), int(d.get("value", 0))]
		if not key in order:
			order.append(key)
		if int(d.get("player", -1)) == local_id:
			mine[key] = int(mine.get(key, 0)) + int(d.get("amount", 0))
		else:
			if not others.has(key):
				others[key] = []
			if not int(d["player"]) in others[key]:
				(others[key] as Array).append(int(d["player"]))
	var font: Font = TableSkin.black_font()
	for key: String in order:
		var parts: PackedStringArray = key.split(":")
		var p: Vector2 = spot_point(StringName(parts[0]), int(parts[1]))
		if others.has(key):
			var list: Array = others[key]
			for i: int in mini(list.size(), 3):
				var col: Color = color_of.call(int(list[i])) if color_of.is_valid() else Palette.CREAM
				var at: Vector2 = p + Vector2(10 + i * 5, -8 + i * 3)
				TableSkin.draw_chip(self, at, 7.0, col, Palette.CREAM)
		if mine.has(key):
			var amount: int = int(mine[key])
			TableSkin.draw_chip(self, p, 12.0, Color("#C8963A"), Palette.CREAM)
			var t: String = _short(amount)
			var fs: int = 11 if t.length() <= 3 else 9
			var ts: Vector2 = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, p + Vector2(-ts.x * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.CASINO_BLACK)


## "50", "1.2k", "15k" (fits on a chip).
static func _short(n: int) -> String:
	if n >= 10000:
		return "%dk" % (n / 1000)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


func _process(_delta: float) -> void:
	if winning >= 0:
		queue_redraw()  # the winning number pulses
