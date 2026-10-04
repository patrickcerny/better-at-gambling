class_name EmoteWheel
extends Control
## Radial emote picker (§2.4.2): hold the emote key, point with the mouse or right stick,
## release to send. Six emotes.

signal picked(id: StringName)

const EMOTES: Array[Array] = [
	[&"wave", "👋 WAVE"], [&"laugh", "😂 LAUGH"], [&"taunt", "😜 TAUNT"],
	[&"cry", "😭 CRY"], [&"dance", "🕺 DANCE"], [&"gg", "🤝 GG"],
]
const RADIUS: float = 150.0

var selected: int = -1
var _labels: Array[Label] = []
var _centre: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_centre = Control.new()
	_centre.set_anchors_preset(Control.PRESET_CENTER)
	_centre.anchor_left = 0.5
	_centre.anchor_right = 0.5
	_centre.anchor_top = 0.5
	_centre.anchor_bottom = 0.5
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_centre)
	for i: int in EMOTES.size():
		var l := Label.new()
		l.text = EMOTES[i][1]
		l.theme_type_variation = &"HeadingLabel"
		l.add_theme_font_size_override(&"font_size", 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(180, 60)
		var a: float = -PI * 0.5 + i * TAU / EMOTES.size()
		l.position = Vector2(cos(a), sin(a)) * RADIUS - l.custom_minimum_size * 0.5
		_centre.add_child(l)
		_labels.append(l)


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
		picked.emit(EMOTES[selected][0])


func _process(_delta: float) -> void:
	if not visible:
		return
	var dir: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if dir.length() < 0.5:
		dir = get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
	if dir.length() < 40.0:
		return
	var a: float = fposmod(dir.angle() + PI * 0.5 + PI / EMOTES.size(), TAU)
	selected = int(a / (TAU / EMOTES.size())) % EMOTES.size()
	_highlight()


func _highlight() -> void:
	for i: int in _labels.size():
		_labels[i].add_theme_color_override(&"font_color", Palette.VIP_GOLD if i == selected else Palette.CREAM)
		_labels[i].scale = Vector2.ONE * (1.2 if i == selected else 1.0)
