class_name MinigameBriefing
extends CanvasLayer
## The rules screen before every minigame (0.8.13): the minigame's name, how to play, who is
## ready and a countdown. Everyone clicks READY (or presses Space / Enter / the interact button);
## the server starts the minigame when all players are ready or when the briefing time runs out.
## Sits above the stage UI and swallows keys so the stage can't act before the start.

const WIDTH: float = 760.0

var rules_label: Label
var title_label: Label
var countdown_label: Label
var ready_button: Button
var players_box: VBoxContainer
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
	_build(title, rules)
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


func _input(event: InputEvent) -> void:
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
			var l := Label.new()
			l.theme_type_variation = &"HeadingLabel"
			players_box.add_child(l)
			rows[p] = l
		var is_ready: bool = ready_ids.has(p)
		var l: Label = rows[p]
		l.text = "%s  %s" % ["✓" if is_ready else "…", state.player_name(p) if state != null else str(p)]
		l.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if is_ready else Palette.CREAM)
	if sent or ready_ids.has(local_id):
		ready_button.text = "WAITING FOR THE OTHERS…" if ready_ids.size() < players.size() else "STARTING…"
		ready_button.disabled = true
	countdown_label.text = "Starts in %d s" % ceili(left) if left > 0.0 else "Starting…"


func _build(title: String, rules: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(Palette.CASINO_BLACK, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.WARM_CHARCOAL, 0.96)
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
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
	rules_label = Label.new()
	rules_label.text = rules
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_label.custom_minimum_size = Vector2(WIDTH - 56, 0)
	rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_label.add_theme_font_size_override(&"font_size", 24)
	rules_label.add_theme_color_override(&"font_color", Palette.CREAM)
	col.add_child(rules_label)
	var sep := HSeparator.new()
	col.add_child(sep)
	players_box = VBoxContainer.new()
	players_box.alignment = BoxContainer.ALIGNMENT_CENTER
	players_box.add_theme_constant_override(&"separation", 4)
	col.add_child(players_box)
	countdown_label = Label.new()
	countdown_label.theme_type_variation = &"HeadingLabel"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	col.add_child(countdown_label)
	ready_button = Button.new()
	ready_button.theme_type_variation = &"ActionButton"
	ready_button.text = "READY  (Space / Enter)"
	ready_button.custom_minimum_size = Vector2(360, 72)
	ready_button.add_theme_font_size_override(&"font_size", 30)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ready_button.focus_mode = Control.FOCUS_NONE
	ready_button.pressed.connect(press_ready)
	col.add_child(ready_button)
