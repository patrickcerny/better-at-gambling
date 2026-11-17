class_name PictureCard
extends Button
## A big menu button that is a picture with a caption (Patrick 2026-11-16: "ein menu mit bildern
## als buttons und die bild beschreiben was abgeht"): the picture fills the card, a dark band at the
## bottom carries the title and one line on what happens. Hover or focus (mouse, keyboard, pad)
## lifts the card a little, rings it in gold and zooms the picture slightly. With the mouse only
## the hovered card lights up (Patrick 2026-11-17: "theres alwys one selected on pc"): `FocusGate`
## lets the focus go while you use the mouse. Disabled cards are
## dimmed and stay still. Used by PLAY ONLINE (`OnlineMenu`) and the tutorial's overview
## (`HowToPlayPanel`). The card's size comes from its container (`custom_minimum_size`).

const RADIUS: int = 16
const BAND_COLOR := Color("#16120F")
const RING_IDLE := Color("#4A3F35")
const LIFT: float = 1.035
const ZOOM: float = 1.07

var picture: TextureRect
var title_label: Label
var caption_label: Label
var _ring: Panel
var _frame: Control
var _lit: bool = false
var _tween: Tween


func _init(card_name: String, title_text: String, caption: String, texture: Texture2D = null) -> void:
	name = card_name
	text = ""
	tooltip_text = ""
	focus_mode = Control.FOCUS_ALL
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW  # the picture keeps the rounded corners
	var plate: StyleBoxFlat = _box(Color("#221D19"), Color(0, 0, 0, 0), 0)
	for s: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"hover_pressed"]:
		add_theme_stylebox_override(s, plate)
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())  # the gold ring shows focus instead
	_frame = Control.new()  # the picture zooms inside this, clipped by the card
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	picture = TextureRect.new()
	picture.name = "Picture"
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.texture = texture
	_frame.add_child(picture)
	var band := PanelContainer.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bsb: StyleBoxFlat = _box(Color(BAND_COLOR, 0.93), Color(0, 0, 0, 0), 0)
	bsb.content_margin_left = 20
	bsb.content_margin_right = 20
	bsb.content_margin_top = 14
	bsb.content_margin_bottom = 18
	bsb.border_width_top = 2
	bsb.border_color = Color(Palette.WARM_GOLD, 0.55)
	band.add_theme_stylebox_override(&"panel", bsb)
	add_child(band)
	var tv := VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_theme_constant_override(&"separation", 2)
	band.add_child(tv)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = title_text
	title_label.theme_type_variation = &"HeadingLabel"
	title_label.add_theme_font_size_override(&"font_size", 28)
	title_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(title_label)
	caption_label = Label.new()
	caption_label.name = "Caption"
	caption_label.text = caption
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.add_theme_font_size_override(&"font_size", 17)
	caption_label.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.82))
	caption_label.custom_minimum_size = Vector2(0, 46)
	tv.add_child(caption_label)
	_ring = Panel.new()  # over everything so the ring stays crisp
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ring)
	_paint(false)


func _ready() -> void:
	mouse_entered.connect(_update_lit)
	mouse_exited.connect(_update_lit)
	focus_entered.connect(_update_lit)
	focus_exited.connect(_update_lit)
	resized.connect(_recenter)
	_recenter()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		_update_lit()


## Hovered or focused (and enabled): lifted, ringed in gold, the picture zoomed in a little.
func is_lit() -> bool:
	return _lit


func set_texture(texture: Texture2D) -> void:
	picture.texture = texture


func _update_lit() -> void:
	if not is_inside_tree():
		return
	var on: bool = not disabled and (has_focus() or is_hovered())
	modulate = Color(0.5, 0.5, 0.5, 0.85) if disabled else Color.WHITE
	if on == _lit:
		return
	_lit = on
	_paint(on)
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * (LIFT if on else 1.0), 0.16)
	_tween.tween_property(_frame, "scale", Vector2.ONE * (ZOOM if on else 1.0), 0.35)


func _paint(on: bool) -> void:
	_ring.add_theme_stylebox_override(&"panel", _box(Color(0, 0, 0, 0), Palette.VIP_GOLD if on else RING_IDLE, 4 if on else 2))


func _recenter() -> void:
	pivot_offset = size * 0.5
	_frame.pivot_offset = size * 0.5


static func _box(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(RADIUS)
	sb.anti_aliasing = true
	return sb


## A picture with rounded corners (Patrick 2026-11-16: "images are clipping"): for tiles inside a
## rounded button, so the picture's corners stay inside the button's rounding. `pic` is the
## TextureRect inside (named "Picture").
static func rounded_picture(texture: Texture2D, min_size: Vector2, radius: int = 10) -> Panel:
	var mask := Panel.new()
	mask.name = "PictureMask"
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.custom_minimum_size = min_size
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	mask.add_theme_stylebox_override(&"panel", sb)
	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.texture = texture
	mask.add_child(pic)
	return mask
