class_name SplitOrStealStage
extends MinigameStage
## Client presentation of the Split or Steal show (§2.9): a 3D game-show set like the quiz's. A
## burgundy curtain backdrop, two podiums front and centre for the pair on stage (their beans,
## names and colours on the podium fronts, a choice card over each head), Lucky the host between
## them at a lectern, spotlights on the pair, and everyone else sitting in two audience rows at the
## sides (the local player's seat ringed in gold). One match at a time: ANNOUNCE (the pair hops up
## to the podiums) → DECIDE (SPLIT / STEAL, keys 1 / 2 or pad A / B, only for the two on stage;
## "LOCKED IN" cards show who decided, never what) → REVEAL (both cards flip up with the payout,
## the beans cheer or sulk, the host reacts).
##
## 2D overlay (1920×1080 base): match counter, phase and timer at the top; the show's schedule
## with every revealed result top left; standings top right; the host's speech bubble; the big
## SPLIT / STEAL buttons at the bottom for the pair, "Waiting for X vs Y" for the audience.
## Everything comes from events, the public snapshot and our private state, which also carries
## the pair on stage so a stage built after the first events (behind the curtain) still catches up.

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

enum Step { WAITING, INTRO, ANNOUNCE, DECIDE, REVEAL, OUTRO }

var players: Array[int] = []
var phase: Step = Step.WAITING
var schedule: Array = []
var pair_index: int = -1
var total: int = 0
## The pair on stage ([] between matches) and which of them plays for the house (NOBODY).
var pair: Array[int] = []
var house: int = NOBODY
var announce_time: float = SplitOrStealLogic.ANNOUNCE_TIME
var decide_time: float = SplitOrStealLogic.DECIDE_TIME
var time_left: float = 0.0
var phase_length: float = 1.0
var points: Dictionary = {}
var steals: Dictionary = {}
var locked: Dictionary = {}
var can_choose: bool = false
var my_choice: String = ""
## The last revealed match (see `SplitOrStealLogic._score_pair`), {} while none is shown.
var last_result: Dictionary = {}
var ranking_rows: Array = []

## player → {bean: AvatarVisuals, puppet: BeanPuppet, seat: Node3D}
var beans: Dictionary[int, Dictionary] = {}
## Per podium side (0 = left, 1 = right): {root, body_mat, stripe_mat, name, score, card,
## card_mat, card_label, gain, light, talk}.
var podiums: Array[Dictionary] = []
var host: QuizHost
var you_marker: Node3D

## The match counter, on the show sign.
var header_label: Label3D
var phase_label: Label
var timer_bar: ProgressBar
var timer_fill: StyleBoxFlat
var result_label: Label
var status_panel: PanelContainer
var status_label: Label
var button_row: HBoxContainer
var choice_buttons: Dictionary[String, Button] = {}
var schedule_box: VBoxContainer
var standings: VBoxContainer
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
	_host_say("Welcome to Split or Steal! One pair at a time...", QuizHost.Pose.HAPPY)
	Audio.play(&"announcer_opening", &"UI", -2.0)
	_refresh_all()


func _process(delta: float) -> void:
	if phase == Step.DECIDE or phase == Step.ANNOUNCE:
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
			_set_schedule(ev.get("schedule", []))
			announce_time = float(ev.get("announce_time", announce_time))
			decide_time = float(ev.get("decide_time", decide_time))
			phase = Step.INTRO
			_set_phase_text("SPLIT OR STEAL", Palette.VIP_GOLD)
			var each: int = int(ev.get("matches_each", 1))
			_show_result("%d match%s, one pair at a time" % [total, "" if total == 1 else "es"], Palette.CREAM)
			_host_say("Tonight: %d match%s! Everyone plays %s." % [total, "" if total == 1 else "es", "once" if each == 1 else "%d times" % each], QuizHost.Pose.HAPPY)
			_refresh_all()
		&"split_or_steal_pair":
			_set_pair(int(ev.get("index", 0)), [int(ev.get("a", NOBODY)), int(ev.get("b", NOBODY))], int(ev.get("house", NOBODY)))
			total = maxi(total, int(ev.get("total", total)))
			announce_time = float(ev.get("announce_time", announce_time))
			decide_time = float(ev.get("decide_time", decide_time))
			_enter_announce(announce_time, true)
		&"split_or_steal_decide":
			if int(ev.get("index", pair_index)) == pair_index:
				_enter_decide(float(ev.get("decide_time", decide_time)))
		&"split_or_steal_locked":
			if int(ev.get("index", pair_index)) == pair_index:
				_mark_locked(int(ev.get("player", NOBODY)))
		&"split_or_steal_reveal":
			points = _int_keys(ev.get("points", points))
			steals = _int_keys(ev.get("steals", steals))
			_show_reveal(ev, true)
		&"split_or_steal_finished":
			ranking_rows = ev.get("ranking", [])
			_show_final(true)


## Late join / reconnect: the public snapshot (see `SplitOrStealLogic.get_public_state`).
func apply_state(st: Dictionary) -> void:
	_set_schedule(st.get("schedule", []))
	total = int(st.get("total", total))
	announce_time = float(st.get("announce_time", announce_time))
	decide_time = float(st.get("decide_time", decide_time))
	points = _int_keys(st.get("points", {}))
	steals = _int_keys(st.get("steals", {}))
	var idx: int = int(st.get("index", -1))
	var s: int = int(st.get("state", -1))
	var timer: float = float(st.get("timer", 0.0))
	if idx >= 0 and idx < schedule.size() and s in [SplitOrStealLogic.State.ANNOUNCE, SplitOrStealLogic.State.DECIDE, SplitOrStealLogic.State.REVEAL]:
		var e: Dictionary = schedule[idx]
		_set_pair(idx, [int(e["a"]), int(e["b"])], int(e.get("house", NOBODY)), false)
		for p: Variant in st.get("locked", []):
			locked[int(p)] = true
		match s:
			SplitOrStealLogic.State.ANNOUNCE:
				_enter_announce(timer, false)
			SplitOrStealLogic.State.DECIDE:
				_enter_decide(decide_time, timer)
			SplitOrStealLogic.State.REVEAL:
				var r: Dictionary = (e.get("result", {}) as Dictionary).duplicate()
				r["index"] = idx
				_show_reveal(r, false)
		for p: int in locked:
			_mark_locked(p, false)
	elif s == SplitOrStealLogic.State.INTRO:
		phase = Step.INTRO
	elif s == SplitOrStealLogic.State.OUTRO or s == SplitOrStealLogic.State.DONE:
		ranking_rows = st.get("ranking", [])
		_show_final(false)
	can_choose = phase == Step.DECIDE and local_id in pair and not locked.has(local_id)
	_refresh_all()


## Our private minigame state, every frame. Besides our buttons it names the pair on stage: when
## an event went missing (the stage is built behind the curtain, after the show may have begun)
## the stage catches up from it instead of showing an empty match.
func on_private(priv: Dictionary) -> void:
	var mine: Dictionary = priv.get("minigame", {})
	if mine.is_empty() or not mine.has("index"):
		return
	var idx: int = int(mine.get("index", -1))
	var s: int = int(mine.get("state", -1))
	var their_pair: Array = mine.get("pair", [])
	if idx > pair_index and their_pair.size() == 2 and s in [SplitOrStealLogic.State.ANNOUNCE, SplitOrStealLogic.State.DECIDE]:
		_set_pair(idx, [int(their_pair[0]), int(their_pair[1])], int(mine.get("house", NOBODY)))
		_enter_announce(float(mine.get("timer", 0.0)) if s == SplitOrStealLogic.State.ANNOUNCE else 0.0, false)
	if idx != pair_index:
		return  # stale, or a reveal / the end we wait for the event of
	if s == SplitOrStealLogic.State.DECIDE and (phase == Step.ANNOUNCE or phase == Step.WAITING or phase == Step.INTRO):
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

func _set_schedule(s: Variant) -> void:
	if not (s is Array) or (s as Array).is_empty():
		return
	schedule = []
	for e: Variant in s:
		var d: Dictionary = e
		schedule.append({"a": int(d.get("a", NOBODY)), "b": int(d.get("b", NOBODY)), "house": int(d.get("house", NOBODY)), "result": d.get("result", {})})
	total = schedule.size()


## Puts match `idx` on stage: the two beans go up to the podiums, everyone else to their seats.
func _set_pair(idx: int, p: Array, p_house: int, animate: bool = true) -> void:
	var next: Array[int] = []
	for x: Variant in p:
		next.append(int(x))
	var fresh: bool = idx != pair_index or pair.size() != next.size() or (not next.is_empty() and (pair[0] != next[0] or pair[1] != next[1]))
	pair_index = idx
	pair = next
	house = p_house
	while schedule.size() <= idx:
		schedule.append({"a": NOBODY, "b": NOBODY, "house": NOBODY, "result": {}})
	schedule[idx]["a"] = pair[0]
	schedule[idx]["b"] = pair[1]
	schedule[idx]["house"] = house
	total = maxi(total, schedule.size())
	if fresh:
		locked.clear()
		my_choice = ""
		can_choose = false
		last_result = {}
		for pd: Dictionary in podiums:
			(pd["gain"] as Label3D).visible = false
	for pid: int in beans:
		var side: int = pair.find(pid)
		_seat_bean(pid, side, animate and fresh)
	for side: int in 2:
		_dress_podium(side)
	_refresh_all()


func _enter_announce(remaining: float, live: bool) -> void:
	phase = Step.ANNOUNCE
	phase_length = maxf(announce_time, 0.01)
	time_left = remaining
	timer_bar.visible = false
	_set_phase_text("MATCH %d" % (pair_index + 1), Palette.VIP_GOLD)
	var a: String = state.player_name(pair[0])
	var b: String = state.player_name(pair[1])
	_show_result("%s  vs  %s" % [a, b], Palette.CREAM)
	if house != NOBODY:
		_host_say("Bonus match! %s steps in for the house: only %s can score." % [state.player_name(house), state.player_name(_other(house))], QuizHost.Pose.SURPRISED)
	elif local_id in pair:
		_host_say("You're up, %s! Facing %s." % [state.player_name(local_id), state.player_name(_other(local_id))], QuizHost.Pose.SURPRISED)
	else:
		_host_say("Up next: %s and %s!" % [a, b], QuizHost.Pose.HAPPY)
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
	can_choose = local_id in pair and not locked.has(local_id)
	if local_id in pair:
		_show_result("Talk %s into splitting. Or don't." % state.player_name(_other(local_id)), Palette.CREAM)
	else:
		_show_result("", Palette.CREAM)
	_host_say("Split... or steal? Make your case!", QuizHost.Pose.DRUMROLL, 0.0)
	for side: int in 2:
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
	_refresh_buttons()
	_refresh_schedule()


func _show_reveal(r: Dictionary, live: bool) -> void:
	if r.is_empty() or not r.has("choice_a"):
		return
	var idx: int = int(r.get("index", pair_index))
	if idx != pair_index or pair.size() < 2 or int(r["a"]) != pair[0]:
		_set_pair(idx, [int(r["a"]), int(r["b"])], int(r.get("house", NOBODY)), false)
	phase = Step.REVEAL
	can_choose = false
	timer_bar.visible = false
	last_result = r
	if idx >= 0 and idx < schedule.size():
		schedule[idx]["result"] = r.duplicate()
	_set_phase_text("THE REVEAL", Palette.VIP_GOLD)
	var ca: String = str(r["choice_a"])
	var cb: String = str(r["choice_b"])
	var pa: int = int(r["points_a"])
	var pb: int = int(r["points_b"])
	var choices: Array[String] = [ca, cb]
	var gains: Array[int] = [pa, pb]
	for side: int in 2:
		var c: String = choices[side]
		var auto: bool = bool(r.get("auto_a" if side == 0 else "auto_b", false))
		_flip_card(side, c + ("*" if auto else ""), _choice_color(c), live)
		var gain: Label3D = podiums[side]["gain"]
		var pid: int = pair[side]
		if pid == house:
			gain.text = "for the house"
			gain.modulate = MUTED
		else:
			gain.text = "+%d" % gains[side]
			gain.modulate = Palette.MONEY_GREEN if gains[side] > 0 else Palette.LOSS_RED
		gain.visible = true
		_react(pid, c, choices[1 - side])
	var na: String = state.player_name(pair[0])
	var nb: String = state.player_name(pair[1])
	var line: String
	var color: Color
	var pose: QuizHost.Pose
	if ca == SPLIT and cb == SPLIT:
		line = "BOTH SPLIT!  +%d each" % SplitOrStealLogic.POINTS_BOTH_SPLIT if house == NOBODY else "BOTH SPLIT!"
		color = Palette.MONEY_GREEN
		pose = QuizHost.Pose.HAPPY
		_host_say("How wholesome. Trust wins!", pose)
	elif ca == STEAL and cb == STEAL:
		line = "BOTH STEAL!  Nobody gets a thing"
		color = Palette.LOSS_RED
		pose = QuizHost.Pose.DISAPPOINTED
		_host_say("Two thieves, empty pockets.", pose)
	else:
		var thief: String = na if ca == STEAL else nb
		var victim: String = nb if ca == STEAL else na
		line = "%s STEALS FROM %s!" % [thief.to_upper(), victim.to_upper()]
		color = Palette.VIP_GOLD
		pose = QuizHost.Pose.SURPRISED
		_host_say("Ooh! %s never saw it coming." % victim, pose)
	if bool(r.get("auto_a", false)) or bool(r.get("auto_b", false)):
		line += "   (* too slow: counted as SPLIT)"
	_show_result(line, color)
	_pop(result_label, 1.0, 0.7)
	if live:
		Audio.play(&"card_flip", &"UI", -4.0)
		var mine: int = pair.find(local_id)
		if mine >= 0 and pair[mine] != house:
			Audio.play(&"cash_register" if gains[mine] > 0 else &"buzzer", &"UI", -6.0)
		elif ca == STEAL or cb == STEAL:
			Audio.play(&"buzzer", &"UI", -12.0)
	_refresh_all()


func _show_final(live: bool) -> void:
	phase = Step.OUTRO
	can_choose = false
	timer_bar.visible = false
	last_result = {}
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
	if bean.get_parent() != target:
		bean.get_parent().remove_child(bean)
		target.add_child(bean)
	if side >= 0:
		bean.position = Vector3(0, PODIUM_TOP, 0)
		bean.scale = Vector3.ONE
		bean.rotation = Vector3(0, PI - 0.18 * (1.0 if side == 0 else -1.0), 0)  # face out, a little towards each other
	else:
		bean.position = Vector3.ZERO
		bean.scale = Vector3.ONE * AUDIENCE_SCALE
		bean.rotation = Vector3.ZERO
	puppet.base = bean.position
	puppet.set_mood(BeanPuppet.Mood.IDLE)
	if animate and side >= 0 and not _headless:
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
	var sub: Label3D = pd["score"]
	if not on:
		sub.text = ""
	elif pid == house:
		sub.text = "FOR THE HOUSE"
	else:
		sub.text = ("YOU · %d pts" if pid == local_id else "%d pts") % _pts(pid)
	(pd["light"] as SpotLight3D).light_energy = 5.0 if on else 0.0
	(pd["card"] as Node3D).visible = on and phase != Step.OUTRO
	if phase != Step.REVEAL:
		(pd["gain"] as Label3D).visible = false
	if on and phase in [Step.ANNOUNCE, Step.DECIDE] and not locked.has(pid):
		_set_card(side, "?", Palette.WARM_CHARCOAL, Palette.CREAM.darkened(0.2))


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
	if pid == house:
		bean.react(&"surprise")
		return
	if mine == STEAL and theirs == SPLIT:
		puppet.set_mood(BeanPuppet.Mood.CHEER)
		bean.react(&"big_win")
		if not _headless:
			ConfettiBurst.burst(bean.get_parent() as Node3D, Vector3(0, 2.8, 0), 90, 1.0)
	elif mine == SPLIT and theirs == SPLIT:
		puppet.set_mood(BeanPuppet.Mood.CHEER)
		bean.react(&"win")
	else:
		puppet.set_mood(BeanPuppet.Mood.SAD)
		bean.react(&"loss")


## Lights "TALKING" under the card of whoever on stage is audibly speaking (voice is global).
func _update_talk() -> void:
	var vc: VoiceChannel = VoiceChannel.current
	for side: int in podiums.size():
		var on: bool = side < pair.size() and vc != null and vc.is_talking(pair[side])
		(podiums[side]["talk"] as Label3D).visible = on


func _other(pid: int) -> int:
	if pair.size() < 2:
		return NOBODY
	return pair[1] if pair[0] == pid else pair[0]


# --- 2D overlay -------------------------------------------------------------------------------

func _refresh_all() -> void:
	if phase_label == null:
		return
	_refresh_header()
	_refresh_buttons()
	_refresh_schedule()
	_refresh_standings()
	for side: int in podiums.size():
		var pd: Dictionary = podiums[side]
		if side < pair.size():
			var pid: int = pair[side]
			(pd["score"] as Label3D).text = "FOR THE HOUSE" if pid == house else ("YOU · %d pts" if pid == local_id else "%d pts") % _pts(pid)


func _refresh_header() -> void:
	if header_label == null:
		return
	if pair_index >= 0 and total > 0 and phase != Step.OUTRO:
		header_label.text = "MATCH %d / %d" % [mini(pair_index + 1, total), total]
	else:
		header_label.text = "TONIGHT'S SHOW" if phase != Step.OUTRO else "THAT'S A WRAP"


func _set_phase_text(text: String, color: Color) -> void:
	phase_label.text = text
	phase_label.add_theme_color_override(&"font_color", color)


func _show_result(text: String, color: Color) -> void:
	result_label.text = text
	result_label.visible = text != ""
	result_label.add_theme_color_override(&"font_color", color)


func _refresh_buttons() -> void:
	var on_stage: bool = local_id in pair and phase in [Step.ANNOUNCE, Step.DECIDE, Step.REVEAL]
	button_row.visible = on_stage and phase != Step.REVEAL
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
	if phase == Step.OUTRO or phase == Step.WAITING or phase == Step.INTRO:
		text = ""
	elif not on_stage and pair.size() == 2:
		var a: String = state.player_name(pair[0])
		var b2: String = state.player_name(pair[1])
		if phase == Step.REVEAL:
			text = "%s vs %s" % [a, b2]
		elif phase == Step.DECIDE:
			var n: int = int(locked.has(pair[0])) + int(locked.has(pair[1]))
			text = "Waiting for %s vs %s  ·  %d / 2 decided" % [a, b2, n]
		else:
			text = "Waiting for %s vs %s" % [a, b2]
	elif on_stage and phase == Step.ANNOUNCE:
		text = "Get ready: SPLIT or STEAL opens in a moment"
	elif on_stage and phase == Step.DECIDE:
		if my_choice != "":
			text = "You locked in %s. %s" % [my_choice, "Waiting for %s..." % state.player_name(_other(local_id)) if not locked.has(_other(local_id)) else "Here comes the reveal!"]
		elif local_id == house:
			text = "You play for the house: only %s can score" % state.player_name(_other(local_id))
		else:
			text = "Press 1 = SPLIT  ·  2 = STEAL" + ("   ·   %s has locked in!" % state.player_name(_other(local_id)) if locked.has(_other(local_id)) else "")
	status_label.text = text
	status_panel.visible = text != ""


func _refresh_schedule() -> void:
	if schedule_box == null:
		return
	for c: Node in schedule_box.get_children():
		schedule_box.remove_child(c)
		c.queue_free()
	if schedule.is_empty():
		schedule_box.add_child(_label("The pairs are drawn...", 20, MUTED))
		return
	for i: int in schedule.size():
		var e: Dictionary = schedule[i]
		var current: bool = i == pair_index and phase != Step.OUTRO
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.WARM_GOLD.darkened(0.55) if current else Color(0, 0, 0, 0.0)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		row.add_theme_stylebox_override(&"panel", sb)
		schedule_box.add_child(row)
		var v := VBoxContainer.new()
		v.add_theme_constant_override(&"separation", 0)
		row.add_child(v)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 6)
		v.add_child(h)
		var done: bool = not (e["result"] as Dictionary).is_empty()
		h.add_child(_label(str(i + 1), 20, Palette.VIP_GOLD if current else MUTED, 22))
		for k: String in ["a", "b"]:
			var pid: int = int(e[k])
			if k == "b":
				h.add_child(_label("vs", 18, MUTED))
			h.add_child(_dot(_player_color(pid), 12))
			var n: Label = _label(_short(state.player_name(pid)) if pid != NOBODY else "?", 22, Palette.VIP_GOLD if pid == local_id else Palette.CREAM)
			h.add_child(n)
		if int(e["house"]) != NOBODY:
			h.add_child(_label("bonus", 16, Palette.WARM_GOLD))
		var r: Dictionary = e["result"]
		if done:
			var res := HBoxContainer.new()
			res.add_theme_constant_override(&"separation", 8)
			res.add_child(_label("", 16, MUTED, 22))
			res.add_child(_tag(str(r["choice_a"]), _choice_color(str(r["choice_a"]))))
			res.add_child(_label(_gain_text(int(r["a"]), int(r["points_a"]), int(r.get("house", NOBODY))), 18, Palette.CREAM.darkened(0.1)))
			res.add_child(_tag(str(r["choice_b"]), _choice_color(str(r["choice_b"]))))
			res.add_child(_label(_gain_text(int(r["b"]), int(r["points_b"]), int(r.get("house", NOBODY))), 18, Palette.CREAM.darkened(0.1)))
			v.add_child(res)
		elif current and phase == Step.DECIDE:
			var st := HBoxContainer.new()
			st.add_theme_constant_override(&"separation", 8)
			st.add_child(_label("", 16, MUTED, 22))
			for k: String in ["a", "b"]:
				var pid: int = int(e[k])
				st.add_child(_label("decided" if locked.has(pid) else "thinking...", 16, Palette.VIP_GOLD if locked.has(pid) else MUTED))
			v.add_child(st)


func _gain_text(pid: int, pts: int, p_house: int) -> String:
	return "house" if pid == p_house else "+%d" % pts


func _refresh_standings() -> void:
	if standings == null:
		return
	for c: Node in standings.get_children():
		standings.remove_child(c)
		c.queue_free()
	var rows: Array = players.duplicate()
	rows.sort_custom(func(a: int, b: int) -> bool:
		if _pts(a) != _pts(b):
			return _pts(a) > _pts(b)
		if _stl(a) != _stl(b):
			return _stl(a) < _stl(b)
		return a < b)
	var place: int = 0
	for i: int in rows.size():
		var pid: int = rows[i]
		if i == 0 or _pts(pid) != _pts(rows[i - 1]) or _stl(pid) != _stl(rows[i - 1]):
			place = i + 1
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 8)
		h.add_child(_label(str(place), 22, Palette.VIP_GOLD if place == 1 else Palette.CREAM.darkened(0.25), 22))
		h.add_child(_dot(_player_color(pid), 14))
		var n: Label = _label(state.player_name(pid), 22, Palette.VIP_GOLD if pid == local_id else Palette.CREAM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(n)
		var on: bool = pid in pair and phase != Step.OUTRO
		var tag: Label = _label("ON STAGE" if on else "", 14, Palette.WARM_GOLD, 70)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(tag)
		var pts: Label = _label(str(_pts(pid)), 24, Palette.CREAM, 34)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(pts)
		var stl: Label = _label("%d stl" % _stl(pid), 14, Palette.LOSS_RED.lerp(Palette.CREAM, 0.3) if _stl(pid) > 0 else MUTED, 56)
		stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(stl)
		standings.add_child(h)


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
	return Palette.player_color(int(state.players.get(pid, {}).get("color", pid - 1)))


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
	seat.rotation.y = PI + s * 0.45  # face the camera, turned towards the podiums
	add_child(seat)
	var bean := AvatarVisuals.new()
	bean.scale = Vector3.ONE * AUDIENCE_SCALE
	seat.add_child(bean)
	bean.set_color(_player_color(pid))
	bean.set_skin(StringName(state.players.get(pid, {}).get("skin", "bean")))
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

	# Top left: the show's schedule. Top right: standings.
	var left := _side_panel(root, "THE SHOW", true)
	schedule_box = VBoxContainer.new()
	schedule_box.add_theme_constant_override(&"separation", 2)
	left.add_child(schedule_box)
	var right := _side_panel(root, "STANDINGS", false)
	standings = VBoxContainer.new()
	standings.add_theme_constant_override(&"separation", 2)
	right.add_child(standings)
	right.add_child(_label("Ties: fewer steals wins", 16, MUTED))
	var voice := _label(_voice_hint(), 16, MUTED)
	voice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voice.custom_minimum_size = Vector2(340, 0)
	right.add_child(voice)

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
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Palette.WARM_GOLD.darkened(0.2)
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
