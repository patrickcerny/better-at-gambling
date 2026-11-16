class_name DevButton
extends GearButton
## Developer mode's small corner button in the main menu (Patrick 2026-11-16: "Devmode kleiner
## button unten rechts"): a smaller square than the gear with "</>" drawn in code, above the trophy
## and left of the Daily Spin wheel. Only exists for `DevMode.allowed()`; opens the `DevPanel`.

const SMALL: float = 48.0


func _init() -> void:
	super()
	custom_minimum_size = Vector2(SMALL, SMALL)
	tooltip_text = "Dev dashboard"


func _draw() -> void:
	var hot: bool = has_focus() or is_hovered() or button_pressed
	var col: Color = Palette.VIP_GOLD if hot else Color(Palette.MONEY_GREEN, 0.9)
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	var w: float = maxf(r * 0.11, 2.0)
	var h: float = r * 0.36
	var dx: float = r * 0.28
	# "<"
	draw_polyline(PackedVector2Array([c + Vector2(-dx * 0.9, -h), c + Vector2(-dx * 2.0, 0.0), c + Vector2(-dx * 0.9, h)]), col, w, true)
	# ">"
	draw_polyline(PackedVector2Array([c + Vector2(dx * 0.9, -h), c + Vector2(dx * 2.0, 0.0), c + Vector2(dx * 0.9, h)]), col, w, true)
	# "/"
	draw_line(c + Vector2(dx * 0.35, -h * 1.1), c + Vector2(-dx * 0.35, h * 1.1), col, w, true)
