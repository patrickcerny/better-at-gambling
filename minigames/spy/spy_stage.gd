class_name SpyStage
extends MinigameStage
## Client presentation for Spy as a lit game-show panel (the Vote Race set): the game clock dial,
## a bulb marquee ("WHO IS THE SPY?"), your secret card (the word, or "YOU ARE THE SPY" with the
## category and later the hint), an action strip (whose clue turn it is with a timer bar, your
## clue entry on your turn, CALL A VOTE / V) and one cream card per player in seat order with
## their clues as numbered slips. The speaker stands in a warm spotlight. In a vote you click a
## card or press its number; at the reveal (`spy_vote_result`) every voter's name chip flies onto
## the card they picked, the tallies count up, then the verdict stamps the accused card
## ("OUT · THE SPY" / "OUT · INNOCENT"). The end shows the word, the spies and the winning side.
##
## Everything secret comes from the private state (`on_private`, every frame); the events and the
## snapshot are public. A rules briefing holds the clock until `minigame_go`.

const CHIP_STAGGER: float = 0.12
const VOTE_CONFIRM_TIMEOUT: float = 1.5
const MESSAGE_TIME: float = 3.0
const CARD_MIN_W: float = 170.0
const CARD_MAX_W: float = 290.0
const CARD_GAP: float = 22.0

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")

const REJECT_TEXT: Dictionary = {
	&"is_the_word": "That's the secret word itself - give a clue, not the answer!",
	&"empty_clue": "Type a clue word first.",
	&"not_your_turn": "It's not your turn any more.",
	&"cooldown": "A vote just ended - wait a moment before calling another.",
	&"not_now": "You can't call a vote right now.",
	&"already_voted": "You already voted.",
	&"bad_target": "You can't vote for that player.",
	&"out": "You're out of the game - watch the rest.",
}

var root: Control
var set_bg: VoteRaceSet
var marquee: VoteRaceMarquee
var clock: SpyClock
var secret_card: SpySecretCard
var action_label: Label
var action_bar: ProgressBar
var action_time: Label
var entry: LineEdit
var say_button: Button
var vote_button: Button
var cards_row: HBoxContainer
var status_label: Label

var seats: Array[int] = []
var alive: Array[int] = []
var caught: Array[int] = []
var cards: Dictionary[int, SpyCard] = {}
var clues: Dictionary[int, Array] = {}
## intro, clues, open, vote, reveal, over.
var phase: String = "intro"
var held: bool = false
var spy_count: int = 1
var round_num: int = 0
var rounds: int = SpyLogic.CLUE_ROUNDS
var speaker: int = -1
var turn_left: float = SpyLogic.CLUE_TIME
var turn_span: float = SpyLogic.CLUE_TIME
var clock_left: float = 0.0
var clock_total: float = 0.0
var vote_left: float = SpyLogic.VOTE_TIME
var vote_span: float = SpyLogic.VOTE_TIME
var vote_needed: int = 0
var vote_caller: int = -1
var voted_set: Dictionary[int, bool] = {}
var my_vote: int = -1
## From the private state.
var role: String = ""
var word: String = ""
var category: String = ""
var hint: String = ""
var me_in: bool = false
var my_turn: bool = false
var can_call: bool = false
var can_vote: bool = false
var hint_given: bool = false
var hint_after: float = SpyLogic.HINT_AFTER
## The last vote's result (shown at the reveal) and the end info.
var result: Dictionary = {}
var over: bool = false
var end: Dictionary = {}
## player → [stamp text, colour].
var stamps: Dictionary[int, Array] = {}
var message: String = ""
var _message_left: float = 0.0
var _reveal_tween: Tween = null
var _reveal_paid: bool = true
var _vote_sent_at: float = -1.0
var _clue_sent: bool = false
var _clock: float = 0.0
var _secret_key: String = ""
## How intents leave (tests swap it).
var send_intent: Callable = func(i: Dictionary) -> Dictionary: return Net.send_intent(i)


func _build(start: Dictionary) -> void:
	_set_seats(start.get("players", []))
	alive = seats.duplicate()
	clock_total = SpyLogic.SECONDS_PER_PLAYER * float(seats.size())
	clock_left = clock_total
	spy_count = SpyLogic.spy_count_for(seats.size())
	var hold: Variant = start.get("briefing", 0.0)
	held = (hold is Dictionary) or float(hold) > 0.0
	_build_ui()
	_rebuild_cards()
	if state != null and str(state.minigame.get("minigame", "")) == "spy" and state.minigame.has("seats"):
		apply_state(state.minigame)
	_refresh()


func _set_seats(list: Array) -> void:
	var fresh: Array[int] = []
	for p: Variant in list:
		fresh.append(int(p))
	seats = fresh
	for p: int in seats:
		if not clues.has(p):
			clues[p] = []


# --- UI ------------------------------------------------------------------------------------------

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	set_bg = VoteRaceSet.new()
	set_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(set_bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 14)
	margin.add_child(col)

	# Top: the clock, the marquee and your secret card.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 22)
	col.add_child(top)
	clock = SpyClock.new()
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(clock)
	marquee = VoteRaceMarquee.new()
	marquee.custom_minimum_size = Vector2(0, 0)
	marquee.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(marquee)
	secret_card = SpySecretCard.new()
	top.add_child(secret_card)

	# The action strip: whose turn, the timer, your clue entry, CALL A VOTE.
	var strip := PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.72)
	sb.border_color = Color(Palette.WARM_GOLD, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 20
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	strip.add_theme_stylebox_override(&"panel", sb)
	strip.custom_minimum_size = Vector2(0, 74)
	col.add_child(strip)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 16)
	strip.add_child(row)
	action_label = _label("", BLACK_FONT, 34, Palette.CREAM)
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	action_label.custom_minimum_size = Vector2(560, 0)
	action_label.clip_text = true
	action_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(action_label)
	action_bar = _bar(Vector2(200, 18))
	action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(action_bar)
	action_time = _label("", BLACK_FONT, 38, Palette.CREAM)
	action_time.custom_minimum_size = Vector2(56, 0)
	row.add_child(action_time)
	entry = LineEdit.new()
	entry.max_length = SpyLogic.CLUE_MAX
	entry.placeholder_text = "one clue word…"
	entry.custom_minimum_size = Vector2(330, 56)
	entry.add_theme_font_override(&"font", BLACK_FONT)
	entry.add_theme_font_size_override(&"font_size", 34)
	entry.add_theme_color_override(&"font_color", SpyCard.CARD_DARK)
	entry.add_theme_color_override(&"font_placeholder_color", Color(SpyCard.CARD_DARK, 0.4))
	entry.add_theme_color_override(&"caret_color", Palette.VIP_BURGUNDY)
	var eb := StyleBoxFlat.new()
	eb.bg_color = Palette.CREAM
	eb.border_color = Palette.VIP_GOLD
	eb.set_border_width_all(4)
	eb.set_corner_radius_all(10)
	eb.content_margin_left = 14
	eb.content_margin_right = 14
	for st: String in ["normal", "focus", "read_only"]:
		entry.add_theme_stylebox_override(st, eb)
	entry.text_submitted.connect(func(_t: String) -> void: send_clue())
	entry.visible = false
	row.add_child(entry)
	say_button = _button("SAY IT  ⏎", Palette.FELT_GREEN)
	say_button.pressed.connect(send_clue)
	say_button.visible = false
	row.add_child(say_button)
	vote_button = _button("CALL A VOTE  [V]", Palette.VIP_BURGUNDY)
	vote_button.pressed.connect(call_vote)
	row.add_child(vote_button)

	cards_row = HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_row.add_theme_constant_override(&"separation", int(CARD_GAP))
	cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_row.resized.connect(_size_cards)
	col.add_child(cards_row)

	status_label = _label("", BOLD_FONT, 32, Palette.CREAM)
	status_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	status_label.add_theme_constant_override(&"shadow_offset_y", 3)
	col.add_child(status_label)


func _label(text: String, font: Font, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_override(&"font", BLACK_FONT)
	b.add_theme_font_size_override(&"font_size", 30)
	for st: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, Palette.CREAM)
	b.add_theme_color_override(&"font_disabled_color", Color(Palette.CREAM, 0.4))
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.border_color = Palette.WARM_GOLD
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
		match st:
			"hover":
				sb.bg_color = color.lightened(0.15)
				sb.border_color = Palette.VIP_GOLD
			"pressed":
				sb.bg_color = color.darkened(0.15)
			"disabled":
				sb.bg_color = color.darkened(0.45)
				sb.border_color = Color(Palette.WARM_GOLD, 0.35)
			"focus":
				sb.draw_center = false
				sb.set_border_width_all(0)
				sb.shadow_size = 0
		b.add_theme_stylebox_override(st, sb)
	return b


func _bar(min_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = min_size
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(Palette.CASINO_BLACK, 0.8)
	back.border_color = Color(Palette.WARM_GOLD, 0.6)
	back.set_border_width_all(2)
	back.set_corner_radius_all(int(min_size.y / 2.0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.WARM_GOLD
	fill.set_corner_radius_all(int(min_size.y / 2.0))
	bar.add_theme_stylebox_override(&"background", back)
	bar.add_theme_stylebox_override(&"fill", fill)
	return bar


func _name(p: int) -> String:
	if state != null:
		return state.player_name(p)
	return "Player %d" % p


func _color(p: int) -> Color:
	var idx: int = p
	if state != null and state.players.has(p):
		idx = int(state.players[p].get("color", p))
	return Palette.player_color(idx)


func _rebuild_cards() -> void:
	for c: SpyCard in cards.values():
		c.queue_free()
	cards.clear()
	for p: int in seats:
		var card := SpyCard.new()
		card.name = "Card%d" % p
		card.size_flags_horizontal = Control.SIZE_FILL
		card.setup(p, _name(p), _color(p))
		card.pressed.connect(_on_card_pressed.bind(p))
		card.chip_landed.connect(_on_chip_landed)
		cards_row.add_child(card)
		cards[p] = card
	_size_cards()


func _size_cards() -> void:
	var n: int = maxi(cards.size(), 1)
	var avail: float = cards_row.size.x if cards_row.size.x > 0.0 else 1824.0
	var w: float = clampf((avail - CARD_GAP * float(n - 1)) / float(n), CARD_MIN_W, CARD_MAX_W)
	for c: SpyCard in cards.values():
		c.custom_minimum_size = Vector2(w, 0)
	_update_spots.call_deferred()


## Who the local player can vote for, in card order (the number keys follow it).
func vote_targets() -> Array[int]:
	var out: Array[int] = []
	for p: int in seats:
		if p != local_id and p in alive:
			out.append(p)
	return out


func can_vote_now() -> bool:
	return phase == "vote" and not held and not over and can_vote and my_vote < 0 and local_id in alive


func can_call_now() -> bool:
	return phase in ["clues", "open"] and not held and not over and can_call


func _refresh() -> void:
	var voting: bool = can_vote_now()
	var targets: Array[int] = vote_targets()
	for p: int in cards:
		var card: SpyCard = cards[p]
		var texts: Array[String] = []
		for t: Variant in clues.get(p, []):
			texts.append(str(t))
		card.clue_texts = texts
		card.is_self = p == local_id
		card.speaking = phase == "clues" and speaker == p and not held
		card.turn_frac = clampf(turn_left / maxf(turn_span, 0.01), 0.0, 1.0)
		card.votable = voting and p in targets
		card.key_hint = str(targets.find(p) + 1) if p in targets and targets.find(p) < 9 else ""
		card.is_my_vote = my_vote == p and phase in ["vote", "reveal"]
		card.has_voted = phase == "vote" and voted_set.has(p)
		card.is_out = p in caught
		card.tag_override = _tag_for(p)
		var stp: Array = stamps.get(p, [])
		card.stamp_text = str(stp[0]) if stp.size() == 2 else ""
		card.stamp_color = stp[1] if stp.size() == 2 else Palette.FELT_GREEN
		card.refresh()
	_update_secret()
	_update_marquee()
	_update_strip()
	_update_status()
	_update_clock()
	_update_spots.call_deferred()


func _tag_for(p: int) -> String:
	if over:
		for row: Variant in end.get("ranking", []):
			var r: Dictionary = row
			if int(r.get("player", -1)) == p:
				var pts: int = int(r.get("points", 0))
				return "#%d  ·  %d PT%s" % [int(r.get("rank", 0)), pts, "" if pts == 1 else "S"]
		return ""
	if p in caught:
		return "CAUGHT"
	if vote_caller == p and phase == "vote":
		return "CALLED THE VOTE" if p != local_id else "YOU CALLED IT"
	return ""


func _update_secret() -> void:
	var hint_in: float = maxf(hint_after - (clock_total - clock_left), 0.0) if not hint_given else -1.0
	var key: String = "%s|%s|%s|%s|%d|%s" % [role, word, category, hint, ceili(hint_in), str(over)]
	if key == _secret_key:
		return
	_secret_key = key
	match role:
		"civilian":
			secret_card.show_civilian(word, category)
		"spy":
			secret_card.show_spy(category, hint, hint_in if phase != "intro" else hint_after)
		_:
			secret_card.show_watching()
	if over:
		secret_card.reveal_word(str(end.get("word", "")), str(end.get("category", "")))


func _update_marquee() -> void:
	var spies_txt: String = "1 SPY AT THE TABLE" if spy_count == 1 else "%d SPIES AT THE TABLE" % spy_count
	if over:
		var spies_won: bool = str(end.get("winner", "")) == SpyLogic.SIDE_SPIES
		var head: String = ("THE SPY WINS!" if _spy_list().size() == 1 else "THE SPIES WIN!") if spies_won else "THE GROUP WINS!"
		marquee.set_texts("THE WORD WAS:  %s  ·  %s" % [str(end.get("word", "")).to_upper(), str(end.get("category", "")).to_upper()], head, _end_reason())
		return
	match phase:
		"vote":
			marquee.set_texts("VOTE CALLED BY %s" % _name(vote_caller).to_upper() if vote_caller >= 0 else "VOTE!",
				"WHO IS THE SPY?", "Out with %d votes or more  ·  a tie sends nobody out" % vote_needed)
		"reveal":
			if not _reveal_paid:
				marquee.set_texts("THE VOTE", "THE VOTES ARE IN…", "Who voted for whom")
			else:
				var out: int = int(result.get("out", -1))
				if out >= 0:
					var spy: bool = bool(result.get("was_spy", false))
					marquee.set_texts("THE VOTE", "OUT: %s" % _name(out).to_upper(),
						("was THE SPY!" + (" One more spy is hiding…" if int(result.get("spies_left", 0)) > 0 else "")) if spy else "was a civilian - an innocent!")
				else:
					var why: String = str(result.get("why", "tie"))
					var sub: String = "A tie - nobody is out." if why == "tie" else ("Nobody voted." if why == "none" else "Not enough votes - %d needed." % int(result.get("needed", 0)))
					marquee.set_texts("THE VOTE", "NOBODY IS OUT", sub)
		"open":
			marquee.set_texts("SPY  ·  ALL CLUES ARE IN  ·  " + spies_txt, "WHO IS THE SPY?", "Talk it out on voice, then CALL A VOTE")
		_:
			marquee.set_texts("SPY  ·  CLUE ROUND %d OF %d  ·  %s" % [round_num + 1, maxi(rounds, round_num + 1), spies_txt], "WHO IS THE SPY?",
				"One clue word each - prove you know the word without giving it away")


func _end_reason() -> String:
	match str(end.get("reason", "")):
		"wrong_vote":
			var out: int = int(result.get("out", -1))
			return "%s was voted out - an innocent!" % _name(out) if out >= 0 else "An innocent was voted out!"
		"caught":
			return "Every spy was caught!" if spy_count > 1 else "The spy was caught: %s!" % _spy_names()
		"clock":
			return "The clock ran out - %s survived!" % _spy_names(true)
		"spies_left":
			return "The spy left the table - caught!"
		"group_left":
			return "Nobody is left to find the spy."
	return ""


func _spy_list() -> Array[int]:
	var out: Array[int] = []
	for p: Variant in end.get("spies", []):
		out.append(int(p))
	return out


## The spies' names (`free_only`: the ones never caught).
func _spy_names(free_only: bool = false) -> String:
	var names: Array[String] = []
	for p: int in _spy_list():
		if not (free_only and p in caught):
			names.append(_name(p))
	return " & ".join(names) if not names.is_empty() else "the spy"


func _won(p: int) -> bool:
	for row: Variant in end.get("ranking", []):
		if int((row as Dictionary).get("player", -1)) == p:
			return bool((row as Dictionary).get("won", false))
	return false


func _update_strip() -> void:
	var text: String = ""
	var frac: float = -1.0
	var secs: float = -1.0
	var show_entry: bool = false
	if over:
		text = "THE GAME IS OVER"
	elif held:
		text = "GET READY - THE PANEL STARTS WHEN EVERYONE IS READY"
	else:
		match phase:
			"intro":
				text = "LUCKY DEALS THE SECRET CARDS…"
			"clues":
				if speaker == local_id and my_turn:
					text = "YOUR TURN - ONE CLUE WORD:"
					show_entry = not _clue_sent
				elif speaker >= 0:
					text = "%s IS GIVING A CLUE…" % _name(speaker).to_upper()
				frac = turn_left / maxf(turn_span, 0.01)
				secs = turn_left
			"open":
				text = "ALL CLUES ARE IN - TALK IT OUT!"
			"vote":
				text = "VOTE!  %d/%d VOTED" % [voted_set.size(), alive.size()]
				frac = vote_left / maxf(vote_span, 0.01)
				secs = vote_left
			"reveal":
				text = "THE VOTES ARE IN…" if not _reveal_paid else "THE VERDICT"
	action_label.text = text
	action_bar.visible = frac >= 0.0 and not show_entry
	action_time.visible = secs >= 0.0
	if frac >= 0.0:
		action_bar.value = clampf(frac, 0.0, 1.0)
		(action_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = Palette.CASINO_RED if secs <= 3.0 else Palette.WARM_GOLD
	if secs >= 0.0:
		action_time.text = "%d" % ceili(secs)
	if show_entry != entry.visible:
		entry.visible = show_entry
		say_button.visible = show_entry
		if show_entry:
			entry.clear()
			if entry.is_inside_tree():
				entry.grab_focus()
		elif entry.has_focus():
			entry.release_focus()
	vote_button.visible = not over and phase in ["clues", "open", "intro"] and me_in
	vote_button.disabled = not can_call_now()


func _update_status() -> void:
	if message != "":
		status_label.text = message
		status_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		return
	status_label.add_theme_color_override(&"font_color", Palette.CREAM)
	var text: String = ""
	if over:
		text = "You win!" if _won(local_id) else ("Better luck next time." if local_id in seats else "")
	elif not me_in and role != "":
		text = "You were caught - watch the rest play it out." if role == "spy" else "Watch the panel."
	elif phase == "vote":
		if can_vote_now():
			text = "Click a card or press 1-%d: who is the spy?" % vote_targets().size()
		elif my_vote >= 0:
			text = "You voted for %s - waiting for the others" % _name(my_vote)
	elif phase in ["clues", "open"]:
		if role == "spy":
			text = "Blend in: give a clue that fits %s - and find out the word." % category if category != "" else "Blend in."
		elif role == "civilian":
			text = "Spot the one who doesn't know the word. Press V to call a vote."
	status_label.text = text


func _update_clock() -> void:
	var counting: bool = phase in ["clues", "open", "vote"] and not held and not over
	clock.set_time(clock_left, clock_total, not counting)


func _update_spots() -> void:
	if set_bg == null:
		return
	var lit: Array[int] = []
	if over:
		for row: Variant in end.get("ranking", []):
			if bool((row as Dictionary).get("won", false)):
				lit.append(int((row as Dictionary).get("player", -1)))
	elif phase == "reveal" and _reveal_paid and int(result.get("out", -1)) >= 0:
		lit.append(int(result["out"]))
	elif phase == "clues" and speaker >= 0:
		lit.append(speaker)
	var rects: Array[Rect2] = []
	for p: int in lit:
		var card: SpyCard = cards.get(p, null)
		if card != null and card.is_inside_tree():
			rects.append(Rect2(card.global_position - set_bg.global_position, card.size))
	set_bg.set_spots(rects)
	for p: int in cards:
		var on: bool = p in lit
		if cards[p].spotlit != on:
			cards[p].spotlit = on
			cards[p].refresh()


static func _ints(list: Variant) -> Array[int]:
	var out: Array[int] = []
	if list is Array:
		for v: Variant in list:
			out.append(int(v))
	return out


func say(text: String) -> void:
	message = text
	_message_left = MESSAGE_TIME
	_update_status()


# --- Input ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			message = ""
			_update_status()
	if held or over:
		return
	if phase in ["clues", "open", "vote"]:
		clock_left = maxf(clock_left - delta, 0.0)
		_update_clock()
	if phase == "clues" and turn_left > 0.0:
		turn_left = maxf(turn_left - delta, 0.0)
		var card: SpyCard = cards.get(speaker, null)
		if card != null:
			card.set_turn(turn_left / maxf(turn_span, 0.01))
		_update_strip()
	elif phase == "vote" and vote_left > 0.0:
		vote_left = maxf(vote_left - delta, 0.0)
		_update_strip()
	if role == "spy" and not hint_given:
		_update_secret()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if entry != null and entry.has_focus():
		return
	if key.keycode == KEY_V and can_call_now():
		call_vote()
		get_viewport().set_input_as_handled()
		return
	if not can_vote_now():
		return
	var n: int = -1
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		n = key.keycode - KEY_1
	elif key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_9:
		n = key.keycode - KEY_KP_1
	var targets: Array[int] = vote_targets()
	if n >= 0 and n < targets.size():
		_on_card_pressed(targets[n])
		get_viewport().set_input_as_handled()


## Sends the typed clue (Enter or SAY IT).
func send_clue() -> void:
	if not my_turn or phase != "clues" or _clue_sent:
		return
	var text: String = SpyLogic.sanitize_clue(entry.text)
	if text == "":
		say(REJECT_TEXT[&"empty_clue"])
		return
	if role == "civilian" and SpyLogic.mentions_word(text, word):
		say(REJECT_TEXT[&"is_the_word"])
		return
	var res: Dictionary = send_intent.call(Intents.make(&"spy_clue", {"text": text}))
	if not bool(res.get("ok", false)) and not bool(res.get("pending", false)):
		say(REJECT_TEXT.get(StringName(res.get("error", &"")), "That clue didn't go through."))
		return
	_clue_sent = true
	Audio.play(&"chip_clack", &"UI", -4.0)
	_update_strip()


func call_vote() -> void:
	if not can_call_now():
		return
	var res: Dictionary = send_intent.call(Intents.make(&"spy_call_vote", {}))
	if not bool(res.get("ok", false)) and not bool(res.get("pending", false)):
		say(REJECT_TEXT.get(StringName(res.get("error", &"")), "You can't call a vote right now."))
		return
	can_call = false
	Audio.play(&"chip_clack", &"UI", -2.0)
	_refresh()


func _on_card_pressed(target: int) -> void:
	if not can_vote_now() or target == local_id or not target in alive:
		return
	my_vote = target
	_vote_sent_at = _clock
	var res: Dictionary = send_intent.call(Intents.make(&"spy_vote", {"target": target}))
	if not bool(res.get("ok", false)) and not bool(res.get("pending", false)):
		my_vote = -1
		_vote_sent_at = -1.0
		say(REJECT_TEXT.get(StringName(res.get("error", &"")), "That vote didn't count."))
	else:
		Audio.play(&"chip_clack", &"UI", -4.0)
		var card: SpyCard = cards.get(target, null)
		if card != null:
			card.is_my_vote = true
			card.pop(0.06)
	_refresh()


## Called every frame with the local private snapshot.
func on_private(priv: Dictionary) -> void:
	var mg: Dictionary = priv.get("minigame", priv)
	var changed: bool = false
	var r: String = str(mg.get("role", ""))
	var w: String = str(mg.get("word", ""))
	var c: String = str(mg.get("category", ""))
	var h: String = str(mg.get("hint", ""))
	if r != role or w != word or c != category or h != hint:
		role = r
		word = w
		category = c
		hint = h
		if h != "":
			hint_given = true
		changed = true
	var mi: bool = bool(mg.get("in", false))
	var mt: bool = bool(mg.get("my_turn", false))
	var cc: bool = bool(mg.get("can_call", false))
	var cv: bool = bool(mg.get("can_vote", false))
	if mi != me_in or mt != my_turn or cc != can_call or cv != can_vote:
		me_in = mi
		if mt != my_turn and not mt:
			_clue_sent = false
		my_turn = mt
		can_call = cc
		can_vote = cv
		changed = true
	var vf: int = int(mg.get("voted_for", -1))
	if vf >= 0 and vf != my_vote:
		my_vote = vf
		changed = true
	elif vf < 0 and my_vote >= 0 and cv and phase == "vote" and _vote_sent_at >= 0.0 and _clock - _vote_sent_at > VOTE_CONFIRM_TIMEOUT:
		my_vote = -1
		_vote_sent_at = -1.0
		changed = true
	if changed:
		_refresh()


# --- Server data ---------------------------------------------------------------------------------

## Late join / resync from the public snapshot.
func apply_state(st: Dictionary) -> void:
	if st.has("seats"):
		var before: Array[int] = seats.duplicate()
		_set_seats(st["seats"])
		if before != seats:
			_rebuild_cards()
	alive = _ints(st.get("alive", alive))
	caught = _ints(st.get("caught", caught))
	spy_count = int(st.get("spy_count", spy_count))
	clock_left = float(st.get("clock", clock_left))
	clock_total = float(st.get("clock_total", clock_total))
	round_num = int(st.get("round", round_num))
	rounds = int(st.get("rounds", rounds))
	hint_given = bool(st.get("hint_given", hint_given))
	var cl: Dictionary = st.get("clues", {})
	for k: Variant in cl:
		var list: Array = []
		for t: Variant in cl[k]:
			list.append(str(t))
		clues[int(k)] = list
	phase = String(st.get("phase", phase))
	speaker = int(st.get("speaker", -1))
	var t_left: float = float(st.get("timer", 0.0))
	turn_span = float(st.get("clue_time", turn_span))
	vote_span = float(st.get("vote_time", vote_span))
	if phase == "clues":
		turn_left = t_left
	voted_set.clear()
	if phase == "vote":
		vote_left = t_left
		var v: Dictionary = st.get("vote", {})
		vote_caller = int(v.get("by", -1))
		vote_needed = int(v.get("needed", 0))
		for p: int in _ints(v.get("voted", [])):
			voted_set[p] = true
	if st.has("briefing"):
		held = true
	for p: int in caught:
		stamps[p] = ["CAUGHT · SPY", Palette.FELT_GREEN]
	if phase == "over":
		_clear_reveal()
		result = st.get("result", {})
		_show_end(st, false)
		return
	if phase == "reveal" and st.has("result"):
		_show_reveal(st["result"], true)
	else:
		_clear_reveal()
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"minigame_go":
			held = false
			_refresh()
		&"spy_started":
			var before: Array[int] = seats.duplicate()
			_set_seats(ev.get("seats", ev.get("players", [])))
			alive = seats.duplicate()
			spy_count = int(ev.get("spy_count", spy_count))
			clock_total = float(ev.get("clock", clock_total))
			clock_left = clock_total
			turn_span = float(ev.get("clue_time", turn_span))
			vote_span = float(ev.get("vote_time", vote_span))
			hint_after = float(ev.get("hint_after", hint_after))
			if before != seats:
				_rebuild_cards()
			_refresh()
		&"spy_round":
			round_num = int(ev.get("round", 0))
			rounds = int(ev.get("rounds", rounds))
			_refresh()
		&"spy_turn":
			_end_reveal()
			phase = "clues"
			speaker = int(ev.get("player", -1))
			round_num = int(ev.get("round", round_num))
			turn_left = float(ev.get("seconds", turn_span))
			turn_span = turn_left
			clock_left = float(ev.get("clock", clock_left))
			_clue_sent = false
			_refresh()
			if speaker == local_id:
				Audio.play(&"coin", &"UI", -8.0)
		&"spy_clue":
			var p: int = int(ev.get("player", -1))
			if not clues.has(p):
				clues[p] = []
			clues[p].append(str(ev.get("text", "")))
			if speaker == p:
				speaker = -1
			if p == local_id:
				_clue_sent = false
			var card: SpyCard = cards.get(p, null)
			_refresh()
			if card != null and str(ev.get("text", "")) != "":
				card.pop(0.05)
				Audio.play(&"chip_clack", &"UI", -12.0)
		&"spy_open":
			_end_reveal()
			phase = "open"
			speaker = -1
			clock_left = float(ev.get("clock", clock_left))
			_refresh()
		&"spy_hint":
			hint_given = true
			if role == "spy":
				say("Your hint just arrived - check your card!")
			_refresh()
		&"spy_vote_called":
			_end_reveal()
			phase = "vote"
			vote_caller = int(ev.get("by", -1))
			vote_left = float(ev.get("seconds", vote_span))
			vote_span = vote_left
			vote_needed = int(ev.get("needed", 0))
			alive = _ints(ev.get("alive", alive))
			clock_left = float(ev.get("clock", clock_left))
			voted_set.clear()
			my_vote = -1
			_vote_sent_at = -1.0
			if entry.has_focus():
				entry.release_focus()
			Audio.play(&"buzzer", &"UI", -8.0)
			_refresh()
		&"spy_voted":
			voted_set[int(ev.get("player", -1))] = true
			_refresh()
		&"spy_vote_result":
			phase = "reveal"
			_show_reveal(ev, false)
			_refresh()
		&"spy_over":
			_end_reveal()
			_show_end(ev, true)
		&"intent_rejected":
			if int(ev.get("player", -1)) != local_id:
				return
			var it: StringName = StringName(str(ev.get("intent", "")))
			if not it in [&"spy_clue", &"spy_call_vote", &"spy_vote"]:
				return
			if it == &"spy_vote":
				my_vote = -1
				_vote_sent_at = -1.0
			elif it == &"spy_clue":
				_clue_sent = false
			say(REJECT_TEXT.get(StringName(ev.get("error", &"")), "That didn't go through."))
			_refresh()


# --- Reveal --------------------------------------------------------------------------------------

func _clear_reveal() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	_reveal_paid = true
	for c: SpyCard in cards.values():
		c.clear_chips()
		c.scale = Vector2.ONE


## The reveal is over (the next turn, the floor, the end): chips off, the verdict stays.
func _end_reveal() -> void:
	_finish_reveal()
	_clear_reveal()


## Who voted for whom: each voter's chip flies from their card to the card they picked; once all
## landed the verdict (`_reveal_payoff`). `instant` (late join) puts everything in place at once.
func _show_reveal(rev: Dictionary, instant: bool) -> void:
	_clear_reveal()
	result = rev.duplicate(true)
	_reveal_paid = false
	var cast: Dictionary = {}  # voter → target, int keys whatever the wire made of them
	var raw: Dictionary = rev.get("votes", {})
	for k: Variant in raw:
		cast[int(k)] = int(raw[k])
	var voters: Array[int] = []
	for p: int in seats:
		if cast.has(p):
			voters.append(p)
	var i: int = 0
	for voter: int in voters:
		var target_id: int = int(cast[voter])
		var target: SpyCard = cards.get(target_id, null)
		if target == null:
			continue
		var from_card: SpyCard = cards.get(voter, null)
		var from: Vector2 = from_card.global_position + Vector2(from_card.size.x * 0.5, 70.0) if from_card != null else marquee.global_position + marquee.size * 0.5
		target.add_chip("YOU" if voter == local_id else _name(voter), _color(voter), voter == local_id, from, CHIP_STAGGER * float(i), instant)
		i += 1
	if instant:
		_reveal_payoff(false)
		return
	_reveal_tween = create_tween()
	_reveal_tween.tween_interval(CHIP_STAGGER * float(maxi(i - 1, 0)) + SpyCard.FLIGHT_TIME + 0.35)
	_reveal_tween.tween_callback(_reveal_payoff.bind(true))


func _on_chip_landed(card: SpyCard) -> void:
	card.refresh()
	Audio.play(&"chip_clack", &"UI", -14.0, randf_range(0.9, 1.15))


func _finish_reveal() -> void:
	if result.is_empty() or _reveal_paid:
		return
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_payoff(false)


## Skips the chip show (tests, the dev shot): every chip lands and the verdict shows now.
func skip_reveal() -> void:
	_finish_reveal()


func _reveal_payoff(animate: bool) -> void:
	_reveal_paid = true
	for c: SpyCard in cards.values():
		c.land_all()
	var out: int = int(result.get("out", -1))
	if out >= 0:
		if bool(result.get("was_spy", false)):
			if not out in caught:
				caught.append(out)
			stamps[out] = ["OUT · THE SPY", Palette.FELT_GREEN]
		else:
			stamps[out] = ["OUT · INNOCENT", Palette.CASINO_RED.darkened(0.15)]
		alive.erase(out)
	_refresh()
	if not animate:
		return
	var card: SpyCard = cards.get(out, null)
	if card != null:
		card.pop(0.14)
	if out >= 0 and bool(result.get("was_spy", false)):
		Audio.play(&"minor_win", &"UI", -6.0)
	elif out >= 0:
		Audio.play(&"buzzer", &"UI", -6.0)
	else:
		Audio.play(&"coin", &"UI", -10.0)


## The end screen: the word on the marquee and the secret card, every spy stamped, the winning
## side under the spotlights with their rank on the tag line.
func _show_end(info: Dictionary, animate: bool) -> void:
	over = true
	phase = "over"
	speaker = -1
	end = info.duplicate(true)
	caught = _ints(info.get("caught", caught))
	for p: int in _spy_list():
		stamps[p] = ["THE SPY", Palette.VIP_BURGUNDY]
	var out: int = int(result.get("out", -1))
	if out >= 0 and not out in _spy_list():
		stamps[out] = ["INNOCENT", Palette.CASINO_RED.darkened(0.15)]
	if entry.has_focus():
		entry.release_focus()
	_refresh()
	if not animate:
		return
	for p: int in cards:
		if _won(p):
			cards[p].pop(0.1)
	if _won(local_id):
		Audio.play(&"big_win", &"UI", -4.0)
