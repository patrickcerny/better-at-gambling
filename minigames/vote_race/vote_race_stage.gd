class_name VoteRaceStage
extends MinigameStage
## Client presentation for Vote Race as a lit game-show set: a bulb marquee with the question, a
## cream candidate card per racer (their steps as pips; the leader under a warm spotlight), a
## countdown bar, and under them the race itself in 3D (`VoteRaceTrack`): a red-carpet runway
## with a lane per racer, a puppet bean per player on their step and the CASHIER window at step 5.
## You vote by clicking a card or pressing its number; the card you picked gets a check badge.
## While a round is voting only THAT someone voted shows ("VOTED" badges); who voted for whom
## appears at the server's reveal (`vote_race_reveal`): every voter's name chip in their colour
## flies from their own card onto the card they picked (0.1 s apart, yours ringed in gold) while
## an arc of beads runs between their beans on the track and the camera pushes in; then the
## zero-vote cards pop and their beans hop a plate forward.
##
## The stage is built behind the minigame curtain, after the server already sent
## `vote_race_started` / the first `vote_race_round`, so it starts in round 1's vote on its own
## (and catches up from the last snapshot when there is one); a rules briefing holds the clock
## until `minigame_go`.

const TRACK_LENGTH: int = VoteRaceLogic.TRACK_LENGTH
const CHIP_STAGGER: float = 0.1
## A vote the server never confirmed (rejected on the way) is given back after this long.
const VOTE_CONFIRM_TIMEOUT: float = 1.5
const CARD_MIN_W: float = 170.0
const CARD_MAX_W: float = 290.0
const CARD_GAP: float = 22.0
const CARD_H: float = 300.0

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")

var root: Control
var set_bg: VoteRaceSet
var marquee: VoteRaceMarquee
var round_label: Label
var timer_label: Label
var voted_label: Label
var countdown_bar: ProgressBar
var cards_row: HBoxContainer
var track: VoteRaceTrack
var status_label: Label

var players_list: Array[int] = []
var racing: Array[int] = []
var positions: Dictionary[int, int] = {}
## Steps shown on the cards and the track: they catch up with `positions` at the reveal's payoff.
var display_steps: Dictionary[int, int] = {}
var finish_place: Dictionary[int, int] = {}  # player → finishing place
## player → their candidate card (everyone at the table, finished ones dimmed).
var cards: Dictionary[int, VoteRaceCard] = {}
var round_num: int = 0
var voted_count: int = 0
var voted_this_round: Dictionary[int, bool] = {}
var time_left: float = VoteRaceLogic.VOTE_TIME
var time_span: float = VoteRaceLogic.VOTE_TIME
var voting: bool = false
## The rules briefing is still up: the server isn't counting down yet.
var held: bool = false
var over: bool = false
var my_vote: int = -1
var can_vote: bool = false
var ranking: Array = []
## The reveal being shown (its payoff runs once the chips have landed).
var reveal: Dictionary = {}
var _reveal_tween: Tween = null
var _reveal_paid: bool = true
var _vote_sent_at: float = -1.0
var _clock: float = 0.0
var _track_key: String = ""
## How intents leave (tests swap it).
var send_intent: Callable = func(i: Dictionary) -> Dictionary: return Net.send_intent(i)


func _build(start: Dictionary) -> void:
	_set_players(start.get("players", []))
	# The opening events went out with `minigame_started`, while the curtain was still closing
	# and this stage didn't exist yet: start in round 1's vote with everyone racing.
	racing = players_list.duplicate()
	voting = true
	var hold: Variant = start.get("briefing", 0.0)
	held = (hold is Dictionary) or float(hold) > 0.0
	track = VoteRaceTrack.new()
	track.name = "Track"
	track.track_length = TRACK_LENGTH
	track.local_id = local_id
	add_child(track)
	camera = track.camera
	_build_ui()
	_rebuild_cards()
	if state != null and state.minigame.has("racing") and state.minigame.has("track"):
		apply_state(state.minigame)  # a snapshot already reached us: use it
	_refresh()


func _set_players(list: Array) -> void:
	var fresh: Array[int] = []
	for p: Variant in list:
		fresh.append(int(p))
	fresh.sort()
	players_list = fresh
	for p: int in players_list:
		if not positions.has(p):
			positions[p] = 0
		if not display_steps.has(p):
			display_steps[p] = positions[p]


# --- UI ----------------------------------------------------------------------------------------

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
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 18)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 14)
	margin.add_child(col)

	marquee = VoteRaceMarquee.new()
	col.add_child(marquee)

	# Countdown: round, a gold bar, seconds and how many have voted.
	var clock := HBoxContainer.new()
	clock.alignment = BoxContainer.ALIGNMENT_CENTER
	clock.add_theme_constant_override(&"separation", 22)
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(clock)
	round_label = _label("ROUND 1", BOLD_FONT, 30, Palette.WARM_GOLD)
	round_label.custom_minimum_size = Vector2(150, 0)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.add_child(round_label)
	countdown_bar = _bar(Vector2(820, 20))
	countdown_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock.add_child(countdown_bar)
	timer_label = _label("", BLACK_FONT, 40, Palette.CREAM)
	timer_label.custom_minimum_size = Vector2(80, 0)
	clock.add_child(timer_label)
	voted_label = _label("", BOLD_FONT, 28, Color(Palette.CREAM, 0.8))
	voted_label.custom_minimum_size = Vector2(170, 0)
	voted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	clock.add_child(voted_label)

	cards_row = HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.custom_minimum_size = Vector2(0, CARD_H)
	cards_row.add_theme_constant_override(&"separation", int(CARD_GAP))
	cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_row.resized.connect(_size_cards)
	col.add_child(cards_row)

	# The 3D runway shows through here.
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

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
	for c: VoteRaceCard in cards.values():
		c.queue_free()
	cards.clear()
	for p: int in players_list:
		var card := VoteRaceCard.new()
		card.name = "Card%d" % p
		card.size_flags_horizontal = Control.SIZE_FILL
		card.setup(p, _name(p), _color(p), TRACK_LENGTH)
		card.is_self = p == local_id
		card.pressed.connect(_on_vote_pressed.bind(p))
		card.chip_landed.connect(_on_chip_landed)
		cards_row.add_child(card)
		cards[p] = card
	_size_cards()
	_sync_track()


## Card width from the room there is: 2 to 8 cards always fit in one row.
func _size_cards() -> void:
	var n: int = maxi(cards.size(), 1)
	var avail: float = cards_row.size.x if cards_row.size.x > 0.0 else 1824.0
	var w: float = clampf((avail - CARD_GAP * float(n - 1)) / float(n), CARD_MIN_W, CARD_MAX_W)
	for c: VoteRaceCard in cards.values():
		c.custom_minimum_size = Vector2(w, CARD_H)
	_update_spots.call_deferred()


## Votable racers in card order (the number keys follow it).
func vote_targets() -> Array[int]:
	var out: Array[int] = []
	for p: int in players_list:
		if p != local_id and p in racing:
			out.append(p)
	return out


func _refresh() -> void:
	var active: bool = can_act()
	var targets: Array[int] = vote_targets()
	for p: int in cards:
		var card: VoteRaceCard = cards[p]
		card.steps = display_steps.get(p, 0)
		card.is_self = p == local_id
		card.is_my_vote = my_vote == p and (voting or not reveal.is_empty())
		card.has_voted = voting and voted_this_round.has(p)
		card.votable = active and p in targets
		card.finished_place = finish_place.get(p, 0) if display_steps.get(p, 0) >= TRACK_LENGTH or over else 0
		card.key_hint = str(targets.find(p) + 1) if p in targets and targets.find(p) < 9 else ""
		card.refresh()
	_sync_track()
	round_label.text = "ROUND %d" % (round_num + 1)
	voted_label.text = "%d/%d VOTED" % [voted_count, racing.size()] if voting else ""
	_update_marquee()
	_update_clock()
	_update_status()
	_update_spots.call_deferred()


func _update_marquee() -> void:
	if over:
		var top: int = _winner()
		var head: String = "YOU WIN!" if top == local_id else ("%s WINS THE RACE!" % _name(top).to_upper() if top >= 0 else "RACE OVER")
		marquee.set_texts("VOTE RACE  ·  THE RESULTS", head, "")
	elif voting:
		marquee.set_texts("VOTE RACE  ·  ROUND %d" % (round_num + 1), "WHO SHOULDN'T MOVE?", "Every racer with ZERO votes steps toward the cashier  ·  first to step %d wins" % TRACK_LENGTH)
	else:
		var moved: Array = reveal.get("moved", [])
		var head: String = "THE VOTES ARE IN!"
		if _reveal_paid:
			head = "EVERYONE GOT A VOTE!" if moved.is_empty() else ("ZERO VOTES: STEP FORWARD!")
		marquee.set_texts("VOTE RACE  ·  ROUND %d REVEAL" % (int(reveal.get("round", round_num)) + 1), head, "Who voted for whom")


func _update_clock() -> void:
	var counting: bool = voting and not over
	countdown_bar.visible = counting
	timer_label.visible = counting
	round_label.visible = counting
	voted_label.visible = counting
	if not counting:
		return
	var frac: float = clampf(time_left / maxf(time_span, 0.01), 0.0, 1.0)
	countdown_bar.value = frac
	var fill: StyleBoxFlat = countdown_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	fill.bg_color = Palette.CASINO_RED if (time_left <= 3.0 and not held) else Palette.WARM_GOLD
	timer_label.text = "%d" % ceili(time_left)


func _update_status() -> void:
	var text: String = ""
	if over:
		var top: int = _winner()
		text = "YOU WIN!" if top == local_id else ("%s wins the race!" % _name(top) if top >= 0 else "The race is over.")
	elif voting:
		if local_id not in racing:
			text = "You made it to the cashier - watch the rest race." if finish_place.has(local_id) else "Watch the race."
		elif held:
			text = "Get ready - the vote opens when everyone is ready."
		elif my_vote >= 0:
			text = ""  # the ✓ on the card you picked says it
		else:
			text = "Click a card or press 1-%d: who should NOT step forward?" % vote_targets().size()
	elif not reveal.is_empty() and _reveal_paid:
		var moved: Array[int] = _ints(reveal.get("moved", []))
		if local_id in _ints(reveal.get("finished", [])) and finish_place.has(local_id):
			text = "You reached the cashier - finished #%d!" % finish_place[local_id]
		elif local_id in moved:
			text = "Nobody voted for you - you step forward!"
		elif local_id in racing:
			text = "You got votes - you stay put."
	elif not reveal.is_empty():
		text = "Who voted for whom…"
	status_label.text = text


## Spotlights: the winner at the end, the racers stepping forward at the reveal, else the leader.
func _update_spots() -> void:
	if set_bg == null:
		return
	var lit: Array[int] = []
	if over:
		for row: Variant in ranking:
			if int((row as Dictionary).get("rank", 0)) == 1:
				lit.append(int((row as Dictionary).get("player", -1)))
	elif not reveal.is_empty() and not voting:
		if _reveal_paid:
			lit = _ints(reveal.get("moved", []))
	else:
		var best: int = 0
		for p: int in racing:
			best = maxi(best, display_steps.get(p, 0))
		if best > 0:
			for p: int in racing:
				if display_steps.get(p, 0) == best:
					lit.append(p)
	var rects: Array[Rect2] = []
	for p: int in lit:
		var card: VoteRaceCard = cards.get(p, null)
		if card != null and card.is_inside_tree():
			rects.append(Rect2(card.global_position - set_bg.global_position, card.size))
	set_bg.set_spots(rects)
	for p: int in cards:
		var lit_now: bool = p in lit
		if cards[p].spotlit != lit_now:
			cards[p].spotlit = lit_now
			cards[p].refresh()


## Lanes for everyone in the race (racing, at the cashier, or all of them once it is over); the
## rest of the table (out of the race, watching) sits on the couch.
func _sync_track() -> void:
	if track == null:
		return
	var lanes: Array[int] = []
	var bench: Array[int] = []
	for p: int in players_list:
		if over or p in racing or finish_place.has(p) or display_steps.get(p, 0) >= TRACK_LENGTH:
			lanes.append(p)
		else:
			bench.append(p)
	if state != null:
		var rest: Array[int] = _ints(state.players.keys())
		rest.sort()
		for p: int in rest:
			if p not in players_list:
				bench.append(p)
	var key: String = "%s|%s|%s" % [lanes, bench, display_steps]
	if key == _track_key:
		return
	_track_key = key
	var info: Dictionary = {}
	for p: int in lanes + bench:
		var skin: String = "bean"
		if state != null and state.players.has(p):
			skin = String(state.players[p].get("skin", "bean"))
		info[p] = {"name": _name(p), "color": _color(p), "skin": skin, "steps": display_steps.get(p, 0)}
	track.set_racers(lanes, bench, info)


func _winner() -> int:
	if ranking.is_empty():
		return -1
	return int((ranking[0] as Dictionary).get("player", -1))


static func _ints(list: Variant) -> Array[int]:
	var out: Array[int] = []
	if list is Array:
		for v: Variant in list:
			out.append(int(v))
	return out


# --- Input -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if voting and not held and time_left > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		_update_clock()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not can_act():
		return
	var n: int = -1
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		n = key.keycode - KEY_1
	elif key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_9:
		n = key.keycode - KEY_KP_1
	var targets: Array[int] = vote_targets()
	if n >= 0 and n < targets.size():
		_on_vote_pressed(targets[n])
		get_viewport().set_input_as_handled()


## True while the local racer may still cast this round's vote.
func can_act() -> bool:
	return voting and not held and not over and can_vote and my_vote < 0 and local_id in racing


func _on_vote_pressed(target: int) -> void:
	if not can_act() or target == local_id or target not in racing:
		return
	my_vote = target
	_vote_sent_at = _clock
	var res: Dictionary = send_intent.call(Intents.make(&"vote_race_vote", {"target": target}))
	if not bool(res.get("ok", false)) and not bool(res.get("pending", false)):
		my_vote = -1  # refused (too early, round over…): the cards stay open
		_vote_sent_at = -1.0
	else:
		Audio.play(&"chip_clack", &"UI", -4.0)
		var card: VoteRaceCard = cards.get(target, null)
		if card != null:
			card.is_my_vote = true
			card.pop(0.06)
	_refresh()


## Called every frame with the local private snapshot.
func on_private(priv: Dictionary) -> void:
	var mg: Dictionary = priv.get("minigame", priv)
	var cv: bool = bool(mg.get("can_vote", false))
	var vf: int = int(mg.get("voted_for", -1))
	var changed: bool = cv != can_vote
	can_vote = cv
	if vf >= 0 and vf != my_vote:
		my_vote = vf  # the server has our vote (also after a resync)
		changed = true
	elif vf < 0 and my_vote >= 0 and cv and voting and _vote_sent_at >= 0.0 and _clock - _vote_sent_at > VOTE_CONFIRM_TIMEOUT:
		my_vote = -1  # the server never took it: vote again
		_vote_sent_at = -1.0
		changed = true
	if changed:
		_refresh()


# --- Server data -------------------------------------------------------------------------------

## Late join / resync: positions, racers, and the last RESOLVED round only.
func apply_state(st: Dictionary) -> void:
	if st.has("players"):
		var before: Array[int] = players_list.duplicate()
		_set_players(st["players"])
		if before != players_list:
			_rebuild_cards()
	for k: Variant in (st.get("positions", {}) as Dictionary):
		positions[int(k)] = int(st["positions"][k])
		display_steps[int(k)] = int(st["positions"][k])
	racing = _ints(st.get("racing", racing))
	finish_place.clear()
	var place: int = 1
	for group: Variant in st.get("finish_order", []):
		for p: Variant in group:
			finish_place[int(p)] = place
		place += (group as Array).size()
	round_num = int(st.get("round", 0))
	var phase: String = String(st.get("phase", "voting"))
	voting = phase == "voting"
	over = phase == "over" or bool(st.get("finished", false))
	time_left = float(st.get("time_left", time_left))
	voted_count = int(st.get("votes_cast", 0))
	voted_this_round.clear()
	if st.has("briefing"):
		held = true
	var rev: Dictionary = st.get("last_reveal", {})
	if phase == "reveal" and not rev.is_empty():
		_show_reveal(rev, true)
	else:
		_clear_reveal()
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"minigame_go":
			if held:
				held = false
				if voting:
					time_left = time_span  # the server's clock starts now
			_refresh()
		&"vote_race_started":
			var before: Array[int] = players_list.duplicate()
			_set_players(ev.get("players", []))
			for k: Variant in (ev.get("positions", {}) as Dictionary):
				positions[int(k)] = int(ev["positions"][k])
				display_steps[int(k)] = positions[int(k)]
			time_span = float(ev.get("vote_time", time_span))
			racing = players_list.duplicate()
			finish_place.clear()
			if before != players_list:
				_rebuild_cards()
			_refresh()
		&"vote_race_round":
			_finish_reveal()
			round_num = int(ev.get("round", 0))
			racing = _ints(ev.get("racing", []))
			for k: Variant in (ev.get("positions", {}) as Dictionary):
				positions[int(k)] = int(ev["positions"][k])
				display_steps[int(k)] = positions[int(k)]
			voting = true
			voted_count = 0
			voted_this_round.clear()
			my_vote = -1
			_vote_sent_at = -1.0
			time_left = float(ev.get("time_left", time_span))
			_clear_reveal()
			_refresh()
		&"vote_race_voted":
			var who: int = int(ev.get("player", -1))
			if not voted_this_round.has(who):
				voted_this_round[who] = true
				voted_count += 1
			_refresh()
		&"vote_race_reveal":
			voting = false
			for k: Variant in (ev.get("positions", {}) as Dictionary):
				positions[int(k)] = int(ev["positions"][k])
			var place: int = finish_place.size() + 1
			for p: Variant in ev.get("finished", []):
				finish_place[int(p)] = place
			racing = _ints(ev.get("racing", []))
			_show_reveal(ev, false)
			_refresh()
		&"vote_race_over":
			_finish_reveal()
			voting = false
			over = true
			ranking = ev.get("ranking", [])
			for k: Variant in (ev.get("positions", {}) as Dictionary):
				positions[int(k)] = int(ev["positions"][k])
				display_steps[int(k)] = positions[int(k)]
			_show_result()


# --- Reveal ------------------------------------------------------------------------------------

func _clear_reveal() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	reveal = {}
	_reveal_paid = true
	if track != null:
		track.clear_votes()
		track.push_in(false)
	for c: VoteRaceCard in cards.values():
		c.clear_chips()
		c.stamp_text = ""
		c.scale = Vector2.ONE


## Who voted for whom: each voter's chip flies from their own card to the card they picked,
## CHIP_STAGGER apart; once all have landed the zero-vote cards pop and step (`_reveal_payoff`).
## `instant` (late join) puts everything in place at once.
func _show_reveal(rev: Dictionary, instant: bool) -> void:
	_clear_reveal()
	reveal = rev.duplicate(true)
	_reveal_paid = false
	var cast: Dictionary = rev.get("votes", {})
	var voters: Array[int] = _ints(cast.keys())
	voters.sort()
	var counts: Dictionary = rev.get("vote_counts", {})
	for k: Variant in counts:
		var card: VoteRaceCard = cards.get(int(k), null)
		if card != null:
			card.show_tally = true
	var i: int = 0
	for voter: int in voters:
		var target: VoteRaceCard = cards.get(int(cast[voter]), null)
		if target == null:
			continue
		var from_card: VoteRaceCard = cards.get(voter, null)
		var from: Vector2 = from_card.global_position + Vector2(from_card.size.x * 0.5, 60.0) if from_card != null else marquee.global_position + marquee.size * 0.5
		var label: String = "YOU" if voter == local_id else _name(voter)
		target.add_chip(label, _color(voter), voter == local_id, from, CHIP_STAGGER * float(i), instant)
		i += 1
	track.show_votes(cast, CHIP_STAGGER, instant)
	if instant:
		_reveal_payoff(false)
		return
	track.push_in(true)
	_reveal_tween = create_tween()
	_reveal_tween.tween_interval(CHIP_STAGGER * float(maxi(i - 1, 0)) + VoteRaceCard.FLIGHT_TIME + 0.2)
	_reveal_tween.tween_callback(_reveal_payoff.bind(true))


func _on_chip_landed(card: VoteRaceCard) -> void:
	card.refresh()
	Audio.play(&"chip_clack", &"UI", -14.0, randf_range(0.9, 1.15))


## Lands whatever is still flying and pays the reveal off now (next round, game over, tests).
func _finish_reveal() -> void:
	if reveal.is_empty() or _reveal_paid:
		return
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_payoff(false)


## Skips the reveal show (tests, impatient callers): every chip lands and the cards step now.
func skip_reveal() -> void:
	_finish_reveal()


## The payoff: the zero-vote cards step forward (pips, track) and pop with a stamp.
func _reveal_payoff(animate: bool) -> void:
	_reveal_paid = true
	for c: VoteRaceCard in cards.values():
		c.land_all()
	var moved: Array[int] = _ints(reveal.get("moved", []))
	var done: Array[int] = _ints(reveal.get("finished", []))
	for p: int in moved:
		display_steps[p] = positions.get(p, display_steps.get(p, 0))
		track.set_step(p, display_steps[p], animate)
		var card: VoteRaceCard = cards.get(p, null)
		if card == null:
			continue
		if p in done:
			card.stamp_text = "CASHIER  #%d" % finish_place.get(p, 0)
			card.stamp_color = Palette.VIP_BURGUNDY
		else:
			card.stamp_text = "+1 STEP"
			card.stamp_color = Palette.FELT_GREEN
	_refresh()
	if animate:
		for p: int in moved:
			var card: VoteRaceCard = cards.get(p, null)
			if card != null:
				card.pop()
		if local_id in moved:
			Audio.play(&"minor_win", &"UI", -6.0)
		elif not moved.is_empty():
			Audio.play(&"coin", &"UI", -10.0)


## The final ranking on the cards: a place stamp on everyone, the winner pops in the spotlight.
## On the track the winner cheers by the cashier and the last two slump.
func _show_result() -> void:
	for row: Variant in ranking:
		var r: Dictionary = row
		var p: int = int(r.get("player", -1))
		var rank: int = int(r.get("rank", 0))
		finish_place[p] = rank
		var card: VoteRaceCard = cards.get(p, null)
		if card == null:
			continue
		card.clear_chips()
		card.stamp_text = "WINNER" if rank == 1 else "#%d" % rank
		card.stamp_color = Palette.WARM_GOLD.darkened(0.35) if rank == 1 else Palette.WARM_CHARCOAL
	_refresh()
	track.land_all()
	track.show_result(ranking)
	var top: VoteRaceCard = cards.get(_winner(), null)
	if top != null:
		top.pop(0.16)
	if _winner() == local_id:
		Audio.play(&"big_win", &"UI", -4.0)
