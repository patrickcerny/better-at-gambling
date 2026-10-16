class_name HorseRaceUi
extends StationUi
## Horse race overlay: a slim strip at the bottom so the track stays in view. Pick a chip, click a
## horse (number, this round's name, 1:4) to put it on that horse; Enter puts another chip on the
## horse you picked. One horse per player per race. Shows the countdown to the gates, the leader
## while they run and the winner, your stake, and a dot per other player on each horse.

const STRIP_WIDTH: float = 820.0
const HORSE_SIZE: Vector2 = Vector2(176, 78)

var bet_panel: BetPanel
var horse_buttons: Array[Button] = []
var race_label: Label
var my_bets: Label
## The horse the local player picked (−1 = none yet); Enter adds a chip on it.
var selected_horse: int = -1
var _badges: Array[Label] = []
var _dots: Array[Label] = []


func _init() -> void:
	game_title = "HORSE RACE"


func _panel_height() -> float:
	return 262.0


## Locked while bets are open (the race itself you may watch with the head free).
func wants_camera_lock() -> bool:
	return int(pub.get("state", 0)) == HorseRaceLogic.State.BETTING


func _build() -> void:
	panel.offset_left = -STRIP_WIDTH * 0.5
	panel.offset_right = STRIP_WIDTH * 0.5
	body.add_theme_constant_override(&"separation", 6)
	status_label.add_theme_font_size_override(&"font_size", 22)
	race_label = Label.new()
	race_label.name = "Race"
	race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_label.add_theme_font_size_override(&"font_size", 18)
	race_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	body.add_child(race_label)
	var row := HBoxContainer.new()
	row.name = "Horses"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 8)
	body.add_child(row)
	for i: int in HorseRaceLogic.HORSES:
		row.add_child(_horse_button(i))
	var bets_row := HBoxContainer.new()
	bets_row.name = "BetsRow"
	bets_row.add_theme_constant_override(&"separation", 10)
	body.add_child(bets_row)
	my_bets = Label.new()
	my_bets.name = "MyBets"
	my_bets.theme_type_variation = &"SmallLabel"
	my_bets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	my_bets.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	my_bets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_bets.custom_minimum_size = Vector2(200, 0)
	my_bets.add_theme_font_size_override(&"font_size", 15)
	bets_row.add_child(my_bets)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(62, 42)
	bet_panel.chip_gap = 6
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.cleared.connect(func() -> void: send(&"clear_bets"))
	bet_panel.confirmed.connect(func(_a: int) -> void:
		if selected_horse >= 0:
			bet_on(selected_horse))
	bets_row.add_child(bet_panel)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.horse_min_bet)
	var hi: int = scaled(Registry.balance.horse_max_total)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "")
	bet_panel.configure_visibility(false, false, true, false)
	selected_horse = -1


## Puts the selected chip on `horse` (sends the bet; the server checks everything).
func bet_on(horse: int) -> bool:
	selected_horse = horse
	return send(&"place_bet", {"bet": {"horse": horse, "amount": bet_panel.chip_stake(bet_room())}})


func _hint_text() -> String:
	return "%s Stand up   ·   one horse per race, the first over the line pays 1:4" % InputGlyphs.hint(&"leave_station")


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var timer: float = float(pub.get("timer", 0.0))
	var names: Array = pub.get("names", [])
	var open_bets: bool = st == HorseRaceLogic.State.BETTING
	match st:
		HorseRaceLogic.State.IDLE:
			status_label.text = "Waiting for players…"
		HorseRaceLogic.State.BETTING:
			status_label.text = ("PLACE YOUR BETS  ·  GATES OPEN IN %d s" % int(ceil(timer))) if bool(pub.get("counting", false)) else "PICK A HORSE: the gates open %d s after the first bet" % int(Registry.balance.horse_countdown)
		HorseRaceLogic.State.RACING:
			status_label.text = "No more bets: AND THEY'RE OFF!"
		HorseRaceLogic.State.RESULT:
			status_label.text = "Next race in %d s" % int(ceil(timer))
	race_label.text = _race_text(st, pub, names)
	var mine: Dictionary = {}
	var others: Dictionary = {}
	for b: Dictionary in pub.get("bets", []):
		var h: int = int(b["horse"])
		if int(b["player"]) == local_id:
			mine[h] = int(mine.get(h, 0)) + int(b["amount"])
		else:
			if not others.has(h):
				others[h] = []
			if not int(b["player"]) in others[h]:
				others[h].append(int(b["player"]))
	var backed: int = mine.keys()[0] if mine.size() > 0 else -1
	if backed >= 0:
		selected_horse = backed
	for i: int in horse_buttons.size():
		var b: Button = horse_buttons[i]
		var horse_name: String = String(names[i]) if i < names.size() else ""
		b.text = "%d  %s\n1:4" % [i + 1, horse_name.to_upper()]
		b.disabled = not open_bets or (backed >= 0 and backed != i)
		_badges[i].visible = mine.has(i)
		if mine.has(i):
			_badges[i].text = "$%d" % int(mine[i])
		_dots[i].visible = others.has(i)
		if others.has(i):
			_dots[i].text = "●".repeat(mini((others[i] as Array).size(), 5))
			_dots[i].add_theme_color_override(&"font_color", Palette.player_color(int(state.players.get(int(others[i][0]), {}).get("color", 0))) if state != null else Palette.CREAM)
	if backed >= 0:
		var horse_name: String = String(names[backed]) if backed < names.size() else ""
		my_bets.text = "YOUR BET $%d on %d %s" % [int(mine[backed]), backed + 1, horse_name]
	elif st == HorseRaceLogic.State.BETTING:
		my_bets.text = "No bet yet: pick a chip, click a horse"
	else:
		my_bets.text = ""


## The line under the status: the leader during the race, the winner after it.
static func _race_text(st: int, p: Dictionary, names: Array) -> String:
	if st == HorseRaceLogic.State.RACING:
		var order: Array[int] = HorseRaceLogic.order_of(p.get("progress", []))
		if order.is_empty():
			return ""
		var lead: int = order[0]
		return "Leading: %d %s" % [lead + 1, String(names[lead]) if lead < names.size() else ""]
	if st == HorseRaceLogic.State.RESULT and int(p.get("winner", -1)) >= 0:
		var w: int = int(p["winner"])
		return "WINNER: %d %s" % [w + 1, String(names[w]).to_upper() if w < names.size() else ""]
	return ""


func _horse_button(i: int) -> Button:
	var b := Button.new()
	b.name = "Horse%d" % (i + 1)
	b.custom_minimum_size = HORSE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 15)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dark_text: bool = HorseRaceStation.LANE_COLORS[i].get_luminance() > 0.5
	for state_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		b.add_theme_color_override(state_name, Palette.CASINO_BLACK if dark_text else Palette.CREAM)
	var sb := StyleBoxFlat.new()
	sb.bg_color = HorseRaceStation.LANE_COLORS[i].darkened(0.1)
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
	off.bg_color = HorseRaceStation.LANE_COLORS[i].darkened(0.55)
	off.border_color = Palette.WARM_CHARCOAL
	b.add_theme_stylebox_override(&"disabled", off)
	b.pressed.connect(func() -> void: bet_on(i))
	horse_buttons.append(b)
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
	_badges.append(badge)
	var dots := Label.new()
	dots.add_theme_font_size_override(&"font_size", 12)
	dots.position = Vector2(6, 2)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.visible = false
	b.add_child(dots)
	_dots.append(dots)
	return b
