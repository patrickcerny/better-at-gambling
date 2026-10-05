class_name Vfx
extends RefCounted
## Shared switch and helpers for client-only effects (table animations, win/lose bursts, hot table,
## Last Call lighting). Nothing visual is built on a headless server or in headless tests unless a
## test turns `force_enabled` on to exercise the effect itself.

const FONT_PATH: String = "res://assets/fonts/BarlowCondensed-Black.ttf"

## Tests set this to run effects under the headless runner (reset it in `after_each`).
static var force_enabled: bool = false


## True when effects may be built (a real display, or a test forcing them).
static func enabled() -> bool:
	return force_enabled or DisplayServer.get_name() != "headless"


## The heading font (Barlow Condensed Black).
static func font() -> Font:
	return load(FONT_PATH) as Font


## Unshaded, alpha-blended material that takes particle / vertex colours (additive for glows).
static func glow_material(color: Color = Color.WHITE, additive: bool = false, billboard: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = soft_dot()
	return m


## Soft round dot (white centre fading out) for sparkle and ember billboards.
static func soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.35, Color(1, 1, 1, 0.7))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## Frees `node` after `seconds` (the tween dies with the node, so an early free is harmless).
static func free_after(node: Node, seconds: float) -> void:
	var t: Tween = node.create_tween()
	t.tween_interval(seconds)
	t.tween_callback(node.queue_free)


## Billboard text that floats up and fades, then frees itself.
static func floating_text(parent: Node, pos: Vector3, text: String, color: Color, size: int = 96, rise: float = 1.0, seconds: float = 1.4) -> Label3D:
	if not enabled() or parent == null or not parent.is_inside_tree():
		return null
	var l := Label3D.new()
	l.name = "FloatingText"
	l.text = text
	l.font = font()
	l.font_size = size
	l.pixel_size = 0.003
	l.outline_size = 20
	l.modulate = color
	l.outline_modulate = Palette.CASINO_BLACK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	l.outline_render_priority = 4
	parent.add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.4
	var t: Tween = l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", l.position.y + rise, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, seconds * 0.45).set_delay(seconds * 0.55)
	t.tween_property(l, "outline_modulate:a", 0.0, seconds * 0.45).set_delay(seconds * 0.55)
	t.chain().tween_callback(l.queue_free)
	return l
