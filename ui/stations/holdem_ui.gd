class_name HoldemUi
extends StationUi
## Casino Hold'em overlay: a column down the right third of the screen (the seat camera frames the
## felt on the left). Pick the ANTE with the chips and the AA BONUS (off or a chip), DEAL puts them
## down; once the flop is out the two big buttons FOLD or CALL (twice the ante) on your own clock.
## Your hand is named live ("Pair of Kings"), the dealer's at the showdown, then the result line.
## The paytables are folded away under HOW IT WORKS.
## Keys: [1-4] chip, [B] bonus, [Space] deal, [R] repeat; [C] or [H] call, [F] or [S] fold (gamepad:
## A call, X fold). Key names follow the device in use (InputGlyphs).

var cards_label: Label
var hand_label: Label
var dealer_label: Label
var result_label: Label
var actions: HBoxContainer
var call_btn: Button
var fold_btn: Button
var bet_panel: BetPanel
var bonus_row: HBoxContainer
var bonus_buttons: Array[Button] = []
## The AA Bonus sizes on offer (0 = off), and the one picked.
var bonus_sizes: Array[int] = [0]
var bonus: int = 0
var others_label: Label


func _init() -> void:
	game_title = "CASINO HOLD'EM"


func _dock_column() -> bool:
	return true


## Locked while you can ante (no hand yet) and while your own decision is open.
func wants_camera_lock() -> bool:
	var mine: Dictionary = my_hand()
	match int(pub.get("state", 0)):
		HoldemLogic.State.IDLE, HoldemLogic.State.BETTING:
			return true
		HoldemLogic.State.DECIDING:
			return not mine.is_empty() and StringName(mine.get("decision", &"")) == &""
	return false


## The local player's hand in the newest state (empty when they have none).
func my_hand() -> Dictionary:
	return HoldemStation.hand_of(pub.get("hands", {}), local_id)


func _build() -> void:
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(120, 0)
	dealer_label = _line("", 22, Palette.WARM_GOLD)
	dealer_label.name = "Dealer"
	cards_label = _line("", 26, Palette.CREAM)
	cards_label.name = "Cards"
	hand_label = _line("", 34, Palette.VIP_GOLD)
	hand_label.name = "Hand"
	result_label = _line("", 22, Palette.CREAM)
	result_label.name = "Result"
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(120, 0)
	actions = HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override(&"separation", 12)
	body.add_child(actions)
	fold_btn = _action("Fold", fold)
	call_btn = _action("Call", call_it)
	var bonus_title := _line("AA BONUS  ·  pays on your first five cards", 17, Palette.WARM_GOLD)
	bonus_title.name = "BonusTitle"
	bonus_row = HBoxContainer.new()
	bonus_row.name = "Bonus"
	bonus_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bonus_row.add_theme_constant_override(&"separation", 8)
	body.add_child(bonus_row)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(72, 48)
	bet_panel.chip_gap = 8
	bet_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bet_panel.confirmed.connect(func(a: int) -> void: deal(a))
	body.add_child(bet_panel)
	others_label = _line("", 16, Color("#9A8F7A"))
	others_label.name = "Others"
	others_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	others_label.custom_minimum_size = Vector2(120, 0)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.holdem_min_bet)
	var hi: int = scaled(Registry.balance.holdem_max_bet)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "DEAL")
	bet_panel.set_amount(lo * 2 + lo / 2)
	var bmax: int = scaled(Registry.balance.holdem_bonus_max_bet)
	bonus_sizes = [0]
	for s: int in [lo, lo * 2 + lo / 2, bmax]:
		if s <= bmax and not s in bonus_sizes:
			bonus_sizes.append(s)
	for b: Button in bonus_buttons:
		b.queue_free()
	bonus_buttons.clear()
	for i: int in bonus_sizes.size():
		var b := Button.new()
		b.name = "Bonus%d" % i
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(84, 40)
		b.text = "OFF" if bonus_sizes[i] == 0 else money(bonus_sizes[i])
		var idx: int = i
		b.pressed.connect(func() -> void: set_bonus(bonus_sizes[idx]))
		bonus_row.add_child(b)
		bonus_buttons.append(b)
	if not bonus in bonus_sizes:
		bonus = 0
	_show_bonus()


## Picks the AA Bonus for the next deal (0 = none).
func set_bonus(amount: int) -> void:
	bonus = amount if amount in bonus_sizes else 0
	_show_bonus()
	_refresh()


## The next AA Bonus size along (OFF → … → the largest → OFF).
func cycle_bonus() -> void:
	var i: int = bonus_sizes.find(bonus)
	set_bonus(bonus_sizes[(i + 1) % bonus_sizes.size()])


func _show_bonus() -> void:
	for i: int in bonus_buttons.size():
		bonus_buttons[i].set_pressed_no_signal(bonus_sizes[i] == bonus)


## Puts the ante (and the AA Bonus picked) down; the server deals when the window closes.
func deal(ante: int) -> bool:
	var bet: Dictionary = {"amount": ante}
	if bonus > 0:
		bet["bonus"] = bonus
	return send(&"place_bet", {"bet": bet})


func call_it() -> bool:
	return send(&"action", {"action": HoldemLogic.CALL})


func fold() -> bool:
	return send(&"action", {"action": HoldemLogic.FOLD})


func _rules_text() -> String:
	var cfg: BalanceConfig = Registry.balance
	var ante: PackedStringArray = []
	for cat: int in [HoldemHand.Rank.ROYAL_FLUSH, HoldemHand.Rank.STRAIGHT_FLUSH, HoldemHand.Rank.FOUR_OF_A_KIND, HoldemHand.Rank.FULL_HOUSE, HoldemHand.Rank.FLUSH]:
		ante.append("%s %d:1" % [HoldemHand.category_name(cat), cfg.holdem_ante_pays[cat]])
	ante.append("Straight or lower %d:1" % cfg.holdem_ante_pays[HoldemHand.Rank.STRAIGHT])
	var bonus_lines: PackedStringArray = []
	for cat: int in [HoldemHand.Rank.ROYAL_FLUSH, HoldemHand.Rank.STRAIGHT_FLUSH, HoldemHand.Rank.FOUR_OF_A_KIND, HoldemHand.Rank.FULL_HOUSE, HoldemHand.Rank.FLUSH]:
		bonus_lines.append("%s %d:1" % [HoldemHand.category_name(cat), cfg.holdem_bonus_pays[cat]])
	bonus_lines.append("Pair of Aces to Straight %d:1" % cfg.holdem_bonus_pays[HoldemHand.Rank.STRAIGHT])
	return ("Texas Hold'em against the dealer. Put down an ANTE (and the AA BONUS if you like): you get two cards, the dealer two face down, and three cards go on the board. "
		+ "FOLD and lose the ante, or CALL for twice the ante. Then the turn and the river; the best five of your two cards and the five on the board play against the dealer's.\n"
		+ "The dealer needs a pair of 4s or better. If not, your ante pays by the table and the call comes back. If so: beat the dealer and the ante pays by the table and the call 1:1; a tie gives both back; lose and both are lost. Out of time = fold.\n"
		+ "ANTE:  " + "  ·  ".join(ante) + "\n"
		+ "AA BONUS (your cards + the flop, paid even if you fold):  " + "  ·  ".join(bonus_lines))


func _hint_text() -> String:
	if InputGlyphs.gamepad:
		return InputGlyphs.fill("[{bet_chip_prev} / {bet_chip_next}] chip  [{bet_confirm}] deal\n[{bj_hit}] call  [{bj_stand}] fold  [{leave_station}] stand up")
	return InputGlyphs.fill("[1-4] chip  [B] bonus  [{bet_confirm}] deal  [{bet_repeat}] repeat\n[C] call  [F] fold  [{leave_station}] stand up")


func _relabel() -> void:
	_refresh_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key: Key = (event as InputEventKey).physical_keycode if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo else KEY_NONE
	if actions.visible and (event.is_action_pressed(&"bj_hit") or key == KEY_C) and not call_btn.disabled:
		call_btn.pressed.emit()
	elif actions.visible and (event.is_action_pressed(&"bj_stand") or key == KEY_F) and not fold_btn.disabled:
		fold_btn.pressed.emit()
	elif bet_panel.visible and key == KEY_B:
		cycle_bonus()
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var timer: float = float(pub.get("timer", 0.0))
	var mine: Dictionary = my_hand()
	var decision: StringName = StringName(mine.get("decision", &""))
	var deciding: bool = st == HoldemLogic.State.DECIDING and not mine.is_empty() and decision == &""
	match st:
		HoldemLogic.State.IDLE:
			status_label.text = "Ante up to deal a hand"
		HoldemLogic.State.BETTING:
			status_label.text = "Cards in %d s" % int(ceil(timer)) if not mine.is_empty() else "Cards in %d s: ante up to play" % int(ceil(timer))
		HoldemLogic.State.DECIDING:
			if deciding:
				status_label.text = "Fold or call?  (%d s)" % int(ceil(float(mine.get("clock", timer))))
			else:
				status_label.text = "Waiting for the table…"
		HoldemLogic.State.PAYOUT:
			status_label.text = "Showdown"
	var hole: Array = mine.get("hole", [])
	var board: Array = pub.get("board", [])
	if hole.is_empty():
		cards_label.text = ("BOARD  " + "  ".join(_labels(board))) if not board.is_empty() else ""
		hand_label.text = ("ANTE $%d%s" % [int(mine.get("ante", 0)), ("  ·  BONUS $%d" % int(mine["bonus"])) if int(mine.get("bonus", 0)) > 0 else ""]) if not mine.is_empty() else ""
	else:
		cards_label.text = "%s   |   %s" % ["  ".join(_labels(hole)), "  ".join(_labels(board))]
		hand_label.text = "FOLDED" if decision == HoldemLogic.FOLD else String(mine.get("hand", ""))
	dealer_label.text = _dealer_text()
	result_label.text = _result_text(mine)
	actions.visible = deciding
	_refresh_buttons()
	var betting: bool = (st == HoldemLogic.State.IDLE or st == HoldemLogic.State.BETTING) and mine.is_empty()
	bet_panel.visible = betting
	bonus_row.visible = betting
	(body.get_node(^"BonusTitle") as Control).visible = betting
	# All-in keeps the call covered: the most the ante can be is a third of what's left after the bonus.
	if state != null:
		bet_panel.set_balance(maxi(my_balance() - bonus, 0) / 3)
	others_label.text = _others_text()


func _refresh_buttons() -> void:
	if call_btn == null:
		return
	var mine: Dictionary = my_hand()
	var ante: int = int(mine.get("ante", 0))
	call_btn.text = "CALL  %s\n%s" % [InputGlyphs.hint(&"bj_hit") if InputGlyphs.gamepad else "[C]", money(ante * 2)]
	fold_btn.text = "FOLD  %s\nlose %s" % [InputGlyphs.hint(&"bj_stand") if InputGlyphs.gamepad else "[F]", money(ante)]
	call_btn.disabled = ante * 2 > my_balance()


## "DEALER  ?? ??", then "DEALER  4♣ 4♦  ·  Pair of Fours" or "… does not qualify".
func _dealer_text() -> String:
	var dealer: Array = pub.get("dealer", [])
	var down: int = int(pub.get("dealer_down", 0))
	if dealer.is_empty() and down == 0:
		return ""
	if dealer.is_empty():
		return "DEALER  " + "  ".join(PackedStringArray(["??", "??"]).slice(0, down))
	var out: String = "DEALER  %s  ·  %s" % ["  ".join(_labels(dealer)), String(pub.get("dealer_hand", ""))]
	if not bool(pub.get("qualifies", true)):
		out += "  ·  does not qualify"
	return out


## The settled bets of your hand: the bonus as soon as the flop is out, the rest at the showdown.
func _result_text(mine: Dictionary) -> String:
	if mine.is_empty():
		return ""
	var lines: PackedStringArray = []
	var b: int = int(mine.get("bonus", 0))
	var b_ret: int = int(mine.get("bonus_returned", -1))
	if b > 0 and b_ret >= 0:
		lines.append(("AA BONUS  +%s" % money(b_ret - b)) if b_ret > 0 else "AA BONUS lost")
	var ante: int = int(mine.get("ante", 0))
	var call: int = int(mine.get("call", 0))
	var net: int = int(mine.get("returned", 0)) - ante - call
	match StringName(mine.get("outcome", &"")):
		&"fold":
			lines.append("Folded: the ante (%s) is lost" % money(ante))
		&"no_qualify":
			lines.append("Dealer doesn't qualify: ante pays, call back  ·  +%s" % money(net))
		&"win":
			lines.append("YOU WIN  ·  +%s" % money(net))
		&"push":
			lines.append("Tie: both bets back")
		&"lose":
			lines.append("Dealer wins  ·  −%s" % money(-net))
	return "\n".join(lines)


## Everyone else at the table: their hand name and decision.
func _others_text() -> String:
	var lines: PackedStringArray = []
	var hands: Dictionary = pub.get("hands", {})
	for s: Variant in pub.get("seats", []):
		var pid: int = int(s)
		if pid < 0 or pid == local_id:
			continue
		var h: Dictionary = HoldemStation.hand_of(hands, pid)
		var who: String = state.player_name(pid) if state != null else str(pid)
		if h.is_empty():
			lines.append("%s: watching" % who)
			continue
		var d: StringName = StringName(h.get("decision", &""))
		var what: String = "folded" if d == HoldemLogic.FOLD else ("called" if d == HoldemLogic.CALL else ("deciding" if not (h.get("hole", []) as Array).is_empty() else "ante $%d" % int(h.get("ante", 0))))
		lines.append("%s: %s%s" % [who, what, ("  ·  " + String(h["hand"])) if h.has("hand") and d != HoldemLogic.FOLD else ""])
	return "\n".join(lines)


func _action(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = text
	b.text = text
	b.custom_minimum_size = Vector2(200, 72)
	b.theme_type_variation = &"ActionButton"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 20)
	b.pressed.connect(func() -> void: on_pressed.call())
	actions.add_child(b)
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
		out.append(_pretty(Card.label(int(c))))
	return out


static func _pretty(label: String) -> String:
	return label.replace("S", "♠").replace("H", "♥").replace("D", "♦").replace("C", "♣")
