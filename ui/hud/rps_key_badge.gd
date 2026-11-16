class_name RpsKeyBadge
extends Control
## Which input picks a duel card, following the last device: a brass keycap with the key on
## keyboard + mouse, a little d-pad with the right arm lit on a gamepad.

var action: StringName
var fallback: String


func _init(p_action: StringName = &"", p_fallback: String = "") -> void:
	action = p_action
	fallback = p_fallback
	custom_minimum_size = Vector2(44, 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _key_text() -> String:
	var k: String = InputGlyphs.key(action) if action != &"" else "?"
	return fallback if k == "?" or k == "" else k


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var k: String = _key_text()
	if InputGlyphs.gamepad and k.begins_with("D-pad"):
		_dpad(c, k)
		return
	var font: Font = TableSkin.heavy_font()
	var fs: int = 22
	var w: float = maxf(36.0, font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0)
	var r := Rect2(c - Vector2(w * 0.5, 16), Vector2(w, 32))
	var cap: StyleBoxFlat = TableSkin.plaque(Color("#3A2D24"), TableSkin.BRASS)
	cap.set_content_margin_all(0)
	cap.shadow_size = 0
	cap.border_color = TableSkin.BRASS_DARK
	draw_style_box(cap, r)
	var ts: Vector2 = font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(c.x - ts.x * 0.5, r.position.y + 4 + font.get_ascent(fs) * 0.92), k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.VIP_GOLD)


func _dpad(c: Vector2, k: String) -> void:
	var arm: float = 9.0
	var half: float = 5.0
	var base := Color("#8C7F70")
	var edge := Color("#1A1311")
	draw_rect(Rect2(c - Vector2(half + 1.5, arm + half + 1.5), Vector2(half * 2 + 3, (arm + half) * 2 + 3)), edge)
	draw_rect(Rect2(c - Vector2(arm + half + 1.5, half + 1.5), Vector2((arm + half) * 2 + 3, half * 2 + 3)), edge)
	draw_rect(Rect2(c - Vector2(half, arm + half), Vector2(half * 2, (arm + half) * 2)), base)
	draw_rect(Rect2(c - Vector2(arm + half, half), Vector2((arm + half) * 2, half * 2)), base)
	var dir := Vector2.ZERO
	if k.ends_with("Left"):
		dir = Vector2.LEFT
	elif k.ends_with("Right"):
		dir = Vector2.RIGHT
	elif k.ends_with("Up"):
		dir = Vector2.UP
	elif k.ends_with("Down"):
		dir = Vector2.DOWN
	if dir != Vector2.ZERO:
		var p: Vector2 = c + dir * (arm * 0.5 + half * 0.5)
		var ext: Vector2 = Vector2(absf(dir.x), absf(dir.y)) * (arm * 0.5 + half * 0.5) + Vector2(absf(dir.y), absf(dir.x)) * half
		draw_rect(Rect2(p - ext, ext * 2.0), Palette.VIP_GOLD)
