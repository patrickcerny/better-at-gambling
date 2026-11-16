class_name BlackjackUi
extends StationUi
## Blackjack strip (docs/ART_DIRECTION.md). The cards are dealt on the 3D table (the head follows
## the cursor a little, the cursor clicks these buttons), so this only carries the round status,
## your total and the keys:
## 1-4 chip, Space bet, R repeat, Backspace clear, H hit, S stand, D double, P split, C cut
## (gamepad: A hit, X stand, Y double, RB split). Key names follow the device in use (InputGlyphs).

var hand_label: Label
var total_label: Label
var dealer_label: Label
var others_label: Label
## One panel per seat at the table (name, cards, total, bet), you highlighted in gold.
var seats_row: HBoxContainer
var seat_panels: Array[PanelContainer] = []
var seat_labels: Array[Label] = []
var hit: Button
var stand: Button
var double_btn: Button
var split_btn: Button
## Scissors item: snip the last card (shown only while you hold them).
var cut_btn: Button
## Busted with Scissors in hand (the cut window is open): HIT/DOUBLE hide, STAND reads TAKE BUST.
var rescue_mode: bool = false
var bet_panel: BetPanel
var actions: HBoxContainer
## The cards, drawn: the dealer's row (a face-down card while you play) and your hand(s).
var dealer_box: VBoxContainer
var dealer_cards: CardRow
var dealer_total: Label
var hands_box: VBoxContainer
var hand_rows: Array[CardRow] = []
## After a split, the hand the buttons play ("HAND 1" / "HAND 2"; "" when not split).
var hand_tag: String = ""


func _init() -> void:
	game_title = "BLACKJACK"


func _panel_height() -> float:
	return 560.0


func _dock_right() -> bool:
	return true  # the cards are on the table in the middle of the screen


## Locked while bets are open (or no round yet) and while your own hand still has to act.
func wants_camera_lock() -> bool:
	match int(pub.get("state", 0)):
		BlackjackLogic.State.IDLE, BlackjackLogic.State.BETTING:
			return true
		BlackjackLogic.State.ACTING:
			var hands: Dictionary = pub.get("hands", {})
			var mine: Dictionary = hands.get(local_id, hands.get(str(local_id), {}))
			return not mine.is_empty() and not bool(mine.get("done", true))
	return false


func _build() -> void:
	panel.offset_left = panel.offset_right - 500.0
	dealer_label = _line("DEALER  —", 22, Palette.WARM_GOLD)
	dealer_label.visible = false  # the dealer's cards are on the felt
	seats_row = HBoxContainer.new()
	seats_row.visible = false  # everyone's cards are on the felt now
	seats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seats_row.add_theme_constant_override(&"separation", 10)
	body.add_child(seats_row)
	for i: int in 4:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(190, 96)
		seats_row.add_child(p)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override(&"font_size", 19)
		p.add_child(l)
		seat_panels.append(p)
		seat_labels.append(l)
	dealer_box = VBoxContainer.new()
	dealer_box.name = "DealerBox"
	dealer_box.add_theme_constant_override(&"separation", 4)
	dealer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(dealer_box)
	dealer_box.add_child(TableSkin.caption("DEALER"))
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override(&"separation", 14)
	dealer_box.add_child(drow)
	dealer_cards = CardRow.new(58.0)
	drow.add_child(dealer_cards)
	dealer_total = TableSkin.label("", 26, Palette.CREAM, true)
	dealer_total.custom_minimum_size = Vector2(44, 0)
	drow.add_child(dealer_total)
	hands_box = VBoxContainer.new()
	hands_box.name = "HandsBox"
	hands_box.add_theme_constant_override(&"separation", 12)
	hands_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(hands_box)
	hands_box.add_child(TableSkin.caption("YOUR HAND"))
	for i: int in 2:
		var r := CardRow.new(84.0)
		r.name = "Hand%d" % (i + 1)
		hands_box.add_child(r)
		hand_rows.append(r)
	hand_label = _line("—", 30, Palette.CREAM)
	hand_label.visible = false  # the cards above show the hand; the text stays for the record
	total_label = _line("", 36, Palette.VIP_GOLD)
	total_label.add_theme_font_override(&"font", TableSkin.black_font())
	total_label.add_theme_color_override(&"font_outline_color", Color("#3A2410"))
	total_label.add_theme_constant_override(&"outline_size", 6)
	others_label = _line("", 20, Color("#9A8F7A"))
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override(&"separation", 8)
	body.add_child(actions)
	hit = _action("HIT", func() -> void: send(&"action", {"action": &"hit"}), &"felt")
	stand = _action("STAND", func() -> void: send(&"action", {"action": &"stand"}), &"red")
	double_btn = _action("DOUBLE", func() -> void: send(&"action", {"action": &"double"}), &"gold")
	split_btn = _action("SPLIT", func() -> void: send(&"action", {"action": &"split"}), &"ghost")
	cut_btn = _action("CUT  [C]", func() -> void: send(&"action", {"action": &"cut"}), &"ghost")
	cut_btn.visible = false
	bet_panel = BetPanel.new()
	bet_panel.confirmed.connect(func(a: int) -> void: send(&"place_bet", {"bet": {"amount": a}}))
	body.add_child(bet_panel)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.bj_min_bet)
	var hi: int = scaled(Registry.balance.bj_max_bet)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "BET")
	bet_panel.set_amount(lo * 2 + lo / 2)


func _hint_text() -> String:
	if InputGlyphs.gamepad:
		return InputGlyphs.fill("{look_left}: look around\n[{bet_chip_prev} / {bet_chip_next}] chip  [{bet_confirm}] bet  [{bet_repeat}] repeat\n[{leave_station}] stand up")
	return InputGlyphs.fill("Mouse: look around, click to play\n[1-4] chip  [{bet_confirm}] bet  [{bet_repeat}] repeat\n[{leave_station}] stand up")


func _relabel() -> void:
	var tag: String = (" " + hand_tag) if hand_tag != "" else ""
	hit.text = "HIT%s  %s" % [tag, InputGlyphs.hint(&"bj_hit")]
	stand.text = "%s%s  %s" % ["TAKE BUST" if rescue_mode else "STAND", tag, InputGlyphs.hint(&"bj_stand")]
	double_btn.text = "DOUBLE%s  %s" % [tag, InputGlyphs.hint(&"bj_double")]
	split_btn.text = "SPLIT  %s" % InputGlyphs.hint(&"bj_split")


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"bj_hit") and hit.visible:
		hit.pressed.emit()
	elif event.is_action_pressed(&"bj_stand"):
		stand.pressed.emit()
	elif event.is_action_pressed(&"bj_double") and double_btn.visible:
		double_btn.pressed.emit()
	elif event.is_action_pressed(&"bj_split") and split_btn.visible and not split_btn.disabled:
		split_btn.pressed.emit()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_C and cut_btn.visible:
		cut_btn.pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var timer: float = float(pub.get("timer", 0.0))
	var hands: Dictionary = pub.get("hands", {})
	var mine: Dictionary = hands.get(local_id, hands.get(str(local_id), {}))
	var dealer: Array = pub.get("dealer", [])
	# Your own decision clock (a split extends it), else the table's.
	if st == BlackjackLogic.State.ACTING and mine.has("clock"):
		timer = float(mine["clock"])
	match st:
		BlackjackLogic.State.IDLE:
			status_label.text = "Place a bet to start a round"
		BlackjackLogic.State.BETTING:
			status_label.text = "Bets close in %d s" % int(ceil(timer))
		BlackjackLogic.State.ACTING:
			status_label.text = "Your move  (%d s)" % int(ceil(timer)) if not mine.is_empty() and not bool(mine.get("done", true)) else "Waiting for the table…"
		BlackjackLogic.State.PAYOUT:
			status_label.text = "Dealer shows %d" % HandEval.total(_ints(dealer))
	var dealer_txt: String = " ".join(_labels(dealer))
	if st == BlackjackLogic.State.ACTING and dealer.size() == 1:
		dealer_txt += "  ??"
	dealer_label.text = "DEALER  %s" % (dealer_txt if not dealer.is_empty() else "—")
	if priv.has("hole_card"):
		dealer_label.text += "   (peek: %s)" % Card.label(int(priv["hole_card"]))
	var split: bool = mine.has("split")
	var active: int = int(mine.get("active", 0))
	var active_hand: Dictionary = (mine["split"] as Dictionary) if split and active == 1 else mine
	var playing_split: bool = st == BlackjackLogic.State.ACTING and split and not bool(mine.get("done", true))
	if playing_split:
		status_label.text = "Your move: hand %d of 2  (%d s)" % [active + 1, int(ceil(timer))]
	# Busted with Scissors in hand: a few seconds to cut the busting card away.
	var rescue: bool = st == BlackjackLogic.State.ACTING and bool(mine.get("rescue", false)) and not bool(mine.get("done", true))
	if rescue:
		status_label.text = "BUST!  Cut the last card with your Scissors  (%d s)" % int(ceil(timer))
	if mine.is_empty():
		hand_label.text = "—"
		total_label.text = ""
	elif split:
		# Both hands, the one you are playing marked; the totals ride along on each line.
		var lines: PackedStringArray = []
		for i: int in 2:
			var h: Dictionary = mine if i == 0 else mine["split"]
			var playing: bool = playing_split and active == i
			var hand_done: bool = bool(mine.get("first_done", false)) if i == 0 else bool(mine.get("done", false))
			lines.append("%sHAND %d   %s   %s" % ["» " if playing else "", i + 1, " ".join(_labels(h.get("cards", []))), _total_text(h, false, hand_done)])
		hand_label.text = "\n".join(lines)
		# The big number is the hand you are playing; both stakes once you are done.
		if playing_split:
			total_label.text = "HAND %d: %s" % [active + 1, _total_text(active_hand, false)]
		else:
			total_label.text = "SPLIT  $%d + $%d" % [int(mine.get("stake", 0)), int((mine["split"] as Dictionary).get("stake", 0))]
	else:
		var cards: Array = mine.get("cards", [])
		hand_label.text = " ".join(_labels(cards)) if not cards.is_empty() else "bet $%d" % int(mine.get("stake", 0))
		total_label.text = _total_text(mine, true)
	var acting: bool = st == BlackjackLogic.State.ACTING and not mine.is_empty() and not bool(mine.get("done", true))
	var tag: String = "HAND %d" % (active + 1) if playing_split else ""
	if tag != hand_tag or rescue != rescue_mode:
		hand_tag = tag
		rescue_mode = rescue
		_relabel()
	actions.visible = acting
	hit.visible = not rescue
	double_btn.visible = not rescue
	double_btn.disabled = not acting or (active_hand.get("cards", []) as Array).size() != 2
	split_btn.visible = acting and not rescue and bool(mine.get("can_split", false))
	cut_btn.visible = acting and bool(priv.get("scissors", false))
	cut_btn.disabled = (active_hand.get("cards", []) as Array).size() < 3
	bet_panel.visible = (st == BlackjackLogic.State.IDLE or st == BlackjackLogic.State.BETTING) and mine.is_empty()
	_refresh_seats(pub.get("seats", []), hands)
	others_label.text = ""
	_refresh_cards(st, dealer, mine, split, active, playing_split)


## The drawn cards: the dealer's (a hole card face down while hands are played) and yours, both
## split hands with the one you are playing underlined in gold.
func _refresh_cards(st: int, dealer: Array, mine: Dictionary, split: bool, active: int, playing_split: bool) -> void:
	var shown: Array = dealer.duplicate()
	if st == BlackjackLogic.State.ACTING and dealer.size() == 1:
		shown.append(-1)
	dealer_box.visible = not dealer.is_empty()
	dealer_cards.show_cards(shown)
	dealer_total.text = str(HandEval.total(_ints(dealer))) if not dealer.is_empty() else ""
	var cards: Array = mine.get("cards", [])
	hands_box.visible = not cards.is_empty()
	hand_rows[0].show_cards(cards, int(mine.get("total", 0)) > 21)
	hand_rows[0].active = playing_split and active == 0
	hand_rows[1].visible = split
	if split:
		var h2: Dictionary = mine["split"]
		hand_rows[1].show_cards(h2.get("cards", []), int(h2.get("total", 0)) > 21)
		hand_rows[1].active = playing_split and active == 1


## Every seat: who sits there, their cards and total, their bet, and whether they're done.
func _refresh_seats(seats: Array, hands: Dictionary) -> void:
	for i: int in seat_panels.size():
		var pid: int = int(seats[i]) if i < seats.size() else -1
		var l: Label = seat_labels[i]
		var me: bool = pid == local_id and pid >= 0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Palette.FELT_GREEN, 0.85) if pid >= 0 else Color(Palette.CASINO_BLACK, 0.5)
		sb.border_color = Palette.VIP_GOLD if me else Color(Palette.WARM_GOLD, 0.35)
		sb.set_border_width_all(3 if me else 1)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		seat_panels[i].add_theme_stylebox_override(&"panel", sb)
		if pid < 0:
			l.text = "Seat %d\nempty" % (i + 1)
			l.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.4))
			continue
		var name: String = ("YOU" if me else (state.player_name(pid) if state != null else str(pid)))
		var h: Dictionary = {}
		for k: Variant in hands:
			if int(k) == pid:
				h = hands[k]
		var lines: PackedStringArray = [name]
		if h.is_empty():
			lines.append("no bet")
		else:
			var cards: Array = h.get("cards", [])
			lines.append(" ".join(_labels(cards)) if not cards.is_empty() else "—")
			var total: int = int(h.get("total", 0))
			var shown: String = HandEval.total_text(_ints(cards), bool(h.get("done", false)))
			var tail: String = ""
			if total > 21:
				tail = "  BUST"
			elif bool(h.get("done", false)) and not cards.is_empty():
				tail = "  STAND"
			lines.append("%s$%d%s" % [("%s  ·  " % shown) if total > 0 else "", int(h.get("stake", 0)), tail])
		l.text = "\n".join(lines)
		l.add_theme_color_override(&"font_color", Palette.VIP_GOLD if me else Palette.CREAM)


## "18", "7 / 17" (soft, still in play), "23  BUST", "21  BLACKJACK!" (a natural only counts on
## an unsplit hand).
static func _total_text(h: Dictionary, natural: bool, done: Variant = null) -> String:
	var total: int = int(h.get("total", 0))
	var finished: bool = bool(h.get("done", false)) if done == null else bool(done)
	var out: String = HandEval.total_text(_ints(h.get("cards", [])), finished) if total > 0 else ""
	if total > 21:
		out += "  BUST"
	elif natural and total == 21 and (h.get("cards", []) as Array).size() == 2:
		out += "  BLACKJACK!"
	return out


func _labels(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in cards:
		out.append(_pretty(Card.label(int(c))))
	return out


static func _ints(cards: Array) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in cards:
		out.append(int(c))
	return out


static func _pretty(label: String) -> String:
	return label.replace("S", "♠").replace("H", "♥").replace("D", "♦").replace("C", "♣")


func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	body.add_child(l)
	return l


func _action(text: String, on_pressed: Callable, kind: StringName = &"felt") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TableSkin.style_button(b, kind, 24)
	b.pressed.connect(on_pressed)
	actions.add_child(b)
	return b
