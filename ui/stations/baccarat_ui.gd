class_name BaccaratUi
extends StationUi
## Baccarat overlay: a column down the right third of the screen (the seat camera frames the felt on
## the left). Pick a chip, then click PLAYER, BANKER, TIE or a PAIR to put it there; click again to
## add more. The two hands show live as the cards turn over (cards and total), the winner lights up,
## and your result follows. The last rounds run along the bottom like the table's scoreboard.
## Keys: [1-4] chip, [P] player, [B] banker, [T] tie, [Backspace] clear (gamepad: chip with the
## bumpers, A banker, X player, Y tie). Key names follow the device in use (InputGlyphs).

const MAIN_SIZE: Vector2 = Vector2(258, 92)
const SIDE_SIZE: Vector2 = Vector2(168, 64)

var bet_panel: BetPanel
var player_box: PanelContainer
var banker_box: PanelContainer
var player_cards: Label
var banker_cards: Label
var player_total: Label
var banker_total: Label
var result_label: Label
var my_bets: Label
var road_label: RichTextLabel
## Bet type → its button, the badge with your amount on it and the dots for other players' chips.
var buttons: Dictionary[StringName, Button] = {}
var _badges: Dictionary[StringName, Label] = {}
var _dots: Dictionary[StringName, Label] = {}


func _init() -> void:
	game_title = "BACCARAT"


func _dock_column() -> bool:
	return true


## Locked while bets are open.
func wants_camera_lock() -> bool:
	return int(pub.get("state", 0)) == BaccaratLogic.State.BETTING


func _build() -> void:
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(120, 0)
	var hands := HBoxContainer.new()
	hands.name = "Hands"
	hands.alignment = BoxContainer.ALIGNMENT_CENTER
	hands.add_theme_constant_override(&"separation", 12)
	body.add_child(hands)
	player_box = _hand_box("PLAYER", BaccaratStation.PLAYER_COLOR, hands)
	player_cards = player_box.get_node(^"V/Cards") as Label
	player_total = player_box.get_node(^"V/Total") as Label
	banker_box = _hand_box("BANKER", BaccaratStation.BANKER_COLOR, hands)
	banker_cards = banker_box.get_node(^"V/Cards") as Label
	banker_total = banker_box.get_node(^"V/Total") as Label
	result_label = _line("", 24, Palette.CREAM)
	result_label.name = "Result"
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(120, 0)
	var main := HBoxContainer.new()
	main.name = "MainBets"
	main.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_theme_constant_override(&"separation", 12)
	body.add_child(main)
	var side := HBoxContainer.new()
	side.name = "SideBets"
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override(&"separation", 10)
	body.add_child(side)
	var cfg: BalanceConfig = Registry.balance
	var commission: int = int(round(cfg.baccarat_banker_commission * 100.0))
	_bet_button(BaccaratLogic.PLAYER, "PLAYER\npays 1:1", BaccaratStation.PLAYER_COLOR.darkened(0.35), main, MAIN_SIZE)
	_bet_button(BaccaratLogic.BANKER, "BANKER\npays 1:1 less %d%%" % commission, BaccaratStation.BANKER_COLOR.darkened(0.35), main, MAIN_SIZE)
	_bet_button(BaccaratLogic.PLAYER_PAIR, "P PAIR\n%d:1" % cfg.baccarat_pair_pays, Palette.WARM_CHARCOAL, side, SIDE_SIZE)
	_bet_button(BaccaratLogic.TIE, "TIE\n%d:1" % cfg.baccarat_tie_pays, BaccaratStation.TIE_COLOR.darkened(0.45), side, SIDE_SIZE)
	_bet_button(BaccaratLogic.BANKER_PAIR, "B PAIR\n%d:1" % cfg.baccarat_pair_pays, Palette.WARM_CHARCOAL, side, SIDE_SIZE)
	my_bets = _line("", 17, Palette.CREAM.darkened(0.1))
	my_bets.name = "MyBets"
	my_bets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	my_bets.custom_minimum_size = Vector2(120, 0)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(72, 48)
	bet_panel.chip_gap = 8
	bet_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bet_panel.cleared.connect(func() -> void: send(&"clear_bets"))
	body.add_child(bet_panel)
	var road_title := _line("LAST ROUNDS", 15, Palette.WARM_GOLD)
	road_title.name = "RoadTitle"
	road_label = RichTextLabel.new()
	road_label.name = "Road"
	road_label.bbcode_enabled = true
	road_label.fit_content = true
	road_label.scroll_active = false
	road_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	road_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	road_label.add_theme_font_size_override(&"normal_font_size", 22)
	road_label.add_theme_font_size_override(&"bold_font_size", 22)
	road_label.custom_minimum_size = Vector2(200, 30)
	road_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(road_label)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.baccarat_min_bet)
	var hi: int = scaled(Registry.balance.baccarat_max_total)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "")
	bet_panel.configure_visibility(false, false, true, false)


## Puts the selected chip on a bet; returns whether the table took it.
func bet(type: StringName) -> bool:
	return send(&"place_bet", {"bet": {"type": type, "amount": bet_panel.chip_stake(bet_room())}})


func _rules_text() -> String:
	var cfg: BalanceConfig = Registry.balance
	return ("Punto Banco. Before the cards come out, bet on the PLAYER hand, the BANKER hand or a TIE, and if you like on a PAIR (that hand's first two cards are the same rank). "
		+ "Each hand counts only the last digit of its cards: aces are 1, tens and pictures 0, so 7 + 8 = 5. The hand closer to 9 wins.\n"
		+ "The dealer plays both hands by fixed rules: an 8 or 9 on two cards (a natural) stands. Otherwise the Player draws a third card on 0-5, and the Banker draws by its total and the Player's third card.\n"
		+ "PLAYER pays 1:1. BANKER pays 1:1 less %d%% commission. A tie gives Player and Banker bets back. TIE pays %d:1, P PAIR and B PAIR %d:1." % [int(round(cfg.baccarat_banker_commission * 100.0)), cfg.baccarat_tie_pays, cfg.baccarat_pair_pays])


func _hint_text() -> String:
	if InputGlyphs.gamepad:
		return InputGlyphs.fill("[{bet_chip_prev} / {bet_chip_next}] chip  [{bj_hit}] banker  [{bj_stand}] player\n[{bet_clear}] clear  [{leave_station}] stand up")
	return InputGlyphs.fill("[1-4] chip  [P] player  [B] banker  [T] tie  [{bet_clear}] clear\n[{leave_station}] stand up")


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or int(pub.get("state", 0)) != BaccaratLogic.State.BETTING:
		return
	var key: Key = (event as InputEventKey).physical_keycode if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo else KEY_NONE
	if key == KEY_P or event.is_action_pressed(&"bj_stand"):
		bet(BaccaratLogic.PLAYER)
	elif key == KEY_B or event.is_action_pressed(&"bj_hit"):
		bet(BaccaratLogic.BANKER)
	elif key == KEY_T:
		bet(BaccaratLogic.TIE)
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var timer: float = float(pub.get("timer", 0.0))
	var open_bets: bool = st == BaccaratLogic.State.BETTING
	match st:
		BaccaratLogic.State.IDLE:
			status_label.text = "Waiting for players…"
		BaccaratLogic.State.BETTING:
			status_label.text = "PLACE YOUR BETS  %d s" % int(ceil(timer))
		BaccaratLogic.State.DEALING:
			status_label.text = "No more bets: the cards are coming"
		BaccaratLogic.State.RESULT:
			status_label.text = "Next round in %d s" % int(ceil(timer))
	var win: StringName = StringName(pub.get("winner", &""))
	_show_hand(player_box, player_cards, player_total, pub.get("player_cards", []), int(pub.get("player_total", 0)), win, BaccaratLogic.PLAYER)
	_show_hand(banker_box, banker_cards, banker_total, pub.get("banker_cards", []), int(pub.get("banker_total", 0)), win, BaccaratLogic.BANKER)
	for t: StringName in buttons:
		buttons[t].disabled = not open_bets
	bet_panel.visible = open_bets or st == BaccaratLogic.State.IDLE
	_show_chips()
	result_label.text = _result_text(win)
	road_label.text = "[center]%s[/center]" % road_bbcode(pub.get("history", []))


## Your amount on each bet (gold badge) and a dot per other player with chips there.
func _show_chips() -> void:
	var mine: Dictionary = {}
	var others: Dictionary = {}
	var total: int = 0
	var parts: PackedStringArray = []
	for b: Variant in pub.get("bets", []):
		if not b is Dictionary:
			continue
		var t: StringName = StringName((b as Dictionary).get("type", &""))
		var pid: int = int((b as Dictionary).get("player", -1))
		var amount: int = int((b as Dictionary).get("amount", 0))
		if pid == local_id:
			mine[t] = int(mine.get(t, 0)) + amount
			total += amount
		else:
			if not others.has(t):
				others[t] = []
			if not pid in others[t]:
				(others[t] as Array).append(pid)
	for t: StringName in _badges:
		var badge: Label = _badges[t]
		badge.visible = mine.has(t)
		if badge.visible:
			badge.text = money(int(mine[t]))
			parts.append("%s %s" % [bet_name(t), money(int(mine[t]))])
		var dots: Label = _dots[t]
		dots.visible = others.has(t)
		if dots.visible:
			dots.text = "●".repeat(mini((others[t] as Array).size(), 4))
			dots.add_theme_color_override(&"font_color", Palette.player_color(int(state.players.get(int(others[t][0]), {}).get("color", 0))) if state != null else Palette.CREAM)
	if total > 0:
		my_bets.text = "YOUR BETS %s  ·  %s" % [money(total), "  ·  ".join(parts)]
	elif int(pub.get("state", 0)) == BaccaratLogic.State.BETTING:
		my_bets.text = "Pick a chip, then click a bet"
	else:
		my_bets.text = ""


## "BANKER WINS 7 to 5" and, if you played, what you got back.
func _result_text(win: StringName) -> String:
	if win == &"":
		return ""
	var p: int = int(pub.get("player_total", 0))
	var b: int = int(pub.get("banker_total", 0))
	var line: String = "TIE  %d to %d" % [p, b] if win == BaccaratLogic.TIE else "%s WINS  %d to %d" % [bet_name(win), maxi(p, b), mini(p, b)]
	var net: int = _my_net()
	if net > 0:
		line += "\nYOU WIN  +%s" % money(net)
	elif net < 0:
		line += "\nYou lose  −%s" % money(-net)
	return line


## Your net this round (0 when you sat out or broke even).
func _my_net() -> int:
	var res: Dictionary = pub.get("results", {})
	for k: Variant in res:
		if int(k) == local_id:
			return int(res[k])
	return 0


func _show_hand(box: PanelContainer, cards_l: Label, total_l: Label, cards: Array, total: int, win: StringName, side: StringName) -> void:
	cards_l.text = "  ".join(_labels(cards)) if not cards.is_empty() else "—"
	total_l.text = str(total) if not cards.is_empty() else ""
	var sb: StyleBoxFlat = box.get_theme_stylebox(&"panel") as StyleBoxFlat
	var won: bool = win == side or win == BaccaratLogic.TIE
	sb.set_border_width_all(4 if won and win != &"" else 2)
	sb.border_color = Palette.VIP_GOLD if won and win != &"" else (box.get_meta(&"color") as Color)
	box.modulate = Color(1, 1, 1, 0.55) if win != &"" and not won else Color.WHITE


static func bet_name(type: StringName) -> String:
	match type:
		BaccaratLogic.PLAYER_PAIR:
			return "P PAIR"
		BaccaratLogic.BANKER_PAIR:
			return "B PAIR"
	return String(type).to_upper()


## The last rounds as coloured letters, oldest first: P blue, B red, T green.
static func road_bbcode(history: Array) -> String:
	var out: PackedStringArray = []
	for w: Variant in history:
		var s: StringName = StringName(w)
		var c: Color = BaccaratStation.PLAYER_COLOR if s == BaccaratLogic.PLAYER else (BaccaratStation.BANKER_COLOR if s == BaccaratLogic.BANKER else BaccaratStation.TIE_COLOR)
		out.append("[b][color=#%s]%s[/color][/b]" % [c.lightened(0.2).to_html(false), String(s).substr(0, 1).to_upper()])
	return " ".join(out) if not out.is_empty() else "[color=#9A8F7A]—[/color]"


func _hand_box(word: String, color: Color, parent: Control) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = word.capitalize()
	box.custom_minimum_size = Vector2(MAIN_SIZE.x, 120)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.darkened(0.6), 0.9)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = color
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	box.add_theme_stylebox_override(&"panel", sb)
	box.set_meta(&"color", color)
	parent.add_child(box)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override(&"separation", 2)
	box.add_child(v)
	for spec: Array in [["Word", word, 18, color.lightened(0.35)], ["Cards", "—", 26, Palette.CREAM], ["Total", "", 34, Palette.VIP_GOLD]]:
		var l := Label.new()
		l.name = spec[0]
		l.text = spec[1]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override(&"font_size", spec[2])
		l.add_theme_color_override(&"font_color", spec[3])
		v.add_child(l)
	return box


func _bet_button(type: StringName, text: String, color: Color, parent: Control, size: Vector2) -> Button:
	var b := Button.new()
	b.name = String(type).capitalize().replace(" ", "")
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 20 if size == MAIN_SIZE else 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Palette.WARM_GOLD
	b.add_theme_stylebox_override(&"normal", sb)
	var hover: StyleBoxFlat = sb.duplicate()
	hover.bg_color = color.lightened(0.12)
	hover.border_color = Palette.VIP_GOLD
	hover.set_border_width_all(3)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	b.add_theme_stylebox_override(&"focus", hover)
	var off: StyleBoxFlat = sb.duplicate()
	off.bg_color = color.darkened(0.3)
	off.border_color = Palette.WARM_GOLD.darkened(0.4)
	b.add_theme_stylebox_override(&"disabled", off)
	b.pressed.connect(func() -> void: bet(type))
	parent.add_child(b)
	buttons[type] = b
	var badge := Label.new()
	badge.name = "Badge"
	badge.add_theme_color_override(&"font_color", Palette.CASINO_BLACK)
	var chip := StyleBoxFlat.new()
	chip.bg_color = Palette.VIP_GOLD
	chip.set_corner_radius_all(10)
	chip.border_color = Palette.CREAM
	chip.set_border_width_all(2)
	chip.content_margin_left = 6
	chip.content_margin_right = 6
	badge.add_theme_stylebox_override(&"normal", chip)
	badge.add_theme_font_size_override(&"font_size", 14)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -64
	badge.offset_right = -4
	badge.offset_top = 4
	badge.offset_bottom = 24
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	b.add_child(badge)
	_badges[type] = badge
	var dots := Label.new()
	dots.name = "Dots"
	dots.add_theme_font_size_override(&"font_size", 12)
	dots.position = Vector2(6, 2)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.visible = false
	b.add_child(dots)
	_dots[type] = dots
	return b


func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	body.add_child(l)
	return l


func _labels(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in cards:
		out.append(Card.label(int(c)).replace("S", "♠").replace("H", "♥").replace("D", "♦").replace("C", "♣"))
	return out
