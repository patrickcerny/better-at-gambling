class_name VoteRaceCard
extends Button
## One candidate card on the Vote Race set: a cream card in a gold frame with the racer's colour
## band, name, their steps toward the cashier as five pips, and (after a reveal) the chips of
## everyone who voted for them stacked in the middle with the tally underneath. The whole card is
## the vote button. Purely presentation: the stage tells it what to show.

const CARD_DARK: Color = Color("#2A211C")  # ink on the cream card
const CHIP_H: float = 34.0
const CHIP_GAP: float = 5.0
const FLIGHT_TIME: float = 0.38

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")

## Emitted when a flying vote chip lands on this card (tally already updated).
signal chip_landed(card: VoteRaceCard)

var player_id: int = -1
var player_color: Color = Palette.CREAM
var steps: int = 0
var track_length: int = 5
## Display state, set by the stage before `refresh()`.
var is_self: bool = false
var is_my_vote: bool = false
var has_voted: bool = false
var votable: bool = false
var finished_place: int = 0
var key_hint: String = ""
var stamp_text: String = ""
var stamp_color: Color = Palette.FELT_GREEN
## Vote chips on this card: {chip, mine, landed}.
var chips: Array[Dictionary] = []
var tally: int = 0
var show_tally: bool = false
## Under a spotlight (the leader, a racer stepping forward, the winner): a warm glow round it.
var spotlit: bool = false
var initial: String = "?"

var band: ColorRect
var name_label: Label
var tag_label: Label
var pips: Control
var chip_area: Control
var tally_label: Label
var stamp: Label
var voted_badge: Label
## The check on the card you voted for (your vote is secret until the reveal: only you see it).
var check_badge: Control


func _init() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	custom_minimum_size = Vector2(170, 300)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	resized.connect(_on_resized)


func setup(p_id: int, p_name: String, p_color: Color, p_track: int) -> void:
	player_id = p_id
	player_color = p_color
	track_length = p_track
	name_label.text = p_name.to_upper()
	initial = p_name.left(1).to_upper() if p_name != "" else "?"
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
	name_label = _label("", BLACK_FONT, 40, CARD_DARK)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	tag_label = _label("", BOLD_FONT, 20, Color(CARD_DARK, 0.6))
	col.add_child(tag_label)
	pips = Control.new()
	pips.custom_minimum_size = Vector2(0, 26)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.draw.connect(_draw_pips)
	col.add_child(pips)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(Palette.WARM_GOLD, 0.7)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	chip_area = Control.new()
	chip_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chip_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_area.resized.connect(_layout_chips)
	chip_area.draw.connect(_draw_medal)
	col.add_child(chip_area)
	tally_label = _label("", BLACK_FONT, 46, Palette.VIP_BURGUNDY)
	col.add_child(tally_label)
	# Badges over the card: "VOTED" while voting, the big stamp after a reveal.
	voted_badge = _label("VOTED", BLACK_FONT, 20, Palette.CREAM)
	voted_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	voted_badge.position = Vector2(-86, -16)
	var vb := StyleBoxFlat.new()
	vb.bg_color = Palette.FELT_GREEN
	vb.border_color = Palette.WARM_GOLD
	vb.set_border_width_all(2)
	vb.set_corner_radius_all(10)
	vb.content_margin_left = 10
	vb.content_margin_right = 10
	voted_badge.add_theme_stylebox_override(&"normal", vb)
	voted_badge.visible = false
	add_child(voted_badge)
	check_badge = Control.new()
	check_badge.name = "CheckBadge"
	check_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check_badge.size = Vector2(52, 52)
	check_badge.position = Vector2(-16, -16)
	check_badge.visible = false
	check_badge.draw.connect(_draw_check)
	add_child(check_badge)
	stamp = _label("", BLACK_FONT, 34, Palette.CREAM)
	stamp.visible = false
	stamp.rotation = -0.12
	add_child(stamp)


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
	var dim: bool = finished_place > 0 and stamp_text == ""
	modulate = Color(1, 1, 1, 0.72) if dim else Color.WHITE
	if is_self:
		tag_label.text = "THAT'S YOU"
	elif finished_place > 0 and steps >= track_length:
		tag_label.text = "AT THE CASHIER"
	elif votable and key_hint != "":
		tag_label.text = "PRESS %s" % key_hint
	elif is_my_vote:
		tag_label.text = "YOUR VOTE"
	else:
		tag_label.text = ""
	tag_label.add_theme_color_override(&"font_color", Palette.VIP_BURGUNDY if is_my_vote or is_self else Color(CARD_DARK, 0.6))
	voted_badge.visible = has_voted
	check_badge.visible = is_my_vote and stamp_text == ""
	tally_label.text = ("%d VOTE" % tally + ("" if tally == 1 else "S")) if show_tally else ""
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
	pips.queue_redraw()
	chip_area.queue_redraw()


func _restyle() -> void:
	var border: Color = Palette.WARM_GOLD
	var width: int = 5
	if is_my_vote:
		border = Palette.VIP_BURGUNDY
		width = 9
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
	stamp.position = Vector2((size.x - s.x) * 0.5, size.y * 0.42 - s.y * 0.5)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	_place_stamp()


## A casino-chip medallion in the racer's colour with their initial, filling the card while
## voting; it fades back behind the vote chips at the reveal.
func _draw_medal() -> void:
	var sz: Vector2 = chip_area.size
	var r: float = minf(sz.x * 0.36, sz.y * 0.3)
	if r < 12.0:
		return
	var c := Vector2(sz.x * 0.5, sz.y * 0.48)
	var a: float = 0.16 if not chips.is_empty() else 1.0
	chip_area.draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.18 * a), true, -1.0, true)
	chip_area.draw_circle(c, r, Color(player_color, a), true, -1.0, true)
	for i: int in 8:  # the edge inserts of a casino chip
		var t: float = TAU * float(i) / 8.0
		var d := Vector2(cos(t), sin(t))
		var q := PackedVector2Array([
			c + d * r * 0.78 + d.orthogonal() * r * 0.12, c + d * r + d.orthogonal() * r * 0.14,
			c + d * r - d.orthogonal() * r * 0.14, c + d * r * 0.78 - d.orthogonal() * r * 0.12])
		chip_area.draw_colored_polygon(q, Color(Palette.CREAM, 0.9 * a))
	chip_area.draw_circle(c, r, Color(CARD_DARK, 0.8 * a), false, 3.0, true)
	chip_area.draw_circle(c, r * 0.68, Color(Palette.WARM_GOLD, a), false, 3.0, true)
	chip_area.draw_circle(c, r * 0.64, Color(player_color.darkened(0.12), a), true, -1.0, true)
	var fs: int = int(r * 0.95)
	var ink: Color = CARD_DARK if player_color.get_luminance() > 0.45 else Palette.CREAM
	chip_area.draw_string(BLACK_FONT, c + Vector2(-r, fs * 0.36), initial, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(ink, a))


## A burgundy disc in a gold rim with a cream check mark.
func _draw_check() -> void:
	var c: Vector2 = check_badge.size * 0.5
	var r: float = c.x
	check_badge.draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.4), true, -1.0, true)
	check_badge.draw_circle(c, r, Palette.VIP_GOLD, true, -1.0, true)
	check_badge.draw_circle(c, r - 4.0, Palette.VIP_BURGUNDY, true, -1.0, true)
	var pts := PackedVector2Array([c + Vector2(-11, 1), c + Vector2(-3, 10), c + Vector2(12, -9)])
	check_badge.draw_polyline(pts, Palette.CREAM, 6.0, true)


## Five pips: filled gold for every step taken, the last one is the cashier.
func _draw_pips() -> void:
	var n: int = maxi(track_length, 1)
	var w: float = pips.size.x
	var r: float = minf(10.0, (w / float(n)) * 0.3)
	var gap: float = minf((w - 2.0 * r) / float(maxi(n - 1, 1)), 34.0)
	var x0: float = w * 0.5 - gap * float(n - 1) * 0.5
	var y: float = pips.size.y * 0.5
	if n > 1:
		pips.draw_line(Vector2(x0, y), Vector2(x0 + gap * float(n - 1), y), Color(CARD_DARK, 0.25), 3.0, true)
	for i: int in n:
		var c := Vector2(x0 + gap * float(i), y)
		if i < steps:
			pips.draw_circle(c, r, Palette.WARM_GOLD, true, -1.0, true)
			pips.draw_circle(c, r, CARD_DARK, false, 1.5, true)
		else:
			pips.draw_circle(c, r, Palette.CREAM.darkened(0.12), true, -1.0, true)
			pips.draw_circle(c, r, Color(CARD_DARK, 0.4), false, 1.5, true)


# --- Vote chips --------------------------------------------------------------------------------

## Removes every chip and the tally (a new round).
func clear_chips() -> void:
	for c: Dictionary in chips:
		(c["chip"] as Control).queue_free()
	chips.clear()
	tally = 0
	show_tally = false


## A voter's name chip flies from `from_global` (the voter's own card) and lands here after
## `delay` seconds. `instant` puts it straight in place (late join, skipping the show).
func add_chip(voter_name: String, color: Color, mine: bool, from_global: Vector2, delay: float, instant: bool) -> Control:
	var chip := make_chip(voter_name, color, mine)
	chip_area.add_child(chip)
	var entry: Dictionary = {"chip": chip, "mine": mine, "landed": false}
	chips.append(entry)
	var slot: Vector2 = _slot_pos(chips.size() - 1)
	chip.size = Vector2(chip_area.size.x, CHIP_H)
	if instant:
		chip.position = slot
		_land(entry, false)
		return chip
	chip.position = from_global - chip_area.global_position - chip.size * 0.5
	chip.modulate.a = 0.0
	chip.z_index = 20  # fly over the neighbouring cards
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


## Every chip still in the air lands now.
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
		tw.kill()  # landed early (skipped show): stop the flight
	chip.modulate.a = 1.0
	chip.scale = Vector2.ONE
	chip.z_index = 0
	tally += 1
	show_tally = true
	_layout_chips()
	tally_label.text = "%d VOTE" % tally + ("" if tally == 1 else "S")
	if signal_it:
		chip_landed.emit(self)


func _slot_pos(i: int) -> Vector2:
	var n: int = maxi(chips.size(), 1)
	var step: float = CHIP_H + CHIP_GAP
	if n * step > chip_area.size.y and n > 1:
		step = maxf((chip_area.size.y - CHIP_H) / float(n - 1), 8.0)  # overlap a little when crowded
	return Vector2(0, 6.0 + step * float(i))


func _layout_chips() -> void:
	for i: int in chips.size():
		var c: Dictionary = chips[i]
		var chip: Control = c["chip"]
		if is_instance_valid(chip):
			chip.size = Vector2(chip_area.size.x, CHIP_H)
			chip.pivot_offset = chip.size * 0.5
			if bool(c["landed"]):
				chip.position = _slot_pos(i)


## A voter's name chip: their colour, the name in dark or cream ink (whichever reads), a gold
## double rim and a little lift when it's yours.
static func make_chip(voter_name: String, color: Color, mine: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.set_meta(&"mine", mine)
	chip.set_meta(&"voter", voter_name)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(CHIP_H / 2.0))
	sb.border_color = Palette.VIP_BURGUNDY if mine else Color(CARD_DARK, 0.85)
	sb.set_border_width_all(4 if mine else 2)
	sb.shadow_color = Color(Palette.VIP_GOLD, 0.9) if mine else Color(0, 0, 0, 0.3)
	sb.shadow_size = 7 if mine else 3
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.anti_aliasing = true
	chip.add_theme_stylebox_override(&"panel", sb)
	var l := Label.new()
	l.text = voter_name.to_upper()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override(&"font", BLACK_FONT)
	l.add_theme_font_size_override(&"font_size", 24 if mine else 22)
	l.add_theme_color_override(&"font_color", CARD_DARK if color.get_luminance() > 0.45 else Palette.CREAM)
	chip.add_child(l)
	return chip


## A quick bounce (the reveal's payoff on the cards that step forward, the winner at the end).
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
