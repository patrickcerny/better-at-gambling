class_name CoinIcon
extends Control
## The Coin (out-of-match currency, docs/GDD.md "Progression") drawn in code: a gold disc with a
## darker milled rim, a raised inner ring and a bean stamped in the middle, so it never reads as
## a casino chip or a $ bill. `draw_coin` paints it onto any CanvasItem.

const RIM := Color("#B8862B")
const SHINE := Color("#FFE9A3")


static func make(px: float = 28.0) -> CoinIcon:
	var c := CoinIcon.new()
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _draw() -> void:
	draw_coin(self, size * 0.5, minf(size.x, size.y) * 0.5)


## A coin of radius `r` centred on `c`.
static func draw_coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.08), r, Color(0, 0, 0, 0.35))  # drop shadow
	ci.draw_circle(c, r, RIM)
	# Milled edge: little notches round the rim.
	for i: int in 24:
		var a: float = TAU * float(i) / 24.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 0.86, c + d * r * 0.98, RIM.darkened(0.25), maxf(r * 0.06, 1.0))
	ci.draw_circle(c, r * 0.82, Palette.COIN_GOLD)
	ci.draw_arc(c, r * 0.66, 0.0, TAU, 32, RIM, maxf(r * 0.08, 1.0), true)
	# A bean stamped in the middle: two overlapping discs.
	var bean: Color = RIM.darkened(0.05)
	ci.draw_circle(c + Vector2(-r * 0.06, r * 0.12), r * 0.28, bean)
	ci.draw_circle(c + Vector2(r * 0.04, -r * 0.14), r * 0.22, bean)
	# Shine on the upper left.
	ci.draw_arc(c, r * 0.74, PI * 1.05, PI * 1.45, 10, SHINE, maxf(r * 0.1, 1.0), true)
