class_name ScratchCardView
extends Control
## The scratch card, big on screen: a cream card with the tier's coloured header and price, the
## 3×3 grid of symbols under silver foil, and the prize table printed underneath (the same table
## the server pays by). Drag with the left mouse button to scratch the foil off: it comes away
## under the coin with a scratchy sound and foil flakes; once most of a cell is bare the rest of
## its foil pops off. `reveal_all` scratches every cell for you, one after another. The prize
## stamp only shows once the whole card is bare.

signal cell_revealed(index: int)
signal all_revealed

const CARD_SIZE: Vector2 = Vector2(500, 750)
const HEADER_H: float = 92.0
const GRID_TOP: float = 146.0
const CELL: float = 124.0
const GAP: float = 14.0
const GRID_SIZE: float = CELL * 3.0 + GAP * 2.0
const GRID_X: float = (CARD_SIZE.x - GRID_SIZE) * 0.5
const PAY_TOP: float = GRID_TOP + GRID_SIZE + 20.0
## Screen pixels per foil pixel, and the coin's radius in screen pixels.
const FOIL_SCALE: int = 4
const BRUSH: float = 22.0
## A cell's last foil pops off once less than this share of it is left.
const POP_AT: float = 0.45
## Seconds between cells when REVEAL ALL scratches the card.
const REVEAL_STEP: float = 0.075
const FOIL_A: Color = Color("#BDB6A6")
const FOIL_B: Color = Color("#E4DCC8")
const INK: Color = Color("#2A2320")

## Symbols on the card (empty = no card yet: a face-down sample of the tier).
var symbols: Array[int] = []
var tier: int = 0
var price: int = 10
## True while the foil can be scratched.
var interactive: bool = false
var revealed: Array[bool] = []
var prize_label: Label
## Foil pixels still covering each cell, and how many each cell has under fresh foil.
var covered: Array[int] = []
var cell_pixels: Array[int] = []
var flakes: Array[Dictionary] = []
var _foil: Image
var _foil_tex: ImageTexture
var _foil_dirty: bool = false
## Foil pixel → cell index (−1 in the gaps between cells).
var _cell_of: PackedInt32Array = PackedInt32Array()
var _foil_w: int = 0
var _scratching: bool = false
var _last_pos: Vector2 = Vector2.ZERO
var _sfx_cooldown: float = 0.0
var _reveal_queue: Array[int] = []
var _reveal_timer: float = 0.0
var _font: Font
var _all_sent: bool = false


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_font = Vfx.font()
	_foil_w = int(ceil(GRID_SIZE / FOIL_SCALE))
	_cell_of.resize(_foil_w * _foil_w)
	cell_pixels.resize(ScratchLogic.CELLS)
	cell_pixels.fill(0)
	for py: int in _foil_w:
		for px: int in _foil_w:
			var c: int = _cell_at(Vector2(px + 0.5, py + 0.5) * FOIL_SCALE)
			_cell_of[py * _foil_w + px] = c
			if c >= 0:
				cell_pixels[c] += 1
	prize_label = Label.new()
	prize_label.name = "Prize"
	prize_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prize_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prize_label.add_theme_font_override(&"font", _font)
	prize_label.add_theme_font_size_override(&"font_size", 72)
	prize_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	prize_label.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	prize_label.add_theme_constant_override(&"outline_size", 18)
	prize_label.position = Vector2(GRID_X - 20.0, GRID_TOP + GRID_SIZE * 0.5 - 60.0)
	prize_label.size = Vector2(GRID_SIZE + 40.0, 120.0)
	prize_label.pivot_offset = prize_label.size * 0.5
	prize_label.rotation = deg_to_rad(-8.0)
	prize_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prize_label.visible = false
	add_child(prize_label)
	_reset_foil()


## A new card to scratch: fresh foil over `p_symbols`.
func set_card(p_symbols: Array[int], p_tier: int, p_price: int) -> void:
	symbols = p_symbols.duplicate()
	tier = p_tier
	price = p_price
	interactive = true
	_reset_foil()


## No card bought yet: the tier's card face down (foil on, nothing under it), not scratchable.
func set_preview(p_tier: int, p_price: int) -> void:
	symbols = []
	tier = p_tier
	price = p_price
	interactive = false
	_reset_foil()


## A card that is already bare (it paid while the panel was closed).
func show_revealed(p_symbols: Array[int], p_tier: int, p_price: int) -> void:
	set_card(p_symbols, p_tier, p_price)
	for i: int in ScratchLogic.CELLS:
		_pop(i, false)
	interactive = false
	_check_done()


## Scratches every cell still under foil, one after another (`fast`: all at once).
func reveal_all(fast: bool = false) -> void:
	if symbols.is_empty():
		return
	interactive = false
	_reveal_queue.clear()
	for i: int in ScratchLogic.CELLS:
		if not revealed[i]:
			_reveal_queue.append(i)
	if fast:
		while not _reveal_queue.is_empty():
			_pop(_reveal_queue.pop_front(), false)
		_check_done()
	else:
		_reveal_timer = 0.0


## True once every cell is bare.
func is_fully_revealed() -> bool:
	return not symbols.is_empty() and not revealed.has(false)


## Share of a cell's foil still on (1 = untouched, 0 = bare).
func foil_left(cell: int) -> float:
	return covered[cell] / float(cell_pixels[cell]) if cell_pixels[cell] > 0 else 0.0


## Top-left of a cell in this control.
static func cell_rect(cell: int) -> Rect2:
	var col: int = cell % 3
	var row: int = cell / 3
	return Rect2(Vector2(GRID_X + col * (CELL + GAP), GRID_TOP + row * (CELL + GAP)), Vector2(CELL, CELL))


## Scratches a stroke from `from` to `to` (local), coin-sized; returns the foil pixels removed.
func scratch_stroke(from: Vector2, to: Vector2) -> int:
	if not interactive or symbols.is_empty():
		return 0
	var removed: int = 0
	var dist: float = from.distance_to(to)
	var steps: int = maxi(1, int(ceil(dist / (BRUSH * 0.4))))
	for i: int in steps + 1:
		removed += _erase(from.lerp(to, i / float(steps)))
	if removed > 0:
		_spawn_flakes(to, clampi(removed / 6, 1, 6), (to - from).normalized())
		if _sfx_cooldown <= 0.0:
			Audio.play(&"scratch", &"SFX", -6.0, randf_range(0.9, 1.15))
			_sfx_cooldown = 0.075
	for c: int in ScratchLogic.CELLS:
		if not revealed[c] and foil_left(c) < POP_AT:
			_pop(c, true)
	_check_done()
	return removed


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_scratching = mb.pressed and interactive
			_last_pos = mb.position
			if _scratching:
				scratch_stroke(mb.position, mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _scratching and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			scratch_stroke(_last_pos, mm.position)
			_last_pos = mm.position
			accept_event()
		elif _scratching:
			_scratching = false


func _process(delta: float) -> void:
	_sfx_cooldown -= delta
	if not _reveal_queue.is_empty():
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			_reveal_timer = REVEAL_STEP
			_pop(_reveal_queue.pop_front(), true)
			_check_done()
	if not flakes.is_empty():
		var g: float = 1400.0
		for f: Dictionary in flakes:
			var v: Vector2 = f["v"]
			v.y += g * delta
			v *= 1.0 - 1.5 * delta
			f["v"] = v
			f["p"] = (f["p"] as Vector2) + v * delta
			f["r"] = float(f["r"]) + float(f["spin"]) * delta
			f["life"] = float(f["life"]) - delta
		flakes = flakes.filter(func(f: Dictionary) -> bool: return float(f["life"]) > 0.0)
		queue_redraw()
	if _foil_dirty and _foil_tex != null:
		_foil_tex.update(_foil)
		_foil_dirty = false
		queue_redraw()


func _draw() -> void:
	var col: Color = ScratchStation.TIER_COLORS[clampi(tier, 0, 2)]
	var card := StyleBoxFlat.new()
	card.bg_color = Palette.CREAM
	card.border_color = col
	card.set_border_width_all(7)
	card.set_corner_radius_all(18)
	card.shadow_color = Color(0, 0, 0, 0.45)
	card.shadow_size = 14
	draw_style_box(card, Rect2(Vector2.ZERO, CARD_SIZE))
	var head := StyleBoxFlat.new()
	head.bg_color = col
	head.corner_radius_top_left = 14
	head.corner_radius_top_right = 14
	draw_style_box(head, Rect2(Vector2(5, 5), Vector2(CARD_SIZE.x - 10, HEADER_H)))
	draw_rect(Rect2(Vector2(5, HEADER_H + 1), Vector2(CARD_SIZE.x - 10, 4)), Palette.WARM_GOLD)
	_text(ScratchStation.TIER_NAMES[clampi(tier, 0, 2)], Vector2(28, 62), 44, Palette.CREAM, HORIZONTAL_ALIGNMENT_LEFT, 330.0)
	draw_circle(Vector2(CARD_SIZE.x - 66, 50), 38, Palette.VIP_GOLD)
	draw_arc(Vector2(CARD_SIZE.x - 66, 50), 38, 0.0, TAU, 40, Palette.CASINO_BLACK.lightened(0.15), 3.0, true)
	_text("$%d" % price, Vector2(CARD_SIZE.x - 104, 62), 32 if price < 100 else 24, Palette.CASINO_BLACK, HORIZONTAL_ALIGNMENT_CENTER, 76.0)
	_text("3 IN A ROW, COLUMN OR DIAGONAL WINS  ·  $ = INSTANT WIN", Vector2(0, 130), 17, INK.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER, CARD_SIZE.x)
	for i: int in ScratchLogic.CELLS:
		var r: Rect2 = cell_rect(i)
		var cell := StyleBoxFlat.new()
		cell.bg_color = Color("#FBF4E4")
		cell.border_color = Color(Palette.WARM_GOLD, 0.8)
		cell.set_border_width_all(2)
		cell.set_corner_radius_all(10)
		draw_style_box(cell, r)
		if i < symbols.size():
			_draw_symbol(symbols[i], r.grow(-14.0))
	if _foil_tex != null:
		draw_texture_rect(_foil_tex, Rect2(Vector2(GRID_X, GRID_TOP), Vector2(_foil_w, _foil_w) * FOIL_SCALE), false)
	if is_fully_revealed():
		_draw_wins()
	_draw_prize_table(col)
	for f: Dictionary in flakes:
		var a: float = clampf(float(f["life"]) / 0.35, 0.0, 1.0)
		var c: Color = f["c"]
		c.a = a
		var s: float = f["s"]
		draw_set_transform(f["p"], f["r"])
		draw_rect(Rect2(Vector2(-s, -s * 0.6), Vector2(s * 2.0, s * 1.2)), c)
	draw_set_transform(Vector2.ZERO, 0.0)


## Gold bars through every winning line and rings round every "$".
func _draw_wins() -> void:
	for li: int in ScratchLogic.winning_lines(symbols):
		var l: Array = ScratchLogic.LINES[li]
		var a: Vector2 = cell_rect(int(l[0])).get_center()
		var b: Vector2 = cell_rect(int(l[2])).get_center()
		draw_line(a, b, Color(Palette.CASINO_BLACK, 0.4), 22.0, true)
		draw_line(a, b, Color(Palette.VIP_GOLD, 0.9), 14.0, true)
	for i: int in symbols.size():
		if symbols[i] == ScratchLogic.Sym.CASH:
			draw_arc(cell_rect(i).get_center(), CELL * 0.48, 0.0, TAU, 40, Palette.MONEY_GREEN, 6.0, true)


## The printed prize table: every line prize in dollars for this card's price, highest first, and
## the instant "$" prize.
func _draw_prize_table(col: Color) -> void:
	_text("PRIZES", Vector2(0, PAY_TOP + 8), 20, col.darkened(0.1), HORIZONTAL_ALIGNMENT_CENTER, CARD_SIZE.x)
	var rows: Array[Dictionary] = ScratchCardView.prize_rows(Registry.balance, tier, price)
	for k: int in rows.size():
		var row: Dictionary = rows[k]
		var x: float = 34.0 + (k % 2) * 226.0
		if k == rows.size() - 1 and k % 2 == 0:
			x = 147.0  # the instant prize, centred on its own row
		var y: float = PAY_TOP + 20.0 + (k / 2) * 34.0
		var sym: int = int(row["symbol"])
		if sym == ScratchLogic.Sym.CASH:
			_draw_symbol(sym, Rect2(Vector2(x, y), Vector2(26, 26)))
			_text("ANYWHERE", Vector2(x + 32, y + 20), 16, INK, HORIZONTAL_ALIGNMENT_LEFT, 90.0)
		else:
			for j: int in 3:
				_draw_symbol(sym, Rect2(Vector2(x + j * 27.0, y), Vector2(26, 26)))
		_text("$%s" % Hud._thousands(int(row["amount"])), Vector2(x + 92, y + 21), 22, INK, HORIZONTAL_ALIGNMENT_RIGHT, 110.0)
	_text("PAID AS PRINTED  ·  LUCKY LOUNGE", Vector2(0, CARD_SIZE.y - 12), 13, INK.lightened(0.45), HORIZONTAL_ALIGNMENT_CENTER, CARD_SIZE.x)


## The printed prize rows for a card: {symbol, amount}, line prizes highest first, then "$".
static func prize_rows(cfg: BalanceConfig, p_tier: int, p_price: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pays: PackedFloat32Array = cfg.scratch_pays(p_tier)
	for s: int in range(ScratchLogic.LINE_SYMBOLS - 1, -1, -1):
		out.append({"symbol": s, "amount": ScratchLogic.prize(p_price, pays[s])})
	out.append({"symbol": ScratchLogic.Sym.CASH, "amount": ScratchLogic.prize(p_price, cfg.scratch_cash_pays[p_tier])})
	return out


func _draw_symbol(sym: int, r: Rect2) -> void:
	if sym == ScratchLogic.Sym.CASH:
		var c: Vector2 = r.get_center()
		var rad: float = minf(r.size.x, r.size.y) * 0.5
		draw_circle(c, rad, Palette.WARM_GOLD.darkened(0.15))
		draw_circle(c, rad * 0.86, Palette.VIP_GOLD)
		draw_arc(c, rad * 0.72, 0.0, TAU, 32, Palette.WARM_GOLD.darkened(0.2), maxf(1.0, rad * 0.06), true)
		_text("$", Vector2(c.x - rad, c.y + rad * 0.42), int(rad * 1.25), Palette.FELT_GREEN.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0)
		return
	var tex: Texture2D = ScratchCardView.symbol_texture(sym)
	if tex != null:
		draw_texture_rect(tex, r, false)


## Picture for a line symbol (the slot machine's reel art); null for the "$" (drawn as a coin).
static func symbol_texture(sym: int) -> Texture2D:
	if sym < 0 or sym >= ScratchLogic.LINE_SYMBOLS:
		return null
	return SlotReelsFx.SYMBOL_TEXTURES.get(ScratchLogic.SYMBOL_NAMES[sym], null)


func _text(t: String, pos: Vector2, font_size: int, color: Color, align: HorizontalAlignment, width: float) -> void:
	draw_string(_font, pos, t, align, width, font_size, color)


func _cell_at(p: Vector2) -> int:
	for i: int in ScratchLogic.CELLS:
		var r: Rect2 = cell_rect(i)
		if r.has_point(p + Vector2(GRID_X, GRID_TOP)):
			return i
	return -1


## Fresh foil over every cell: a warm silver with a fine diamond lattice and a little grain.
func _reset_foil() -> void:
	if _foil_w <= 0:
		return
	_foil = Image.create(_foil_w, _foil_w, false, Image.FORMAT_RGBA8)
	covered = cell_pixels.duplicate()
	revealed.resize(ScratchLogic.CELLS)
	revealed.fill(false)
	for py: int in _foil_w:
		for px: int in _foil_w:
			if _cell_of[py * _foil_w + px] < 0:
				_foil.set_pixel(px, py, Color(0, 0, 0, 0))
				continue
			var grain: float = float(posmod(px * 7919 + py * 104729 + px * py * 31, 97)) / 97.0
			var c: Color = FOIL_A.lerp(FOIL_B, 0.35 + 0.4 * grain + 0.25 * sin((px + py) * 0.18))
			if posmod(px + py, 7) == 0 or posmod(px - py, 7) == 0:
				c = c.darkened(0.12)
			_foil.set_pixel(px, py, c)
	if _foil_tex == null:
		_foil_tex = ImageTexture.create_from_image(_foil)
	else:
		_foil_tex.update(_foil)
	flakes.clear()
	_reveal_queue.clear()
	_scratching = false
	_all_sent = false
	if prize_label != null:
		prize_label.visible = false
	queue_redraw()


## Removes the foil under the coin at `p` (local); returns how many foil pixels came off.
func _erase(p: Vector2) -> int:
	var c: Vector2 = (p - Vector2(GRID_X, GRID_TOP)) / FOIL_SCALE
	var r: float = BRUSH / FOIL_SCALE
	var removed: int = 0
	for py: int in range(maxi(0, int(c.y - r)), mini(_foil_w, int(c.y + r) + 1)):
		for px: int in range(maxi(0, int(c.x - r)), mini(_foil_w, int(c.x + r) + 1)):
			if Vector2(px + 0.5, py + 0.5).distance_squared_to(c) > r * r:
				continue
			var cell: int = _cell_of[py * _foil_w + px]
			if cell < 0 or revealed[cell] or _foil.get_pixel(px, py).a <= 0.0:
				continue
			_foil.set_pixel(px, py, Color(0, 0, 0, 0))
			covered[cell] -= 1
			removed += 1
	if removed > 0:
		_foil_dirty = true
	return removed


## A cell's last foil comes off at once (with a puff of flakes when `burst`).
func _pop(cell: int, burst: bool) -> void:
	if cell < 0 or cell >= revealed.size() or revealed[cell]:
		return
	revealed[cell] = true
	covered[cell] = 0
	var r: Rect2 = cell_rect(cell)
	for py: int in _foil_w:
		for px: int in _foil_w:
			if _cell_of[py * _foil_w + px] == cell:
				_foil.set_pixel(px, py, Color(0, 0, 0, 0))
	_foil_dirty = true
	if burst:
		_spawn_flakes(r.get_center(), 14, Vector2.ZERO, r.size * 0.4)
		Audio.play(&"scratch", &"SFX", -10.0, randf_range(1.15, 1.3))
	cell_revealed.emit(cell)
	queue_redraw()


func _check_done() -> void:
	if _all_sent or not is_fully_revealed():
		return
	_all_sent = true
	interactive = false
	_scratching = false
	queue_redraw()
	all_revealed.emit()


func _spawn_flakes(at: Vector2, count: int, dir: Vector2, spread: Vector2 = Vector2(6, 6)) -> void:
	for i: int in count:
		if flakes.size() > 220:
			break
		var v := Vector2(randf_range(-160.0, 160.0), randf_range(-260.0, -60.0)) + dir * 140.0
		flakes.append({
			"p": at + Vector2(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y)),
			"v": v, "r": randf() * TAU, "spin": randf_range(-14.0, 14.0), "s": randf_range(2.0, 4.5),
			"life": randf_range(0.45, 0.9), "c": FOIL_A.lerp(FOIL_B, randf()).darkened(randf() * 0.2),
		})
	queue_redraw()
