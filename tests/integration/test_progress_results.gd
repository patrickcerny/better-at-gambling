extends GutTest
## The results event carries the XP/Coins breakdown (docs/GDD.md "Progression"): the server
## computes a row per player from the match (placement, minigames won, money, hands), every
## client gets the same rows and a match id, the snapshot repeats them for late joiners, and a
## client's profile adds only its own row, exactly once.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3)
	fx.server.start_match()
	fx.run(3.1)
	fx.place_all()
	ProfileManager.reload()  # in memory under GUT: a fresh profile


func after_each() -> void:
	fx.server.free()
	ProfileManager.reload()


func _ended() -> Dictionary:
	var ended: Array[Dictionary] = fx.of_type(&"match_ended")
	assert_eq(ended.size(), 1)
	return ended[0] if not ended.is_empty() else {}


func test_match_ended_carries_a_row_per_player() -> void:
	var p1: int = fx.player_ids[0]
	fx.server.stats[p1]["hands"] = 9  # as if 9 table rounds were played
	fx.server.run_to_end()
	var ev: Dictionary = _ended()
	var progress: Dictionary = ev.get("progress", {})
	assert_eq(progress.size(), 3, "every player has a row")
	assert_ne(str(ev.get("match_id", "")), "", "a match id to apply it once")
	for row: Variant in ev["standings"]:
		var pid: int = int(row["player"])
		var mine: Dictionary = progress[pid]
		assert_eq(int(mine["rank"]), int(row["rank"]), "placement from the standings")
		assert_true(bool(mine["practice"]), "no online room: Practice rate")
		var sum: int = 0
		for part: Dictionary in mine["parts"]:
			sum += int(part["xp"])
		assert_eq(int(mine["xp"]), sum, "the total is the parts")
		assert_eq(int(mine["coins"]), Progression.coins_for_xp(ProgressionConfig.default(), int(mine["xp"])))
	var hands: Array = (progress[p1]["parts"] as Array).filter(func(p: Dictionary) -> bool: return p["id"] == &"hands")
	assert_eq(hands.size(), 1)
	assert_eq(int(hands[0]["xp"]), 9, "9 hands × 2 XP, at half rate")
	# Two quizzes ran: someone won them, and that shows.
	var won: int = 0
	for pid: int in fx.player_ids:
		won += int(fx.server.stats[pid]["minigames_won"])
	assert_gte(won, 2, "each minigame's winner counted")
	assert_true(Serializer.is_wire_safe(ev), "the rows travel over the wire")
	var snap: Dictionary = fx.server.get_snapshot()
	assert_eq((snap.get("progress", {}) as Dictionary).size(), 3, "late joiners see the rows too")
	assert_eq(snap.get("match_id", ""), ev["match_id"])


func test_an_online_room_earns_full_rate() -> void:
	fx.server.room_mode = true
	fx.server.run_to_end()
	var row: Dictionary = _ended()["progress"][fx.player_ids[0]]
	assert_false(bool(row["practice"]))
	var match_part: Dictionary = (row["parts"] as Array)[0]
	assert_eq(int(match_part["xp"]), ProgressionConfig.default().xp_match)


func test_the_client_profile_applies_its_own_row_once() -> void:
	fx.server.run_to_end()
	var ev: Dictionary = bytes_to_var(var_to_bytes(_ended()))  # as a client receives it
	var me: int = fx.player_ids[1]
	var row: Dictionary = ev["progress"][me]
	var changed: Array[int] = [0]
	var count: Callable = func() -> void: changed[0] += 1
	ProfileManager.changed.connect(count)
	var got: Dictionary = ProfileManager.apply_results(ev, me)
	assert_eq(int(got["xp"]), int(row["xp"]))
	assert_eq(ProfileManager.profile.xp, int(row["xp"]))
	assert_eq(ProfileManager.profile.coins, int(row["coins"]) + int(got["level_bonus"]))
	assert_eq(ProfileManager.profile.matches, 1)
	assert_eq(changed[0], 1)
	assert_eq(ProfileManager.apply_results(ev, me), {}, "the same event again (a replay) adds nothing")
	assert_eq(ProfileManager.profile.matches, 1)
	assert_eq(ProfileManager.profile.xp, int(row["xp"]))
	assert_eq(ProfileManager.apply_results(ev, 99), {}, "no row for a spectator")
	assert_eq(changed[0], 1)
	ProfileManager.changed.disconnect(count)
	# The client mirror keeps the rows for the results screen.
	var mirror := ClientMatchState.new()
	mirror.apply_event(ev)
	assert_eq(mirror.progress.size(), 3)
	assert_eq(mirror.match_id, str(ev["match_id"]))
