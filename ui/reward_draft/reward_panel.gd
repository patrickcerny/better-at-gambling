class_name RewardPanel
extends Control
## The reward phase after a minigame (§2.10): everyone's placement and cash, and the local
## player's item draft (pick 1 of the offered items with a click or 1-3, 8 s, default = first).
## Offers arrive as private data; picks go out as `draft_pick` intents.

const RARITY_COLORS: Array[Color] = [Palette.CREAM, Color("#6FA8DC"), Palette.VIP_GOLD]
const RARITY_NAMES: Array[String] = ["COMMON", "RARE", "LEGENDARY"]

var state: ClientMatchState
var local_id: int = -1
var rows_box: VBoxContainer
var draft_box: VBoxContainer
var choices_row: HBoxContainer
var draft_title: Label
var bonus_label: Label
var timer_label: Label
var result_label: Label
var time_left: float = 0.0
var _offer_key: String = ""
var _picked: int = -1
var _choice_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id


## Shows the reward table from `rewards_started` ([{player, placement, cash, draft, bonus_count}]).
func open(rewards: Array, seconds: float) -> void:
	visible = true
	time_left = seconds
	_offer_key = ""
	_picked = -1
	result_label.text = ""
	draft_box.visible = false
	for c: Node in rows_box.get_children():
		c.queue_free()
	var sorted: Array = rewards.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["placement"]) < int(b["placement"]))
	for r: Variant in sorted:
		var row: Dictionary = r
		var framed := PanelContainer.new()
		framed.theme_type_variation = &"RowPanelHighlight" if int(row["player"]) == local_id else &"RowPanel"
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 18)
		framed.add_child(h)
		var place := Label.new()
		place.text = Hud._ordinal(int(row["placement"]))
		place.custom_minimum_size = Vector2(70, 0)
		place.add_theme_color_override(&"font_color", Palette.VIP_GOLD if int(row["placement"]) == 1 else Palette.CREAM)
		h.add_child(place)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(18, 18)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Palette.player_color(int(state.players.get(int(row["player"]), {}).get("color", 0)))
		h.add_child(dot)
		var n := Label.new()
		n.text = state.player_name(int(row["player"]))
		n.custom_minimum_size = Vector2(260, 0)
		if int(row["player"]) == local_id:
			n.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		h.add_child(n)
		var cash := Label.new()
		cash.theme_type_variation = &"MoneyLabel"
		cash.text = "+$%s" % Hud._thousands(int(row["cash"])) if int(row["cash"]) > 0 else ""
		cash.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
		cash.add_theme_font_size_override(&"font_size", 36)
		cash.custom_minimum_size = Vector2(150, 0)
		h.add_child(cash)
		var extra := Label.new()
		extra.theme_type_variation = &"SmallLabel"
		var bits: PackedStringArray = []
		if bool(row.get("draft", false)):
			bits.append("item pick")
		if int(row.get("bonus_count", 0)) > 0:
			bits.append("+%d bonus item%s" % [int(row["bonus_count"]), "s" if int(row["bonus_count"]) > 1 else ""])
		extra.text = " · ".join(bits)
		extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(extra)
		rows_box.add_child(framed)
	Audio.play(&"coin", &"UI", -6.0)


func close() -> void:
	visible = false


## Our own draft result (`draft_result` for the local player).
func show_result(items: Array, kept: Array) -> void:
	var names: PackedStringArray = []
	for id: Variant in items:
		names.append(item_name(StringName(id)))
	result_label.text = "You got: %s" % ", ".join(names) if not names.is_empty() else ""
	if kept.size() < items.size():
		result_label.text += "  (inventory full: %d dropped)" % (items.size() - kept.size())


func _process(delta: float) -> void:
	if not visible:
		return
	time_left = maxf(time_left - delta, 0.0)
	timer_label.text = "%d" % ceili(time_left) if time_left > 0.0 else ""
	var priv: Dictionary = Net.request_private_snapshot()
	var draft: Dictionary = priv.get("draft", {})
	var key: String = str(draft.get("choices", [])) + str(draft.get("bonus", []))
	if not draft.is_empty() and key != _offer_key:
		_offer_key = key
		_show_offer(draft)
	if not draft.is_empty() and int(draft.get("pick", -1)) >= 0 and _picked < 0:
		_mark_pick(int(draft["pick"]))


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _choice_buttons.is_empty() or _picked >= 0:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var i: int = (event as InputEventKey).keycode - KEY_1
		if i >= 0 and i < _choice_buttons.size():
			_pick(i)
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var i: int = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X].find((event as InputEventJoypadButton).button_index)
		if i >= 0 and i < _choice_buttons.size():
			_pick(i)
			get_viewport().set_input_as_handled()


func _show_offer(draft: Dictionary) -> void:
	draft_box.visible = true
	for c: Node in choices_row.get_children():
		c.queue_free()
	_choice_buttons.clear()
	var choices: Array = draft.get("choices", [])
	draft_title.text = "PICK YOUR REWARD" if not choices.is_empty() else "YOUR ITEMS"
	for i: int in choices.size():
		var id: StringName = StringName(choices[i])
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 170)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick.bind(i))
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_right = -14
		v.offset_top = 10
		v.offset_bottom = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var rarity: int = item_rarity(id)
		var r := Label.new()
		r.theme_type_variation = &"SmallLabel"
		r.text = "%d · %s" % [i + 1, RARITY_NAMES[rarity]]
		r.add_theme_color_override(&"font_color", RARITY_COLORS[rarity])
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(r)
		var n := Label.new()
		n.theme_type_variation = &"HeadingLabel"
		n.text = item_name(id)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(n)
		var d := Label.new()
		d.theme_type_variation = &"SmallLabel"
		d.text = item_description(id)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		choices_row.add_child(b)
		_choice_buttons.append(b)
	var bonus: Array = draft.get("bonus", [])
	var names: PackedStringArray = []
	for id: Variant in bonus:
		names.append(item_name(StringName(id)))
	bonus_label.text = ("Bonus: %s" % ", ".join(names)) if not names.is_empty() else ""


func _pick(i: int) -> void:
	if _picked >= 0:
		return
	_mark_pick(i)
	Audio.play(&"ui_click", &"UI", -4.0)
	Net.send_intent(Intents.make(&"draft_pick", {"choice": i}))


func _mark_pick(i: int) -> void:
	_picked = i
	for j: int in _choice_buttons.size():
		_choice_buttons[j].disabled = j != i
		_choice_buttons[j].modulate = Color.WHITE if j == i else Color(1, 1, 1, 0.4)


static func item_name(id: StringName) -> String:
	var def: ItemDefinition = Registry.items.get(id, null)
	return def.display_name if def != null else String(id).capitalize()


static func item_description(id: StringName) -> String:
	var def: ItemDefinition = Registry.items.get(id, null)
	return def.description if def != null else ""


static func item_rarity(id: StringName) -> int:
	var def: ItemDefinition = Registry.items.get(id, null)
	return clampi(def.rarity if def != null else 0, 0, 2)


func _build() -> void:
	theme = load("res://ui/theme/main_theme.tres") as Theme
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -320
	panel.offset_bottom = 320
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "QUIZ RESULTS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	timer_label = Label.new()
	timer_label.theme_type_variation = &"MoneyLabel"
	timer_label.add_theme_font_size_override(&"font_size", 48)
	top.add_child(timer_label)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override(&"separation", 4)
	v.add_child(rows_box)
	draft_box = VBoxContainer.new()
	draft_box.visible = false
	v.add_child(draft_box)
	draft_title = Label.new()
	draft_title.theme_type_variation = &"HeadingLabel"
	draft_title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	draft_box.add_child(draft_title)
	choices_row = HBoxContainer.new()
	choices_row.add_theme_constant_override(&"separation", 16)
	draft_box.add_child(choices_row)
	bonus_label = Label.new()
	bonus_label.theme_type_variation = &"SmallLabel"
	draft_box.add_child(bonus_label)
	result_label = Label.new()
	result_label.theme_type_variation = &"HeadingLabel"
	v.add_child(result_label)
