extends GutTest
## HUD messages clear on time (Patrick, 0.9.16: "sometimes the doors should open text (or other
## text) dont disappear"): a toast goes after its seconds even when another replaces it half way
## or it is posted as the phase changes and the HUD hides and comes back; a banner that replaces
## another stays its own time and then goes; every feed line goes after its seconds, also when the
## feed is full and a line expires in the same frame; and the hall doors put up no text of their
## own (the 3-2-1 on the doors is enough; the spawn protection is a feed line), in the real match
## scene through a regroup.

var hud: Hud
var state: ClientMatchState


func before_each() -> void:
	state = ClientMatchState.new()
	state.players = {1: {"id": 1, "name": "A", "color": 0}}
	state.balances = {1: 1000}
	hud = Hud.new()
	add_child_autofree(hud)
	hud.bind(state, 1)
	await wait_process_frames(1)


## Waits up to `seconds` of process time for `cond`; true when it held in time.
func _wait_for(cond: Callable, seconds: float) -> bool:
	var t: float = 0.0
	while not cond.call() and t < seconds:
		await wait_process_frames(1)
		t += get_process_delta_time()
	return cond.call()


func test_a_toast_goes_after_its_seconds() -> void:
	hud.toast("Hello", 0.4)
	assert_true(hud.toast_label.visible)
	assert_eq(hud.toast_label.text, "Hello")
	assert_true(await _wait_for(func() -> bool: return not hud.toast_label.visible, 1.0), "gone after its 0.4 s")


func test_a_toast_replaced_half_way_goes_after_its_own_seconds() -> void:
	hud.toast("First", 2.0)
	await wait_seconds(0.3)
	hud.toast("Second", 0.4)
	assert_eq(hud.toast_label.text, "Second")
	assert_true(await _wait_for(func() -> bool: return not hud.toast_label.visible, 1.0), "the second goes after its own 0.4 s, not the first one's 2 s")
	# And a short one replaced by a long one stays the long one's time.
	hud.toast("Short", 0.2)
	await wait_seconds(0.1)
	hud.toast("Long", 0.8)
	await wait_seconds(0.4)
	assert_true(hud.toast_label.visible, "the long one is still up")
	assert_true(await _wait_for(func() -> bool: return not hud.toast_label.visible, 1.0))


func test_an_empty_toast_clears_at_once() -> void:
	hud.toast("Something", 3.0)
	hud.toast("", 0.0)
	assert_false(hud.toast_label.visible, "an empty toast is no toast")


func test_a_toast_posted_as_the_phase_changes_still_goes() -> void:
	# What the match scene does on the way into a minigame and back: the HUD hides, the phase
	# changes, a toast goes up, the HUD comes back.
	hud.toast("Bets returned: +$25", 0.5)
	hud.visible = false
	state.apply_event(GameEvents.make(&"phase_changed", {"phase": Phase.Id.MINIGAME, "from": Phase.Id.PRE_MINIGAME}))
	hud.toast("Into the minigame", 0.5)
	await wait_seconds(0.2)
	state.apply_event(GameEvents.make(&"phase_changed", {"phase": Phase.Id.REGROUP, "from": Phase.Id.REWARDS}))
	hud.visible = true
	hud.toast("Back in the hall", 0.5)
	state.apply_event(GameEvents.make(&"phase_changed", {"phase": Phase.Id.CASINO, "from": Phase.Id.REGROUP}))
	assert_true(hud.toast_label.visible)
	assert_true(await _wait_for(func() -> bool: return not hud.toast_label.visible, 1.2), "gone after its 0.5 s across the phase changes")


func test_a_banner_replaced_half_way_stays_its_own_time_then_goes() -> void:
	hud.banner("FIRST", Palette.VIP_GOLD, 0.6)
	await wait_seconds(0.5)
	hud.banner("SECOND", Palette.VIP_GOLD, 0.8)
	await wait_seconds(0.6)
	assert_true(hud.item_banner.visible and hud.item_banner.modulate.a > 0.9, "the first banner's fade does not take the second one down early")
	assert_eq(hud.item_banner.text, "SECOND")
	assert_true(await _wait_for(func() -> bool: return not hud.item_banner.visible, 2.0), "then it goes")


func test_every_feed_line_goes_after_its_seconds() -> void:
	for i: int in Hud.FEED_MAX:
		state.feed_message.emit("line %d" % i, &"info")
	assert_eq(hud.feed.get_child_count(), Hud.FEED_MAX)
	# The oldest lines run out while new ones push into the full feed in the same frames.
	await wait_seconds(Hud.FEED_SECONDS - 0.05)
	for i: int in 3:
		await wait_process_frames(1)
		state.feed_message.emit("late %d" % i, &"info")
		state.feed_message.emit("later %d" % i, &"info")
	assert_true(await _wait_for(func() -> bool: return hud.feed.get_child_count() == 0, Hud.FEED_SECONDS + 1.0), "every line goes, the last ones too (%d left)" % hud.feed.get_child_count())


func test_the_regroup_puts_up_no_door_text() -> void:
	state.apply_event(GameEvents.make(&"regroup_started", {"seconds": 5.0, "positions": {}, "floor_plan": {}}))
	state.apply_event(GameEvents.make(&"phase_changed", {"phase": Phase.Id.REGROUP, "from": Phase.Id.REWARDS}))
	await wait_process_frames(2)
	assert_false(hud.minigame_warning.visible, "the 3-2-1 on the doors is enough")
	state.lobby_settings = {"mode": MatchMode.MINIGAMES}
	await wait_process_frames(2)
	assert_true(hud.minigame_warning.visible, "minigames only: the next minigame's countdown stays")
	assert_string_starts_with(hud.minigame_warning.text, "Next minigame in")


## The real match scene through a regroup and back to the tables: no door toast, and the HUD's
## toast is down a moment after it was due.
func test_through_a_regroup_in_the_match_scene() -> void:
	Net.stop()
	MatchScene.test_dummies = 1
	MatchScene.test_briefing = 0.0
	MatchScene.test_curtain_fast = true
	var scene: MatchScene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	var t: float = 0.0
	while scene.server.phases.phase != Phase.Id.REGROUP and t < 900.0:
		scene.server.advance(MatchServer.TICK)
		t += MatchServer.TICK
	assert_eq(scene.server.phases.phase, Phase.Id.REGROUP)
	var seen: Array[String] = []
	var shown_for: float = 0.0
	var back: float = -1.0
	var fed: Array[String] = []
	t = 0.0
	while t < 12.0:
		await wait_process_frames(1)
		var dt: float = get_process_delta_time()
		t += dt
		var h: Hud = scene.hud
		if h.toast_label.visible:
			shown_for += dt
			if not h.toast_label.text in seen:
				seen.append(h.toast_label.text)
		else:
			shown_for = 0.0
		if h.minigame_warning.visible and not h.minigame_warning.text in seen:
			seen.append(h.minigame_warning.text)
		for line: Node in h.feed.get_children():
			if not (line as Label).text in fed:
				fed.append((line as Label).text)
		assert_lt(shown_for, 4.5, "no toast stays up (%s)" % h.toast_label.text)
		if back < 0.0 and scene.server.phases.phase == Phase.Id.CASINO:
			back = t
		if back >= 0.0 and t > back + 3.0:
			break
	assert_gt(back, 0.0, "the doors opened")
	for text: String in seen:
		assert_false(text.containsn("door"), "no door text: %s" % text)
	assert_false(scene.hud.toast_label.visible, "nothing left up after the doors opened")
	assert_true(fed.any(func(x: String) -> bool: return x.begins_with("Spawn protection")), "the spawn protection is a quiet feed line: %s" % [fed])
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = -1.0
	MatchScene.test_curtain_fast = false
