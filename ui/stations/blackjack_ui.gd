class_name BlackjackUi
extends StationUi
## Blackjack overlay (docs/ART_DIRECTION.md): YOUR HAND, total, dealer, HIT / STAND / DOUBLE,
## bet stepper. Keys: H hit, S stand, D double.

var hand_label: Label
var total_label: Label
var dealer_label: Label
var others_label: Label
var hit: Button
var stand: Button
var double_btn: Button
var bet_panel: BetPanel
var actions: HBoxContainer


func _init() -> void:
	game_title = "BLACKJACK"


func _panel_height() -> float:
	return 470.0


func _build() -> void:
	dealer_label = _line("DEALER  —", 26, Palette.WARM_GOLD)
	var your := Label.new()
	your.theme_type_variation = &"SmallLabel"
	your.text = "YOUR HAND"
	your.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(your)
	hand_label = _line("—", 44, Palette.CREAM)
	total_label = _line("", 30, Palette.VIP_GOLD)
	others_label = _line("", 20, Color("#9A8F7A"))
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override(&"separation", 14)
	body.add_child(actions)
	hit = _action("HIT  [H]", func() -> void: send(&"action", {"action": &"hit"}))
	stand = _action("STAND  [S]", func() -> void: send(&"action", {"action": &"stand"}))
	double_btn = _action("DOUBLE  [D]", func() -> void: send(&"action", {"action": &"double"}))
	bet_panel = BetPanel.new()
	bet_panel.confirmed.connect(func(a: int) -> void: send(&"place_bet", {"bet": {"amount": a}}))
	body.add_child(bet_panel)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.bj_min_bet)
	var hi: int = scaled(Registry.balance.bj_max_bet)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "BET")
	bet_panel.set_amount(lo * 2 + lo / 2)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"bj_hit"):
		hit.pressed.emit()
	elif event.is_action_pressed(&"bj_stand"):
		stand.pressed.emit()
	elif event.is_action_pressed(&"bj_double"):
		double_btn.pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var timer: float = float(pub.get("timer", 0.0))
	var hands: Dictionary = pub.get("hands", {})
	var mine: Dictionary = hands.get(local_id, hands.get(str(local_id), {}))
	var dealer: Array = pub.get("dealer", [])
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
	if mine.is_empty():
		hand_label.text = "—"
		total_label.text = ""
	else:
		var cards: Array = mine.get("cards", [])
		hand_label.text = " ".join(_labels(cards)) if not cards.is_empty() else "bet $%d" % int(mine.get("stake", 0))
		var total: int = int(mine.get("total", 0))
		total_label.text = ("%d" % total) if total > 0 else ""
		if total > 21:
			total_label.text += "  BUST"
		elif total == 21 and cards.size() == 2:
			total_label.text += "  BLACKJACK!"
	var acting: bool = st == BlackjackLogic.State.ACTING and not mine.is_empty() and not bool(mine.get("done", true))
	actions.visible = acting
	double_btn.disabled = not acting or (mine.get("cards", []) as Array).size() != 2
	bet_panel.visible = (st == BlackjackLogic.State.IDLE or st == BlackjackLogic.State.BETTING) and mine.is_empty()
	var others: Array[String] = []
	for pid: Variant in hands:
		if int(pid) == local_id:
			continue
		var h: Dictionary = hands[pid]
		others.append("%s: %s (%d)" % [state.player_name(int(pid)) if state != null else str(pid), " ".join(_labels(h.get("cards", []))), int(h.get("total", 0))])
	others_label.text = "   ".join(others)


func _labels(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in cards:
		out.append(_pretty(Card.label(int(c))))
	return out


func _ints(cards: Array) -> Array[int]:
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


func _action(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 56)
	b.pressed.connect(on_pressed)
	actions.add_child(b)
	return b
