class_name CrapsUi
extends StationUi
## Craps overlay: a column down the right third of the screen, so the felt and the dice fill the
## rest (the seat camera frames them on the left). The come-out or the point and the throw
## countdown on top; who shoots or the last roll under it; four bet buttons (Pass Line, Don't
## Pass, Field, Any Seven) with the odds the felt prints, your stake on each and a dot per other
## player; chips, clear, and the SHOOT button for the shooter. Click a bet to put the selected
## chip on it, Enter adds another chip to the bet you picked last, the repeat key shoots. How it
## works is folded away under the key hint.

const BET_SIZE: Vector2 = Vector2(268, 92)
const BET_COLORS: Dictionary = {
	&"pass": Color("#2E6B4E"), &"dont_pass": Color("#2B2422"), &"field": Color("#2F5A73"), &"any_seven": Color("#9A2F36"),
}
const BET_LINES: Dictionary = {
	&"pass": "PASS LINE\n1:1", &"dont_pass": "DON'T PASS\n1:1 · 12 pushes", &"field": "FIELD  1:1\n2 & 12 pay 2:1", &"any_seven": "ANY SEVEN\n4:1",
}

var bet_panel: BetPanel
var bet_buttons: Dictionary[StringName, Button] = {}
var roll_label: Label
var my_bets: Label
var shoot_button: Button
## The bet the local player picked last (Enter adds a chip on it).
var selected_bet: StringName = &""
var _badges: Dictionary[StringName, Label] = {}
var _dots: Dictionary[StringName, Label] = {}


func _init() -> void:
	game_title = "CRAPS"


func _dock_column() -> bool:
	return true


## Locked while bets are open; with the dice in the air you may look around.
func wants_camera_lock() -> bool:
	return int(pub.get("state", 0)) == CrapsLogic.State.BETTING


func _build() -> void:
	body.add_theme_constant_override(&"separation", 10)
	status_label.add_theme_font_size_override(&"font_size", 22)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(120, 0)
	roll_label = Label.new()
	roll_label.name = "Roll"
	roll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roll_label.custom_minimum_size = Vector2(120, 0)
	roll_label.add_theme_font_size_override(&"font_size", 19)
	roll_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	body.add_child(roll_label)
	var row := GridContainer.new()
	row.name = "Bets"
	row.columns = 2
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override(&"h_separation", 8)
	row.add_theme_constant_override(&"v_separation", 8)
	body.add_child(row)
	for t: StringName in CrapsLogic.BET_TYPES:
		row.add_child(_bet_button(t))
	var bets_row := VBoxContainer.new()
	bets_row.name = "BetsRow"
	bets_row.add_theme_constant_override(&"separation", 8)
	body.add_child(bets_row)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(66, 44)
	bet_panel.chip_gap = 8
	bet_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.cleared.connect(func() -> void: send(&"clear_bets"))
	bet_panel.confirmed.connect(func(_a: int) -> void:
		if selected_bet != &"":
			bet_on(selected_bet))
	bet_panel.repeated.connect(func() -> void:
		if shoot_button.visible and not shoot_button.disabled:
			shoot())
	bets_row.add_child(bet_panel)
	my_bets = Label.new()
	my_bets.name = "MyBets"
	my_bets.theme_type_variation = &"SmallLabel"
	my_bets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	my_bets.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	my_bets.custom_minimum_size = Vector2(120, 0)
	my_bets.add_theme_font_size_override(&"font_size", 16)
	bets_row.add_child(my_bets)
	shoot_button = Button.new()
	shoot_button.name = "Shoot"
	shoot_button.focus_mode = Control.FOCUS_NONE
	shoot_button.custom_minimum_size = Vector2(280, 58)
	shoot_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shoot_button.add_theme_font_size_override(&"font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.WARM_GOLD
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Palette.CREAM
	shoot_button.add_theme_stylebox_override(&"normal", sb)
	var hover: StyleBoxFlat = sb.duplicate()
	hover.bg_color = Palette.VIP_GOLD
	shoot_button.add_theme_stylebox_override(&"hover", hover)
	shoot_button.add_theme_stylebox_override(&"pressed", hover)
	var off: StyleBoxFlat = sb.duplicate()
	off.bg_color = Palette.WARM_CHARCOAL
	off.border_color = Palette.WARM_GOLD.darkened(0.4)
	shoot_button.add_theme_stylebox_override(&"disabled", off)
	for state_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		shoot_button.add_theme_color_override(state_name, Palette.CASINO_BLACK)
	shoot_button.add_theme_color_override(&"font_disabled_color", Palette.CREAM.darkened(0.35))
	shoot_button.pressed.connect(shoot)
	bets_row.add_child(shoot_button)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.craps_min_bet)
	var hi: int = scaled(Registry.balance.craps_max_total)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "")
	bet_panel.configure_visibility(false, false, true, false)
	selected_bet = &""


## Puts the selected chip on `type` (sends the bet; the server checks everything).
func bet_on(type: StringName) -> bool:
	selected_bet = type
	return send(&"place_bet", {"bet": {"type": type, "amount": bet_panel.chip_stake(bet_room())}})


## The shooter throws the dice.
func shoot() -> bool:
	return send(&"action", {"action": &"shoot"})


func _hint_text() -> String:
	return "%s Stand up   ·   %s shoot when you have the dice" % [InputGlyphs.hint(&"leave_station"), InputGlyphs.hint(&"bet_repeat")]


func _rules_text() -> String:
	return ("Pick a chip, then click a bet. Pass Line and Don't Pass go down on the come-out roll only, one side each: "
		+ "7 or 11 wins the Pass Line, 2, 3 or 12 loses it (Don't Pass wins on 2 and 3, 12 pushes), any other number becomes the point, and the line bets ride until "
		+ "the point comes again (Pass wins) or a 7 (Don't Pass wins). Field and Any Seven are one-roll bets, open whenever bets are. "
		+ "The shooter throws once someone has bet.")


func _relabel() -> void:
	_refresh_shoot()


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var point: int = int(pub.get("point", 0))
	var shooter: int = int(pub.get("shooter", -1))
	var open_bets: bool = st == CrapsLogic.State.BETTING
	var phase: String = ("POINT IS %d" % point) if point > 0 else "COME-OUT ROLL"
	match st:
		CrapsLogic.State.IDLE:
			status_label.text = "Waiting for players…"
		CrapsLogic.State.BETTING:
			if bool(pub.get("counting", false)):
				status_label.text = "%s  ·  DICE IN %d s" % [phase, int(ceil(float(pub.get("timer", 0.0))))]
			else:
				status_label.text = "%s  ·  PLACE YOUR BETS" % phase
		CrapsLogic.State.ROLLING:
			status_label.text = "%s  ·  THE DICE ARE OUT" % phase
		CrapsLogic.State.RESULT:
			status_label.text = phase
	roll_label.text = _roll_text(st, pub, _shooter_name(shooter))
	var mine: Dictionary = {}
	var others: Dictionary = {}
	for b: Dictionary in pub.get("bets", []):
		var t: StringName = StringName(b["type"])
		if int(b["player"]) == local_id:
			mine[t] = int(mine.get(t, 0)) + int(b["amount"])
		else:
			if not others.has(t):
				others[t] = []
			if not int(b["player"]) in others[t]:
				others[t].append(int(b["player"]))
	for t: StringName in bet_buttons:
		var b: Button = bet_buttons[t]
		var line_locked: bool = t in CrapsLogic.LINE_BETS and (point != 0 or mine.has(&"dont_pass" if t == &"pass" else &"pass"))
		b.disabled = not open_bets or line_locked
		_badges[t].visible = mine.has(t)
		if mine.has(t):
			_badges[t].text = "$%d" % int(mine[t])
		_dots[t].visible = others.has(t)
		if others.has(t):
			_dots[t].text = "●".repeat(mini((others[t] as Array).size(), 5))
			_dots[t].add_theme_color_override(&"font_color", Palette.player_color(int(state.players.get(int(others[t][0]), {}).get("color", 0))) if state != null else Palette.CREAM)
	var parts: PackedStringArray = []
	var total: int = 0
	for t: StringName in CrapsLogic.BET_TYPES:
		if mine.has(t):
			parts.append("%s $%d" % [CrapsLogic.NAMES[t], int(mine[t])])
			total += int(mine[t])
	if total > 0:
		my_bets.text = "ON THE FELT $%d: %s" % [total, ", ".join(parts)]
	elif open_bets:
		my_bets.text = "No bet yet: pick a chip, click a bet"
	else:
		my_bets.text = ""
	_refresh_shoot()


func _refresh_shoot() -> void:
	if shoot_button == null:
		return
	var st: int = int(pub.get("state", 0))
	var mine: bool = int(pub.get("shooter", -1)) == local_id and local_id >= 0
	shoot_button.visible = mine
	if not mine:
		return
	var wait: float = float(pub.get("shoot_in", 0.0))
	var has_bets: bool = not (pub.get("bets", []) as Array).is_empty()
	shoot_button.disabled = st != CrapsLogic.State.BETTING or not has_bets or wait > 0.0
	if st == CrapsLogic.State.BETTING and has_bets and wait > 0.0:
		shoot_button.text = "SHOOT in %d" % ceili(wait)
	else:
		shoot_button.text = "SHOOT  %s" % InputGlyphs.hint(&"bet_repeat")


func _shooter_name(pid: int) -> String:
	if pid < 0:
		return "the stickman"
	if pid == local_id:
		return "YOU"
	return state.player_name(pid) if state != null else "Player %d" % pid


## The line under the status: who has the dice, and the last roll with what it did.
static func _roll_text(st: int, p: Dictionary, shooter_name: String) -> String:
	var d: Array = p.get("dice", [])
	if st == CrapsLogic.State.RESULT and d.size() == 2:
		var total: int = int(d[0]) + int(d[1])
		var words: Dictionary = {&"natural": "NATURAL, PASS WINS", &"craps": "CRAPS", &"point_set": "THE POINT IS %d" % total, &"point_made": "POINT MADE, PASS WINS", &"seven_out": "SEVEN OUT", &"roll": "NO DECISION ON THE LINE"}
		return "ROLLED %d + %d = %d  ·  %s" % [int(d[0]), int(d[1]), total, words.get(StringName(p.get("outcome", &"")), "")]
	if st == CrapsLogic.State.IDLE:
		return ""
	return "SHOOTER: %s" % shooter_name


func _bet_button(t: StringName) -> Button:
	var b := Button.new()
	b.name = String(t).to_pascal_case()
	b.text = String(BET_LINES[t])
	b.custom_minimum_size = BET_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 19)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for state_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		b.add_theme_color_override(state_name, Palette.CREAM)
	var base: Color = BET_COLORS[t]
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Palette.WARM_GOLD
	b.add_theme_stylebox_override(&"normal", sb)
	var hover: StyleBoxFlat = sb.duplicate()
	hover.border_color = Palette.VIP_GOLD
	hover.set_border_width_all(3)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	var off: StyleBoxFlat = sb.duplicate()
	off.bg_color = base.darkened(0.55)
	off.border_color = Palette.WARM_CHARCOAL
	b.add_theme_stylebox_override(&"disabled", off)
	b.pressed.connect(func() -> void: bet_on(t))
	bet_buttons[t] = b
	var badge := Label.new()
	badge.add_theme_color_override(&"font_color", Palette.CASINO_BLACK)
	var chip := StyleBoxFlat.new()
	chip.bg_color = Palette.VIP_GOLD
	chip.set_corner_radius_all(9)
	chip.border_color = Palette.CREAM
	chip.set_border_width_all(2)
	chip.content_margin_left = 5
	chip.content_margin_right = 5
	badge.add_theme_stylebox_override(&"normal", chip)
	badge.add_theme_font_size_override(&"font_size", 13)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -52
	badge.offset_right = -4
	badge.offset_top = 4
	badge.offset_bottom = 24
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	b.add_child(badge)
	_badges[t] = badge
	var dots := Label.new()
	dots.add_theme_font_size_override(&"font_size", 12)
	dots.position = Vector2(6, 2)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.visible = false
	b.add_child(dots)
	_dots[t] = dots
	return b
