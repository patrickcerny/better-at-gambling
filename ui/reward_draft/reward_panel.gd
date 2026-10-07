class_name RewardPanel
extends Control
## "ROUND RESULTS" after a minigame (§2.10, Patrick's note #11): no draft. One row per player in
## placement order; the rows flip their item card one after another while the cash counts up, and
## a broke player's House Comp shows on their row ("Lucky slips you $300"). Purely a display of
## the public `rewards_started` rows; it never takes input, so the inventory-full discard choice
## (keys 1-4, handled by the ItemController) shows on top of it without being blocked.

const RARITY_COLORS: Array[Color] = [Palette.CREAM, Color("#6FA8DC"), Palette.VIP_GOLD]
const RARITY_NAMES: Array[String] = ["COMMON", "RARE", "LEGENDARY"]
## Seconds before the first row flips, and how long the cash takes to count up.
const FIRST_FLIP: float = 0.5
const COUNT_UP: float = 0.6

var state: ClientMatchState
var local_id: int = -1
var rows_box: VBoxContainer
var timer_label: Label
var discard_label: Label
var time_left: float = 0.0
## Per row: {data, card: Label, rarity: Label, cash: Label, comp: Label, flip_at: float, flipped: bool}.
var _rows: Array[Dictionary] = []
var _clock: float = 0.0
var _poll: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id


## Shows the rows from `rewards_started` ([{player, placement, cash, item, bonus?, comp?}]).
## `instant`: everything already revealed (joining in the middle of the reveal).
func open(rewards: Array, seconds: float, instant: bool = false) -> void:
	visible = true
	time_left = seconds
	_clock = 0.0
	_rows.clear()
	discard_label.text = ""
	for c: Node in rows_box.get_children():
		c.queue_free()
	var sorted: Array = rewards.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["placement"]) < int(b["placement"]))
	var step: float = Registry.balance.reward_row_time
	for i: int in sorted.size():
		var row: Dictionary = sorted[i]
		var r: Dictionary = _build_row(row)
		r["flip_at"] = -1.0 if instant else FIRST_FLIP + step * i
		_rows.append(r)
		if instant:
			_flip(r, false)
	Audio.play(&"whoosh", &"UI", -8.0)


func close() -> void:
	visible = false
	_rows.clear()


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	time_left = maxf(time_left - delta, 0.0)
	timer_label.text = "%d" % ceili(time_left) if time_left > 0.0 else ""
	for r: Dictionary in _rows:
		if not bool(r["flipped"]) and _clock >= float(r["flip_at"]):
			_flip(r, true)
		if bool(r["flipped"]):
			var cash: int = int(r["data"].get("cash", 0))
			var t: float = clampf((_clock - float(r["flip_at"])) / COUNT_UP, 0.0, 1.0) if float(r["flip_at"]) >= 0.0 else 1.0
			(r["cash"] as Label).text = "+$%s" % Hud._thousands(int(round(cash * t))) if cash > 0 else ""
	_poll += delta
	if _poll >= 0.25:
		_poll = 0.0
		discard_label.text = discard_text(Net.request_private_snapshot().get("items", {}), _inventory())


## "INVENTORY FULL" line while the server waits for the local player's discard choice ("" if none).
static func discard_text(items_priv: Dictionary, inventory: Array) -> String:
	var d: Dictionary = items_priv.get("discard", {})
	if d.is_empty():
		return ""
	var parts: PackedStringArray = []
	for i: int in inventory.size():
		parts.append("[%d] %s" % [i + 1, item_name(StringName(inventory[i]))])
	parts.append("[4] new %s" % item_name(StringName(d.get("item", ""))))
	return "INVENTORY FULL: drop one (%ds)   %s" % [ceili(float(d.get("left", 0.0))), "   ".join(parts)]


func _inventory() -> Array:
	if state == null:
		return []
	return state.players.get(local_id, {}).get("inventory", [])


func _flip(r: Dictionary, sound: bool) -> void:
	r["flipped"] = true
	var data: Dictionary = r["data"]
	var item: StringName = StringName(data.get("item", &""))
	var card: Label = r["card"]
	var rarity_label: Label = r["rarity"]
	if item == &"":
		card.text = "—"
		rarity_label.text = ""
	else:
		var rarity: int = item_rarity(item)
		card.text = item_name(item)
		card.add_theme_color_override(&"font_color", RARITY_COLORS[rarity])
		rarity_label.text = RARITY_NAMES[rarity]
		rarity_label.add_theme_color_override(&"font_color", RARITY_COLORS[rarity])
		var bonus: StringName = StringName(data.get("bonus", &""))
		if bonus != &"":
			rarity_label.text += "  + UNDERDOG %s" % item_name(bonus).to_upper()
	var comp: int = int(data.get("comp", 0))
	(r["comp"] as Label).text = "Lucky slips you $%s" % Hud._thousands(comp) if comp > 0 else ""
	var card_box: Control = card.get_parent().get_parent()
	card_box.pivot_offset = card_box.size * 0.5
	card_box.scale = Vector2(0.0, 1.0)
	var tw: Tween = create_tween()
	tw.tween_property(card_box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if sound:
		Audio.play(&"ui_click", &"UI", -6.0)
		if int(data.get("cash", 0)) > 0 or comp > 0:
			Audio.play(&"coin", &"UI", -8.0 if int(data.get("player", -1)) != local_id else -3.0)


func _build_row(row: Dictionary) -> Dictionary:
	var pid: int = int(row["player"])
	var framed := PanelContainer.new()
	framed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	framed.theme_type_variation = &"RowPanelHighlight" if pid == local_id else &"RowPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	framed.add_child(h)
	var place := Label.new()
	place.text = Hud._ordinal(int(row["placement"]))
	place.custom_minimum_size = Vector2(64, 0)
	place.add_theme_color_override(&"font_color", Palette.VIP_GOLD if int(row["placement"]) == 1 else Palette.CREAM)
	h.add_child(place)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = Palette.player_color(int(state.players.get(pid, {}).get("color", 0))) if state != null else Palette.CREAM
	h.add_child(dot)
	var n := Label.new()
	n.text = state.player_name(pid) if state != null else "Player"
	n.custom_minimum_size = Vector2(210, 0)
	n.clip_text = true
	if pid == local_id:
		n.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	h.add_child(n)
	var cash := Label.new()
	cash.theme_type_variation = &"MoneyLabel"
	cash.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
	cash.add_theme_font_size_override(&"font_size", 32)
	cash.custom_minimum_size = Vector2(130, 0)
	h.add_child(cash)
	# The item card: face down ("?") until its row flips.
	var card_box := PanelContainer.new()
	card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.theme_type_variation = &"RowPanel"
	card_box.custom_minimum_size = Vector2(300, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 0)
	card_box.add_child(cv)
	var card := Label.new()
	card.theme_type_variation = &"HeadingLabel"
	card.text = "?"
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(card)
	var rarity := Label.new()
	rarity.theme_type_variation = &"SmallLabel"
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(rarity)
	h.add_child(card_box)
	var comp := Label.new()
	comp.theme_type_variation = &"SmallLabel"
	comp.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	comp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	comp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	comp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(comp)
	rows_box.add_child(framed)
	return {"data": row, "card": card, "rarity": rarity, "cash": cash, "comp": comp, "flip_at": 0.0, "flipped": false}


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
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560
	panel.offset_right = 560
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
	title.text = "ROUND RESULTS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	timer_label = Label.new()
	timer_label.theme_type_variation = &"MoneyLabel"
	timer_label.add_theme_font_size_override(&"font_size", 48)
	top.add_child(timer_label)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override(&"separation", 4)
	v.add_child(rows_box)
	discard_label = Label.new()
	discard_label.theme_type_variation = &"HeadingLabel"
	discard_label.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	discard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(discard_label)
