class_name StationUi
extends Control
## Base for the per-game overlays shown while seated. Subclasses build their controls in
## `_build`, redraw from the station's public/private state in `_refresh`, and send intents
## with `send`. Esc / leave_station is handled by the match scene (stand up). While seated the
## cursor is free (InputRouter), so every button here is clicked with the mouse as well.

signal rejected(error: StringName)
## A short heads-up for the HUD toast (e.g. "ALL IN").
signal notice(text: String)

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
## True at a waiting-room table (`FunRoom`): play money, shown as such under the title.
var fun: bool = false
## "PLAY MONEY $1,000" under the title at a waiting-room table (hidden elsewhere).
var play_money_label: Label
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
	play_money_label = Label.new()
	play_money_label.name = "PlayMoney"
	play_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_money_label.add_theme_font_size_override(&"font_size", 22)
	play_money_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	play_money_label.visible = false
	body.add_child(play_money_label)
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
	fun = FunRoom.is_fun(station_id)
	title.text = game_title
	play_money_label.visible = fun
	_show_play_money()
	_sync_bet_panel()
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
	_show_play_money()
	_sync_bet_panel()
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


## The balance this table plays with: the waiting room's play money at a fun table, else the
## real balance.
func my_balance() -> int:
	if state == null:
		return 0
	return state.fun_balance(local_id) if fun else state.balance(local_id)


func _show_play_money() -> void:
	if fun and play_money_label != null:
		play_money_label.text = "PLAY MONEY  %s  ·  just for fun" % money(my_balance())


## The table's `BetPanel` (a subclass's `bet_panel`), null for tables without one.
func the_bet_panel() -> BetPanel:
	return get(&"bet_panel") as BetPanel


## All-in: the bet panel clamps to what you have, and its first all-in per bet is a toast.
## Any table whose overlay has a `bet_panel: BetPanel` gets this without doing anything.
func _sync_bet_panel() -> void:
	var bp: BetPanel = the_bet_panel()
	if bp == null:
		return
	if not bp.went_all_in.is_connected(_on_went_all_in):
		bp.went_all_in.connect(_on_went_all_in)
	if state != null:
		bp.set_balance(my_balance())


## What the table still takes from you this round when its max is a per-round total (roulette,
## horse race): the bet panel's max minus your bets in the public state's `bets` list.
func bet_room() -> int:
	var bp: BetPanel = the_bet_panel()
	if bp == null:
		return 0
	var total: int = 0
	for b: Variant in pub.get("bets", []):
		if b is Dictionary and int((b as Dictionary).get("player", -1)) == local_id:
			total += int((b as Dictionary).get("amount", 0))
	return maxi(bp.max_bet - total, 0)


func _on_went_all_in(amount: int) -> void:
	notice.emit(all_in_text(amount))


static func all_in_text(amount: int) -> String:
	return "ALL IN: betting everything you have (%s)" % money(amount)


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
		&"one_horse_only":
			return "One horse per race"
		&"invalid_horse":
			return "Pick a horse"
		&"invalid_symbol":
			return "Pick a symbol"
		&"card_open":
			return "Scratch your card first"
		&"no_card":
			return "No card to scratch"
	return String(error).capitalize()
