class_name LobbyPanel
extends PanelContainer
## The 2D lobby panel (§2.2) that mirrors the physical entrance hall for gamepad and
## accessibility: the 8 slots (name, color, ready, leader) and — for the party leader — the mode (casino or minigames only), match length (minigames,
## gambling minutes between them), items, which minigames are on (MinigameSelector), INVITE FRIENDS (Steam overlay) and a KICK button
## next to every other player (press twice: KICK → SURE?). Every button sends an intent; the panel
## only redraws from the ClientMatchState mirror. There is no READY button: players get ready
## only by standing on their pedestal (Patrick); the slots just show it. Opened at the settings
## tablet; Tab shows the `PlayerList` instead. COSMETICS opens the cosmetics shop
## (`CosmeticsPanel`) over the lobby.

signal closed
signal leave_requested
signal cosmetics_requested

var state: ClientMatchState
var local_id: int = -1

const WIDTH: float = 1120.0
const HEIGHT: float = 700.0
const ROW_HEIGHT: float = 58.0
const MUTED: Color = Color("#9A8F7A")

var _title: Label
## "Public lobby · …" / "Private lobby · …" under the title.
var _kind_label: Label
## "3 / 8 PLAYERS" chip in the header.
var _count_label: Label
## The burgundy band under the header: countdown or how to get ready, and "2 / 3 READY".
var _status_band: PanelContainer
var _ready_count: Label
var _slots: VBoxContainer
var _settings_box: VBoxContainer
var _close_button: Button
var _settings_note: Label
var _countdown_label: Label
## Match length steppers (Patrick's note #12): setting key → {minus, plus, value: Label}.
var _steppers: Dictionary[String, Dictionary] = {}
var _items_button: Button
## Leader-only toggle: party mode (`MatchMode`).
var mode_button: Button
## Opens the Steam overlay's invite dialog (every party is a Steam lobby on the host's PC; there is
## no server browser and no PUBLIC toggle any more). Disabled in a dev `--connect` room.
var invite_button: Button
## MINIGAMES: opens the minigame selector (`minigame_pool`; read-only for everyone but the leader).
var minigames_button: Button
## Opens the cosmetics shop (bean colours) without leaving the lobby.
var cosmetics_button: Button
var selector: MinigameSelector
## Player id whose KICK was pressed once (the second press kicks), and when it disarms.
var _kick_armed: int = -1
var _kick_armed_until: float = 0.0
var _length_note: Label
## The 8 slot rows, built once and updated in place (rebuilding them made the panel jump on
## every snapshot, so clicks missed). Each: {frame, swatch, portrait, name, tag, pill, ready, kick, empty}.
var _rows: Array[Dictionary] = []
## Frame the panel was opened on: the Tab press that opened it must not close it again.
var _opened_frame: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = -HEIGHT / 2.0
	offset_bottom = HEIGHT / 2.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	# Fully opaque (0.9.41): the pedestal names in the hall no longer show through the panel.
	var bg: StyleBoxFlat = box(Color("#191615"), Palette.WARM_GOLD.darkened(0.25), 18, 2)
	bg.shadow_color = Color(0, 0, 0, 0.55)
	bg.shadow_size = 28
	bg.set_content_margin_all(26)
	add_theme_stylebox_override(&"panel", bg)
	visible = false
	_build()
	add_child(BeanPortraits.new())


## Connects to the mirror.
func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.lobby_changed.connect(_refresh)
	state.players_changed.connect(_refresh)
	selector.bind(state, local_id)
	_refresh()


## Shows the panel; `focus` is &"settings" or &"" (general).
func open(focus: StringName = &"") -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	_refresh()
	match focus:
		&"settings":
			if _steppers.has("minigames"):
				(_steppers["minigames"]["plus"] as Button).grab_focus()
		_:
			_close_button.grab_focus()


func close() -> void:
	if visible:
		visible = false
		selector.close()
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var tab: bool = event.is_action_pressed(&"leaderboard") and Engine.get_process_frames() != _opened_frame
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") or tab:
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	add_child(v)
	# Header: title and lobby kind on the left, the player count on the right.
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 16)
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", -6)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	titles.add_child(_title)
	_kind_label = Label.new()
	_kind_label.theme_type_variation = &"MutedLabel"
	titles.add_child(_kind_label)
	var count_chip := PanelContainer.new()
	count_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_box: StyleBoxFlat = box(Color("#2A2422"), Palette.WARM_GOLD.darkened(0.35), 22, 1)
	chip_box.content_margin_left = 18
	chip_box.content_margin_right = 18
	chip_box.content_margin_top = 6
	chip_box.content_margin_bottom = 6
	count_chip.add_theme_stylebox_override(&"panel", chip_box)
	head.add_child(count_chip)
	_count_label = Label.new()
	_count_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	count_chip.add_child(_count_label)
	# Status band: the countdown, or how to get ready and how many are.
	_status_band = PanelContainer.new()
	var band: StyleBoxFlat = box(Palette.VIP_BURGUNDY.darkened(0.25), Palette.VIP_BURGUNDY.lightened(0.2), 12, 1)
	band.content_margin_left = 18
	band.content_margin_right = 18
	band.content_margin_top = 8
	band.content_margin_bottom = 8
	_status_band.add_theme_stylebox_override(&"panel", band)
	v.add_child(_status_band)
	var band_row := HBoxContainer.new()
	_status_band.add_child(band_row)
	_countdown_label = Label.new()
	_countdown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_countdown_label.add_theme_color_override(&"font_color", Palette.CREAM)
	band_row.add_child(_countdown_label)
	_ready_count = Label.new()
	_ready_count.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	band_row.add_child(_ready_count)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var players_card: VBoxContainer = _card(cols, "PLAYERS")
	players_card.get_parent().custom_minimum_size = Vector2(520, 0)
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override(&"separation", 5)
	players_card.add_child(_slots)
	for i: int in Protocol.MAX_PLAYERS:
		_rows.append(_make_row())
	var right: VBoxContainer = _card(cols, "MATCH SETTINGS")
	right.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_note = Label.new()
	_settings_note.theme_type_variation = &"SmallLabel"
	_settings_note.add_theme_color_override(&"font_color", MUTED)
	right.add_child(_settings_note)
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override(&"separation", 8)
	right.add_child(_settings_box)
	mode_button = Button.new()
	mode_button.name = "Mode"
	mode_button.custom_minimum_size = Vector2(230, 46)
	mode_button.pressed.connect(func() -> void:
		var now: StringName = MatchMode.normalize(state.lobby_settings.get("mode", MatchMode.CASINO))
		Net.send_intent(Intents.make(&"lobby_setting", {"key": "mode", "value": MatchMode.MINIGAMES if now == MatchMode.CASINO else MatchMode.CASINO})))
	_setting_row("MODE").add_child(mode_button)
	_add_stepper("minigames", "MINIGAMES")
	_add_stepper("gamble_minutes", "GAMBLING")
	_items_button = Button.new()
	_items_button.name = "Items"
	_items_button.toggle_mode = true
	_items_button.custom_minimum_size = Vector2(230, 46)
	_items_button.pressed.connect(func() -> void:
		Net.send_intent(Intents.make(&"lobby_setting", {"key": "items_enabled", "value": not bool(state.lobby_settings.get("items_enabled", true))})))
	_setting_row("ITEMS").add_child(_items_button)
	minigames_button = Button.new()
	minigames_button.name = "Minigames"
	minigames_button.custom_minimum_size = Vector2(230, 46)
	minigames_button.pressed.connect(func() -> void: selector.open())
	_setting_row("GAMES").add_child(minigames_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	_length_note = Label.new()
	_length_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_length_note.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	right.add_child(_length_note)
	selector = MinigameSelector.new()
	add_child(selector)
	# Footer: leave on the far left (away from the rest), then the everyday buttons.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 14)
	v.add_child(bottom)
	var leave := Button.new()
	leave.text = "LEAVE LOBBY"
	leave.name = "LeaveButton"
	leave.add_theme_color_override(&"font_color", Palette.LOSS_RED.lightened(0.15))
	# Patrick: "Are you sure Dialog after quit game or leave game (so you dont misclick)".
	leave.pressed.connect(func() -> void:
		ConfirmDialog.ask(get_parent() if get_parent() != null else self, "LEAVE THE LOBBY?", "You go back to the main menu.", "LEAVE", func() -> void: leave_requested.emit()))
	bottom.add_child(leave)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	cosmetics_button = Button.new()
	cosmetics_button.name = "CosmeticsButton"
	cosmetics_button.text = "COSMETICS"
	cosmetics_button.pressed.connect(func() -> void: cosmetics_requested.emit())
	bottom.add_child(cosmetics_button)
	invite_button = Button.new()
	invite_button.name = "InviteFriends"
	invite_button.text = "INVITE FRIENDS"
	invite_button.tooltip_text = "Invite friends (Steam overlay)"
	invite_button.pressed.connect(func() -> void: SteamSvc.invite_friends())
	bottom.add_child(invite_button)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = "CLOSE"
	_close_button.custom_minimum_size = Vector2(150, 0)
	_close_button.pressed.connect(close)
	bottom.add_child(_close_button)


## A dark rounded card with a small gold heading; returns its content box.
func _card(parent: Control, heading: String) -> VBoxContainer:
	var card := PanelContainer.new()
	var sb: StyleBoxFlat = box(Color("#221E1C"), Color("#3A322C"), 14, 1)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override(&"panel", sb)
	parent.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 8)
	card.add_child(inner)
	inner.add_child(_heading(heading))
	return inner


## A settings line: the name on the left, its control (added by the caller) on the right.
func _setting_row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	_settings_box.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", MUTED.lightened(0.25))
	row.add_child(label)
	return row


func _make_row() -> Dictionary:
	var framed := PanelContainer.new()
	framed.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	framed.add_theme_stylebox_override(&"panel", _row_box(false, false))
	_slots.add_child(framed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	framed.add_child(row)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(5, 0)
	row.add_child(sw)
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(40, 50)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var empty := Label.new()
	empty.text = "Open slot"
	empty.theme_type_variation = &"MutedLabel"
	empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(empty)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override(&"separation", -4)
	row.add_child(texts)
	var label := Label.new()
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(label)
	var tag := Label.new()
	tag.theme_type_variation = &"SmallLabel"
	tag.add_theme_font_size_override(&"font_size", 16)
	texts.add_child(tag)
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pill)
	var ready := Label.new()
	ready.theme_type_variation = &"SmallLabel"
	ready.add_theme_font_size_override(&"font_size", 16)
	ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready.custom_minimum_size = Vector2(92, 0)
	pill.add_child(ready)
	var kick := Button.new()
	kick.name = "Kick"
	kick.text = "KICK"
	kick.theme_type_variation = &"ChipButton"
	kick.add_theme_font_size_override(&"font_size", 16)
	kick.custom_minimum_size = Vector2(76, 34)
	kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kick.visible = false
	kick.pressed.connect(_on_kick_pressed.bind(_rows.size()))
	row.add_child(kick)
	var kick_gap := Control.new()  # holds KICK's place so the READY pills line up
	kick_gap.custom_minimum_size = kick.custom_minimum_size
	row.add_child(kick_gap)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	row.add_child(pad)
	return {"frame": framed, "swatch": sw, "portrait": portrait, "name": label, "tag": tag, "pill": pill, "ready": ready, "kick": kick, "kick_gap": kick_gap, "empty": empty}


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeadingLabel"
	l.add_theme_font_size_override(&"font_size", 26)
	return l


## A flat rounded box (the panel's own look, independent of the theme's row styles).
static func box(bg: Color, border: Color, radius: int, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


func _row_box(taken: bool, mine: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat
	if mine:
		sb = box(Color("#3A2622"), Palette.VIP_GOLD.darkened(0.2), 10, 1)
	elif taken:
		sb = box(Color("#2B2522"), Color("#3A322C"), 10, 1)
	else:
		sb = box(Color("#1E1B19"), Color("#2C2622"), 10, 1)
	sb.content_margin_right = 6
	return sb


func _pill_box(on: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = box(Palette.MONEY_GREEN.darkened(0.55) if on else Color("#2F2926"), Palette.MONEY_GREEN.darkened(0.15) if on else Color("#4A403A"), 12, 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _refresh() -> void:
	if state == null or _title == null:
		return
	_title.text = "LOBBY"
	var steam_lobby: int = int(Net.room.get("steam_lobby", 0))
	invite_button.disabled = steam_lobby == 0
	_kind_label.text = ""
	if steam_lobby != 0:
		_kind_label.text = "Public lobby · anyone can join from Browse Lobbies" if SteamSvc.lobby_data(steam_lobby, "public") == "1" else "Private lobby · friends and invites only"
	var ids: Array = state.players.keys()
	ids.sort()
	var ready_n: int = 0
	var here: int = 0
	for pid: int in ids:
		if bool(state.players[pid].get("connected", true)):
			here += 1
			if bool(state.players[pid].get("ready", false)):
				ready_n += 1
	_count_label.text = "%d / %d PLAYERS" % [here, Protocol.MAX_PLAYERS]
	_countdown_label.text = "Doors open in %d…" % ceili(state.countdown) if state.countdown > 0.0 else "Step on the pedestal with your name to get ready."
	_ready_count.text = "%d / %d READY" % [ready_n, here]
	for i: int in _rows.size():
		var r: Dictionary = _rows[i]
		var taken: bool = i < ids.size()
		var mine: bool = taken and ids[i] == local_id
		(r["frame"] as PanelContainer).add_theme_stylebox_override(&"panel", _row_box(taken, mine))
		(r["empty"] as Label).visible = not taken
		for k: String in ["name", "tag", "pill"]:
			(r[k] as Control).visible = taken
		(r["swatch"] as ColorRect).color = Color(0, 0, 0, 0)
		var portrait: TextureRect = r["portrait"]
		portrait.visible = taken
		var kick: Button = r["kick"]
		kick.visible = taken and local_id == state.leader and ids[i] != local_id
		(r["kick_gap"] as Control).visible = taken and not kick.visible and local_id == state.leader
		(r["frame"] as Control).modulate = Color.WHITE
		if not taken:
			r["pid"] = -1
			continue
		var pid: int = ids[i]
		r["pid"] = pid
		var p: Dictionary = state.players[pid]
		kick.text = "SURE?" if _kick_armed == pid and _now() < _kick_armed_until else "KICK"
		kick.tooltip_text = "Kick %s from the lobby (they can join again)" % str(p.get("name", "?"))
		var bean: int = int(p.get("bean_color", p.get("color", 0)))
		(r["swatch"] as ColorRect).color = Palette.player_color(bean)
		portrait.texture = BeanPortraits.texture_for(bean, p.get("outfit", []))
		var label: Label = r["name"]
		label.text = str(p.get("name", "?"))
		if mine:
			label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		else:
			label.remove_theme_color_override(&"font_color")
		var tags: PackedStringArray = []
		if pid == state.leader:
			tags.append("★ LEADER")
		if mine:
			tags.append("YOU")
		var away: bool = not bool(p.get("connected", true))
		if away:
			tags.append("RECONNECTING…")
			(r["frame"] as Control).modulate = Color(1, 1, 1, 0.5)
		var tag: Label = r["tag"]
		tag.text = "  ·  ".join(tags)
		tag.add_theme_color_override(&"font_color", Palette.VIP_GOLD if pid == state.leader else MUTED)
		tag.visible = not tags.is_empty()
		var is_ready: bool = bool(p.get("ready", false))
		var ready: Label = r["ready"]
		ready.text = "READY" if is_ready else "NOT READY"
		ready.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if is_ready else MUTED)
		(r["pill"] as PanelContainer).add_theme_stylebox_override(&"panel", _pill_box(is_ready))
	var leader: bool = local_id == state.leader
	_settings_note.text = "You lead this lobby: the settings are yours." if leader else "Only the lobby leader (★) can change these."
	var presets: MatchPresets = Registry.presets
	var mg: int = int(state.lobby_settings.get("minigames", presets.default_minigames))
	var gm: int = int(state.lobby_settings.get("gamble_minutes", presets.default_gamble_minutes))
	_set_stepper("minigames", "%d" % mg, leader and mg > presets.min_minigames, leader and mg < presets.max_minigames)
	var minigames_only: bool = MatchMode.is_minigames_only(state.lobby_settings)
	_set_stepper("gamble_minutes", "%d MIN" % gm if not minigames_only else "—", leader and not minigames_only and gm > presets.min_gamble_minutes, leader and not minigames_only and gm < presets.max_gamble_minutes)
	_length_note.text = "%d minigames back to back, no casino" % mg if minigames_only else "About %d min of gambling in all" % (gm * (mg + 1))
	mode_button.text = MatchMode.label(state.lobby_settings.get("mode", MatchMode.CASINO))
	mode_button.disabled = not leader
	var items_on: bool = bool(state.lobby_settings.get("items_enabled", true))
	_items_button.text = "ON" if items_on else "OFF"
	_items_button.button_pressed = items_on
	_items_button.disabled = not leader
	var on: int = selector.enabled_ids().size()
	var all: int = Registry.minigames.size()
	minigames_button.text = ("ALL %d" % all if on == all else "%d OF %d" % [on, all]) + ("  ›" if leader else "")


## One "LABEL  [−] value [+]" row; the buttons ask the server to step the setting by one.
func _add_stepper(key: String, title: String) -> void:
	var row: HBoxContainer = _setting_row(title)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(50, 46)
	minus.pressed.connect(_step_setting.bind(key, -1))
	row.add_child(minus)
	var value := Label.new()
	value.custom_minimum_size = Vector2(110, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_color_override(&"font_color", Palette.CREAM)
	row.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(50, 46)
	plus.pressed.connect(_step_setting.bind(key, 1))
	row.add_child(plus)
	_steppers[key] = {"minus": minus, "plus": plus, "value": value}


func _set_stepper(key: String, text: String, can_down: bool, can_up: bool) -> void:
	var s: Dictionary = _steppers[key]
	(s["value"] as Label).text = text
	(s["minus"] as Button).disabled = not can_down
	(s["plus"] as Button).disabled = not can_up


func _step_setting(key: String, step: int) -> void:
	var presets: MatchPresets = Registry.presets
	var fallback: int = presets.default_minigames if key == "minigames" else presets.default_gamble_minutes
	var now: int = int(state.lobby_settings.get(key, fallback))
	Net.send_intent(Intents.make(&"lobby_setting", {"key": key, "value": now + step}))


## KICK on slot `slot`: the first press arms it ("SURE?" for 3 s), the second kicks.
func _on_kick_pressed(slot: int) -> void:
	if state == null or local_id != state.leader:
		return
	var pid: int = int(_rows[slot].get("pid", -1))
	if pid < 0 or pid == local_id:
		return
	if _kick_armed == pid and _now() < _kick_armed_until:
		_kick_armed = -1
		Net.send_intent(Intents.make(&"kick_player", {"target": pid}))
	else:
		_kick_armed = pid
		_kick_armed_until = _now() + 3.0
		get_tree().create_timer(3.05).timeout.connect(_refresh)
	_refresh()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


