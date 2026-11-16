class_name SplitOrStealStage
extends MinigameStage
## Client presentation of the Split or Steal tournament (§2.9): a 3D game-show set like the
## quiz's. A burgundy curtain backdrop, two podiums front and centre, Lucky the host between them
## at a lectern, spotlights, and two audience rows at the sides (the local player's seat ringed in
## gold). Everyone plays everyone: every ROUND all duels run at the same time. The podiums show
## OUR duel (us on the left, our opponent on the right; when we sit a round out, the round's first
## duel), everyone else watches from the seats. ROUND (the duels are announced, the two beans hop
## up) → DECIDE (SPLIT / STEAL, keys 1 / 2 or pad A / B; "LOCKED IN" cards show who decided,
## never what) → REVEAL (every duel of the round flips at once, the beans cheer or sulk).
##
## 2D overlay (1920×1080 base): round counter, phase and timer at the top; THIS ROUND top left
## (every duel of the round: who decided, then both picks and the points); standings top right;
## the host's speech bubble; the big SPLIT / STEAL buttons at the bottom for whoever has a duel,
## "You sit this round out" for the one left over with an odd count. Everything comes from events,
## the public snapshot and our private state, which also carries the round being played so a
## stage built after the first events (behind the curtain) still catches up.

const SPLIT: String = SplitOrStealLogic.SPLIT
const STEAL: String = SplitOrStealLogic.STEAL
const NOBODY: int = SplitOrStealLogic.NOBODY
const SPLIT_COLOR: Color = Palette.FELT_GREEN
const STEAL_COLOR: Color = Palette.CASINO_RED
const PANEL_BG: Color = Color(0.09, 0.08, 0.08, 0.88)
const MUTED: Color = Color(0.95, 0.9, 0.79, 0.55)
const WARM_LIGHT: Color = Color("#FFE2B0")
## Podium x positions (left = pair[0], right = pair[1]).
const PODIUM_X: float = 2.5
const PODIUM_Z: float = 0.9
const PODIUM_TOP: float = 1.1
## Audience seats: four per side, starting this far from the middle.
const SEAT_X0: float = 4.7
const SEAT_STEP: float = 0.72
const SEAT_Z: float = 2.6
const SEAT_Y: float = 0.45
const AUDIENCE_SCALE: float = 0.62
const CARD_Y: float = 3.45

enum Step { WAITING, INTRO, ROUND, DECIDE, REVEAL, OUTRO }

var players: Array[int] = []
var phase: Step = Step.WAITING
## Every round of the show: {duels: [{a, b, result}], bye: [ids]}.
var rounds: Array = []
var round_index: int = -1
var total: int = 0
var duels_each: int = 0
## The current round's duels and who sits it out.
var duels: Array = []
var bye: Array[int] = []
## The duel on the podiums ([] between rounds): ours (us first), else the round's first one.
var pair: Array[int] = []
var round_time: float = SplitOrStealLogic.ROUND_TIME
var decide_time: float = SplitOrStealLogic.DECIDE_TIME
var time_left: float = 0.0
var phase_length: float = 1.0
var points: Dictionary = {}
var steals: Dictionary = {}
var locked: Dictionary = {}
var can_choose: bool = false
var my_choice: String = ""
## The last revealed round's results (see `SplitOrStealLogic._score_duel`), [] while none is shown.
var last_results: Array = []
var ranking_rows: Array = []

## player → {bean: AvatarVisuals, puppet: BeanPuppet, seat: Node3D}
var beans: Dictionary[int, Dictionary] = {}
## Per podium side (0 = left, 1 = right): {root, body_mat, stripe_mat, name, score, card,
## card_mat, card_label, gain, light, talk}.
var podiums: Array[Dictionary] = []
var host: QuizHost
var you_marker: Node3D

## The round counter, on the show sign.
var header_label: Label3D
var phase_label: Label
var timer_bar: ProgressBar
var timer_fill: StyleBoxFlat
var result_label: Label
var status_panel: PanelContainer
var status_label: Label
var button_row: HBoxContainer
var choice_buttons: Dictionary[String, Button] = {}
var round_title: Label
var round_box: VBoxContainer
var standings: MinigameScoreboard
var bubble: PanelContainer
var bubble_label: Label
var _headless: bool = false
var _last_tick: int = -1
## Card flips still running, per podium side.
var _card_tweens: Dictionary[int, Tween] = {}


func _build(start: Dictionary) -> void:
	_headless = DisplayServer.get_name() == "headless"
	for p: Variant in start.get("players", []):
		players.append(int(p))
	for p: int in players:
		points[p] = 0
		steals[p] = 0
	_build_set()
	_build_ui()
	_set_phase_text("SPLIT OR STEAL", Palette.VIP_GOLD)
	_host_say("Welcome to Split or Steal! Everyone plays everyone...", QuizHost.Pose.HAPPY)
	Audio.play(&"announcer_opening", &"UI", -2.0)
	_refresh_all()


func _process(delta: float) -> void:
	if phase == Step.DECIDE or phase == Step.ROUND:
		time_left = maxf(time_left - delta, 0.0)
		timer_bar.value = time_left / maxf(phase_length, 0.01) * 100.0
		if phase == Step.DECIDE:
			var t: int = ceili(time_left)
			phase_label.text = "DECIDE!  %d" % t
			if t <= 3 and t > 0 and t != _last_tick:
				_last_tick = t
				Audio.play(&"countdown_beep", &"UI", -10.0, 1.2)
	_update_talk()
	_place_bubble()


# --- Server data ------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	match ev.get("type", &""):
		&"split_or_steal_started":
			_set_rounds(ev.get("rounds", []))
			round_time = float(ev.get("round_time", round_time))
			decide_time = float(ev.get("decide_time", decide_time))
			duels_each = int(ev.get("duels_each", duels_each))
			phase = Step.INTRO
			_set_phase_text("SPLIT OR STEAL", Palette.VIP_GOLD)
			_show_result("Everyone vs everyone  ·  %d round%s" % [total, "" if total == 1 else "s"], Palette.CREAM)
			_host_say("Tonight everyone faces everyone: %d duel%s each!" % [duels_each, "" if duels_each == 1 else "s"], QuizHost.Pose.HAPPY)
			_refresh_all()
		&"split_or_steal_round":
			total = maxi(total, int(ev.get("total", total)))
			round_time = float(ev.get("round_time", round_time))
			decide_time = float(ev.get("decide_time", decide_time))
			_set_round(int(ev.get("index", 0)), ev.get("duels", []), ev.get("bye", []))
			_enter_round(round_time, true)
		&"split_or_steal_decide":
			if int(ev.get("index", round_index)) == round_index:
				_enter_decide(float(ev.get("decide_time", decide_time)))
		&"split_or_steal_locked":
			if int(ev.get("index", round_index)) == round_index:
				_mark_locked(int(ev.get("player", NOBODY)))
		&"split_or_steal_reveal":
			points = _int_keys(ev.get("points", points))
			steals = _int_keys(ev.get("steals", steals))
			_show_reveal(int(ev.get("index", round_index)), ev.get("results", []), true)
		&"split_or_steal_finished":
			ranking_rows = ev.get("ranking", [])
			_show_final(true)


## Late join / reconnect: the public snapshot (see `SplitOrStealLogic.get_public_state`).
func apply_state(st: Dictionary) -> void:
	_set_rounds(st.get("rounds", []))
	total = int(st.get("total", total))
	duels_each = int(st.get("duels_each", duels_each))
	round_time = float(st.get("round_time", round_time))
	decide_time = float(st.get("decide_time", decide_time))
	points = _int_keys(st.get("points", {}))
	steals = _int_keys(st.get("steals", {}))
	var idx: int = int(st.get("index", -1))
	var s: int = int(st.get("state", -1))
	var timer: float = float(st.get("timer", 0.0))
	if idx >= 0 and idx < rounds.size() and s in [SplitOrStealLogic.State.ROUND, SplitOrStealLogic.State.DECIDE, SplitOrStealLogic.State.REVEAL]:
		var r: Dictionary = rounds[idx]
		_set_round(idx, r["duels"], r["bye"], false)
		for p: Variant in st.get("locked", []):
			locked[int(p)] = true
		match s:
			SplitOrStealLogic.State.ROUND:
				_enter_round(timer, false)
			SplitOrStealLogic.State.DECIDE:
				_enter_decide(decide_time, timer)
			SplitOrStealLogic.State.REVEAL:
				var results: Array = []
				for d: Variant in r["duels"]:
					results.append((d as Dictionary).get("result", {}))
				_show_reveal(idx, results, false)
		for p: int in locked:
			_mark_locked(p, false)
	elif s == SplitOrStealLogic.State.INTRO:
		phase = Step.INTRO
	elif s == SplitOrStealLogic.State.OUTRO or s == SplitOrStealLogic.State.DONE:
		ranking_rows = st.get("ranking", [])
		_show_final(false)
	can_choose = phase == Step.DECIDE and opponent() != NOBODY and not locked.has(local_id)
	_refresh_all()


## Our private minigame state, every frame. Besides our buttons it carries the round being played:
## when an event went missing (the stage is built behind the curtain, after the show may have
## begun) the stage catches up from it instead of showing an empty round.
func on_private(priv: Dictionary) -> void:
	var mine: Dictionary = priv.get("minigame", {})
	if mine.is_empty() or not mine.has("index"):
		return
	var idx: int = int(mine.get("index", -1))
	var s: int = int(mine.get("state", -1))
	var their_duels: Array = mine.get("duels", [])
	if idx > round_index and not their_duels.is_empty() and s in [SplitOrStealLogic.State.ROUND, SplitOrStealLogic.State.DECIDE]:
		_set_round(idx, their_duels, mine.get("bye", []))
		_enter_round(float(mine.get("timer", 0.0)) if s == SplitOrStealLogic.State.ROUND else 0.0, false)
	if idx != round_index:
		return  # stale, or a reveal / the end we wait for the event of
	if s == SplitOrStealLogic.State.DECIDE and phase in [Step.ROUND, Step.WAITING, Step.INTRO]:
		_enter_decide(decide_time, float(mine.get("timer", decide_time)))
	if phase != Step.DECIDE:
		return
	# Once we picked locally, a lagging snapshot must not re-open the buttons.
	var choose: bool = bool(mine.get("can_choose", false)) and not locked.has(local_id)
	var chosen: String = str(mine.get("my_choice", ""))
	if choose != can_choose or (chosen != "" and chosen != my_choice):
		can_choose = choose
		if chosen != "":
			my_choice = chosen
			locked[local_id] = true
			_mark_locked(local_id, false)
		_refresh_buttons()


# --- Input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not can_choose:
		return
	var pick: String = ""
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).keycode
		if k == KEY_1 or k == KEY_KP_1:
			pick = SPLIT
		elif k == KEY_2 or k == KEY_KP_2:
			pick = STEAL
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b: JoyButton = (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_A:
			pick = SPLIT
		elif b == JOY_BUTTON_B:
			pick = STEAL
	if pick != "":
		_on_choice(pick)
		get_viewport().set_input_as_handled()


func _on_choice(choice: String) -> void:
	if not can_choose:
		return
	var res: Dictionary = Net.send_intent(Intents.make(&"split_or_steal_pick", {"choice": choice}))
	if res.has("ok") and not bool(res["ok"]):
		return  # refused (e.g. the window just closed): the server's state will follow
	my_choice = choice
	can_choose = false
	Audio.play(&"chip_clack", &"UI", -6.0)
	_mark_locked(local_id)
	_refresh_buttons()


# --- State changes ----------------------------------------------------------------------------

func _set_rounds(s: Variant) -> void:
	if not (s is Array) or (s as Array).is_empty():
		return
	rounds = []
	for r: Variant in s:
		var d: Dictionary = r
		rounds.append({"duels": _clean_duels(d.get("duels", [])), "bye": _ints(d.get("bye", []))})
	total = rounds.size()


static func _clean_duels(src: Variant) -> Array:
	var out: Array = []
	if src is Array:
		for e: Variant in src:
			var d: Dictionary = e
			out.append({"a": int(d.get("a", NOBODY)), "b": int(d.get("b", NOBODY)), "result": (d.get("result", {}) as Dictionary).duplicate()})
	return out


static func _ints(src: Variant) -> Array[int]:
	var out: Array[int] = []
	if src is Array:
		for x: Variant in src:
			out.append(int(x))
	return out


## Starts round `idx`: its duels, who sits out, our duel on the podiums, everyone else seated.
func _set_round(idx: int, p_duels: Variant, p_bye: Variant, animate: bool = true) -> void:
	var fresh: bool = idx != round_index
	round_index = idx
	duels = _clean_duels(p_duels)
	bye = _ints(p_bye)
	while rounds.size() <= idx:
		rounds.append({"duels": [], "bye": []})
	if fresh or (rounds[idx]["duels"] as Array).is_empty():
		rounds[idx] = {"duels": duels.duplicate(true), "bye": bye.duplicate()}
	total = maxi(total, rounds.size())
	var next: Array[int] = _focus_pair()
	var moved: bool = next != pair
	pair = next
	if fresh:
		locked.clear()
		my_choice = ""
		can_choose = false
		last_results = []
		for pd: Dictionary in podiums:
			(pd["gain"] as Label3D).visible = false
	for pid: int in beans:
		_seat_bean(pid, pair.find(pid), animate and (fresh or moved))
		(beans[pid]["puppet"] as BeanPuppet).set_mood(BeanPuppet.Mood.IDLE)
	for side: int in 2:
		_dress_podium(side)
	_refresh_all()


## The duel to put on the podiums: ours (us on the left), else the round's first.
func _focus_pair() -> Array[int]:
	var out: Array[int] = []
	var opp: int = opponent()
	if opp != NOBODY:
		out.assign([local_id, opp])
	elif not duels.is_empty():
		out.assign([int(duels[0]["a"]), int(duels[0]["b"])])
	return out


## Our opponent this round (NOBODY when sitting out or between rounds).
func opponent() -> int:
	return opponent_in(duels, local_id)


static func opponent_in(p_duels: Array, pid: int) -> int:
	for d: Variant in p_duels:
		if int(d["a"]) == pid:
			return int(d["b"])
		if int(d["b"]) == pid:
			return int(d["a"])
	return NOBODY


## Everyone with a duel this round.
func _duelists() -> Array[int]:
	var out: Array[int] = []
	for d: Variant in duels:
		out.append(int(d["a"]))
		out.append(int(d["b"]))
	return out


func _enter_round(remaining: float, live: bool) -> void:
	phase = Step.ROUND
	phase_length = maxf(round_time, 0.01)
	time_left = remaining
	timer_bar.visible = false
	for side: int in mini(2, pair.size()):
		_set_card(side, "LOCKED IN" if locked.has(pair[side]) else "?", Palette.WARM_GOLD if locked.has(pair[side]) else Palette.WARM_CHARCOAL,
			Palette.CASINO_BLACK if locked.has(pair[side]) else Palette.CREAM.darkened(0.2))
	_set_phase_text("ROUND %d" % (round_index + 1), Palette.VIP_GOLD)
	var opp: int = opponent()
	if opp != NOBODY:
		_show_result("You  vs  %s" % state.player_name(opp), Palette.CREAM)
		_host_say("Round %d! %s, you face %s." % [round_index + 1, state.player_name(local_id), state.player_name(opp)], QuizHost.Pose.SURPRISED)
	else:
		_show_result("%d duel%s at once" % [duels.size(), "" if duels.size() == 1 else "s"], Palette.CREAM)
		if local_id in bye:
			_host_say("Round %d! You sit this one out. Enjoy the show." % (round_index + 1), QuizHost.Pose.HAPPY)
		else:
			_host_say("Round %d! %d duels at once!" % [round_index + 1, duels.size()], QuizHost.Pose.HAPPY)
	if live:
		Audio.play(&"whoosh", &"UI", -6.0)
	_refresh_all()


func _enter_decide(length: float, remaining: float = -1.0) -> void:
	phase = Step.DECIDE
	phase_length = maxf(length, 0.01)
	time_left = remaining if remaining >= 0.0 else length
	_last_tick = -1
	timer_bar.visible = true
	timer_fill.bg_color = Palette.WARM_GOLD
	_set_phase_text("DECIDE!  %d" % ceili(time_left), Palette.CREAM)
	var opp: int = opponent()
	can_choose = opp != NOBODY and not locked.has(local_id)
	if opp != NOBODY:
		_show_result("Talk %s into splitting. Or don't." % state.player_name(opp), Palette.CREAM)
	else:
		_show_result("", Palette.CREAM)
	_host_say("Split... or steal? Make your case!", QuizHost.Pose.DRUMROLL, 0.0)
	for side: int in mini(2, pair.size()):
		if locked.has(pair[side]):
			_set_card(side, "LOCKED IN", Palette.WARM_GOLD, Palette.CASINO_BLACK)
		else:
			_set_card(side, "?", Palette.WARM_CHARCOAL, Palette.CREAM.darkened(0.2))
	_refresh_all()


func _mark_locked(pid: int, sound: bool = true) -> void:
	locked[pid] = true
	var side: int = pair.find(pid)
	if side >= 0 and phase != Step.REVEAL:
		_set_card(side, "LOCKED IN", Palette.WARM_GOLD, Palette.CASINO_BLACK)
		_pop3d(podiums[side]["card"] as Node3D)
		var pup: BeanPuppet = beans[pid]["puppet"] if beans.has(pid) else null
		if pup != null:
			pup.hop(0.25)
		if sound and pid != local_id:
			Audio.play(&"chip_clack", &"UI", -8.0, 0.8)
	elif beans.has(pid) and phase != Step.REVEAL and sound:
		(beans[pid]["puppet"] as BeanPuppet).hop(0.18)  # a little hop in the seats too
	_refresh_buttons()
	_refresh_round()
	_refresh_standings()


## Round `idx` is revealed: every duel's picks and points (results as in `_score_duel`).
func _show_reveal(idx: int, results: Variant, live: bool) -> void:
	var res: Array = []
	if results is Array:
		for r: Variant in results:
			if r is Dictionary and (r as Dictionary).has("choice_a"):
				res.append(r)
	if res.is_empty():
		return
	if idx != round_index:
		var dl: Array = []
		for r: Dictionary in res:
			dl.append({"a": r["a"], "b": r["b"], "result": {}})
		_set_round(idx, dl, rounds[idx]["bye"] if idx >= 0 and idx < rounds.size() else [], false)
	phase = Step.REVEAL
	can_choose = false
	timer_bar.visible = false
	last_results = res
	for r: Dictionary in res:
		for d: Variant in duels:
			if int(d["a"]) == int(r["a"]) and int(d["b"]) == int(r["b"]):
				d["result"] = r.duplicate()
	if idx >= 0 and idx < rounds.size():
		rounds[idx]["duels"] = duels.duplicate(true)
	_set_phase_text("THE REVEAL", Palette.VIP_GOLD)
	# The podiums: the duel on show flips its two cards.
	var shown: Dictionary = _result_of(pair)
	if not shown.is_empty():
		var flipped: bool = int(shown["a"]) != pair[0]
		var choices: Array[String] = [str(shown["choice_a"]), str(shown["choice_b"])]
		var gains: Array[int] = [int(shown["points_a"]), int(shown["points_b"])]
		var autos: Array[bool] = [bool(shown.get("auto_a", false)), bool(shown.get("auto_b", false))]
		if flipped:
			choices.reverse()
			gains.reverse()
			autos.reverse()
		for side: int in 2:
			_flip_card(side, choices[side] + ("*" if autos[side] else ""), _choice_color(choices[side]), live)
			var gain: Label3D = podiums[side]["gain"]
			gain.text = "+%d" % gains[side]
			gain.modulate = Palette.MONEY_GREEN if gains[side] > 0 else Palette.LOSS_RED
			gain.visible = true
	# Every bean reacts to its own duel, on the podiums and in the seats alike.
	var n_steal: int = 0
	var n_split: int = 0
	for r: Dictionary in res:
		var ca: String = str(r["choice_a"])
		var cb: String = str(r["choice_b"])
		_react(int(r["a"]), ca, cb)
		_react(int(r["b"]), cb, ca)
		n_steal += int(ca == STEAL) + int(cb == STEAL)
		n_split += int(ca == SPLIT and cb == SPLIT)
	# The headline: our duel, or the round at a glance.
	var line: String
	var color: Color
	var mine: Dictionary = _result_of([local_id, opponent()]) if opponent() != NOBODY else {}
	var my_gain: int = -1
	if not mine.is_empty():
		var me_a: bool = int(mine["a"]) == local_id
		var me_c: String = str(mine["choice_a" if me_a else "choice_b"])
		var them_c: String = str(mine["choice_b" if me_a else "choice_a"])
		my_gain = int(mine["points_a" if me_a else "points_b"])
		var them: String = state.player_name(opponent()).to_upper()
		if me_c == SPLIT and them_c == SPLIT:
			line = "YOU BOTH SPLIT!  +%d" % my_gain
			color = Palette.MONEY_GREEN
		elif me_c == STEAL and them_c == STEAL:
			line = "YOU BOTH STOLE!  Nobody gets a thing"
			color = Palette.LOSS_RED
		elif me_c == STEAL:
			line = "YOU STEAL FROM %s!  +%d" % [them, my_gain]
			color = Palette.VIP_GOLD
		else:
			line = "%s STEALS FROM YOU!  +0" % them
			color = Palette.LOSS_RED
		if bool(mine.get("auto_a" if me_a else "auto_b", false)):
			line += "   (* too slow: counted as SPLIT)"
	else:
		line = "%d steal%s  ·  %d duel%s both split" % [n_steal, "" if n_steal == 1 else "s", n_split, "" if n_split == 1 else "s"]
		color = Palette.VIP_GOLD if n_steal > 0 else Palette.MONEY_GREEN
	_show_result(line, color)
	_pop(result_label, 1.0, 0.7)
	if n_steal == 0:
		_host_say("Nobody stole! How wholesome.", QuizHost.Pose.HAPPY)
	elif n_split == 0 and n_steal >= res.size() * 2:
		_host_say("Thieves everywhere! Empty pockets all round.", QuizHost.Pose.DISAPPOINTED)
	else:
		_host_say("%d steal%s this round! Who saw that coming?" % [n_steal, "" if n_steal == 1 else "s"], QuizHost.Pose.SURPRISED)
	if live:
		Audio.play(&"card_flip", &"UI", -4.0)
		if my_gain > 0:
			Audio.play(&"cash_register", &"UI", -6.0)
		elif my_gain == 0:
			Audio.play(&"buzzer", &"UI", -6.0)
		elif n_steal > 0:
			Audio.play(&"buzzer", &"UI", -12.0)
	_refresh_all()


## The revealed result of the duel between the two players in `p` (either order), {} if none.
func _result_of(p: Array) -> Dictionary:
	if p.size() < 2:
		return {}
	for r: Variant in last_results:
		var a: int = int(r["a"])
		var b: int = int(r["b"])
		if (a == int(p[0]) and b == int(p[1])) or (a == int(p[1]) and b == int(p[0])):
			return r
	return {}


func _show_final(live: bool) -> void:
	phase = Step.OUTRO
	can_choose = false
	timer_bar.visible = false
	last_results = []
	for r: Variant in ranking_rows:
		var row: Dictionary = r
		points[int(row["player"])] = int(row["points"])
		steals[int(row["player"])] = int(row["steals"])
	var winners: Array[int] = []
	for r: Variant in ranking_rows:
		if int((r as Dictionary)["rank"]) == 1:
			winners.append(int((r as Dictionary)["player"]))
	var names: Array[String] = []
	for w: int in winners:
		names.append(state.player_name(w))
	_set_phase_text("SHOW'S OVER", Palette.VIP_GOLD)
	_show_result(("%s WIN%s!" % [" & ".join(names).to_upper(), "" if names.size() > 1 else "S"]) if not names.is_empty() else "What a show!", Palette.VIP_GOLD)
	_pop(result_label, 1.0, 0.7)
	# Winners take the podiums, everyone else back to the seats.
	pair = []
	for pid: int in beans:
		var side: int = winners.find(pid) if winners.size() <= 2 else -1
		_seat_bean(pid, side, live)
		(beans[pid]["puppet"] as BeanPuppet).set_mood(BeanPuppet.Mood.CHEER if pid in winners else BeanPuppet.Mood.IDLE)
	if winners.size() <= 2:
		pair.assign(winners)
	for side: int in 2:
		_dress_podium(side)
		_set_card(side, "WINNER" if side < pair.size() else "", Palette.VIP_GOLD, Palette.CASINO_BLACK)
		(podiums[side]["card"] as Node3D).visible = side < pair.size()
	_host_say("Give it up for %s!" % " & ".join(names) if not names.is_empty() else "What a show!", QuizHost.Pose.HAPPY, 0.0)
	if live:
		Audio.play(&"quiz_winner", &"UI", -3.0)
		if not _headless:
			ConfettiBurst.rain(self, Vector3(0, 8.5, 0.5), Vector3(12, 0.2, 4), 140)
	_refresh_all()


# --- 3D presentation --------------------------------------------------------------------------

## Moves a player's bean to podium `side` (0 / 1) or back to their audience seat (-1).
func _seat_bean(pid: int, side: int, animate: bool) -> void:
	var b: Dictionary = beans[pid]
	var bean: AvatarVisuals = b["bean"]
	var puppet: BeanPuppet = b["puppet"]
	var target: Node3D = (podiums[side]["root"] as Node3D) if side >= 0 else (b["seat"] as Node3D)
	var moved: bool = bean.get_parent() != target
	if moved:
		bean.get_parent().remove_child(bean)
		target.add_child(bean)
	if side >= 0:
		bean.position = Vector3(0, PODIUM_TOP, 0)
		bean.scale = Vector3.ONE
		bean.rotation = Vector3(0, PI + 0.18 * (1.0 if side == 0 else -1.0), 0)  # face out, a little towards each other
	else:
		bean.position = Vector3.ZERO
		bean.scale = Vector3.ONE * AUDIENCE_SCALE
		bean.rotation = Vector3.ZERO
	puppet.base = bean.position
	if animate and moved and side >= 0 and not _headless:
		puppet.drop_in(2.5)
	(b["seat_label"] as Label3D).visible = side < 0
	if pid == local_id and you_marker != null:
		you_marker.visible = side < 0


## Paints podium `side` for the player on it: colour, name, score, spotlight.
func _dress_podium(side: int) -> void:
	var pd: Dictionary = podiums[side]
	var on: bool = side < pair.size()
	var pid: int = pair[side] if on else NOBODY
	var col: Color = _player_color(pid) if on else Palette.WARM_CHARCOAL
	(pd["body_mat"] as StandardMaterial3D).albedo_color = col.darkened(0.25) if on else Palette.WARM_CHARCOAL
	(pd["stripe_mat"] as StandardMaterial3D).albedo_color = col
	var name_l: Label3D = pd["name"]
	var nm: String = state.player_name(pid) if on else ""
	if nm.length() > 12:
		nm = nm.left(11) + "…"
	name_l.text = nm
	(pd["score"] as Label3D).text = _podium_score(pid) if on else ""
	(pd["light"] as SpotLight3D).light_energy = 5.0 if on else 0.0
	(pd["card"] as Node3D).visible = on and phase != Step.OUTRO
	if phase != Step.REVEAL:
		(pd["gain"] as Label3D).visible = false
	if on and phase in [Step.ROUND, Step.DECIDE] and not locked.has(pid):
		_set_card(side, "?", Palette.WARM_CHARCOAL, Palette.CREAM.darkened(0.2))


func _podium_score(pid: int) -> String:
	return ("YOU · %d pts" if pid == local_id else "%d pts") % _pts(pid)


func _set_card(side: int, text: String, bg: Color, fg: Color) -> void:
	var tw: Tween = _card_tweens.get(side, null)
	if tw != null and tw.is_valid():
		tw.kill()  # a flip still running from the last reveal must not paint over this
		(podiums[side]["card"] as Node3D).scale = Vector3.ONE
	_card_tweens.erase(side)
	_apply_card(side, text, bg, fg)


func _apply_card(side: int, text: String, bg: Color, fg: Color) -> void:
	var pd: Dictionary = podiums[side]
	(pd["card_label"] as Label3D).text = text
	(pd["card_label"] as Label3D).modulate = fg
	(pd["card_mat"] as StandardMaterial3D).albedo_color = bg


## The choice card turns over (squash to an edge, swap the face, open up) to show `text`.
func _flip_card(side: int, text: String, bg: Color, live: bool) -> void:
	var card: Node3D = podiums[side]["card"]
	card.visible = true
	if not live or _headless:
		_set_card(side, text, bg, Palette.CREAM)
		card.scale = Vector3.ONE
		return
	_set_card(side, "?", Palette.WARM_CHARCOAL, Palette.CREAM.darkened(0.2))
	var tw: Tween = card.create_tween()
	_card_tweens[side] = tw
	tw.tween_interval(0.25 * side)
	tw.tween_property(card, "scale:y", 0.02, 0.14).set_ease(Tween.EASE_IN)
	tw.tween_callback(_apply_card.bind(side, text, bg, Palette.CREAM))
	tw.tween_property(card, "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A bean's reaction to the reveal: `mine` vs `theirs`.
func _react(pid: int, mine: String, theirs: String) -> void:
	if not beans.has(pid):
		return
	var bean: AvatarVisuals = beans[pid]["bean"]
	var puppet: BeanPuppet = beans[pid]["puppet"]
	var on_podium: bool = pid in pair
	if mine == STEAL and theirs == SPLIT:
		puppet.set_mood(BeanPuppet.Mood.CHEER)
		bean.react(&"big_win")
		if on_podium and not _headless:
			ConfettiBurst.burst(bean.get_parent() as Node3D, Vector3(0, 2.8, 0), 90, 1.0)
	elif mine == SPLIT and theirs == SPLIT:
		puppet.set_mood(BeanPuppet.Mood.CHEER)
		bean.react(&"win")
	else:
		puppet.set_mood(BeanPuppet.Mood.SAD)
		bean.react(&"loss")


## Lights "TALKING" under the card of whoever on the podiums is audibly speaking (voice is global).
func _update_talk() -> void:
	var vc: VoiceChannel = VoiceChannel.current
	for side: int in podiums.size():
		var on: bool = side < pair.size() and vc != null and vc.is_talking(pair[side])
		(podiums[side]["talk"] as Label3D).visible = on


# --- 2D overlay -------------------------------------------------------------------------------

func _refresh_all() -> void:
	if phase_label == null:
		return
	_refresh_header()
	_refresh_buttons()
	_refresh_round()
	_refresh_standings()
	for side: int in podiums.size():
		if side < pair.size():
			(podiums[side]["score"] as Label3D).text = _podium_score(pair[side])


func _refresh_header() -> void:
	if header_label == null:
		return
	if round_index >= 0 and total > 0 and phase != Step.OUTRO:
		header_label.text = "ROUND %d / %d" % [mini(round_index + 1, total), total]
	else:
		header_label.text = "EVERYONE VS EVERYONE" if phase != Step.OUTRO else "THAT'S A WRAP"


func _set_phase_text(text: String, color: Color) -> void:
	phase_label.text = text
	phase_label.add_theme_color_override(&"font_color", color)


func _show_result(text: String, color: Color) -> void:
	result_label.text = text
	result_label.visible = text != ""
	result_label.add_theme_color_override(&"font_color", color)


func _refresh_buttons() -> void:
	var opp: int = opponent()
	var dueling: bool = opp != NOBODY and phase in [Step.ROUND, Step.DECIDE]
	button_row.visible = dueling
	for c: String in choice_buttons:
		var b: Button = choice_buttons[c]
		b.disabled = not can_choose
		if my_choice == c:
			b.modulate = Color.WHITE
		elif my_choice != "":
			b.modulate = Color(1, 1, 1, 0.3)
		else:
			b.modulate = Color.WHITE if can_choose else Color(1, 1, 1, 0.55)
	var text: String = ""
	var them: String = state.player_name(opp) if opp != NOBODY else ""
	if phase in [Step.OUTRO, Step.WAITING, Step.INTRO, Step.REVEAL]:
		text = ""
	elif opp == NOBODY:
		var all: Array[int] = _duelists()
		var n: int = 0
		for p: int in all:
			n += int(locked.has(p))
		text = "You sit this round out" if local_id in bye else "Watching"
		if phase == Step.DECIDE:
			text += "  ·  %d / %d decided" % [n, all.size()]
	elif phase == Step.ROUND:
		text = "You face %s  ·  SPLIT or STEAL opens in a moment" % them
	elif my_choice != "":
		text = "You locked in %s vs %s. %s" % [my_choice, them, "Waiting for the others..." if locked.has(opp) else "Waiting for %s..." % them]
	else:
		text = "vs %s  ·  1 / A = SPLIT  ·  2 / B = STEAL" % them + ("   ·   %s has locked in!" % them if locked.has(opp) else "")
	status_label.text = text
	status_panel.visible = text != ""


## THIS ROUND: every duel of the round, who decided, then the picks and points.
func _refresh_round() -> void:
	if round_box == null:
		return
	for c: Node in round_box.get_children():
		round_box.remove_child(c)
		c.queue_free()
	if round_index < 0 or phase == Step.OUTRO or duels.is_empty():
		round_title.text = "EVERYONE VS EVERYONE"
		var twice: bool = duels_each > players.size() - 1
		var line: String = "Every pair meets %s." % ("twice" if twice else "once")
		if total > 0:
			line = "%d rounds  ·  every pair meets %s." % [total, "twice" if twice else "once"]
		if phase == Step.OUTRO:
			line = "%d duels played." % _duels_played()
		round_box.add_child(_label(line, 20, MUTED))
		return
	round_title.text = "ROUND %d / %d" % [round_index + 1, maxi(total, round_index + 1)]
	for d: Variant in duels:
		var a: int = int(d["a"])
		var b: int = int(d["b"])
		var ours: bool = local_id == a or local_id == b
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.WARM_GOLD.darkened(0.55) if ours else Color(0, 0, 0, 0.0)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		row.add_theme_stylebox_override(&"panel", sb)
		round_box.add_child(row)
		var v := VBoxContainer.new()
		v.add_theme_constant_override(&"separation", 0)
		row.add_child(v)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 6)
		v.add_child(h)
		for pid: int in [a, b]:
			if pid == b:
				h.add_child(_label("vs", 18, MUTED))
			h.add_child(_dot(_player_color(pid), 12))
			h.add_child(_label(_short(state.player_name(pid)), 22, Palette.VIP_GOLD if pid == local_id else Palette.CREAM))
		var r: Dictionary = d["result"]
		var sub := HBoxContainer.new()
		sub.add_theme_constant_override(&"separation", 8)
		if r.has("choice_a"):
			sub.add_child(_tag(str(r["choice_a"]), _choice_color(str(r["choice_a"]))))
			sub.add_child(_label(_gain_text(r, "a"), 18, Palette.CREAM.darkened(0.1)))
			sub.add_child(_label("·", 18, MUTED))
			sub.add_child(_tag(str(r["choice_b"]), _choice_color(str(r["choice_b"]))))
			sub.add_child(_label(_gain_text(r, "b"), 18, Palette.CREAM.darkened(0.1)))
			v.add_child(sub)
		elif phase == Step.DECIDE:
			for pid: int in [a, b]:
				var gone: bool = pid not in state.players
				sub.add_child(_label("left" if gone else ("decided" if locked.has(pid) else "thinking..."), 16, Palette.VIP_GOLD if locked.has(pid) else MUTED, 150))
			v.add_child(sub)
	if not bye.is_empty():
		var names: Array[String] = []
		for p: int in bye:
			names.append("You" if p == local_id else _short(state.player_name(p)))
		round_box.add_child(_label("Sitting out: %s" % ", ".join(names), 18, MUTED))


func _duels_played() -> int:
	var n: int = 0
	for r: Variant in rounds:
		for d: Variant in (r as Dictionary)["duels"]:
			n += int(((d as Dictionary)["result"] as Dictionary).has("choice_a"))
	return n


func _gain_text(r: Dictionary, side: String) -> String:
	if bool(r.get("gone_" + side, false)):
		return "left"
	return "+%d%s" % [int(r["points_" + side]), "*" if bool(r.get("auto_" + side, false)) else ""]


func _refresh_standings() -> void:
	if standings == null:
		return
	var order: Array = players.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		if _pts(a) != _pts(b):
			return _pts(a) > _pts(b)
		if _stl(a) != _stl(b):
			return _stl(a) < _stl(b)
		return a < b)
	var rows: Array = []
	var dueling: Array[int] = _duelists()
	for pid: int in order:
		var r: Dictionary = {"player": pid, "score": _pts(pid), "steals": _stl(pid),
			"detail": "%d steal%s" % [_stl(pid), "" if _stl(pid) == 1 else "s"]}
		if phase in [Step.ROUND, Step.DECIDE, Step.REVEAL]:
			if pid in bye:
				r["tag"] = "SITS OUT"
				r["tag_color"] = MUTED
			elif pid in dueling:
				var opp: int = opponent_in(duels, pid)
				r["tag"] = "VS %s" % _short(state.player_name(opp)).to_upper()
				r["tag_color"] = Palette.WARM_GOLD
				if phase == Step.DECIDE:
					r["status"] = &"done" if locked.has(pid) else &"waiting"
		rows.append(r)
	MinigameScoreboard.rank_rows(rows, "score", "steals")
	standings.set_rows(rows)


## The host speaks (speech bubble) and strikes a pose (`hold` 0 = keep the pose).
func _host_say(text: String, pose: QuizHost.Pose = QuizHost.Pose.IDLE, hold: float = 2.2) -> void:
	if host == null:
		return
	host.say(text)
	host.set_pose(pose, hold)
	if bubble_label != null:
		bubble_label.text = text
		bubble.visible = text != ""
		_pop(bubble, 1.0, 0.85)


## Keeps the speech bubble over Lucky's head on screen.
func _place_bubble() -> void:
	if bubble == null or not bubble.visible or camera == null or host == null or not camera.is_inside_tree():
		return
	var p: Vector2 = PixelView.to_canvas(camera, camera.unproject_position(host.bubble_anchor()), bubble)
	var vp: Vector2 = bubble.get_viewport_rect().size
	bubble.reset_size()
	bubble.pivot_offset = Vector2(bubble.size.x * 0.5, bubble.size.y)
	bubble.position = Vector2(clampf(p.x - bubble.size.x * 0.5, 16.0, vp.x - bubble.size.x - 16.0), clampf(p.y - bubble.size.y, 16.0, vp.y - bubble.size.y - 16.0))


func _choice_color(c: String) -> Color:
	if c == SPLIT:
		return SPLIT_COLOR
	if c == STEAL:
		return STEAL_COLOR
	return Palette.WARM_CHARCOAL


func _pts(pid: int) -> int:
	return int(points.get(pid, 0))


func _stl(pid: int) -> int:
	return int(steals.get(pid, 0))


func _short(s: String) -> String:
	return s if s.length() <= 10 else s.left(9) + "…"


## Per-player tables from the wire may carry string keys: normalise to ints.
static func _int_keys(d: Variant) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for k: Variant in d:
			out[int(k)] = int(d[k])
	return out


func _player_color(pid: int) -> Color:
	if pid == NOBODY:
		return Palette.WARM_CHARCOAL
	return PlayerColors.of_player(state.players, pid)


# --- Building: the set ------------------------------------------------------------------------

func _build_set() -> void:
	# Floor and a raised round stage with a gold rim.
	_box(self, Vector3(40, 0.2, 26), Vector3(0, -0.1, 0), Palette.VIP_BURGUNDY.darkened(0.45))
	var rim := _cyl(self, 6.3, 6.3, 0.26, Vector3(0, 0.13, -0.2), Palette.WARM_GOLD, 0.7)
	rim.name = "StageRim"
	_cyl(self, 6.1, 6.1, 0.3, Vector3(0, 0.15, -0.2), Palette.WARM_CHARCOAL.lightened(0.05))
	# Curtain backdrop: deep burgundy folds under a gold-fringed valance.
	var folds := Node3D.new()
	folds.name = "Curtain"
	add_child(folds)
	var x: float = -13.0
	var i: int = 0
	while x <= 13.0:
		var shade: Color = Palette.VIP_BURGUNDY.darkened(0.05 if i % 2 == 0 else 0.3)
		_cyl(folds, 0.36, 0.36, 12.0, Vector3(x, 6.0, -5.2 - 0.12 * float(i % 2)), shade, 0.0, 10)
		x += 0.6
		i += 1
	_box(self, Vector3(28, 1.2, 0.5), Vector3(0, 10.6, -4.8), Palette.VIP_BURGUNDY.darkened(0.15))
	_box(self, Vector3(28, 0.14, 0.55), Vector3(0, 10.0, -4.78), Palette.WARM_GOLD, 0.7)
	# The sign: dark panel, gold frame, marquee bulbs, the show's name.
	_box(self, Vector3(8.6, 1.9, 0.2), Vector3(0, 7.0, -4.6), Palette.WARM_GOLD, 0.8)
	_box(self, Vector3(8.2, 1.5, 0.22), Vector3(0, 7.0, -4.55), Palette.CASINO_BLACK.lightened(0.04))
	var bulb_mat: StandardMaterial3D = _mat(WARM_LIGHT, 0.0, true)
	for b: int in 14:
		for y: float in [7.88, 6.12]:
			var bulb := MeshInstance3D.new()
			var bm := SphereMesh.new()
			bm.radius = 0.07
			bm.height = 0.14
			bulb.mesh = bm
			bulb.material_override = bulb_mat
			bulb.position = Vector3(-3.9 + b * 0.6, y, -4.42)
			add_child(bulb)
	var title := Label3D.new()
	title.name = "ShowTitle"
	title.text = "SPLIT  OR  STEAL"
	title.font_size = 120
	title.pixel_size = 0.0085
	title.outline_size = 10
	title.outline_modulate = Palette.CASINO_BLACK
	title.modulate = Palette.VIP_GOLD
	title.position = Vector3(0, 7.15, -4.4)
	add_child(title)
	header_label = Label3D.new()
	header_label.name = "MatchCounter"
	header_label.font_size = 40
	header_label.pixel_size = 0.0085
	header_label.outline_size = 0
	header_label.modulate = Palette.WARM_GOLD
	header_label.position = Vector3(0, 6.48, -4.4)
	add_child(header_label)
	# Two podiums.
	for side: int in 2:
		podiums.append(_build_podium(side))
	# Lucky between and behind them, at a lectern.
	var host_root := Node3D.new()
	host_root.name = "Host"
	host_root.position = Vector3(0, 0.3, -1.4)
	host_root.scale = Vector3.ONE * 1.15
	add_child(host_root)
	host = QuizHost.new()
	host_root.add_child(host)
	_box(host_root, Vector3(1.4, 0.85, 0.6), Vector3(0, 0.42, 0.75), Palette.VIP_BURGUNDY)
	_box(host_root, Vector3(1.5, 0.07, 0.7), Vector3(0, 0.86, 0.75), Palette.WARM_GOLD, 0.8)
	var plate := Label3D.new()
	plate.text = "$"
	plate.font_size = 64
	plate.pixel_size = 0.008
	plate.modulate = Palette.VIP_GOLD
	plate.position = Vector3(0, 0.45, 1.06)
	host_root.add_child(plate)
	# Audience: benches at both sides, every player's bean in a seat.
	for s: float in [-1.0, 1.0]:
		var cx: float = s * (SEAT_X0 + SEAT_STEP * 1.5)
		_box(self, Vector3(SEAT_STEP * 4.0 + 0.4, SEAT_Y, 0.8), Vector3(cx, SEAT_Y * 0.5, SEAT_Z), Palette.VIP_BURGUNDY.darkened(0.1))
		_box(self, Vector3(SEAT_STEP * 4.0 + 0.5, 0.06, 0.9), Vector3(cx, SEAT_Y + 0.03, SEAT_Z), Palette.WARM_GOLD, 0.7)
	for idx: int in players.size():
		_build_seat(players[idx], idx)
	_build_lights()
	camera = Camera3D.new()
	camera.name = "ShowCamera"
	camera.fov = 52.0
	camera.far = 90.0  # the casino floor is 400 m away: keep its labels out
	add_child(camera)
	camera.position = Vector3(0, 3.3, 11.0)
	camera.look_at(global_position + Vector3(0, 1.75, -0.5))


func _build_podium(side: int) -> Dictionary:
	var s: float = -1.0 if side == 0 else 1.0
	var root := Node3D.new()
	root.name = "Podium%d" % side
	root.position = Vector3(s * PODIUM_X, 0.3, PODIUM_Z)
	add_child(root)
	var body_mat: StandardMaterial3D = _mat(Palette.WARM_CHARCOAL)
	var body := _cyl(root, 0.85, 0.95, PODIUM_TOP - 0.3, Vector3(0, (PODIUM_TOP - 0.3) * 0.5, 0), Palette.WARM_CHARCOAL, 0.0, 8)
	body.material_override = body_mat
	_cyl(root, 0.98, 0.98, 0.08, Vector3(0, PODIUM_TOP - 0.3 + 0.04, 0), Palette.WARM_GOLD, 0.8, 8)
	_cyl(root, 1.0, 1.0, 0.08, Vector3(0, 0.04, 0), Palette.WARM_GOLD, 0.8, 8)
	# A colour stripe and the name on the front.
	var stripe_mat: StandardMaterial3D = _mat(Palette.CREAM)
	var stripe: MeshInstance3D = _box(root, Vector3(1.25, 0.08, 0.05), Vector3(0, 0.62, 0.86), Palette.CREAM)
	stripe.material_override = stripe_mat
	var name_l := Label3D.new()
	name_l.font_size = 46
	name_l.pixel_size = 0.0058
	name_l.outline_size = 8
	name_l.outline_modulate = Palette.CASINO_BLACK
	name_l.modulate = Palette.CREAM
	name_l.position = Vector3(0, 0.38, 0.93)
	root.add_child(name_l)
	var score := Label3D.new()
	score.font_size = 30
	score.pixel_size = 0.0058
	score.outline_size = 6
	score.outline_modulate = Palette.CASINO_BLACK
	score.modulate = Palette.VIP_GOLD
	score.position = Vector3(0, 0.16, 0.93)
	root.add_child(score)
	# The choice card over the head: "?", "LOCKED IN", then SPLIT / STEAL.
	var card := Node3D.new()
	card.name = "Card"
	card.position = Vector3(0, CARD_Y - 0.3, 0)
	card.visible = false
	root.add_child(card)
	_box(card, Vector3(1.86, 0.84, 0.05), Vector3(0, 0, -0.03), Palette.WARM_GOLD, 0.8)
	var card_mat: StandardMaterial3D = _mat(Palette.WARM_CHARCOAL)
	var face: MeshInstance3D = _box(card, Vector3(1.72, 0.7, 0.06), Vector3.ZERO, Palette.WARM_CHARCOAL)
	face.material_override = card_mat
	var card_label := Label3D.new()
	card_label.text = "?"
	card_label.font_size = 76
	card_label.pixel_size = 0.0058
	card_label.outline_size = 0
	card_label.modulate = Palette.CREAM
	card_label.position = Vector3(0, 0, 0.045)
	card.add_child(card_label)
	var gain := Label3D.new()
	gain.font_size = 56
	gain.pixel_size = 0.0058
	gain.outline_size = 10
	gain.outline_modulate = Palette.CASINO_BLACK
	gain.position = Vector3(0, CARD_Y + 0.25, 0)
	gain.visible = false
	root.add_child(gain)
	var talk := Label3D.new()
	talk.text = "TALKING"
	talk.font_size = 24
	talk.pixel_size = 0.0058
	talk.outline_size = 6
	talk.outline_modulate = Palette.CASINO_BLACK
	talk.modulate = Palette.MONEY_GREEN
	talk.position = Vector3(0, CARD_Y - 0.82, 0.1)
	talk.visible = false
	root.add_child(talk)
	var light := SpotLight3D.new()
	light.name = "Spot"
	light.position = Vector3(s * 0.8, 7.0, 3.2)
	light.spot_range = 12.0
	light.spot_angle = 16.0
	light.spot_attenuation = 0.6
	light.light_energy = 0.0
	light.light_color = WARM_LIGHT
	light.shadow_enabled = true
	root.add_child(light)
	if light.is_inside_tree():
		light.look_at(root.to_global(Vector3(0, 1.6, 0)))
	return {"root": root, "body_mat": body_mat, "stripe_mat": stripe_mat, "name": name_l, "score": score,
		"card": card, "card_mat": card_mat, "card_label": card_label, "gain": gain, "light": light, "talk": talk}


func _build_seat(pid: int, idx: int) -> void:
	var s: float = 1.0 if idx % 2 == 0 else -1.0
	var slot: int = idx >> 1
	var seat := Node3D.new()
	seat.name = "Seat%d" % pid
	seat.position = Vector3(s * (SEAT_X0 + SEAT_STEP * slot), SEAT_Y + 0.06, SEAT_Z)
	seat.rotation.y = PI - s * 0.45  # face the camera, turned in towards the podiums (−Z is the bean's front)
	add_child(seat)
	var bean := AvatarVisuals.new()
	bean.scale = Vector3.ONE * AUDIENCE_SCALE
	seat.add_child(bean)
	bean.set_color(Palette.bean_color(state.players.get(pid, {"color": pid - 1})))
	bean.set_outfit(Cosmetics.outfit_of(state.players.get(pid, {})))
	var puppet: BeanPuppet = BeanPuppet.attach(bean)
	puppet.cheer_height = 0.2
	var tag := Label3D.new()
	tag.text = _short(state.player_name(pid))
	tag.font_size = 30
	tag.pixel_size = 0.0055
	tag.outline_size = 6
	tag.outline_modulate = Palette.CASINO_BLACK
	tag.modulate = Palette.VIP_GOLD if pid == local_id else Palette.CREAM.darkened(0.1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(s * (SEAT_X0 + SEAT_STEP * slot), SEAT_Y + 0.1, SEAT_Z + 0.52)
	add_child(tag)
	beans[pid] = {"bean": bean, "puppet": puppet, "seat": seat, "seat_label": tag}
	if pid == local_id:
		you_marker = Node3D.new()
		you_marker.name = "YourSeat"
		you_marker.position = seat.position + Vector3(0, -0.02, 0)
		add_child(you_marker)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.34
		tm.outer_radius = 0.44
		ring.mesh = tm
		ring.material_override = _mat(Palette.VIP_GOLD, 0.0, true)
		you_marker.add_child(ring)
		var you := Label3D.new()
		you.text = "YOU"
		you.font_size = 34
		you.pixel_size = 0.0055
		you.outline_size = 8
		you.outline_modulate = Palette.CASINO_BLACK
		you.modulate = Palette.VIP_GOLD
		you.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		you.position = Vector3(0, 1.45, 0)
		you_marker.add_child(you)


func _build_lights() -> void:
	var key := SpotLight3D.new()
	key.name = "Key"
	key.position = Vector3(0, 9, 7)
	key.spot_range = 22.0
	key.spot_angle = 48.0
	key.light_energy = 2.2
	key.light_color = WARM_LIGHT
	key.shadow_enabled = true
	add_child(key)
	key.look_at(to_global(Vector3(0, 1.0, 0)))
	var curtain_wash := SpotLight3D.new()
	curtain_wash.position = Vector3(0, 2.0, 2.0)
	curtain_wash.spot_range = 14.0
	curtain_wash.spot_angle = 55.0
	curtain_wash.light_energy = 1.4
	curtain_wash.light_color = Palette.VIP_GOLD
	add_child(curtain_wash)
	curtain_wash.look_at(to_global(Vector3(0, 6.5, -5.0)))
	for sx: float in [-6.5, 6.5]:
		var fill := OmniLight3D.new()
		fill.position = Vector3(sx, 3.5, 4.0)
		fill.omni_range = 9.0
		fill.light_energy = 1.1
		fill.light_color = Palette.VIP_GOLD
		add_child(fill)
	var host_light := SpotLight3D.new()
	host_light.position = Vector3(0, 6.0, 2.5)
	host_light.spot_range = 10.0
	host_light.spot_angle = 14.0
	host_light.light_energy = 2.5
	host_light.light_color = WARM_LIGHT
	add_child(host_light)
	host_light.look_at(to_global(Vector3(0, 1.6, -1.4)))


func _mat(c: Color, metallic: float = 0.0, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.45 if metallic > 0.0 else 0.8
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, c: Color, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c, metallic)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node, top: float, bottom: float, height: float, pos: Vector3, c: Color, metallic: float = 0.0, segments: int = 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(c, metallic)
	parent.add_child(mi)
	return mi


# --- Building: the overlay --------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	ui.add_child(root)

	# Top centre: match counter, phase + timer, the result line.
	var head := VBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	head.anchor_left = 0.5
	head.anchor_right = 0.5
	head.offset_left = -460
	head.offset_right = 460
	head.offset_top = 192
	head.add_theme_constant_override(&"separation", 2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	phase_label = _label("", 54, Palette.CREAM)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_override(&"font", load("res://assets/fonts/BarlowCondensed-Black.ttf") as Font)
	phase_label.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	phase_label.add_theme_constant_override(&"outline_size", 12)
	head.add_child(phase_label)
	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(0, 12)
	timer_bar.value = 100.0
	timer_bar.visible = false
	timer_fill = StyleBoxFlat.new()
	timer_fill.bg_color = Palette.WARM_GOLD
	timer_fill.set_corner_radius_all(6)
	timer_bar.add_theme_stylebox_override(&"fill", timer_fill)
	var tbg := StyleBoxFlat.new()
	tbg.bg_color = Color(0, 0, 0, 0.55)
	tbg.set_corner_radius_all(6)
	timer_bar.add_theme_stylebox_override(&"background", tbg)
	head.add_child(timer_bar)
	result_label = _label("", 34, Palette.CREAM)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(920, 0)
	result_label.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	result_label.add_theme_constant_override(&"outline_size", 10)
	result_label.visible = false
	head.add_child(result_label)

	# Bottom centre: the big buttons (the pair) or the status pill (the audience).
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -520
	bottom.offset_right = 520
	bottom.offset_bottom = -18
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override(&"separation", 10)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	button_row = HBoxContainer.new()
	button_row.add_theme_constant_override(&"separation", 40)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.visible = false
	bottom.add_child(button_row)
	for c: String in [SPLIT, STEAL]:
		button_row.add_child(_choice_button(c))
	status_panel = PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = PANEL_BG
	ssb.set_corner_radius_all(30)
	ssb.set_border_width_all(3)
	ssb.border_color = Palette.WARM_GOLD
	ssb.content_margin_left = 34
	ssb.content_margin_right = 34
	ssb.content_margin_top = 10
	ssb.content_margin_bottom = 12
	status_panel.add_theme_stylebox_override(&"panel", ssb)
	status_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.visible = false
	bottom.add_child(status_panel)
	status_label = _label("", 28, Palette.CREAM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_panel.add_child(status_label)
	var legend := _label("Both SPLIT: +1 each   ·   STEAL vs SPLIT: +3 / +0   ·   Both STEAL: +0", 18, Palette.CREAM.darkened(0.2))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	legend.add_theme_constant_override(&"outline_size", 6)
	bottom.add_child(legend)

	# Top left: this round's duels. Top right: standings.
	var left := _side_panel(root, "EVERYONE VS EVERYONE", true)
	round_title = left.get_child(0) as Label
	round_box = VBoxContainer.new()
	round_box.name = "RoundBox"
	round_box.add_theme_constant_override(&"separation", 2)
	left.add_child(round_box)
	standings = MinigameScoreboard.new("STANDINGS", "fewer steals breaks ties").bind(state, local_id)
	standings.anchor_left = 1.0
	standings.anchor_right = 1.0
	standings.offset_left = -400.0
	standings.offset_right = -20.0
	standings.offset_top = 20.0
	root.add_child(standings)
	standings.add_footer(_voice_hint())

	# Lucky's speech bubble (follows the host on screen).
	bubble = PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Palette.CREAM
	bsb.set_corner_radius_all(18)
	bsb.set_border_width_all(3)
	bsb.border_color = Palette.WARM_GOLD
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
	bubble_label = _label("", 24, Palette.CASINO_BLACK)
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_label.custom_minimum_size = Vector2(300, 0)
	bubble.add_child(bubble_label)


## A big game-show button: the word, a one-line promise, the keys.
func _choice_button(c: String) -> Button:
	var b := Button.new()
	b.name = c.capitalize() + "Button"
	b.custom_minimum_size = Vector2(400, 116)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = true
	_style_button(b, SPLIT_COLOR if c == SPLIT else STEAL_COLOR)
	b.pressed.connect(_on_choice.bind(c))
	choice_buttons[c] = b
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", -6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var word: Label = _label(c, 60, Palette.CREAM)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_font_override(&"font", load("res://assets/fonts/BarlowCondensed-Black.ttf") as Font)
	word.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	word.add_theme_constant_override(&"outline_size", 8)
	v.add_child(word)
	var sub: Label = _label(("share the pot  ·  1 / A" if c == SPLIT else "take it all  ·  2 / B"), 22, Palette.CREAM.darkened(0.1))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	return b


func _side_panel(root: Control, title: String, left: bool) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb: StyleBoxFlat = TableSkin.panel_box()  # matches the shared scoreboard opposite
	p.draw.connect(TableSkin.draw_frame.bind(p))
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override(&"panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.0 if left else 1.0
	p.anchor_right = p.anchor_left
	p.offset_left = 20.0 if left else -400.0
	p.offset_right = 400.0 if left else -20.0
	p.offset_top = 20.0
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	p.add_child(v)
	v.add_child(_label(title, 22, Palette.WARM_GOLD))
	return v


func _voice_hint() -> String:
	if VoiceChannel.current == null:
		return "Voice chat is off here: plead with emotes."
	var mode: String = VoiceChannel.current.mode_key()
	if mode == "off":
		return "Your mic is off (Settings → Voice). Everyone can still talk to you."
	if mode == "open_mic":
		return "Mic open: everyone hears everyone during the show."
	return "Hold %s to talk: everyone hears everyone during the show." % Settings.binding_label(&"push_to_talk")


func _label(text: String, size: int, color: Color, min_w: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_w > 0.0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _tag(text: String, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	p.add_theme_stylebox_override(&"panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_label(text, 15, Palette.CREAM))
	return p


func _dot(c: Color, px: int) -> ColorRect:
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = c
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


func _style_button(b: Button, color: Color) -> void:
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.12) if st == "hover" else color.darkened(0.4) if st == "disabled" else color
		sb.set_corner_radius_all(22)
		sb.set_border_width_all(5)
		sb.border_color = Palette.VIP_GOLD if st != "disabled" else Palette.WARM_GOLD.darkened(0.45)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 5)
		if st == "pressed":
			sb.border_color = Palette.CREAM
		b.add_theme_stylebox_override(st, sb)


## A little scale "pop" on a control.
func _pop(c: Control, to: float = 1.0, from: float = 0.85) -> void:
	if c == null or _headless or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5 if c != bubble else Vector2(c.size.x * 0.5, c.size.y)
	c.scale = Vector2(from, from)
	var tw: Tween = c.create_tween()
	tw.tween_property(c, "scale", Vector2(to, to), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pop3d(n: Node3D) -> void:
	if n == null or _headless or not n.is_inside_tree():
		return
	n.scale = Vector3.ONE * 0.7
	var tw: Tween = n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
