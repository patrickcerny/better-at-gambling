class_name ShopAwning
extends Control
## The Gift Shop window's top edge: red and cream awning stripes with a scalloped hem, like the
## booth's awning in the Lucky Lounge (`GiftShopKiosk`). Pure drawing, no input.

const STRIPE: float = 56.0
## Height of the hem's half-circles.
const HEM: float = 14.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var count: int = maxi(1, int(round(size.x / STRIPE)))
	var w: float = size.x / count
	var band: float = size.y - HEM
	for i: int in count:
		var c: Color = Palette.CASINO_RED.darkened(0.08) if i % 2 == 0 else Palette.CREAM.darkened(0.05)
		draw_rect(Rect2(i * w, 0, w + 0.5, band), c)
		var pts := PackedVector2Array()
		var steps: int = 12
		for k: int in steps + 1:
			var a: float = PI * float(k) / float(steps)
			pts.append(Vector2(i * w + w * 0.5 + cos(a) * w * 0.5, band + sin(a) * HEM))
		draw_colored_polygon(pts, c)
	# Brass rod along the top, with a soft shade under the stripes.
	draw_rect(Rect2(0, 0, size.x, 5), Palette.WARM_GOLD)
	draw_rect(Rect2(0, band - 4, size.x, 4), Color(0, 0, 0, 0.18))
