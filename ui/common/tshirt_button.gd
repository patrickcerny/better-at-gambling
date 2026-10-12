class_name TShirtButton
extends GearButton
## The clothes button (Patrick: "put in clothes menu (T-shirt icon next to settings gear)"): the
## gear's square button with a T-shirt drawn in code instead of the cog. Opens the `ClothesPanel`.


func _init() -> void:
	super()
	tooltip_text = "Clothes"


func _draw() -> void:
	var hot: bool = has_focus() or is_hovered() or button_pressed
	var col: Color = Palette.VIP_GOLD if hot else Palette.CREAM
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	# Unit outline (x right, y down, about -1..1): collar, sleeves, body.
	var outline: Array[Vector2] = [
		Vector2(-0.24, -0.62), Vector2(-0.66, -0.44), Vector2(-0.9, -0.08), Vector2(-0.6, 0.06),
		Vector2(-0.46, -0.12), Vector2(-0.46, 0.66), Vector2(0.46, 0.66), Vector2(0.46, -0.12),
		Vector2(0.6, 0.06), Vector2(0.9, -0.08), Vector2(0.66, -0.44), Vector2(0.24, -0.62),
	]
	var pts := PackedVector2Array()
	for p: Vector2 in outline:
		pts.append(c + p * r * 0.72)
	# The collar dips in a curve between the shoulders.
	for i: int in range(1, 8):
		var t: float = float(i) / 8.0
		pts.append(c + Vector2(lerpf(0.24, -0.24, t), -0.62 + sin(t * PI) * 0.2) * r * 0.72)
	draw_colored_polygon(pts, col)
