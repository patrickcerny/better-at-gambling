class_name SwordRingView
extends Control
## The Sword Tapper overlay's picture of the pedestal top (Patrick: "make the ui the same as the
## game / the 3d model"): the gold rim and the red velvet, the gem lamps round the ring where the
## pedestal has them (index 0, the ruby, at the top; clockwise), each dot sized like its 3D lamp
## (`SwordTapperStation.gem_radius`: the ruby biggest) with the prize for the picked stake beside
## it, and the stone in the middle with the multiplier rule on it. `lit` lights dots gold the way
## the pedestal lights its lamps (the overlay copies the pedestal's `lit` every frame).

## Share of the radius (the rim's outside) where the dots sit, from the 3D ring.
const GEM_AT: float = SwordTapperStation.GEM_R / SwordTapperStation.DISC_R
const RIM: float = 0.06
const FONT_SIZE: int = 15

## Prize text for each gem, in ring order ("$125", "$2.50").
var prizes: PackedStringArray = PackedStringArray()
## Ring indices lit right now.
var lit: Array[int] = []
## Small text on the stone (the multiplier rule).
var centre_text: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The prizes for a stake of `amount` (whole dollars).
func set_stake(amount: int) -> void:
	var out := PackedStringArray()
	for v: float in Registry.balance.sword_ring:
		out.append(SwordTapperStation.cents_text(roundi(v * 100.0) * amount))
	if out != prizes:
		prizes = out
		queue_redraw()


func set_lit(p_lit: Array[int]) -> void:
	if p_lit != lit:
		lit = p_lit.duplicate()
		queue_redraw()


## Where gem `i`'s dot sits (local pixels).
func gem_point(i: int) -> Vector2:
	return _at(i, GEM_AT)


## Gem `i`'s dot radius in pixels: the 3D lamp's radius at this picture's scale, never under 4 px.
func gem_px(i: int) -> float:
	return maxf(SwordTapperStation.gem_radius(i) / SwordTapperStation.DISC_R * _radius(), 4.0)


## The dot's colour: the ruby always red (brighter lit), the others warm white, gold when lit.
func gem_color(i: int) -> Color:
	var on: bool = i in lit
	if SwordTapperStation.is_ruby(i):
		return SwordTapperStation.RUBY.lightened(0.25) if on else SwordTapperStation.RUBY
	return SwordTapperStation.GEM_LIT if on else SwordTapperStation.GEM_IDLE.darkened(0.25)


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 2.0


func _at(i: int, share: float) -> Vector2:
	var n: int = maxi(Registry.balance.sword_ring.size(), 1)
	var a: float = TAU * i / n
	return size * 0.5 + Vector2(sin(a), -cos(a)) * _radius() * share


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = _radius()
	draw_circle(c, r, Palette.WARM_GOLD)  # the brass rim
	draw_circle(c, r * (1.0 - RIM), SwordTapperStation.VELVET.lerp(Palette.CASINO_RED, 0.55))  # the velvet, as it looks lit
	draw_arc(c, r * (1.0 - RIM * 0.5), 0.0, TAU, 64, Palette.VIP_GOLD.lightened(0.2), 1.5, true)
	# The stone in the middle (a rough octagon, like the rock).
	var stone := PackedVector2Array()
	for k: int in 8:
		var a: float = TAU * (k + 0.5) / 8.0
		stone.append(c + Vector2(cos(a), sin(a)) * r * (0.27 + 0.025 * float(k % 2)))
	draw_colored_polygon(stone, Color("#D9C9A8"))
	var font: Font = get_theme_default_font()
	if centre_text != "":
		var lines: PackedStringArray = centre_text.split("\n")
		var y0: float = c.y - (lines.size() - 1) * FONT_SIZE * 0.6
		for k: int in lines.size():
			draw_string(font, Vector2(c.x - r * 0.3, y0 + k * FONT_SIZE * 1.2 + FONT_SIZE * 0.35), lines[k], HORIZONTAL_ALIGNMENT_CENTER, r * 0.6, FONT_SIZE - 1, Palette.CASINO_BLACK)
	for i: int in Registry.balance.sword_ring.size():
		var p: Vector2 = gem_point(i)
		var g: float = gem_px(i)
		var on: bool = i in lit
		if on:
			draw_circle(p, g * 1.9, Color(SwordTapperStation.GEM_LIT, 0.35))  # the glow
		draw_circle(p, g + 2.5, Palette.WARM_GOLD)  # the brass setting
		draw_circle(p, g, gem_color(i))
		if i < prizes.size():
			# Just inside the dot, its near edge clear of it whichever way the ring turns there.
			var text: Vector2 = font.get_string_size(prizes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			var out: Vector2 = (p - c).normalized()
			var gap: float = g + 5.0 + absf(out.x) * text.x * 0.5 + absf(out.y) * FONT_SIZE * 0.45
			var lp: Vector2 = p - out * gap
			var col: Color = Palette.VIP_GOLD if on else Palette.CREAM
			var base := Vector2(lp.x - text.x * 0.5, lp.y + FONT_SIZE * 0.35)
			draw_string_outline(font, base, prizes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0.2, 0.03, 0.05))
			draw_string(font, base, prizes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
