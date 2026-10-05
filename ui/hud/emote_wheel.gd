class_name EmoteWheel
extends Control
## Radial emote picker (§2.4.2): hold the emote key (G / D-pad down), point with the mouse or
## right stick, release to send. Six emotes (`Emotes`), each a charcoal pill that lights up gold
## when pointed at; the centre says what you picked and how to send it.

signal picked(id: StringName)

const RADIUS: float = 200.0
const PILL_SIZE: Vector2 = Vector2(190, 64)
## Pointer distance (px) from the centre before a pill is chosen.
const DEAD_ZONE: float = 40.0

var selected: int = -1
var _pills: Array[PanelContainer] = []
var _centre: Control
var _centre_label: Label
var _glyph_epoch: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(Palette.CASINO_BLACK, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_centre = Control.new()
	_centre.anchor_left = 0.5
	_centre.anchor_right = 0.5
	_centre.anchor_top = 0.5
	_centre.anchor_bottom = 0.5
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_centre)
	var ring := Panel.new()
	ring.size = Vector2(172, 172)
	ring.position = -ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override(&"panel", _style(Color(Palette.CASINO_BLACK, 0.85), Palette.WARM_GOLD, 86, 2))
	_centre.add_child(ring)
	_centre_label = Label.new()
	_centre_label.size = ring.size
	_centre_label.position = ring.position
	_centre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_centre_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_centre_label.add_theme_font_size_override(&"font_size", 20)
	_centre_label.add_theme_color_override(&"font_color", Palette.CREAM)
	_centre.add_child(_centre_label)
	for i: int in Emotes.LIST.size():
		var pill := PanelContainer.new()
		pill.size = PILL_SIZE
		pill.custom_minimum_size = PILL_SIZE
		pill.pivot_offset = PILL_SIZE * 0.5
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var a: float = -PI * 0.5 + i * TAU / Emotes.LIST.size()
		pill.position = Vector2(cos(a), sin(a)) * RADIUS - PILL_SIZE * 0.5
		var l := Label.new()
		l.text = "%s  %s" % [Emotes.LIST[i][1], Emotes.LIST[i][2]]
		l.theme_type_variation = &"HeadingLabel"
		l.add_theme_font_size_override(&"font_size", 28)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.add_child(l)
		_centre.add_child(pill)
		_pills.append(pill)


## Opens the wheel.
func open() -> void:
	selected = -1
	visible = true
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(get_viewport_rect().size * 0.5)
	_highlight()


## Closes the wheel and emits the choice (if any).
func close_and_pick() -> void:
	visible = false
	if selected >= 0:
		picked.emit(Emotes.LIST[selected][0])


func _process(_delta: float) -> void:
	if not visible:
		return
	if DisplayServer.get_name() != "headless" and not Input.is_action_pressed(&"emote_wheel"):
		visible = false  # the key went up while something else took the input mode: don't get stuck
		return
	if _glyph_epoch != InputGlyphs.epoch:
		_highlight()
	var dir: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if dir.length() < 0.5:
		dir = get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
	if dir.length() < DEAD_ZONE:
		return
	var a: float = fposmod(dir.angle() + PI * 0.5 + PI / Emotes.LIST.size(), TAU)
	var pick: int = int(a / (TAU / Emotes.LIST.size())) % Emotes.LIST.size()
	if pick != selected:
		selected = pick
		_highlight()
		Audio.play(&"ui_hover", &"UI", -14.0)


func _highlight() -> void:
	_glyph_epoch = InputGlyphs.epoch
	for i: int in _pills.size():
		var on: bool = i == selected
		_pills[i].add_theme_stylebox_override(&"panel", _style(Palette.VIP_BURGUNDY if on else Color(Palette.WARM_CHARCOAL, 0.92), Palette.VIP_GOLD if on else Color(Palette.WARM_GOLD, 0.4), 32, 3 if on else 1))
		(_pills[i].get_child(0) as Label).add_theme_color_override(&"font_color", Palette.VIP_GOLD if on else Palette.CREAM)
		_pills[i].scale = Vector2.ONE * (1.12 if on else 1.0)
	var aim: String = "Right stick" if InputGlyphs.gamepad else "Mouse"
	var release: String = "Release %s" % InputGlyphs.key(&"emote_wheel")
	_centre_label.text = ("%s\n%s to send" % [Emotes.LIST[selected][2], release]) if selected >= 0 else "%s to pick\n%s" % [aim, release]


static func _style(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


## Shows an emote on a character: bubble with the emoji and word, a hop if standing, and its sound.
static func present(avatar: PlayerAvatar, id: StringName) -> void:
	if avatar == null or not Emotes.has(id):
		return
	avatar.say(Emotes.bubble_text(id), 2.0)
	if avatar.is_standing():
		avatar.hop(Vector3(0, 3.5, 0))
	Audio.play_at(Emotes.sound(id), avatar, -6.0)
