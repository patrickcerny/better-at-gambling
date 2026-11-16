class_name RpsHandIcon
extends Control
## A drawn rock, paper or scissors (the duel screen's cards and its reveal). Code-built like the
## table skins: a faceted grey rock, a cream sheet with a folded corner and ruled lines, steel
## scissors with a gold screw and red finger loops. Warm and readable at any size.

enum Kind { ROCK, PAPER, SCISSORS }

var kind: int = Kind.ROCK:
	set(v):
		kind = v
		queue_redraw()
## 0..1 dims it (a pick you didn't take, the losing hand).
var dim: float = 0.0:
	set(v):
		dim = v
		queue_redraw()
## A soft gold halo behind it (your pick, the winning hand).
var glow: bool = false:
	set(v):
		glow = v
		queue_redraw()
## Draw scale around the centre (hover lift); containers can't reset it.
var zoom: float = 1.0:
	set(v):
		zoom = v
		queue_redraw()


func _init(p_kind: int = Kind.ROCK, min_size: float = 96.0) -> void:
	kind = p_kind
	custom_minimum_size = Vector2(min_size, min_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var c: Vector2 = size * 0.5
	draw_set_transform(c * (1.0 - zoom), 0.0, Vector2(zoom, zoom))
	if glow:
		for k: int in 6:
			draw_circle(c, s * (0.5 - k * 0.04), Color(Palette.VIP_GOLD, 0.05 + k * 0.025))
	# A soft shadow under every hand so it sits on the card.
	_ellipse(c + Vector2(0, s * 0.36), Vector2(s * 0.34, s * 0.07), Color(0, 0, 0, 0.35))
	match kind:
		Kind.ROCK:
			_rock(c, s)
		Kind.PAPER:
			_paper(c, s)
		_:
			_scissors(c, s)


## Eases `zoom` to `to` (hover lift, a pick).
func lift(to: float) -> void:
	if not is_inside_tree():
		zoom = to
		return
	create_tween().tween_property(self, ^"zoom", to, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _col(col: Color) -> Color:
	if dim <= 0.0:
		return col
	var g: float = col.get_luminance()
	return Color(lerpf(col.r, g, dim * 0.8), lerpf(col.g, g, dim * 0.8), lerpf(col.b, g, dim * 0.8), col.a * (1.0 - dim * 0.45))


func _rock(c: Vector2, s: float) -> void:
	var u: float = s * 0.42
	var pts := PackedVector2Array([
		c + Vector2(-0.95, 0.55) * u, c + Vector2(-1.0, 0.0) * u, c + Vector2(-0.7, -0.5) * u,
		c + Vector2(-0.15, -0.78) * u, c + Vector2(0.45, -0.7) * u, c + Vector2(0.92, -0.25) * u,
		c + Vector2(1.0, 0.3) * u, c + Vector2(0.7, 0.72) * u, c + Vector2(-0.4, 0.8) * u,
	])
	var outline := PackedVector2Array()
	for p: Vector2 in pts:
		outline.append(c + (p - c) * 1.07)
	draw_colored_polygon(outline, _col(Color("#2A2522")))
	draw_colored_polygon(pts, _col(Color("#857D76")))
	# Facets: a lit top-left face and a shadowed lower-right face.
	draw_colored_polygon(PackedVector2Array([pts[1], pts[2], pts[3], c + Vector2(-0.1, -0.15) * u, c + Vector2(-0.55, 0.15) * u]), _col(Color("#A39A91")))
	draw_colored_polygon(PackedVector2Array([pts[3], pts[4], c + Vector2(0.35, -0.2) * u, c + Vector2(-0.1, -0.15) * u]), _col(Color("#B8AFA5")))
	draw_colored_polygon(PackedVector2Array([pts[5], pts[6], pts[7], c + Vector2(0.15, 0.45) * u, c + Vector2(0.35, -0.2) * u]), _col(Color("#665F59")))
	draw_colored_polygon(PackedVector2Array([pts[7], pts[8], pts[0], c + Vector2(-0.55, 0.15) * u, c + Vector2(0.15, 0.45) * u]), _col(Color("#5A534E")))
	# Speckles and a highlight.
	for k: Vector2 in [Vector2(-0.45, -0.25), Vector2(0.1, 0.2), Vector2(0.55, 0.05), Vector2(-0.2, 0.5)]:
		draw_circle(c + k * u, u * 0.05, _col(Color(0.2, 0.18, 0.16, 0.5)))
	draw_circle(c + Vector2(-0.4, -0.45) * u, u * 0.08, _col(Color(1, 1, 1, 0.35)))


func _paper(c: Vector2, s: float) -> void:
	var w: float = s * 0.56
	var h: float = s * 0.7
	var rot: float = deg_to_rad(-6.0)
	var fold: float = w * 0.26
	var corners := [Vector2(-w, -h) * 0.5, Vector2(w * 0.5 - fold, -h * 0.5), Vector2(w * 0.5, -h * 0.5 + fold), Vector2(w, h) * 0.5, Vector2(-w * 0.5, h * 0.5)]
	var sheet := PackedVector2Array()
	for p: Vector2 in corners:
		sheet.append(c + p.rotated(rot))
	var rim := PackedVector2Array()
	for p: Vector2 in corners:
		rim.append(c + (p * 1.06 + Vector2(0, 0)).rotated(rot))
	draw_colored_polygon(rim, _col(Color("#3A2E24")))
	draw_colored_polygon(sheet, _col(Palette.CREAM))
	# Ruled lines and a red margin.
	for k: int in 5:
		var y: float = -h * 0.24 + k * h * 0.13
		var x0: float = -w * 0.36
		var x1: float = w * (0.36 if k > 0 else 0.18)
		draw_line(c + Vector2(x0, y).rotated(rot), c + Vector2(x1, y).rotated(rot), _col(Color("#8EA3C4")), maxf(s * 0.018, 1.0), true)
	draw_line(c + Vector2(-w * 0.3, -h * 0.44).rotated(rot), c + Vector2(-w * 0.3, h * 0.44).rotated(rot), _col(Color("#D07A6A")), maxf(s * 0.014, 1.0), true)
	# The folded corner.
	var f0: Vector2 = c + Vector2(w * 0.5 - fold, -h * 0.5).rotated(rot)
	var f1: Vector2 = c + Vector2(w * 0.5, -h * 0.5 + fold).rotated(rot)
	var f2: Vector2 = c + Vector2(w * 0.5 - fold, -h * 0.5 + fold).rotated(rot)
	draw_colored_polygon(PackedVector2Array([f0, f1, f2]), _col(Color("#D8C9A6")))
	draw_polyline(PackedVector2Array([f0, f2, f1]), _col(Color("#A8956E")), maxf(s * 0.012, 1.0), true)


func _scissors(c: Vector2, s: float) -> void:
	var u: float = s * 0.45
	var pivot: Vector2 = c + Vector2(0, -0.05) * u
	for side: float in [-1.0, 1.0]:
		# Each half: a blade up and out from the screw, a handle down and out to its loop.
		var ang: float = deg_to_rad(22.0) * side
		var up := Vector2(0, -1).rotated(ang)
		var tip: Vector2 = pivot + up * u * 0.95
		var base_l: Vector2 = pivot + up.rotated(PI * 0.5) * u * 0.1
		var base_r: Vector2 = pivot - up.rotated(PI * 0.5) * u * 0.1
		draw_colored_polygon(PackedVector2Array([base_l + up * -0.05 * u, tip, base_r + up * -0.05 * u]), _col(Color("#2A2522")))
		draw_colored_polygon(PackedVector2Array([base_l, tip - up * 0.04 * u, base_r]), _col(Color("#C9CDD2")))
		draw_line(base_l, tip - up * 0.04 * u, _col(Color("#F2F4F6")), maxf(s * 0.015, 1.0), true)
		var down := Vector2(0, 1).rotated(-ang * 1.5)
		var loop_c: Vector2 = pivot + down * u * 0.62
		draw_line(pivot, loop_c - down * u * 0.2, _col(Color("#2A2522")), u * 0.17, true)
		draw_line(pivot, loop_c - down * u * 0.2, _col(Color("#B83434")), u * 0.11, true)
		draw_arc(loop_c, u * 0.22, 0, TAU, 32, _col(Color("#2A2522")), u * 0.15, true)
		draw_arc(loop_c, u * 0.22, 0, TAU, 32, _col(Color("#C83D3D")), u * 0.1, true)
		draw_arc(loop_c, u * 0.22, PI * 1.1, PI * 1.6, 12, _col(Color(1, 1, 1, 0.35)), u * 0.03, true)
	draw_circle(pivot, u * 0.1, _col(Color("#2A2522")))
	draw_circle(pivot, u * 0.075, _col(Palette.VIP_GOLD))
	draw_circle(pivot + Vector2(-0.02, -0.02) * u, u * 0.025, _col(Palette.CREAM))


func _ellipse(at: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k: int in 24:
		var a: float = TAU * k / 24.0
		pts.append(at + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, _col(col))
