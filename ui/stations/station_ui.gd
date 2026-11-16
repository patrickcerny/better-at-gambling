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
## Right-hand column (`_dock_column`): its width, its gap to the right and top edges (clear of the
## HUD's clock), and its gap to the bottom (clear of the HUD's rank).
const COLUMN_WIDTH: float = 600.0
const COLUMN_MARGIN: Vector2 = Vector2(24.0, 196.0)
const COLUMN_BOTTOM: float = 104.0

## Display name shown in the header.
var game_title: String = "GAME"
## True at a waiting-room table (`FunRoom`): play money, shown as such under the title.
var fun: bool = false
## "PLAY MONEY $1,000" under the title at a waiting-room table (hidden elsewhere).
var play_money_label: Label
## The folded "HOW IT WORKS" line and its text (null unless `_rules_text` gives one).
var rules_toggle: Button
var rules_label: Label
## InputGlyphs.epoch the key hints were last written for.
var _glyph_epoch: int = -1
## The engraved title row (the title between two brass rules) and the felt band the status
## line sits in.
var header: HBoxContainer
var status_band: PanelContainer
## The draining brass bar under the status band: how long bets stay open / you have to act.
var countdown: CountdownBar
## The ribbon over the panel's top edge that shows a round's result ("WIN +$120").
var result_ribbon: PanelContainer
var result_ribbon_label: Label
## Gamepad bet picker (`pad_targets`): which target the gold frame is on, the frame itself, and
## the left stick's latch (one step per push; held, it repeats).
var pad_index: int = 0
var pad_frame: Panel
var _pad_latched: bool = false
var _pad_hold: float = 0.0
## Stick push (0..1) that moves the picker one step, and where it lets go again.
const PAD_PUSH: float = 0.6
const PAD_RELEASE: float = 0.3
## A held stick repeats a step after this long, then every `PAD_REPEAT`.
const PAD_REPEAT_DELAY: float = 0.4
const PAD_REPEAT: float = 0.16
## A round's results arrive one per bet: summed over a short window into one ribbon.
var _ribbon_stake: int = 0
var _ribbon_net: int = 0
var _ribbon_pending: bool = false


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
	if _dock_column():
		# A column down the right third, under the HUD's clock and over its rank: the table fills
		# the left two thirds of the screen (the seat camera frames it there).
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.anchor_top = 0.0
		panel.anchor_bottom = 1.0
		panel.offset_left = -(_column_width() + COLUMN_MARGIN.x)
		panel.offset_right = -COLUMN_MARGIN.x
		panel.offset_top = COLUMN_MARGIN.y
		panel.offset_bottom = -COLUMN_BOTTOM
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		if not _column_fills_height():
			# Only as tall as its content, from the top of the column down.
			panel.anchor_bottom = 0.0
			panel.offset_bottom = COLUMN_MARGIN.y
			panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.add_theme_stylebox_override(&"panel", TableSkin.panel_box())
	panel.draw.connect(func() -> void: TableSkin.draw_frame(panel))
	add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	panel.add_child(body)
	header = HBoxContainer.new()
	header.name = "Header"
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override(&"separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(header)
	var left_rule := DecoRule.new(false, 56.0)
	left_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left_rule)
	title = Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = game_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override(&"font", TableSkin.black_font())
	title.add_theme_font_size_override(&"font_size", 34)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.add_theme_color_override(&"font_outline_color", Color("#3A2410"))
	title.add_theme_constant_override(&"outline_size", 6)
	title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override(&"shadow_offset_y", 3)
	title.add_theme_constant_override(&"shadow_offset_x", 0)
	header.add_child(title)
	var right_rule := DecoRule.new(true, 56.0)
	right_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(right_rule)
	# A hidden title (the slot machine's marquee says what it is) takes its rules with it.
	title.visibility_changed.connect(func() -> void: header.visible = title.visible)
	play_money_label = Label.new()
	play_money_label.name = "PlayMoney"
	play_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_money_label.add_theme_font_size_override(&"font_size", 22)
	play_money_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	play_money_label.visible = false
	body.add_child(play_money_label)
	status_band = PanelContainer.new()
	status_band.name = "StatusBand"
	status_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_band.add_theme_stylebox_override(&"panel", TableSkin.band_box(Color(TableSkin.FELT_DEEP, 0.95), Color(TableSkin.BRASS, 0.7)))
	body.add_child(status_band)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override(&"font_size", 26)
	status_label.add_theme_font_override(&"font", TableSkin.heavy_font())
	status_label.add_theme_color_override(&"font_color", Palette.CREAM)
	status_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.45))
	status_label.add_theme_constant_override(&"outline_size", 4)
	status_band.add_child(status_label)
	# An empty status line takes its band away too.
	status_band.visible = false
	countdown = CountdownBar.new()
	countdown.name = "Countdown"
	body.add_child(countdown)
	_build_ribbon()
	if _dock_column():
		# The column has a fixed height: a tighter rhythm keeps the folded-open rules inside it.
		body.add_theme_constant_override(&"separation", 6)
		title.add_theme_font_size_override(&"font_size", 30)
	_build()
	if _dock_column() and _column_fills_height():
		# The key hint and the folded rules sit at the foot of the column.
		var push := Control.new()
		push.name = "Push"
		push.size_flags_vertical = Control.SIZE_EXPAND_FILL
		push.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(push)
	TableSkin.skin_buttons(panel)
	hint = Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.text = _hint_text()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override(&"font_color", Color("#9A8F7A"))
	hint.add_theme_font_size_override(&"font_size", 16)
	body.add_child(hint)
	var how: String = _rules_text()
	if not how.is_empty():
		_add_rules(how)
	_build_pad_frame()
	no_gui_focus(self)


## Nothing at a table takes GUI focus: with a focusable button there, the engine hands it the
## focus on the first d-pad press (which then never reaches the items) and A would press it
## instead of betting. The mouse still clicks everything; pads use the keys and the picker.
## Runs after the build and after every redraw (tables rebuild chips and bonus buttons).
static func no_gui_focus(node: Node) -> void:
	for c: Node in node.find_children("*", "BaseButton", true, false):
		(c as BaseButton).focus_mode = Control.FOCUS_NONE


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
	_after_refresh()
	if InputGlyphs.gamepad and not pad_targets().is_empty() and _pad_current() < 0:
		pad_select(clampi(pad_index, 0, pad_targets().size() - 1))


## How the game works, folded away under the key hint: one small "HOW IT WORKS" line that opens
## the text (and shows it as its tooltip), so the explanation takes no screen space by default.
func _add_rules(text: String) -> void:
	rules_toggle = Button.new()
	rules_toggle.name = "RulesToggle"
	rules_toggle.flat = true
	rules_toggle.toggle_mode = true
	rules_toggle.focus_mode = Control.FOCUS_NONE
	rules_toggle.text = "HOW IT WORKS  ▸"
	rules_toggle.tooltip_text = text
	rules_toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_toggle.add_theme_font_size_override(&"font_size", 15)
	for state_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		rules_toggle.add_theme_color_override(state_name, Palette.WARM_GOLD)
	body.add_child(rules_toggle)
	rules_label = Label.new()
	rules_label.name = "Rules"
	rules_label.theme_type_variation = &"SmallLabel"
	rules_label.text = text
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_label.custom_minimum_size = Vector2(120, 0)
	rules_label.add_theme_font_size_override(&"font_size", 15)
	rules_label.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.15))
	rules_label.visible = false
	body.add_child(rules_label)
	rules_toggle.toggled.connect(func(on: bool) -> void:
		rules_label.visible = on
		rules_toggle.text = "HOW IT WORKS  ▾" if on else "HOW IT WORKS  ▸")


func close() -> void:
	visible = false


# --- Gamepad picker ----------------------------------------------------------------------------
# Tables you bet on by clicking a spot (craps, the wheel, the horses, baccarat, Plinko's risk,
# the scratch-card counter) list those spots in `pad_targets`. On a gamepad the left stick (free
# while seated) moves a gold frame between them and `_pad_selected` tells the table; A presses the
# framed spot (`_pad_activate`, by default its button). The d-pad keeps using items.

## Override: the spots a gamepad can pick, in reading order ([] = no picker at this table).
func pad_targets() -> Array[Control]:
	return []


## True while the picker shows and takes the stick and A.
func pad_active() -> bool:
	return visible and InputGlyphs.gamepad and not pad_targets().is_empty()


## Override: the target that is the table's current choice (Plinko's risk), -1 = none. The frame
## sits on it whatever chose it (the mouse included).
func _pad_current() -> int:
	return -1


## Override: the frame moved onto target `i` (remember it as the table's chosen spot).
func _pad_selected(_i: int) -> void:
	pass


## Override: A on target `i`; true when it was used (the press goes no further). By default it
## presses the target's button when that can be pressed.
func _pad_activate(i: int) -> bool:
	var t: Array[Control] = pad_targets()
	if i < 0 or i >= t.size():
		return false
	var b: BaseButton = t[i] as BaseButton
	if b == null or not b.is_visible_in_tree():
		return false
	if b.disabled:
		Audio.play(&"buzzer", &"UI", -18.0, 1.4)
		return true
	b.pressed.emit()
	return true


## Moves the frame one step towards `dir` (screen space): onto the nearest target that way.
func pad_move(dir: Vector2) -> void:
	var t: Array[Control] = pad_targets()
	if t.is_empty():
		return
	pad_index = clampi(pad_index, 0, t.size() - 1)
	var from: Vector2 = t[pad_index].get_global_rect().get_center()
	var best: int = -1
	var best_score: float = INF
	for i: int in t.size():
		if i == pad_index or not t[i].is_visible_in_tree():
			continue
		var d: Vector2 = t[i].get_global_rect().get_center() - from
		var along: float = d.dot(dir)
		if along <= 1.0:
			continue
		var across: float = absf(d.cross(dir))
		var score: float = along + across * 2.5
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		pad_select(best)


## Puts the frame on target `i`.
func pad_select(i: int) -> void:
	var t: Array[Control] = pad_targets()
	if t.is_empty():
		return
	i = clampi(i, 0, t.size() - 1)
	if i != pad_index:
		Audio.play(&"ui_hover", &"UI", -14.0)
	pad_index = i
	_pad_selected(i)
	_place_pad_frame()


func _build_pad_frame() -> void:
	pad_frame = Panel.new()
	pad_frame.name = "PadFrame"
	pad_frame.top_level = true
	pad_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad_frame.z_index = 4
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Palette.VIP_GOLD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(Palette.VIP_GOLD, 0.45)
	sb.shadow_size = 12
	pad_frame.add_theme_stylebox_override(&"panel", sb)
	pad_frame.visible = false
	add_child(pad_frame)


func _place_pad_frame() -> void:
	if pad_frame == null:
		return
	var t: Array[Control] = pad_targets()
	var show: bool = pad_active() and pad_index < t.size() and t[pad_index].is_visible_in_tree()
	pad_frame.visible = show
	if show:
		var r: Rect2 = t[pad_index].get_global_rect().grow(5.0)
		pad_frame.global_position = r.position
		pad_frame.size = r.size


## The left stick, read straight from the pads (not through the move actions: WASD are table keys
## while seated, S stands and D doubles at blackjack).
static func left_stick() -> Vector2:
	var best := Vector2.ZERO
	for d: int in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if v.length() > best.length():
			best = v
	return best


func _process(delta: float) -> void:
	if not visible:
		return
	_pad_step(left_stick(), delta)
	var cur: int = _pad_current()
	if cur >= 0:
		pad_index = cur
	_place_pad_frame()


## One frame of stick input for the picker: a push past `PAD_PUSH` steps once, holding repeats.
func _pad_step(stick: Vector2, delta: float) -> void:
	if not pad_active():
		_pad_latched = false
		return
	if stick.length() < PAD_RELEASE:
		_pad_latched = false
		return
	if stick.length() < PAD_PUSH:
		return
	var dir: Vector2 = Vector2(signf(stick.x), 0.0) if absf(stick.x) >= absf(stick.y) else Vector2(0.0, signf(stick.y))
	if not _pad_latched:
		_pad_latched = true
		_pad_hold = -PAD_REPEAT_DELAY
		pad_move(dir)
		return
	_pad_hold += delta
	if _pad_hold >= PAD_REPEAT:
		_pad_hold = 0.0
		pad_move(dir)


## A clicked button keeps keyboard focus, and Space/Enter would then press it again instead of
## reaching the bet/action keys: let go of the focus once a click is done.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		var f: Control = get_viewport().gui_get_focus_owner()
		if f != null and is_ancestor_of(f):
			get_viewport().gui_release_focus.call_deferred()
	# Gamepad picker: A presses the framed spot before the table's own A (bet / hit) sees it.
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A and pad_active():
		if _pad_activate(clampi(pad_index, 0, pad_targets().size() - 1)):
			get_viewport().set_input_as_handled()


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
		_after_refresh()


## Rewrites every key hint for the device in use (keyboard + mouse or gamepad).
func _update_glyphs() -> void:
	_glyph_epoch = InputGlyphs.epoch
	hint.text = _hint_text()
	_relabel()


## The look that follows every redraw: the status band shows only with a status, and the
## countdown follows the public `timer` (`_countdown_seconds`).
func _after_refresh() -> void:
	no_gui_focus(panel)
	status_band.visible = status_label.visible and status_label.text != ""
	var left: float = _countdown_seconds()
	countdown.feed(left, str(pub.get("state", "")))


## Seconds left on the table's clock for the countdown bar (-1 = no bar). Default: the public
## `timer` while it runs.
func _countdown_seconds() -> float:
	if not pub.has("timer"):
		return -1.0
	return float(pub.get("timer", 0.0))


## The result ribbon (`round_result` events for you at this table, summed per round).
func _build_ribbon() -> void:
	result_ribbon = PanelContainer.new()
	result_ribbon.name = "ResultRibbon"
	result_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_ribbon.visible = false
	result_ribbon.z_index = 5
	add_child(result_ribbon)
	result_ribbon_label = Label.new()
	result_ribbon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_ribbon_label.add_theme_font_override(&"font", TableSkin.black_font())
	result_ribbon_label.add_theme_font_size_override(&"font_size", 34)
	result_ribbon_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.5))
	result_ribbon_label.add_theme_constant_override(&"outline_size", 6)
	result_ribbon.add_child(result_ribbon_label)
	panel.item_rect_changed.connect(func() -> void:
		if result_ribbon.visible:
			_place_ribbon())
	if not Net.event_received.is_connected(_on_table_event):
		Net.event_received.connect(_on_table_event)
	tree_exiting.connect(func() -> void:
		if Net.event_received.is_connected(_on_table_event):
			Net.event_received.disconnect(_on_table_event))


func _on_table_event(ev: Dictionary) -> void:
	if not visible or not _shows_result_ribbon() or StringName(ev.get("type", &"")) != &"round_result":
		return
	if StringName(ev.get("station", &"")) != station_id or int(ev.get("player", -1)) != local_id:
		return
	_ribbon_stake += int(ev.get("stake", 0))
	_ribbon_net += int(ev.get("net", 0))
	if not _ribbon_pending:
		_ribbon_pending = true
		get_tree().create_timer(0.35).timeout.connect(_flush_ribbon)


func _flush_ribbon() -> void:
	_ribbon_pending = false
	var net: int = _ribbon_net
	var stake: int = _ribbon_stake
	_ribbon_net = 0
	_ribbon_stake = 0
	if stake <= 0 and net == 0:
		return
	show_result(net)


## Shows the ribbon for a result of `net` (won > 0, lost < 0, push 0) for a few seconds.
func show_result(net: int) -> void:
	var face: Color
	var ink: Color = Palette.CREAM
	if net > 0:
		result_ribbon_label.text = "WIN  +%s" % money(net)
		face = Color("#C9973F")
		ink = Palette.CASINO_BLACK
		Audio.play(&"ui_click", &"UI", -14.0, 1.5)
	elif net < 0:
		result_ribbon_label.text = "LOST  %s" % money(-net)
		face = Color("#7A1F28")
	else:
		result_ribbon_label.text = "PUSH  ·  BET BACK"
		face = TableSkin.WALNUT_LIGHT
	result_ribbon_label.add_theme_color_override(&"font_color", ink)
	result_ribbon_label.add_theme_constant_override(&"outline_size", 0 if net > 0 else 6)
	var sb: StyleBoxFlat = TableSkin.band_box(face, Palette.VIP_GOLD if net > 0 else Color(Palette.CREAM, 0.6), 10)
	sb.set_border_width_all(2)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.shadow_color = Color(Palette.VIP_GOLD, 0.45) if net > 0 else Color(0, 0, 0, 0.5)
	sb.shadow_size = 18 if net > 0 else 10
	result_ribbon.add_theme_stylebox_override(&"panel", sb)
	result_ribbon.visible = true
	result_ribbon.reset_size()
	_place_ribbon()
	result_ribbon.modulate = Color.WHITE
	TableSkin.pop(result_ribbon, 0.3)
	var tw: Tween = result_ribbon.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(result_ribbon, ^"modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: result_ribbon.visible = false)


func _place_ribbon() -> void:
	var r: Rect2 = panel.get_rect()
	result_ribbon.position = Vector2(r.position.x + (r.size.x - result_ribbon.size.x) * 0.5, r.position.y - result_ribbon.size.y * 0.55)


## False for tables whose results are many small ones shown elsewhere (Plinko's chip history).
func _shows_result_ribbon() -> bool:
	return true


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


## True for overlays that fill a column down the right third of the screen, top to bottom, so the
## table (framed by the seat camera in the left two thirds) is never covered.
func _dock_column() -> bool:
	return false


## The column's width (`_dock_column`); a compact overlay narrows it.
func _column_width() -> float:
	return COLUMN_WIDTH


## False for a compact column (`_dock_column`): only as tall as its content, not down to the rank.
func _column_fills_height() -> bool:
	return true


## Override: how the game works, folded away under the key hint ("" = no such line).
func _rules_text() -> String:
	return ""


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
		&"point_is_on":
			return "Line bets go down on the come-out roll"
		&"one_side_only":
			return "Pass or Don't Pass, not both"
		&"not_shooter":
			return "You're not the shooter"
		&"no_bets":
			return "Someone has to bet first"
		&"wait_for_bets":
			return "Give the table a moment to bet"
		&"invalid_symbol":
			return "Pick a symbol"
		&"no_chance":
			return "No card can do that"
		&"nothing_to_cash":
			return "Win a call first"
		&"card_open":
			return "Scratch your card first"
		&"no_card":
			return "No card to scratch"
		&"pulling":
			return "The sword is still moving"
	return String(error).capitalize()
