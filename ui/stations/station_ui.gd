class_name StationUi
extends Control
## Base for the per-game overlays shown while seated. Subclasses build their controls in
## `_build`, redraw from the station's public/private state in `_refresh`, and send intents
## with `send`. Esc / leave_station is handled by the match scene (stand up). While seated the
## cursor is free (InputRouter), so every button here is clicked with the mouse as well.

signal rejected(error: StringName)

var station_id: StringName
var local_id: int = -1
var state: ClientMatchState
var pub: Dictionary = {}
var priv: Dictionary = {}
var panel: PanelContainer
var body: VBoxContainer
var title: Label
var status_label: Label
var hint: Label
var limits_mult: float = 1.0
## Display name shown in the header.
var game_title: String = "GAME"
## InputGlyphs.epoch the key hints were last written for.
var _glyph_epoch: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -(_panel_height() + 118)
	panel.offset_bottom = -118  # clear of the item bar
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN  # taller content pushes the panel up, never off-screen
	if _dock_right():
		# Games you watch (Plinko's falling chip) keep the middle of the screen clear.
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.anchor_top = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_left = -440
		panel.offset_right = -24
		panel.offset_top = -_panel_height() * 0.5
		panel.offset_bottom = _panel_height() * 0.5
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	panel.add_child(body)
	title = Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = game_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override(&"font_size", 26)
	body.add_child(status_label)
	_build()
	hint = Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.text = _hint_text()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override(&"font_color", Color("#9A8F7A"))
	body.add_child(hint)


## Shows the overlay for a station.
func open(p_station: StringName, p_local: int, p_state: ClientMatchState) -> void:
	station_id = p_station
	local_id = p_local
	state = p_state
	visible = true
	pub = state.stations.get(station_id, {}) if state != null else {}
	var vip: bool = bool(pub.get("vip", false))
	limits_mult = Registry.balance.limits_multiplier(state.segment_index if state != null else 0) * (3.0 if vip else 1.0)
	_on_open()
	_update_glyphs()
	_refresh()


func close() -> void:
	visible = false


## A clicked button keeps keyboard focus, and Space/Enter would then press it again instead of
## reaching the bet/action keys: let go of the focus once a click is done.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		var f: Control = get_viewport().gui_get_focus_owner()
		if f != null and is_ancestor_of(f):
			get_viewport().gui_release_focus.call_deferred()


## Redraws from the newest station state.
func update_state(p_pub: Dictionary, p_priv: Dictionary) -> void:
	pub = p_pub
	priv = p_priv
	if visible:
		if _glyph_epoch != InputGlyphs.epoch:
			_update_glyphs()
		_refresh()


## Rewrites every key hint for the device in use (keyboard + mouse or gamepad).
func _update_glyphs() -> void:
	_glyph_epoch = InputGlyphs.epoch
	hint.text = _hint_text()
	_relabel()


## Sends an intent for this station; shows the rejection if any.
func send(type: StringName, payload: Dictionary = {}) -> bool:
	var p: Dictionary = payload.duplicate()
	if not p.has("station") and type != &"leave":
		p["station"] = station_id
	var res: Dictionary = Net.send_intent(Intents.make(type, p))
	if not res["ok"]:
		rejected.emit(res["error"])
		Audio.play(&"buzzer", &"UI", -16.0, 1.4)
	return res["ok"]


## Limit scaled like the server does.
func scaled(amount: int) -> int:
	return int(floor(amount * limits_mult))


func _panel_height() -> float:
	return 360.0


## True while the player has to act here (bet, play a hand): the head stays on the table instead
## of following the cursor (InputRouter.look_locked).
func wants_camera_lock() -> bool:
	return false


## True for overlays that sit at the right edge instead of over the middle of the screen.
func _dock_right() -> bool:
	return false


func _build() -> void:
	pass


func _on_open() -> void:
	pass


## The small key hint line at the bottom of the panel.
func _hint_text() -> String:
	return "%s Stand up" % InputGlyphs.hint(&"leave_station")


## Override: put the current device's keys on buttons.
func _relabel() -> void:
	pass


func _refresh() -> void:
	pass


static func money(n: int) -> String:
	return "$" + Hud._thousands(n)


static func rejection_text(error: StringName) -> String:
	match error:
		&"insufficient_funds":
			return "Not enough money"
		&"betting_closed":
			return "Bets are closed"
		&"below_min":
			return "Below the table minimum"
		&"above_max":
			return "Above the table maximum"
		&"cooldown":
			return "Wait for the next drop"
		&"busy":
			return "Reels are spinning"
		&"too_early":
			return "Too early to stop"
		&"vip_denied":
			return "VIP ACCESS DENIED"
		&"too_far":
			return "Too far away"
		&"station_full":
			return "Table is full"
	return String(error).capitalize()
