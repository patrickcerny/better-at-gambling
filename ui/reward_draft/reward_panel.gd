class_name RewardPanel
extends Control
## "ROUND RESULTS" after a minigame (§2.10, Patrick's note #11): no draft. One row per player in
## placement order; the rows flip their item card one after another while the cash counts up, and
## a broke player's House Comp shows on their row ("Lucky slips you $300"). Purely a display of
## the public `rewards_started` rows; it never takes input, so the inventory-full discard choice
## (keys 1-4, handled by the ItemController) shows on top of it without being blocked.
##
## The look (Patrick 2026-11-16, "round results look shitty"): the table overlays' walnut panel in
## a brass frame (`TableSkin`), only as big as its rows. Each row: a gold/silver/bronze medallion
## (`PlaceBadge`), the player's bean in its outfit (`BeanPortraits`), the cash counting up, and the
## item as a card that flips over to the item's own 3D model turning in it, framed in its rarity
## colour (legendary ones glow).

const RARITY_COLORS: Array[Color] = [Palette.CREAM, Color("#6FA8DC"), Palette.VIP_GOLD]
const RARITY_NAMES: Array[String] = ["COMMON", "RARE", "LEGENDARY"]
## Card frame colours per rarity (common gets a quiet brass edge, the cream is for its text).
const RARITY_FRAMES: Array[Color] = [TableSkin.BRASS_DARK, Color("#6FA8DC"), Palette.VIP_GOLD]
## Seconds before the first row flips, and how long the cash takes to count up.
const FIRST_FLIP: float = 0.5
const COUNT_UP: float = 0.9
## Rows slide in this far apart (seconds) when the panel opens.
const ROW_STAGGER: float = 0.06
## Item card and portrait sizes.
const CARD_SIZE: Vector2 = Vector2(300, 92)
const MODEL_PX: float = 84.0
const PORTRAIT_SIZE: Vector2 = Vector2(68, 80)
## Pixel size of the live item render (twice the shown size, so it stays crisp).
const LIVE_SIZE: int = 168
const LIVE_SPIN: float = 0.9
## From this many rows on, the rows are a little smaller (eight still fit a 1080p screen).
const COMPACT_FROM: int = 5
const COMPACT: float = 0.82

var state: ClientMatchState
var local_id: int = -1
var rows_box: VBoxContainer
var timer_label: Label
var countdown: CountdownBar
var discard_label: Label
var discard_band: PanelContainer
var panel: PanelContainer
var time_left: float = 0.0
## Per row: {data, row, card_box, card, rarity, cash, comp, face, back, model_rect, vp, model,
## frame, rarity_id, flip_at, flipped, counted}.
var _rows: Array[Dictionary] = []
var _clock: float = 0.0
var _poll: float = 0.0
var _live: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_live = DisplayServer.get_name() != "headless"
	add_child(BeanPortraits.new())
	add_child(ItemThumbnails.new())
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
	_clear_rows()
	discard_label.text = ""
	discard_band.visible = false
	countdown.feed(seconds, "rewards%d" % Time.get_ticks_msec())
	var sorted: Array = rewards.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["placement"]) < int(b["placement"]))
	var step: float = Registry.balance.reward_row_time
	rows_box.add_theme_constant_override(&"separation", 5 if sorted.size() > COMPACT_FROM else 8)
	for i: int in sorted.size():
		var row: Dictionary = sorted[i]
		var r: Dictionary = _build_row(row, sorted.size() > COMPACT_FROM)
		r["flip_at"] = -1.0 if instant else FIRST_FLIP + step * i
		_rows.append(r)
		if instant:
			_flip(r, false)
		else:
			var line: Control = r["row"]
			line.modulate = Color(1, 1, 1, 0)
			var tw: Tween = line.create_tween()
			tw.tween_interval(ROW_STAGGER * i)
			tw.tween_property(line, ^"modulate", Color.WHITE, 0.22).set_trans(Tween.TRANS_SINE)
	if not instant and panel.is_inside_tree():
		TableSkin.pop(panel, 0.9)
	Audio.play(&"whoosh", &"UI", -8.0)


func close() -> void:
	visible = false
	_clear_rows()


func _clear_rows() -> void:
	for r: Dictionary in _rows:
		var vp: SubViewport = r.get("vp", null)
		if vp != null and is_instance_valid(vp):
			vp.queue_free()
	_rows.clear()
	if rows_box != null:
		for c: Node in rows_box.get_children():
			c.queue_free()


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
			t = 1.0 - pow(1.0 - t, 3.0)  # fast first, settling on the total
			(r["cash"] as Label).text = cash_text(int(round(cash * t))) if cash > 0 else ""
			if t >= 1.0 and not bool(r["counted"]):
				r["counted"] = true
				if cash > 0 and float(r["flip_at"]) >= 0.0:
					TableSkin.flash(r["cash"] as Label)
		var model: Node3D = r.get("model", null)
		if model != null and is_instance_valid(model):
			model.rotation.y += LIVE_SPIN * delta
		if int(r.get("rarity_id", 0)) == 2 and bool(r["flipped"]):
			# Legendary: the card's glow breathes.
			var sb: StyleBoxFlat = r["frame"]
			sb.shadow_color = Color(Palette.VIP_GOLD, 0.30 + 0.22 * sin(_clock * 3.2))
	_poll += delta
	if _poll >= 0.25:
		_poll = 0.0
		discard_label.text = discard_text(Net.request_private_snapshot().get("items", {}), _inventory())
		discard_band.visible = discard_label.text != ""


## "+$1,250" (the row's winnings).
static func cash_text(amount: int) -> String:
	return "+$%s" % Hud._thousands(amount)


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
	var comp: int = int(data.get("comp", 0))
	var comp_label: Label = r["comp"]
	comp_label.text = "Lucky slips you $%s" % Hud._thousands(comp) if comp > 0 else ""
	comp_label.visible = comp > 0
	var face: Control = r["face"]
	var back: Control = r["back"]
	var holder: Control = r["card_box"]
	if not holder.visible:
		_flip_sounds(data, comp, sound)
		return
	var turn := func() -> void:
		back.visible = false
		face.visible = true
		if item == &"":
			card.text = "No item"
			card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.add_theme_color_override(&"font_color", TableSkin.TEXT_MUTED)
			rarity_label.text = ""
			(r["rarity_band"] as Control).visible = false
			(r["model_rect"] as Control).visible = false
			return
		var rarity: int = item_rarity(item)
		r["rarity_id"] = rarity
		card.text = item_name(item)
		card.add_theme_color_override(&"font_color", RARITY_COLORS[rarity])
		rarity_label.text = RARITY_NAMES[rarity]
		rarity_label.add_theme_color_override(&"font_color", TableSkin.ink_for(RARITY_FRAMES[rarity]) if rarity > 0 else Palette.CREAM)
		(r["rarity_band"] as PanelContainer).add_theme_stylebox_override(&"panel", _tag_box(RARITY_FRAMES[rarity]))
		var sb: StyleBoxFlat = r["frame"]
		sb.border_color = RARITY_FRAMES[rarity]
		sb.set_border_width_all(2 if rarity > 0 else 1)
		sb.shadow_color = Color(RARITY_FRAMES[rarity], 0.0 if rarity == 0 else 0.4)
		sb.shadow_size = 0 if rarity == 0 else 12
		_show_model(r, item)
		var bonus: StringName = StringName(data.get("bonus", &""))
		var bonus_box: Control = r["bonus_box"]
		bonus_box.visible = bonus != &""
		if bonus != &"":
			(r["bonus_label"] as Label).text = "+ UNDERDOG  %s" % item_name(bonus).to_upper()
			(r["bonus_icon"] as TextureRect).texture = ItemThumbnails.texture_for(bonus)
	var card_node: Control = r["card_node"]
	if sound and card_node.is_inside_tree():
		# Turn the card over: squash to an edge, swap sides, open up again with a little overshoot.
		card_node.pivot_offset = card_node.size * 0.5
		var tw: Tween = card_node.create_tween()
		tw.tween_property(card_node, ^"scale", Vector2(0.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(turn)
		tw.tween_property(card_node, ^"scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		turn.call()
	_flip_sounds(data, comp, sound)


func _flip_sounds(data: Dictionary, comp: int, sound: bool) -> void:
	if not sound:
		return
	Audio.play(&"ui_click", &"UI", -6.0)
	if int(data.get("cash", 0)) > 0 or comp > 0:
		Audio.play(&"coin", &"UI", -8.0 if int(data.get("player", -1)) != local_id else -3.0)


## The item's own model, turning in the card (a still picture where nothing renders).
func _show_model(r: Dictionary, item: StringName) -> void:
	var rect: TextureRect = r["model_rect"]
	rect.visible = true
	if not _live:
		rect.texture = ItemThumbnails.texture_for(item)
		return
	var vp := SubViewport.new()
	vp.name = "Item%d" % _rows.find(r)
	vp.size = Vector2i(LIVE_SIZE, LIVE_SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(vp)
	var stand: Node3D = ItemThumbnails.build_stage(vp)
	var model: Node3D = ItemModels.make(item, 1.0)
	# Facing the camera (the models are built facing away from it) and upright.
	model.rotation_degrees = Vector3(0.0, ItemThumbnails.preview_yaw(item), 180.0 if item in ItemThumbnails.UPSIDE_DOWN else 0.0)
	# Long thin items (bat, bow, cue) lie across the card's corner, bigger, and turn about their
	# own length; everything else stands and turns.
	var tilt := Node3D.new()
	var ext: Vector3 = model.get_meta(&"extent", Vector3.ONE)
	if ext.y > 1.8 * maxf(ext.x, ext.z):
		tilt.rotation_degrees = Vector3(0.0, 0.0, -42.0)
		tilt.scale = Vector3.ONE * 1.3
	stand.add_child(tilt)
	tilt.add_child(model)
	r["vp"] = vp
	r["model"] = model
	rect.texture = vp.get_texture()


func _build_row(row: Dictionary, compact: bool = false) -> Dictionary:
	var k: float = COMPACT if compact else 1.0
	var pid: int = int(row["player"])
	var mine: bool = pid == local_id
	var p: Dictionary = state.players.get(pid, {}) if state != null else {}
	var place: int = int(row["placement"])
	var framed := PanelContainer.new()
	framed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row_sb: StyleBoxFlat = _row_box(mine, place)
	if compact:
		row_sb.content_margin_top = 5
		row_sb.content_margin_bottom = 5
	framed.add_theme_stylebox_override(&"panel", row_sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	framed.add_child(h)
	h.add_child(PlaceBadge.make(place, 60.0 * k))
	# The bean in its outfit, framed in the player's colour.
	var bean: int = int(p.get("bean_color", p.get("color", 0)))
	var pframe := PanelContainer.new()
	pframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pframe.clip_contents = true
	pframe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color("#3A2A22")
	psb.border_color = PlayerColors.of_player(state.players, pid) if state != null else Palette.player_color(bean)
	psb.set_border_width_all(3)
	psb.set_corner_radius_all(12)
	psb.anti_aliasing = true
	pframe.add_theme_stylebox_override(&"panel", psb)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE * k
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = BeanPortraits.texture_for(bean, p.get("outfit", []))
	pframe.add_child(portrait)
	h.add_child(pframe)
	# Name, with YOU / the House Comp under it.
	var nv := VBoxContainer.new()
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.add_theme_constant_override(&"separation", 2)
	nv.custom_minimum_size = Vector2(230, 0)
	h.add_child(nv)
	var n: Label = TableSkin.label(state.player_name(pid) if state != null else "Player", 32, Palette.VIP_GOLD if mine else Palette.CREAM, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size = Vector2(230, 0)
	nv.add_child(n)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override(&"separation", 8)
	nv.add_child(sub)
	if mine:
		var you := PanelContainer.new()
		you.add_theme_stylebox_override(&"panel", _tag_box(Palette.VIP_GOLD))
		var yl: Label = TableSkin.label("YOU", 15, Palette.CASINO_BLACK, true)
		yl.add_theme_constant_override(&"outline_size", 0)
		you.add_child(yl)
		sub.add_child(you)
	var comp: Label = TableSkin.label("", 18, Palette.WARM_GOLD)
	comp.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	comp.visible = false
	sub.add_child(comp)
	sub.visible = true
	# The winnings.
	var cash: Label = TableSkin.label("", 44, Palette.MONEY_GREEN)
	cash.add_theme_font_override(&"font", TableSkin.black_font())
	cash.add_theme_color_override(&"font_outline_color", Color("#0F2A17"))
	cash.add_theme_constant_override(&"outline_size", 6)
	cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash.custom_minimum_size = Vector2(150, 0)
	cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(cash)
	# The item card: face down (a burgundy back with a brass diamond) until its row flips. It sits
	# in a plain holder, so the flip's scale isn't undone by the row's layout.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CARD_SIZE.x, CARD_SIZE.y * k)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.visible = shows_items(state.lobby_settings if state != null else {})
	h.add_child(holder)
	var card_node := PanelContainer.new()
	card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#2A1E18")
	frame.border_color = TableSkin.BRASS_DARK
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(10)
	frame.content_margin_left = 6
	frame.content_margin_right = 12
	frame.content_margin_top = 4
	frame.content_margin_bottom = 4
	frame.shadow_size = 0
	frame.anti_aliasing = true
	card_node.add_theme_stylebox_override(&"panel", frame)
	holder.add_child(card_node)
	var back := _card_back()
	card_node.add_child(back)
	var face := HBoxContainer.new()
	face.add_theme_constant_override(&"separation", 8)
	face.visible = false
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_node.add_child(face)
	var model_rect := TextureRect.new()
	model_rect.custom_minimum_size = Vector2(MODEL_PX, MODEL_PX) * k
	model_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	model_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	model_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.add_child(model_rect)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override(&"separation", 3)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	face.add_child(cv)
	var card: Label = TableSkin.label("?", 26, Palette.CREAM, true)
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.clip_text = true
	cv.add_child(card)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override(&"separation", 6)
	cv.add_child(tags)
	var rarity_band := PanelContainer.new()
	rarity_band.add_theme_stylebox_override(&"panel", _tag_box(TableSkin.BRASS_DARK))
	tags.add_child(rarity_band)
	var rarity: Label = TableSkin.label("", 14, Palette.CREAM, true)
	rarity.add_theme_constant_override(&"outline_size", 0)
	rarity_band.add_child(rarity)
	var bonus_box := HBoxContainer.new()
	bonus_box.add_theme_constant_override(&"separation", 4)
	bonus_box.visible = false
	cv.add_child(bonus_box)
	var bonus_icon := TextureRect.new()
	bonus_icon.custom_minimum_size = Vector2(22, 22)
	bonus_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bonus_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bonus_box.add_child(bonus_icon)
	var bonus_label: Label = TableSkin.label("", 14, Palette.WARM_GOLD, true)
	bonus_label.add_theme_constant_override(&"outline_size", 0)
	bonus_box.add_child(bonus_label)
	rows_box.add_child(framed)
	return {"data": row, "row": framed, "card_box": holder, "card_node": card_node, "card": card,
		"rarity": rarity, "rarity_band": rarity_band, "cash": cash, "comp": comp, "face": face,
		"back": back, "model_rect": model_rect, "frame": frame, "bonus_box": bonus_box,
		"bonus_icon": bonus_icon, "bonus_label": bonus_label, "vp": null, "model": null,
		"rarity_id": 0, "flip_at": 0.0, "flipped": false, "counted": false}


## The face-down side of an item card: burgundy with a brass diamond lattice and a "?".
func _card_back() -> Control:
	var back := Control.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, back.size).grow(-2)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.VIP_BURGUNDY
		sb.border_color = Color(TableSkin.BRASS, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(7)
		sb.anti_aliasing = true
		back.draw_style_box(sb, r)
		var step: float = 18.0
		var y: float = r.position.y + step * 0.5
		var row_i: int = 0
		while y < r.end.y - 4.0:
			var x: float = r.position.x + step * (0.5 if row_i % 2 == 0 else 1.0)
			while x < r.end.x - 4.0:
				TableSkin.diamond(back, Vector2(x, y), 2.0, Color(TableSkin.BRASS, 0.28))
				x += step
			y += step * 0.5
			row_i += 1
		var c: Vector2 = r.get_center()
		TableSkin.diamond(back, c, 24.0, TableSkin.BRASS_DARK)
		TableSkin.diamond(back, c, 21.0, Palette.VIP_BURGUNDY)
		var f: Font = TableSkin.black_font()
		var w: float = f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		back.draw_string(f, c + Vector2(-w * 0.5, 11), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Palette.VIP_GOLD))
	return back


## A row's plaque: walnut with a brass edge; the local player's in burgundy with a gold edge and a
## gold bar down the left; first place a touch warmer.
static func _row_box(mine: bool, place: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.VIP_BURGUNDY, 0.85) if mine else (Color("#33241B") if place == 1 else Color(TableSkin.WALNUT_LIGHT, 0.92))
	sb.border_color = Palette.VIP_GOLD if mine else Color(TableSkin.BRASS, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_left = 5 if mine else 1
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	return sb


## A small rounded tag (YOU, the rarity) in `color`.
static func _tag_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	sb.anti_aliasing = true
	return sb


## False when the match hands out no items (Minigames Only, or items off): the rows then show
## only the cash, without an empty item card.
static func shows_items(settings: Dictionary) -> bool:
	return not MatchMode.is_minigames_only(settings) and bool(settings.get("items_enabled", true))


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
	# Centred and only as big as the rows (no big empty box with the stage bleeding through).
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(760, 0)
	panel.add_theme_stylebox_override(&"panel", TableSkin.panel_box())
	panel.draw.connect(func() -> void: TableSkin.draw_frame(panel))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	panel.add_child(v)
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override(&"separation", 14)
	v.add_child(header)
	var lr := DecoRule.new(false, 70.0)
	lr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(lr)
	var title := Label.new()
	title.text = "ROUND RESULTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override(&"font", TableSkin.black_font())
	title.add_theme_font_size_override(&"font_size", 46)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.add_theme_color_override(&"font_outline_color", Color("#3A2410"))
	title.add_theme_constant_override(&"outline_size", 7)
	title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override(&"shadow_offset_y", 3)
	title.add_theme_constant_override(&"shadow_offset_x", 0)
	header.add_child(title)
	var rr := DecoRule.new(true, 70.0)
	rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(rr)
	# The seconds left, small in the corner of the header; the bar under it drains with them.
	timer_label = TableSkin.label("", 22, TableSkin.TEXT_MUTED, true)
	timer_label.custom_minimum_size = Vector2(28, 0)
	header.add_child(timer_label)
	countdown = CountdownBar.new()
	countdown.custom_minimum_size = Vector2(0, 4)
	v.add_child(countdown)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override(&"separation", 8)
	v.add_child(rows_box)
	discard_band = PanelContainer.new()
	discard_band.add_theme_stylebox_override(&"panel", TableSkin.band_box(Color("#5A1A1E"), Palette.LOSS_RED, 10))
	discard_band.visible = false
	v.add_child(discard_band)
	discard_label = TableSkin.label("", 22, Palette.CREAM, true)
	discard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discard_band.add_child(discard_label)
