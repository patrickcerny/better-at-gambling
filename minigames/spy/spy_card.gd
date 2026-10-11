class_name SpyCard
extends Button
## One player's card on the Spy panel: a cream card in a gold frame with their colour band, name,
## a tag line (THAT'S YOU / SPEAKING / PRESS 3 / YOUR VOTE), the clues they gave so far as
## numbered slips, a timer bar while it is their clue turn, and at a vote's reveal the name chips
## of everyone who voted for them stacked over the clues with the tally underneath. The whole
## card is the vote button. Purely presentation: the stage sets the fields and calls `refresh()`.

const CARD_DARK: Color = Color("#2A211C")
const CHIP_H: float = 34.0
const CHIP_GAP: float = 5.0
const FLIGHT_TIME: float = 0.38

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")

## Emitted when a flying vote chip lands on this card (tally already updated).
signal chip_landed(card: SpyCard)

var player_id: int = -1
var player_color: Color = Palette.CREAM
## Clue texts in order ("" = the turn ran out).
var clue_texts: Array[String] = []
var is_self: bool = false
var speaking: bool = false
## 0..1 of the speaker's clue time left.
var turn_frac: float = 1.0
var votable: bool = false
var is_my_vote: bool = false
var has_voted: bool = false
## Voted out / dropped: the card dims under its stamp.
var is_out: bool = false
var key_hint: String = ""
var tag_override: String = ""
var stamp_text: String = ""
var stamp_color: Color = Palette.FELT_GREEN
var spotlit: bool = false
## Vote chips: {chip, landed, tween}.
var chips: Array[Dictionary] = []
var tally: int = 0
var show_tally: bool = false
var initial: String = "?"

var band: ColorRect
var name_label: Label
var tag_label: Label
var clue_box: VBoxContainer
var turn_bar: ProgressBar
var chip_area: Control
var tally_label: Label
var stamp: Label
var voted_badge: Label


func _init() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	custom_minimum_size = Vector2(170, 380)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	resized.connect(_on_resized)


func setup(p_id: int, p_name: String, p_color: Color) -> void:
	player_id = p_id
	player_color = p_color
	initial = p_name.left(1).to_upper() if p_name != "" else "?"
	name_label.text = p_name.to_upper()
	band.color = p_color
	refresh()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 6)
	margin.add_child(col)
	band = ColorRect.new()
	band.custom_minimum_size = Vector2(0, 12)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(band)
	name_label = _label("", BLACK_FONT, 38, CARD_DARK)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	tag_label = _label("", BOLD_FONT, 21, Color(CARD_DARK, 0.6))
	col.add_child(tag_label)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(Palette.WARM_GOLD, 0.7)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	# The clues, with the vote chips stacked over them at a reveal.
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.draw.connect(_draw_medal.bind(body))
	col.add_child(body)
	clue_box = VBoxContainer.new()
	clue_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clue_box.add_theme_constant_override(&"separation", 6)
	body.add_child(clue_box)
	chip_area = Control.new()
	chip_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chip_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_area.resized.connect(_layout_chips)
	body.add_child(chip_area)
	turn_bar = ProgressBar.new()
	turn_bar.custom_minimum_size = Vector2(0, 12)
	turn_bar.show_percentage = false
	turn_bar.max_value = 1.0
	turn_bar.step = 0.0
	turn_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(CARD_DARK, 0.18)
	back.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.WARM_GOLD.darkened(0.1)
	fill.set_corner_radius_all(6)
	turn_bar.add_theme_stylebox_override(&"background", back)
	turn_bar.add_theme_stylebox_override(&"fill", fill)
	turn_bar.modulate.a = 0.0
	col.add_child(turn_bar)
	tally_label = _label("", BLACK_FONT, 40, Palette.VIP_BURGUNDY)
	tally_label.custom_minimum_size = Vector2(0, 44)
	col.add_child(tally_label)
	voted_badge = _label("VOTED", BLACK_FONT, 20, Palette.CREAM)
	voted_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	voted_badge.position = Vector2(-86, -16)
	voted_badge.add_theme_stylebox_override(&"normal", _badge_box(Palette.FELT_GREEN))
	voted_badge.visible = false
	add_child(voted_badge)
	stamp = _label("", BLACK_FONT, 34, Palette.CREAM)
	stamp.visible = false
	stamp.rotation = -0.12
	add_child(stamp)


static func _badge_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb


func _label(t: String, font: Font, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	return l


## Re-applies styles and labels from the display state.
func refresh() -> void:
	disabled = not votable
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if votable else Control.CURSOR_ARROW
	modulate = Color(1, 1, 1, 0.62) if is_out and stamp_text == "" else Color.WHITE
	var tag: String = ""
	var tag_color: Color = Color(CARD_DARK, 0.6)
	if tag_override != "":
		tag = tag_override
		tag_color = Palette.VIP_BURGUNDY
	elif votable and key_hint != "":
		tag = "PRESS %s" % key_hint
	elif is_my_vote:
		tag = "YOUR VOTE"
		tag_color = Palette.VIP_BURGUNDY
	elif speaking:
		tag = "SPEAKING" if not is_self else "YOUR TURN"
		tag_color = Palette.VIP_BURGUNDY
	elif is_self:
		tag = "THAT'S YOU"
		tag_color = Palette.VIP_BURGUNDY
	tag_label.text = tag
	tag_label.add_theme_color_override(&"font_color", tag_color)
	voted_badge.visible = has_voted
	turn_bar.modulate.a = 1.0 if speaking else 0.0
	turn_bar.value = turn_frac
	(turn_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = Palette.CASINO_RED if turn_frac < 0.25 else Palette.WARM_GOLD.darkened(0.1)
	tally_label.text = ("%d VOTE" % tally + ("" if tally == 1 else "S")) if show_tally else ""
	_refresh_clues()
	if stamp_text != "":
		stamp.text = stamp_text
		var sb := StyleBoxFlat.new()
		sb.bg_color = stamp_color
		sb.border_color = Palette.VIP_GOLD
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 8
		stamp.add_theme_stylebox_override(&"normal", sb)
	stamp.visible = stamp_text != ""
	_restyle()
	_place_stamp()


## Turn progress only (every frame while speaking).
func set_turn(frac: float) -> void:
	turn_frac = frac
	turn_bar.value = frac
	(turn_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = Palette.CASINO_RED if frac < 0.25 else Palette.WARM_GOLD.darkened(0.1)


## One slip per clue: the round number in a gold disc and the word; "…" on the speaker's slip.
func _refresh_clues() -> void:
	var rows: Array[String] = clue_texts.duplicate()
	var typing: bool = speaking
	var want: int = rows.size() + (1 if typing else 0)
	while clue_box.get_child_count() < want:
		clue_box.add_child(_slip())
	for i: int in clue_box.get_child_count():
		var slip: PanelContainer = clue_box.get_child(i) as PanelContainer
		slip.visible = i < want  # spare slips (the speaker's "…") wait hidden
		if i >= want:
			continue
		var num: Label = slip.get_node("Row/Num") as Label
		var word: Label = slip.get_node("Row/Word") as Label
		num.text = str(i + 1)
		var t: String = rows[i] if i < rows.size() else ""
		if i >= rows.size():
			word.text = "…"
			word.add_theme_color_override(&"font_color", Color(CARD_DARK, 0.45))
		elif t == "":
			word.text = "(no clue)"
			word.add_theme_color_override(&"font_color", Color(CARD_DARK, 0.4))
		else:
			word.text = t.to_upper()
			word.add_theme_color_override(&"font_color", CARD_DARK)
	clue_box.modulate.a = 0.22 if tally > 0 else 1.0
	(clue_box.get_parent() as Control).queue_redraw()


func _slip() -> PanelContainer:
	var slip := PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CREAM.lightened(0.45)
	sb.border_color = Color(Palette.WARM_GOLD, 0.55)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	slip.add_theme_stylebox_override(&"panel", sb)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	slip.add_child(row)
	var num := _label("1", BLACK_FONT, 20, Palette.CREAM)
	num.name = "Num"
	num.custom_minimum_size = Vector2(28, 28)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var disc := StyleBoxFlat.new()
	disc.bg_color = Palette.WARM_GOLD.darkened(0.2)
	disc.set_corner_radius_all(14)
	num.add_theme_stylebox_override(&"normal", disc)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	var word := _label("", BLACK_FONT, 30, CARD_DARK)
	word.name = "Word"
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	word.clip_text = true
	word.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(word)
	return slip


## A casino-chip medallion in the player's colour with their initial at the foot of the card,
## when the clues leave room for it (it hides under the vote chips).
func _draw_medal(body: Control) -> void:
	var used: float = clue_box.get_combined_minimum_size().y
	var room: float = body.size.y - used - 16.0
	var r: float = minf(body.size.x * 0.3, room * 0.5 - 6.0)
	if r < 26.0 or tally > 0:
		return
	var c := Vector2(body.size.x * 0.5, body.size.y - r - 10.0)
	var a: float = 0.85
	body.draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.16), true, -1.0, true)
	body.draw_circle(c, r, Color(player_color, a), true, -1.0, true)
	for i: int in 8:
		var t: float = TAU * float(i) / 8.0
		var d := Vector2(cos(t), sin(t))
		var q := PackedVector2Array([
			c + d * r * 0.78 + d.orthogonal() * r * 0.12, c + d * r + d.orthogonal() * r * 0.14,
			c + d * r - d.orthogonal() * r * 0.14, c + d * r * 0.78 - d.orthogonal() * r * 0.12])
		body.draw_colored_polygon(q, Color(Palette.CREAM, 0.9 * a))
	body.draw_circle(c, r, Color(CARD_DARK, 0.7 * a), false, 3.0, true)
	body.draw_circle(c, r * 0.68, Color(Palette.WARM_GOLD, a), false, 3.0, true)
	body.draw_circle(c, r * 0.64, Color(player_color.darkened(0.12), a), true, -1.0, true)
	var fs: int = int(r * 0.95)
	var ink: Color = CARD_DARK if player_color.get_luminance() > 0.45 else Palette.CREAM
	body.draw_string(BLACK_FONT, c + Vector2(-r, fs * 0.36), initial, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(ink, a))


func _restyle() -> void:
	var border: Color = Palette.WARM_GOLD
	var width: int = 5
	if is_my_vote:
		border = Palette.VIP_BURGUNDY
		width = 9
	elif speaking:
		border = Palette.VIP_GOLD
		width = 8
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.CREAM
		sb.border_color = border
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(16)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0, 6)
		if spotlit:
			sb.shadow_color = Color(Palette.VIP_GOLD, 0.45)
			sb.shadow_size = 34
			sb.shadow_offset = Vector2.ZERO
		sb.anti_aliasing = true
		match st:
			"hover":
				sb.bg_color = Palette.CREAM.lightened(0.35)
				sb.border_color = Palette.VIP_GOLD if not is_my_vote else border
				sb.set_border_width_all(maxi(width, 7))
				sb.shadow_color = Color(Palette.VIP_GOLD, 0.35)
				sb.shadow_size = 22
			"pressed":
				sb.bg_color = Palette.CREAM.darkened(0.08)
			"focus":
				sb.draw_center = false
				sb.set_border_width_all(0)
				sb.shadow_size = 0
		add_theme_stylebox_override(st, sb)


func _place_stamp() -> void:
	if not stamp.visible:
		return
	stamp.reset_size()
	var s: Vector2 = stamp.get_combined_minimum_size()
	stamp.size = s
	stamp.pivot_offset = s * 0.5
	stamp.position = Vector2((size.x - s.x) * 0.5, size.y * 0.7 - s.y * 0.5)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	_place_stamp()


# --- Vote chips ----------------------------------------------------------------------------------

func clear_chips() -> void:
	for c: Dictionary in chips:
		(c["chip"] as Control).queue_free()
	chips.clear()
	tally = 0
	show_tally = false
	clue_box.modulate.a = 1.0


## A voter's name chip flies from `from_global` and lands here after `delay` seconds; `instant`
## puts it straight in place (late join, skipping the show).
func add_chip(voter_name: String, color: Color, mine: bool, from_global: Vector2, delay: float, instant: bool) -> Control:
	var chip: PanelContainer = VoteRaceCard.make_chip(voter_name, color, mine)
	chip_area.add_child(chip)
	var entry: Dictionary = {"chip": chip, "landed": false}
	chips.append(entry)
	var slot: Vector2 = _slot_pos(chips.size() - 1)
	chip.size = Vector2(chip_area.size.x, CHIP_H)
	if instant:
		chip.position = slot
		_land(entry, false)
		return chip
	chip.position = from_global - chip_area.global_position - chip.size * 0.5
	chip.modulate.a = 0.0
	chip.z_index = 20
	chip.scale = Vector2(0.6, 0.6)
	chip.pivot_offset = chip.size * 0.5
	var tw: Tween = chip.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(chip, "modulate:a", 1.0, 0.08)
	tw.set_parallel(true)
	tw.tween_property(chip, "position", slot, FLIGHT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(chip, "scale", Vector2.ONE, FLIGHT_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_callback(_land.bind(entry, true))
	entry["tween"] = tw
	return chip


func land_all() -> void:
	for c: Dictionary in chips:
		if not bool(c["landed"]):
			_land(c, false)


func _land(entry: Dictionary, signal_it: bool) -> void:
	if bool(entry["landed"]):
		return
	entry["landed"] = true
	var chip: Control = entry["chip"]
	if not is_instance_valid(chip):
		return
	var tw: Tween = entry.get("tween", null)
	if not signal_it and tw != null and tw.is_valid():
		tw.kill()
	chip.modulate.a = 1.0
	chip.scale = Vector2.ONE
	chip.z_index = 0
	tally += 1
	show_tally = true
	clue_box.modulate.a = 0.22  # the chips sit over the clues now
	_layout_chips()
	tally_label.text = "%d VOTE" % tally + ("" if tally == 1 else "S")
	if signal_it:
		chip_landed.emit(self)


func _slot_pos(i: int) -> Vector2:
	var n: int = maxi(chips.size(), 1)
	var step: float = CHIP_H + CHIP_GAP
	if n * step > chip_area.size.y and n > 1:
		step = maxf((chip_area.size.y - CHIP_H) / float(n - 1), 8.0)
	return Vector2(0, 4.0 + step * float(i))


func _layout_chips() -> void:
	for i: int in chips.size():
		var c: Dictionary = chips[i]
		var chip: Control = c["chip"]
		if is_instance_valid(chip):
			chip.size = Vector2(chip_area.size.x, CHIP_H)
			chip.pivot_offset = chip.size * 0.5
			if bool(c["landed"]):
				chip.position = _slot_pos(i)


func pop(strength: float = 0.12) -> void:
	pivot_offset = size * 0.5
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * (1.0 + strength), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if stamp.visible:
		stamp.scale = Vector2(1.8, 1.8)
		stamp.modulate.a = 0.0
		var st: Tween = create_tween().set_parallel(true)
		st.tween_property(stamp, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_property(stamp, "modulate:a", 1.0, 0.12)
