class_name MinigameBriefing
extends CanvasLayer
## The rules screen before every minigame (0.8.13): the minigame's name, a looping preview clip
## of it being played (MinigamePreview), how to play, its controls for keyboard and gamepad
## (MinigameControls; the device you're using is lit), who is ready and a countdown. Everyone clicks READY (or presses Space / Enter / the interact button);
## the server starts the minigame when all players are ready or when the briefing time runs out.
## Sits above the stage UI and swallows keys so the stage can't act before the start.

const WIDTH: float = 1220.0
## The preview clip's size on the card (16:9).
const PREVIEW: Vector2 = Vector2(512, 288)
const COLUMN: float = 600.0

var rules_label: Label
var title_label: Label
var countdown_label: Label
var ready_button: Button
var players_box: HFlowContainer
var preview: MinigamePreview
var controls_grid: GridContainer
## Keycap chips per device, dimmed when that device isn't the one in use.
var key_chips: Array[Control] = []
var pad_chips: Array[Control] = []
var _glyph_epoch: int = -1
## player → their row label.
var rows: Dictionary = {}
var state: ClientMatchState
var local_id: int = -1
var left: float = 0.0
var sent: bool = false
var players: Array[int] = []
var ready_ids: Array[int] = []


func _init() -> void:
	name = "MinigameBriefing"
	layer = 6


## `start` is the `minigame_started` event (or the snapshot's minigame state, with `briefing`).
func open(start: Dictionary, p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	for p: Variant in start.get("players", []):
		players.append(int(p))
	var briefing: Variant = start.get("briefing", 0.0)
	if briefing is Dictionary:
		left = float((briefing as Dictionary).get("left", 0.0))
		for p: Variant in (briefing as Dictionary).get("ready", []):
			ready_ids.append(int(p))
	else:
		left = float(briefing)
	var def: MinigameDefinition = Registry.minigames.get(StringName(start.get("minigame", "")), null)
	var title: String = str(start.get("name", def.display_name if def != null else "Minigame"))
	var rules: String = str(start.get("rules", def.rules_text if def != null else ""))
	_build(title, rules, StringName(start.get("minigame", "")))
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"minigame_ready":
			ready_ids.clear()
			for p: Variant in ev.get("ready", []):
				ready_ids.append(int(p))
			_refresh()
		&"minigame_go":
			queue_free()


func _process(delta: float) -> void:
	if left > 0.0:
		left = maxf(left - delta, 0.0)
		countdown_label.text = "Starts in %d s" % ceili(left) if left > 0.0 else "Starting…"
	if _glyph_epoch != InputGlyphs.epoch:
		_light_device()


func _input(event: InputEvent) -> void:
	if event.is_action(&"pause"):
		return  # Escape is the pause menu's, even during the rules card
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and (k.physical_keycode == KEY_SPACE or k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_KP_ENTER):
			press_ready()
		get_viewport().set_input_as_handled()  # the stage waits too
	elif event is InputEventJoypadButton and (event.is_action_pressed(&"interact") or event.is_action_pressed(&"jump")):
		press_ready()
		get_viewport().set_input_as_handled()


## Tells the server we're ready (once).
func press_ready() -> void:
	if sent or not players.has(local_id):
		return
	var res: Dictionary = Net.send_intent(Intents.make(&"minigame_ready", {}))
	if res.get("ok", false) or res.get("error", &"") == &"too_late":
		sent = true
		if not ready_ids.has(local_id):
			ready_ids.append(local_id)
		_refresh()


func _refresh() -> void:
	for p: int in players:
		if not rows.has(p):
			var chip := PanelContainer.new()
			players_box.add_child(chip)
			var l := Label.new()
			l.add_theme_font_size_override(&"font_size", 22)
			chip.add_child(l)
			rows[p] = l
		var is_ready: bool = ready_ids.has(p)
		var l: Label = rows[p]
		l.text = "%s  %s" % ["✓" if is_ready else "…", state.player_name(p) if state != null else str(p)]
		l.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if is_ready else Palette.CREAM)
		var chip: PanelContainer = l.get_parent() as PanelContainer
		if chip != null:
			chip.add_theme_stylebox_override(&"panel", _pill(Palette.MONEY_GREEN if is_ready else Color(Palette.CREAM, 0.25)))
	if sent or ready_ids.has(local_id):
		ready_button.text = "WAITING FOR THE OTHERS…" if ready_ids.size() < players.size() else "STARTING…"
		ready_button.disabled = true
	countdown_label.text = "Starts in %d s" % ceili(left) if left > 0.0 else "Starting…"


func _build(title: String, rules: String, id: StringName) -> void:
	var dim := ColorRect.new()
	dim.color = Color(Palette.CASINO_BLACK, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.WARM_CHARCOAL, 0.97)
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(30)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 14)
	panel.add_child(col)
	var kicker := Label.new()
	kicker.theme_type_variation = &"SmallLabel"
	kicker.text = "NEXT MINIGAME"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	col.add_child(kicker)
	title_label = Label.new()
	title_label.theme_type_variation = &"TitleLabel"
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_label)
	# Preview clip on the left, how to play and the controls on the right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 30)
	col.add_child(body)
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Palette.CASINO_BLACK
	fsb.border_color = Palette.VIP_GOLD
	fsb.set_border_width_all(3)
	fsb.set_corner_radius_all(10)
	fsb.set_content_margin_all(3)
	frame.add_theme_stylebox_override(&"panel", fsb)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(frame)
	preview = MinigamePreview.new()
	preview.custom_minimum_size = PREVIEW
	frame.add_child(preview)
	if not preview.set_game(id):
		frame.visible = false
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 10)
	right.custom_minimum_size = Vector2(COLUMN if frame.visible else WIDTH - 60, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_heading("HOW TO PLAY"))
	rules_label = Label.new()
	rules_label.text = rules
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_label.custom_minimum_size = Vector2(right.custom_minimum_size.x, 0)
	rules_label.add_theme_font_size_override(&"font_size", 21 if rules.length() < 330 else 18)
	rules_label.add_theme_color_override(&"font_color", Palette.CREAM)
	right.add_child(rules_label)
	_build_controls(right, id)
	col.add_child(HSeparator.new())
	players_box = HFlowContainer.new()
	players_box.alignment = FlowContainer.ALIGNMENT_CENTER
	players_box.add_theme_constant_override(&"h_separation", 10)
	players_box.add_theme_constant_override(&"v_separation", 8)
	col.add_child(players_box)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override(&"separation", 28)
	col.add_child(foot)
	countdown_label = Label.new()
	countdown_label.theme_type_variation = &"HeadingLabel"
	countdown_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	foot.add_child(countdown_label)
	ready_button = Button.new()
	ready_button.theme_type_variation = &"ActionButton"
	ready_button.text = "READY  (Space / Enter)"
	ready_button.custom_minimum_size = Vector2(380, 68)
	ready_button.add_theme_font_size_override(&"font_size", 28)
	ready_button.focus_mode = Control.FOCUS_NONE
	ready_button.pressed.connect(press_ready)
	foot.add_child(ready_button)
	_light_device()


## The controls table: a header row (KEYBOARD, GAMEPAD), then a keycap per device and what it does.
func _build_controls(parent: Control, id: StringName) -> void:
	var rows_data: Array[Dictionary] = MinigameControls.rows(id)
	if rows_data.is_empty():
		return
	var head := _heading("CONTROLS")
	head.custom_minimum_size.y = 34
	parent.add_child(head)
	controls_grid = GridContainer.new()
	controls_grid.columns = 3
	controls_grid.add_theme_constant_override(&"h_separation", 12)
	controls_grid.add_theme_constant_override(&"v_separation", 6)
	parent.add_child(controls_grid)
	for t: String in ["KEYBOARD", "GAMEPAD", ""]:
		var h := Label.new()
		h.text = t
		h.theme_type_variation = &"SmallLabel"
		h.add_theme_font_size_override(&"font_size", 14)
		h.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.55))
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		controls_grid.add_child(h)
	for r: Dictionary in rows_data:
		var k: Control = _keycap(str(r["key"]))
		var g: Control = _keycap(str(r["pad"]))
		key_chips.append(k)
		pad_chips.append(g)
		controls_grid.add_child(k)
		controls_grid.add_child(g)
		var what := Label.new()
		what.text = str(r["what"])
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.add_theme_font_size_override(&"font_size", 19)
		what.add_theme_color_override(&"font_color", Palette.CREAM)
		controls_grid.add_child(what)


## Lights the column of the device you used last and dims the other.
func _light_device() -> void:
	_glyph_epoch = InputGlyphs.epoch
	for c: Control in key_chips:
		c.modulate.a = 0.4 if InputGlyphs.gamepad else 1.0
	for c: Control in pad_chips:
		c.modulate.a = 1.0 if InputGlyphs.gamepad else 0.4
	if ready_button != null and not ready_button.disabled:
		ready_button.text = "READY  (%s)" % ("A" if InputGlyphs.gamepad else "Space / Enter")


## A key / button name on a little keycap ("" → a dash: that device can't do it).
func _keycap(text: String) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var none: bool = text == "" or text == "?"
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.9) if not none else Color(0, 0, 0, 0)
	sb.border_color = Palette.WARM_GOLD if not none else Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override(&"panel", sb)
	chip.custom_minimum_size = Vector2(150, 0)
	var l := Label.new()
	l.text = text if not none else "—"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", 18)
	l.add_theme_color_override(&"font_color", Palette.VIP_GOLD if not none else Color(Palette.CREAM, 0.35))
	chip.add_child(l)
	return chip


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SmallLabel"
	l.add_theme_font_size_override(&"font_size", 16)
	l.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	return l


func _pill(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.7)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
