class_name FindTheLadyStage
extends MinigameStage
## Client presentation for Find the Lady: Lucky's card table (`CardTableSet`) under a low lamp,
## the players' beans on chairs around it, and three (later four) big cards on the felt. Each
## round Lucky deals the cards face up and the Queen glows (SHOW), turns them over and shuffles
## them exactly as the server's swap sequence says (SHUFFLE: two cards bow past each other per
## swap, faster every round), then everyone picks (PICK: click a card or press 1-4, timer bar).
## Your own pick lifts and rings gold; the others only show THAT they picked. At the reveal the
## cards turn over, the Queen glows and every player's name chip lands on the card they chose.
##
## The shuffle is drawn from a clock (`shuffle_pose`), not from tweens, so a late joiner (or a
## test) can jump to any moment of it. Built behind the minigame curtain after
## `find_the_lady_started`; the first round's deal arrives once the briefing is over.

const CARD_SIZE: Vector2 = Vector2(0.6, 0.84)
## Distance between slot centres, by card count.
const SLOT_GAP: Dictionary = {3: 0.9, 4: 0.78}
const CARD_Z: float = 0.0
## How far the two cards of a swap bow apart (one towards the camera, one away).
const SWAP_ARC: float = 0.3
const SWAP_LIFT: float = 0.03
const DEAL_SLIDE: float = 0.32
## A pick the server never confirmed (refused on the way) is given back after this long.
const PICK_CONFIRM_TIMEOUT: float = 1.5
const MAX_CHIPS_PER_COLUMN: int = 4

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")

var table: CardTableSet
var host: QuizHost
## The card nodes, by card id (id i was dealt into slot i this round).
var cards: Array[TableCard3D] = []
## id → slot it is in now (follows the shuffle).
var slot_of: Array[int] = []
var card_count: int = 3
var lady_id: int = 0
var players_list: Array[int] = []
var round_num: int = 0
var rounds: int = FindTheLadyLogic.ROUNDS
## "intro", "show", "shuffle", "pick", "reveal", "over".
var phase: String = "intro"
var held: bool = false
var over: bool = false
var time_left: float = 0.0
var time_span: float = 1.0
var swaps: Array = []
var swap_time: float = 0.3
var flip_time: float = FindTheLadyLogic.FLIP_TIME
## Seconds into the shuffle animation (< 0: not shuffling).
var shuffle_t: float = -1.0
var my_pick: int = -1
var picked_players: Dictionary[int, bool] = {}
var totals: Dictionary[int, int] = {}
var gains: Dictionary[int, int] = {}
var reveal: Dictionary = {}
var ranking: Array = []
var hover_slot: int = -1

# UI
var root: Control
var round_label: Label
var phase_label: Label
var timer_box: HBoxContainer
var timer_bar: ProgressBar
var timer_label: Label
var prompt_label: Label
var sub_label: Label
var board: VBoxContainer
var board_rows: Dictionary[int, Dictionary] = {}
var chip_layer: Control
## [{chip: Control, slot: int, index: int}] name chips sitting on the cards after a reveal.
var chips: Array[Dictionary] = []
var key_hints: Array[Label] = []
var bubble: PanelContainer
var bubble_label: Label

var _deal_tween: Tween = null
var _reveal_tween: Tween = null
var _pick_sent_at: float = -1.0
var _clock: float = 0.0
var _last_beep: int = -1
var _last_swap_sound: int = -1
## How intents leave (tests swap it).
var send_intent: Callable = func(i: Dictionary) -> Dictionary: return Net.send_intent(i)


static func lady_card() -> int:
	return Card.make(12, 1)  # Q♥


static func decoy_cards() -> Array[int]:
	return [Card.make(13, 0), Card.make(11, 3), Card.make(13, 3)]  # K♠, J♣, K♣


func _build(start: Dictionary) -> void:
	_set_players(start.get("players", []))
	var hold: Variant = start.get("briefing", 0.0)
	held = (hold is Dictionary) or float(hold) > 0.0
	table = CardTableSet.new()
	table.name = "CardTable"
	add_child(table)
	table.build(state, local_id, players_list)
	host = table.host
	camera = table.camera
	for p: int in players_list:
		totals[p] = 0
	_build_ui()
	_ensure_cards(3)
	_stack_cards_at_dealer()
	if state != null and String(state.minigame.get("minigame", "")) == "find_the_lady":
		apply_state(state.minigame)  # a snapshot already reached us: use it
	else:
		_host_say("Welcome to my table! Keep your eyes on the lady.", QuizHost.Pose.HAPPY)
	_refresh()


func _set_players(list: Array) -> void:
	var fresh: Array[int] = []
	for p: Variant in list:
		fresh.append(int(p))
	players_list = fresh


# --- Cards -------------------------------------------------------------------------------------

## Slot centre on the felt (stage space) for `n` cards.
func slot_point(slot: int, n: int = -1) -> Vector3:
	var count: int = card_count if n < 0 else n
	var gap: float = float(SLOT_GAP.get(count, 0.7))
	return table.felt_point(Vector2((float(slot) - float(count - 1) * 0.5) * gap, CARD_Z), 0.015)


func _dealer_point() -> Vector3:
	return table.felt_point(Vector2(0.0, -CardTableSet.FELT_RADII.y + 0.42), 0.02)


func _ensure_cards(n: int) -> void:
	while cards.size() < n:
		var c := TableCard3D.make(TableCard3D.FACE_DOWN, CARD_SIZE, false)
		c.name = "Card%d" % cards.size()
		c.position = _dealer_point() + Vector3(0, 0.01 * cards.size(), 0)
		table.add_child(c)
		cards.append(c)
	while cards.size() > n:
		var extra: TableCard3D = cards.pop_back()
		extra.queue_free()
	slot_of.resize(n)
	for i: int in n:
		slot_of[i] = i


func _stack_cards_at_dealer() -> void:
	for i: int in cards.size():
		cards[i].position = _dealer_point() + Vector3(0, 0.006 * i, 0)
		cards[i].face_up_t = 0.0


## The faces of a fresh deal: card id `lady` is the Queen, the others are decoys.
func _set_faces(lady: int) -> void:
	lady_id = lady
	var decoys: Array[int] = decoy_cards()
	var d: int = 0
	for i: int in cards.size():
		if i == lady:
			cards[i].set_card(lady_card())
		else:
			cards[i].set_card(decoys[d % decoys.size()])
			d += 1


## Stops the deal and the reveal animations (a new phase takes the cards over).
func _kill_deal() -> void:
	if _deal_tween != null and _deal_tween.is_valid():
		_deal_tween.kill()
	_deal_tween = null
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	for c: TableCard3D in cards:
		c.stop_flip()


## A new round: the cards go face down, Lucky lays them out (the fourth one appears from the
## dealer's tray in round 4), then they turn face up and the Queen glows.
func _deal_round(n: int, lady: int, animate: bool) -> void:
	_kill_deal()
	shuffle_t = -1.0
	var was: int = cards.size()
	card_count = n
	_ensure_cards(n)
	for c: TableCard3D in cards:
		c.set_glow(0.0)
	if not animate or not is_inside_tree():
		_set_faces(lady)
		for i: int in n:
			cards[i].position = slot_point(i)
			cards[i].face_up_t = 1.0
		cards[lady].set_glow(0.9)
		return
	_deal_tween = create_tween()
	_deal_tween.set_parallel(true)
	var turn_down: float = 0.0
	for c: TableCard3D in cards:
		if c.face_up_t > 0.01:
			turn_down = 0.24
			_deal_tween.tween_property(c, ^"face_up_t", 0.0, 0.24)
	_deal_tween.chain().tween_callback(_set_faces.bind(lady))
	for i: int in n:
		var from_dealer: bool = i >= was
		var delay: float = 0.08 * float(i) + (0.15 if from_dealer else 0.0)
		_deal_tween.tween_property(cards[i], ^"position", slot_point(i), DEAL_SLIDE).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_deal_tween.chain().tween_interval(0.05)
	for i: int in n:
		_deal_tween.tween_property(cards[i], ^"face_up_t", 1.0, 0.3).set_delay(0.09 * float(i))
	_deal_tween.chain().tween_callback(func() -> void:
		if lady < cards.size():
			cards[lady].set_glow(0.9)
			_pop_card(lady)
		Audio.play(&"chime", &"UI", -12.0, 1.1))
	Audio.play(&"card_deal", &"UI", -8.0)
	if turn_down > 0.0:
		Audio.play(&"card_flip", &"UI", -12.0)


func _pop_card(id: int) -> void:
	if id < 0 or id >= cards.size() or not is_inside_tree():
		return
	var c: TableCard3D = cards[id]
	var t: Tween = c.create_tween()
	var base: Vector3 = c.position
	t.tween_property(c, ^"position:y", base.y + 0.12, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(c, ^"position:y", base.y, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Total length of the current shuffle animation.
func shuffle_length() -> float:
	return flip_time + swap_time * float(swaps.size())


## Poses the cards `t` seconds into the shuffle: they turn face down during `flip_time`, then
## swap pair after pair, each swap taking `swap_time` (the two cards bow past each other).
func shuffle_pose(t: float) -> void:
	var n: int = cards.size()
	var slots: Array[int] = []
	for i: int in n:
		slots.append(i)
	var k: float = (t - flip_time) / maxf(swap_time, 0.01)
	var done: int = clampi(floori(k), 0, swaps.size()) if k > 0.0 else 0
	for j: int in done:
		_apply_swap(slots, swaps[j])
	for i: int in n:
		cards[i].position = slot_point(slots[i])
		cards[i].face_up_t = 1.0 - clampf(t / maxf(flip_time, 0.01), 0.0, 1.0)
		cards[i].set_glow(0.0)
	if k > 0.0 and done < swaps.size():
		var u: float = smoothstep(0.0, 1.0, k - float(done))
		var a: int = int(swaps[done][0])
		var b: int = int(swaps[done][1])
		var bow: float = sin(u * PI)
		for i: int in n:
			if slots[i] == a:
				cards[i].position = slot_point(a).lerp(slot_point(b), u) + Vector3(0, SWAP_LIFT * bow, SWAP_ARC * bow)
			elif slots[i] == b:
				cards[i].position = slot_point(b).lerp(slot_point(a), u) + Vector3(0, SWAP_LIFT * bow * 0.5, -SWAP_ARC * bow)
		if done != _last_swap_sound and u > 0.05:
			_last_swap_sound = done
			Audio.play(&"whoosh", &"UI", -20.0, 1.3 + 0.05 * float(round_num))
	for i: int in n:
		slot_of[i] = slots[i]


static func _apply_swap(slots: Array[int], pair: Variant) -> void:
	var a: int = int(pair[0])
	var b: int = int(pair[1])
	for i: int in slots.size():
		if slots[i] == a:
			slots[i] = b
		elif slots[i] == b:
			slots[i] = a


## The card id lying in `slot` now.
func card_in_slot(slot: int) -> int:
	return slot_of.find(slot)


func _start_shuffle(seq: Array, p_swap_time: float, p_flip_time: float, elapsed: float) -> void:
	_kill_deal()
	swaps = seq.duplicate(true)
	swap_time = p_swap_time
	flip_time = p_flip_time
	shuffle_t = maxf(elapsed, 0.0)
	_last_swap_sound = -1
	for i: int in cards.size():
		slot_of[i] = i
	shuffle_pose(shuffle_t)
	if elapsed <= 0.0:
		Audio.play(&"card_flip", &"UI", -8.0)


## Jumps the shuffle to its end (pick window, reveal, late join).
func _end_shuffle() -> void:
	if shuffle_t >= 0.0 or not swaps.is_empty():
		shuffle_pose(shuffle_length() + 1.0)
	shuffle_t = -1.0


# --- UI ----------------------------------------------------------------------------------------

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	chip_layer = Control.new()
	chip_layer.name = "Chips"
	chip_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chip_layer)

	# Title plate, top left: the game, the round, what's happening.
	var plate := PanelContainer.new()
	plate.position = Vector2(28, 22)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override(&"panel", _panel_style(Color(Palette.CASINO_BLACK, 0.82), Palette.WARM_GOLD, 14))
	root.add_child(plate)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override(&"separation", -4)
	plate.add_child(pcol)
	pcol.add_child(_label("FIND THE LADY", BLACK_FONT, 46, Palette.VIP_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	round_label = _label("ROUND 1 / 5", BOLD_FONT, 28, Palette.CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	pcol.add_child(round_label)
	phase_label = _label("", BOLD_FONT, 24, Color(Palette.CREAM, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	pcol.add_child(phase_label)

	# Scoreboard, top right.
	var board_panel := PanelContainer.new()
	board_panel.anchor_left = 1.0
	board_panel.anchor_right = 1.0
	board_panel.offset_left = -330.0
	board_panel.offset_right = -28.0
	board_panel.offset_top = 22.0
	board_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	board_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_theme_stylebox_override(&"panel", _panel_style(Color(Palette.CASINO_BLACK, 0.82), Palette.WARM_GOLD, 14))
	root.add_child(board_panel)
	board = VBoxContainer.new()
	board.add_theme_constant_override(&"separation", 2)
	board_panel.add_child(board)
	board.add_child(_label("POINTS", BOLD_FONT, 24, Palette.WARM_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	for p: int in players_list:
		_add_board_row(p)

	# Bottom centre: the prompt, a line under it and the pick timer.
	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -190.0
	bottom.offset_bottom = -26.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override(&"separation", 2)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	prompt_label = _label("", BLACK_FONT, 60, Palette.VIP_GOLD)
	_shadow(prompt_label, 4)
	bottom.add_child(prompt_label)
	sub_label = _label("", BOLD_FONT, 30, Palette.CREAM)
	_shadow(sub_label, 3)
	bottom.add_child(sub_label)
	timer_box = HBoxContainer.new()
	timer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_box.add_theme_constant_override(&"separation", 16)
	timer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(timer_box)
	timer_bar = ProgressBar.new()
	timer_bar.custom_minimum_size = Vector2(520, 20)
	timer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer_bar.show_percentage = false
	timer_bar.max_value = 1.0
	timer_bar.step = 0.0
	timer_bar.value = 1.0
	timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_back: StyleBoxFlat = _panel_style(Color(Palette.CASINO_BLACK, 0.8), Color(Palette.WARM_GOLD, 0.6), 10)
	bar_back.set_content_margin_all(0)
	timer_bar.add_theme_stylebox_override(&"background", bar_back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.WARM_GOLD
	fill.set_corner_radius_all(10)
	timer_bar.add_theme_stylebox_override(&"fill", fill)
	timer_box.add_child(timer_bar)
	timer_label = _label("", BLACK_FONT, 40, Palette.CREAM)
	timer_label.custom_minimum_size = Vector2(50, 0)
	_shadow(timer_label, 3)
	timer_box.add_child(timer_label)

	# Lucky's speech bubble (follows the dealer on screen).
	bubble = PanelContainer.new()
	var bsb: StyleBoxFlat = _panel_style(Palette.CREAM, Palette.WARM_GOLD, 18)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.content_margin_top = 8
	bsb.content_margin_bottom = 10
	bsb.shadow_color = Color(0, 0, 0, 0.4)
	bsb.shadow_size = 8
	bubble.add_theme_stylebox_override(&"panel", bsb)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.visible = false
	root.add_child(bubble)
	bubble_label = _label("", BOLD_FONT, 26, Palette.CASINO_BLACK)
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.custom_minimum_size = Vector2(320, 0)
	bubble.add_child(bubble_label)

	for i: int in 4:
		var hint := _label(str(i + 1), BLACK_FONT, 34, Palette.CASINO_BLACK)
		hint.custom_minimum_size = Vector2(44, 44)
		var hs: StyleBoxFlat = _panel_style(Palette.VIP_GOLD, Palette.CREAM, 22)
		hint.add_theme_stylebox_override(&"normal", hs)
		hint.visible = false
		chip_layer.add_child(hint)
		key_hints.append(hint)


func _add_board_row(p: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(row)
	var dot := ColorRect.new()
	dot.color = _color(p)
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var nm := _label(("YOU" if p == local_id else _name(p)).left(12), BOLD_FONT, 26, Palette.VIP_GOLD if p == local_id else Palette.CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size = Vector2(120, 0)
	row.add_child(nm)
	var mark := _label("", BOLD_FONT, 22, Palette.MONEY_GREEN)
	mark.custom_minimum_size = Vector2(66, 0)
	row.add_child(mark)
	var pts := _label("0", BLACK_FONT, 28, Palette.CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
	pts.custom_minimum_size = Vector2(66, 0)
	row.add_child(pts)
	board_rows[p] = {"row": row, "name": nm, "mark": mark, "points": pts}


func _label(text: String, font: Font, size_px: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	return l


func _shadow(l: Label, offset: int) -> void:
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override(&"shadow_offset_y", offset)
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_outline_size", 6)


func _panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb


func _name(p: int) -> String:
	return state.player_name(p) if state != null else "Player %d" % p


func _color(p: int) -> Color:
	var idx: int = p
	if state != null and state.players.has(p):
		idx = int(state.players[p].get("color", p))
	return Palette.player_color(idx)


func _refresh() -> void:
	round_label.text = "ROUND %d / %d  ·  %d CARDS" % [round_num + 1, rounds, card_count]
	phase_label.text = str({"intro": "Take your seats", "show": "Here's the lady", "shuffle": "The shuffle", "pick": "Pick a card",
		"reveal": "The reveal", "over": "Final scores"}.get(phase, ""))
	var counting: bool = phase == "pick" and not over
	timer_box.modulate.a = 1.0 if counting else 0.0  # keeps its room: the prompt does not jump
	_update_clock()
	var prompt: String = ""
	var sub: String = ""
	match phase:
		"intro":
			prompt = "FIND THE LADY"
			sub = "Get ready - the cards come out when everyone is ready." if held else "Watch the Queen of hearts..."
		"show":
			prompt = "THERE SHE IS!"
			sub = "Remember where the Queen is."
		"shuffle":
			prompt = "KEEP YOUR EYE ON HER..."
			sub = "Round %d of %d%s" % [round_num + 1, rounds, " - fourth card in play!" if card_count == 4 and round_num == FindTheLadyLogic.FOURTH_CARD_ROUND else ""]
		"pick":
			if local_id not in players_list:
				prompt = "WHERE'S THE LADY?"
				sub = "Watch the table."
			elif my_pick >= 0:
				prompt = "LOCKED IN!"
				sub = "You picked card %d. %d of %d picked." % [my_pick + 1, picked_players.size(), players_list.size()]
			else:
				prompt = "FIND THE LADY!"
				sub = "Click a card or press 1-%d - faster scores more." % card_count
		"reveal":
			var pts: int = int(gains.get(local_id, 0))
			if local_id not in players_list:
				prompt = "THE REVEAL"
			elif pts > 0:
				prompt = "YOU FOUND HER!  +%d" % pts
			elif int((reveal.get("picks", {}) as Dictionary).get(local_id, -1)) >= 0:
				prompt = "WRONG CARD!"
			else:
				prompt = "TOO SLOW!"
			sub = "The lady was card %d." % (int(reveal.get("lady", 0)) + 1)
		"over":
			var top: Array[int] = _winners()
			if local_id in top:
				prompt = "YOU WIN!" if top.size() == 1 else "SHARED WIN!"
			elif not top.is_empty():
				prompt = "%s WINS!" % _names(top).to_upper()
			else:
				prompt = "GAME OVER"
			sub = "Most points after %d rounds." % rounds
	prompt_label.text = prompt
	prompt_label.add_theme_color_override(&"font_color", Palette.LOSS_RED if prompt in ["WRONG CARD!", "TOO SLOW!"] else Palette.VIP_GOLD)
	sub_label.text = sub
	_refresh_board()
	_refresh_cards()


func _refresh_board() -> void:
	var order: Array[int] = players_list.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(totals.get(a, 0)) != int(totals.get(b, 0)):
			return int(totals.get(a, 0)) > int(totals.get(b, 0))
		return a < b)
	var place: Dictionary = {}
	for row: Variant in ranking:
		place[int((row as Dictionary).get("player", -1))] = int((row as Dictionary).get("rank", 0))
	for i: int in order.size():
		var p: int = order[i]
		if not board_rows.has(p):
			_add_board_row(p)
		var r: Dictionary = board_rows[p]
		board.move_child(r["row"] as Control, i + 1)
		(r["points"] as Label).text = str(int(totals.get(p, 0)))
		var mark: Label = r["mark"]
		mark.text = ""
		if over and place.has(p):
			mark.text = "#%d" % place[p]
			mark.add_theme_color_override(&"font_color", Palette.VIP_GOLD if place[p] == 1 else Palette.CREAM)
		elif phase == "pick" and picked_players.has(p):
			mark.text = "PICKED"
			mark.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.75))
		elif phase == "reveal" and gains.has(p):
			var g: int = int(gains[p])
			mark.text = "+%d" % g if g > 0 else "-"
			mark.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if g > 0 else Color(Palette.LOSS_RED, 0.85))


## Glow and lift: your pick (gold, raised), the hovered card, the Queen at the show and reveal.
func _refresh_cards() -> void:
	if phase == "show" and (_deal_tween == null or not _deal_tween.is_valid()):
		for i: int in cards.size():
			cards[i].set_glow(0.9 if i == lady_id else 0.0)
	elif phase == "pick":
		for i: int in cards.size():
			var s: int = slot_of[i] if i < slot_of.size() else i
			var amount: float = 0.0
			if s == my_pick:
				amount = 1.0
			elif s == hover_slot and can_act():
				amount = 0.45
			cards[i].set_glow(amount)
			var base: Vector3 = slot_point(s)
			cards[i].position = base + Vector3(0, 0.05 if s == my_pick else 0.0, 0)


func _update_clock() -> void:
	if timer_box.modulate.a <= 0.0:
		return
	var frac: float = clampf(time_left / maxf(time_span, 0.01), 0.0, 1.0)
	timer_bar.value = frac
	var fill: StyleBoxFlat = timer_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	fill.bg_color = Palette.CASINO_RED if time_left <= 2.0 else Palette.WARM_GOLD
	timer_label.text = "%d" % ceili(time_left)


func _names(list: Array[int]) -> String:
	var out: PackedStringArray = []
	for p: int in list:
		out.append(_name(p))
	return " & ".join(out)


func _winners() -> Array[int]:
	var out: Array[int] = []
	for row: Variant in ranking:
		if int((row as Dictionary).get("rank", 0)) == 1:
			out.append(int((row as Dictionary).get("player", -1)))
	return out


## The dealer speaks (speech bubble) and strikes a pose.
func _host_say(text: String, pose: QuizHost.Pose = QuizHost.Pose.IDLE, hold: float = 2.2) -> void:
	if host == null:
		return
	host.say(text)
	host.set_pose(pose, hold)
	bubble_label.text = text
	bubble.visible = text != ""


func _place_bubble() -> void:
	if bubble == null or not bubble.visible or camera == null or host == null or not camera.is_inside_tree():
		return
	var p: Vector2 = PixelView.to_canvas(camera, camera.unproject_position(host.bubble_anchor()), bubble)
	var vp: Vector2 = bubble.get_viewport_rect().size
	bubble.reset_size()
	# Up and to the right of Lucky's head, clear of the cards.
	bubble.position = Vector2(clampf(p.x + 40.0, 16.0, vp.x - bubble.size.x - 16.0), clampf(p.y - bubble.size.y - 10.0, 16.0, vp.y - bubble.size.y - 16.0))


## Where a point of the set lands on the (sharp) UI canvas.
func _to_ui(world: Vector3) -> Vector2:
	return PixelView.to_canvas(camera, camera.unproject_position(world), chip_layer)


## The screen rectangle of the card in `slot` (for clicks and chips).
func slot_rect(slot: int) -> Rect2:
	if camera == null or not camera.is_inside_tree():
		return Rect2()
	var c: Vector3 = to_global(slot_point(slot))
	var hx: float = CARD_SIZE.x * 0.5
	var hz: float = CARD_SIZE.y * 0.5
	var r := Rect2(_to_ui(c + Vector3(-hx, 0, -hz)), Vector2.ZERO)
	for corner: Vector3 in [Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz)]:
		r = r.expand(_to_ui(c + corner))
	return r


func slot_at(pos: Vector2) -> int:
	for s: int in card_count:
		if slot_rect(s).grow(10.0).has_point(pos):
			return s
	return -1


## Name chips and key hints follow the cards on screen.
func _place_overlays() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var show_keys: bool = phase == "pick" and can_act()
	for i: int in key_hints.size():
		var hint: Label = key_hints[i]
		hint.visible = show_keys and i < card_count
		if hint.visible:
			var r: Rect2 = slot_rect(i)
			hint.reset_size()
			hint.position = Vector2(r.get_center().x - hint.size.x * 0.5, r.end.y + 8.0)
	for entry: Dictionary in chips:
		var chip: Control = entry["chip"]
		var r: Rect2 = slot_rect(int(entry["slot"]))
		var idx: int = int(entry["index"])
		var col: int = idx / MAX_CHIPS_PER_COLUMN
		var row: int = idx % MAX_CHIPS_PER_COLUMN
		chip.reset_size()
		var x: float = r.get_center().x - chip.size.x * 0.5 + (float(col) - float(entry["cols"] - 1) * 0.5) * (chip.size.x + 6.0)
		chip.position = Vector2(x, r.end.y + 6.0 + float(row) * (chip.size.y + 3.0))


func _clear_chips() -> void:
	for entry: Dictionary in chips:
		(entry["chip"] as Control).queue_free()
	chips.clear()


## Every player's name chip on the card they picked (yours says YOU); right picks ringed gold.
func _show_pick_chips(picks: Dictionary, lady_slot: int, animate: bool) -> void:
	_clear_chips()
	var by_slot: Dictionary = {}
	var pickers: Array[int] = []
	for k: Variant in picks:
		pickers.append(int(k))
	pickers.sort()
	for p: int in pickers:
		var s: int = int(picks[p])
		if not by_slot.has(s):
			by_slot[s] = []
		(by_slot[s] as Array).append(p)
	var n: int = 0
	for s: Variant in by_slot:
		var list: Array = by_slot[s]
		var cols: int = ceili(float(list.size()) / float(MAX_CHIPS_PER_COLUMN))
		for i: int in list.size():
			var p: int = int(list[i])
			var chip: PanelContainer = _make_chip(p, int(s) == lady_slot)
			chip_layer.add_child(chip)
			chips.append({"chip": chip, "slot": int(s), "index": i, "cols": cols, "player": p})
			if animate and is_inside_tree():
				chip.modulate.a = 0.0
				var t: Tween = chip.create_tween()
				t.tween_interval(0.55 + 0.07 * float(n))
				t.tween_property(chip, ^"modulate:a", 1.0, 0.18)
			n += 1
	_place_overlays()


func _make_chip(p: int, right: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Chip%d" % p
	chip.set_meta(&"player", p)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = _panel_style(_color(p), Palette.VIP_GOLD if right else Color(Palette.CASINO_BLACK, 0.6), 12)
	sb.set_border_width_all(3 if right else 2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override(&"panel", sb)
	var text_col: Color = Palette.CASINO_BLACK if _color(p).get_luminance() > 0.5 else Palette.CREAM
	var l := _label(("YOU" if p == local_id else _name(p)).left(10), BOLD_FONT, 24, text_col)
	chip.add_child(l)
	return chip


## Player ids whose chip is on the card in `slot` (tests).
func chips_on(slot: int) -> Array[int]:
	var out: Array[int] = []
	for entry: Dictionary in chips:
		if int(entry["slot"]) == slot:
			out.append(int(entry["player"]))
	return out


# --- Input -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if shuffle_t >= 0.0:
		shuffle_t += delta
		shuffle_pose(minf(shuffle_t, shuffle_length() + 0.01))
	if not held and time_left > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		if phase == "pick":
			_update_clock()
			var sec: int = ceili(time_left)
			if sec <= 3 and sec > 0 and sec != _last_beep:
				_last_beep = sec
				Audio.play(&"countdown_beep", &"UI", -12.0, 1.2)
	_place_bubble()
	_place_overlays()


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var s: int = slot_at(motion.position) if can_act() else -1
		if s != hover_slot:
			hover_slot = s
			_refresh_cards()
		return
	var click := event as InputEventMouseButton
	if click != null:
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and can_act():
			var s: int = slot_at(click.position)
			if s >= 0:
				pick(s)
				get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not can_act():
		return
	var n: int = -1
	if key.keycode >= KEY_1 and key.keycode <= KEY_4:
		n = key.keycode - KEY_1
	elif key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_4:
		n = key.keycode - KEY_KP_1
	if n >= 0 and n < card_count:
		pick(n)
		get_viewport().set_input_as_handled()


## True while the local player may still pick this round.
func can_act() -> bool:
	return phase == "pick" and not held and not over and my_pick < 0 and local_id in players_list and time_left > 0.0


## Picks the card in `slot` (sends the intent; the server decides).
func pick(slot: int) -> void:
	if not can_act() or slot < 0 or slot >= card_count:
		return
	my_pick = slot
	_pick_sent_at = _clock
	var res: Dictionary = send_intent.call(Intents.make(&"find_the_lady_pick", {"slot": slot, "round": round_num}))
	if not bool(res.get("ok", false)) and not bool(res.get("pending", false)):
		my_pick = -1  # refused (too late…)
		_pick_sent_at = -1.0
	else:
		Audio.play(&"chip_clack", &"UI", -4.0)
		table.hop(local_id, 0.2)
	_refresh()


## Called every frame with the local private snapshot.
func on_private(priv: Dictionary) -> void:
	var mg: Dictionary = priv.get("minigame", priv)
	if int(mg.get("round", round_num)) != round_num:
		return
	var picked: int = int(mg.get("picked", -1))
	var changed: bool = false
	if picked >= 0 and picked != my_pick:
		my_pick = picked  # the server has our pick (also after a resync)
		changed = true
	elif picked < 0 and my_pick >= 0 and bool(mg.get("can_pick", false)) and _pick_sent_at >= 0.0 and _clock - _pick_sent_at > PICK_CONFIRM_TIMEOUT:
		my_pick = -1  # the server never took it: pick again
		_pick_sent_at = -1.0
		changed = true
	if changed:
		_refresh()


# --- Server data -------------------------------------------------------------------------------

## Late join: the round, the phase and its clock, the deal / shuffle / reveal as far as it got.
func apply_state(st: Dictionary) -> void:
	if st.has("players"):
		_set_players(st["players"])
		for p: int in players_list:
			if not board_rows.has(p):
				_add_board_row(p)
	for k: Variant in (st.get("totals", {}) as Dictionary):
		totals[int(k)] = int(st["totals"][k])
	rounds = int(st.get("rounds", rounds))
	round_num = int(st.get("round", 0))
	phase = String(st.get("phase", "intro"))
	time_left = float(st.get("timer", 0.0))
	time_span = maxf(float(st.get("phase_time", time_left)), 0.01)
	if st.has("briefing"):
		held = true
	picked_players.clear()
	for p: Variant in st.get("picked", []):
		picked_players[int(p)] = true
	var n: int = int(st.get("cards", 3))
	var start_slot: int = int(st.get("lady_start", 0))
	match phase:
		"intro":
			card_count = n
			_stack_cards_at_dealer()
		"show":
			_deal_round(n, start_slot, false)
		"shuffle", "pick":
			_deal_round(n, start_slot, false)
			var elapsed: float = time_span - time_left if phase == "shuffle" else INF
			_start_shuffle(st.get("swaps", []), float(st.get("swap_time", 0.3)), FindTheLadyLogic.FLIP_TIME, minf(elapsed, 1e6))
			if phase == "pick":
				_end_shuffle()
		"reveal", "over":
			var rev: Dictionary = st.get("reveal", {})
			if not rev.is_empty():
				_deal_round(int(rev.get("cards", n)), int(rev.get("lady_start", 0)), false)
				_start_shuffle(rev.get("swaps", []), 0.3, FindTheLadyLogic.FLIP_TIME, 1e6)
				_end_shuffle()
				_show_reveal(rev, false)
			if phase == "over":
				over = true
				ranking = st.get("ranking", [])
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"minigame_go":
			held = false
			_refresh()
		&"find_the_lady_started":
			_set_players(ev.get("players", players_list))
			rounds = int(ev.get("rounds", rounds))
			for p: int in players_list:
				if not totals.has(p):
					totals[p] = 0
			_refresh()
		&"find_the_lady_round":
			held = false
			round_num = int(ev.get("round", 0))
			phase = "show"
			my_pick = -1
			_pick_sent_at = -1.0
			picked_players.clear()
			gains.clear()
			reveal = {}
			_clear_chips()
			table.calm_all()
			time_left = float(ev.get("seconds", FindTheLadyLogic.SHOW_TIME))
			time_span = time_left
			var n: int = int(ev.get("cards", 3))
			var added: bool = n > cards.size()
			_deal_round(n, int(ev.get("lady_start", 0)), true)
			if added and round_num > 0:
				_host_say("A fourth card joins the game!", QuizHost.Pose.SURPRISED)
			elif round_num == rounds - 1:
				_host_say("Last round. Fastest hands in the house!", QuizHost.Pose.HAPPY)
			elif round_num == 0:
				_host_say("Here's the lady. Watch her closely...", QuizHost.Pose.HAPPY)
			else:
				_host_say(["Again! A little faster this time.", "Think you can keep up?", "Eyes on the Queen..."][round_num % 3], QuizHost.Pose.IDLE)
			_refresh()
		&"find_the_lady_shuffle":
			phase = "shuffle"
			round_num = int(ev.get("round", round_num))
			if int(ev.get("cards", card_count)) != cards.size() or lady_id != int(ev.get("lady_start", lady_id)):
				_deal_round(int(ev.get("cards", card_count)), int(ev.get("lady_start", 0)), false)
			else:
				_kill_deal()
				_set_faces(lady_id)
			time_left = float(ev.get("seconds", 0.0))
			time_span = time_left
			_start_shuffle(ev.get("swaps", []), float(ev.get("swap_time", 0.3)), float(ev.get("flip_time", FindTheLadyLogic.FLIP_TIME)), 0.0)
			_host_say("Round and round she goes...", QuizHost.Pose.DRUMROLL, 0.0)
			_refresh()
		&"find_the_lady_pick":
			_end_shuffle()
			phase = "pick"
			time_left = float(ev.get("seconds", 5.0))
			time_span = time_left
			_last_beep = -1
			_host_say("Where's the Queen?", QuizHost.Pose.SURPRISED)
			_refresh()
		&"find_the_lady_picked":
			var who: int = int(ev.get("player", -1))
			picked_players[who] = true
			if who != local_id:
				table.hop(who, 0.15)
			_refresh()
		&"find_the_lady_reveal":
			_end_shuffle()
			phase = "reveal"
			time_left = FindTheLadyLogic.REVEAL_TIME
			_show_reveal(ev, true)
			_refresh()
		&"find_the_lady_over":
			_end_shuffle()
			phase = "over"
			over = true
			ranking = ev.get("ranking", [])
			for k: Variant in (ev.get("totals", {}) as Dictionary):
				totals[int(k)] = int(ev["totals"][k])
			var top: Array[int] = _winners()
			table.calm_all()
			for p: int in top:
				table.set_mood(p, BeanPuppet.Mood.CHEER)
			if not top.is_empty():
				_host_say("Sharpest eyes in the house: %s!" % _names(top), QuizHost.Pose.HAPPY, 0.0)
			if local_id in top:
				Audio.play(&"big_win", &"UI", -4.0)
			_refresh()


## The reveal: every card turns face up (the Queen last, glowing), the chips land on the picks,
## the beans cheer or sulk, the points go up.
func _show_reveal(rev: Dictionary, animate: bool) -> void:
	_kill_deal()
	reveal = rev.duplicate(true)
	var lady_slot: int = int(rev.get("lady", 0))
	# The server's word is final: if our shuffle drifted, the Queen is where it says.
	var id_there: int = card_in_slot(lady_slot)
	if id_there >= 0 and id_there != lady_id:
		var faces: Array[int] = []
		for c: TableCard3D in cards:
			faces.append(c.card)
		cards[id_there].set_card(lady_card())
		cards[lady_id].set_card(faces[id_there])
		lady_id = id_there
	gains.clear()
	var pts: Dictionary = rev.get("points", {})
	for k: Variant in pts:
		gains[int(k)] = int(pts[k])
	for k: Variant in (rev.get("totals", {}) as Dictionary):
		totals[int(k)] = int(rev["totals"][k])
	var picks: Dictionary = {}
	for k: Variant in (rev.get("picks", {}) as Dictionary):
		picks[int(k)] = int(rev["picks"][k])
	for i: int in cards.size():
		var c: TableCard3D = cards[i]
		c.position = slot_point(slot_of[i])
		c.set_glow(0.0)
		if not animate or not is_inside_tree():
			c.face_up_t = 1.0
		else:
			c.flip_to(true, 0.3, 0.12 * float(slot_of[i]) + (0.35 if i == lady_id else 0.0))
	if lady_id < cards.size():
		if animate and is_inside_tree():
			_reveal_tween = create_tween()
			_reveal_tween.tween_interval(0.7)
			_reveal_tween.tween_callback(func() -> void:
				cards[lady_id].set_glow(1.0)
				_pop_card(lady_id))
		else:
			cards[lady_id].set_glow(1.0)
	_show_pick_chips(picks, lady_slot, animate)
	for p: int in players_list:
		var mood: BeanPuppet.Mood = BeanPuppet.Mood.CHEER if int(gains.get(p, 0)) > 0 else BeanPuppet.Mood.SAD
		table.set_mood(p, mood)
		if mood == BeanPuppet.Mood.CHEER and animate:
			table.hop(p, 0.25)
		table.set_chips(p, 25 + int(totals.get(p, 0)) / 10)
	if not animate:
		return
	Audio.play(&"card_flip", &"UI", -6.0)
	var finders: Array[int] = []
	for p: int in players_list:
		if int(gains.get(p, 0)) > 0:
			finders.append(p)
	if finders.is_empty():
		_host_say("Nobody found her! The house thanks you.", QuizHost.Pose.HAPPY)
	elif finders.size() == players_list.size():
		_host_say("Everyone found her? I'm losing my touch!", QuizHost.Pose.DISAPPOINTED)
	else:
		var best: int = finders[0]
		for p: int in finders:
			if int(gains[p]) > int(gains[best]):
				best = p
		_host_say("Sharp eyes, %s!" % _name(best), QuizHost.Pose.SURPRISED)
	if int(gains.get(local_id, 0)) > 0:
		Audio.play(&"minor_win", &"UI", -6.0)
	elif local_id in players_list:
		Audio.play(&"loss_sting", &"UI", -10.0)
