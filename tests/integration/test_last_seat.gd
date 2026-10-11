extends GutTest
## Last Seat at the Table on the authoritative server: the room opens in the parlor, a sit claim
## after the music stops seats the player (pinned on the stool, shove-proof) and refuses a second
## claimant, and whoever is left standing is eliminated and moved to the gallery.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9, "minigame_pool": "last_seat"})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()


func after_each() -> void:
	fx.server.free()


func _to_game() -> LastSeatLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	var g: LastSeatLogic = fx.server.minigame as LastSeatLogic
	assert_not_null(g, "Last Seat is running")
	t = 0.0
	while fx.server.in_briefing() and t < 60.0:
		fx.run(0.5)
		t += 0.5
	fx.run(0.1)
	return g


## The server's own position for `p`, `dist` metres out from stool `i`.
func _near(g: LastSeatLogic, p: int, i: int, dist: float = 1.0) -> void:
	var out: Vector3 = (g.stools[i] - ParlorRoom.table_center()).normalized()
	fx.server.world.set_transform(p, g.stools[i] + out * dist, 0.0)


func test_room_opens_in_the_parlor() -> void:
	var g: LastSeatLogic = _to_game()
	var started: Dictionary = fx.of_type(&"minigame_started")[0]
	assert_eq(StringName(started["minigame"]), &"last_seat")
	assert_true(started.has("room"))
	for p: int in fx.player_ids:
		var at: Vector3 = fx.server.world.get_position(p)
		assert_true(g.arena.has_point(at), "%d stands in the parlor at %s" % [p, at])
		assert_almost_eq(at.distance_to(g.spawn_for(p)), 0.0, 3.0, "near their spawn")
	assert_eq(fx.of_type(&"last_seat_round").size(), 1, "the first round is announced once the game ticks")
	assert_true(fx.server.get_snapshot()["minigame"]["music"], "late joiners hear the music")


func test_claim_seats_refuses_a_second_and_the_loser_goes_to_the_gallery() -> void:
	var g: LastSeatLogic = _to_game()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	var c: int = fx.player_ids[2]
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	# Everyone away from the table, so nobody sits by touching.
	fx.server.world.set_transform(a, o + Vector3(-6, 0, -5), 0.0)
	fx.server.world.set_transform(b, o + Vector3(6, 0, -5), 0.0)
	fx.server.world.set_transform(c, o + Vector3(-6, 0, 4), 0.0)
	assert_eq(fx.intent(a, &"minigame_action", {"kind": "sit"})["error"], &"music_playing")
	var t: float = 0.0
	while g.state != LastSeatLogic.State.SCRAMBLE and t < 20.0:
		fx.run(0.1)
		t += 0.1
	assert_eq(g.state, LastSeatLogic.State.SCRAMBLE)
	assert_eq(fx.of_type(&"last_seat_stop").size(), 1)
	assert_eq(g.stools.size(), 2)
	_near(g, a, 0)
	var res: Dictionary = fx.intent(a, &"minigame_action", {"kind": "sit", "target": 0})
	assert_true(res["ok"], "sit: %s" % res)
	_near(g, b, 0, 1.1)
	assert_eq(fx.intent(b, &"minigame_action", {"kind": "sit", "target": 0})["error"], &"taken", "first claim wins")
	fx.run(0.1)
	# Pinned on the stool by the server, and shove-proof.
	assert_almost_eq(fx.server.world.get_position(a).distance_to(g.seat_position(0)), 0.0, 0.01, "moved onto the seat")
	assert_false(fx.server.apply_move(a, g.seat_position(0) + Vector3(2.0, -0.5, 0), 0.0, false), "can't walk off the stool")
	assert_true(fx.server.rules.status(a).seated)
	var seat: Vector3 = fx.server.world.get_position(a)
	fx.server.world.set_transform(b, seat + Vector3(0, -0.5, 1.0), 0.0)  # yaw 0 faces -z: towards a
	var shove: Dictionary = fx.intent(b, &"shove", {"aim": [0.0, 0.0, -1.0], "target": a})
	assert_false(shove["ok"], "a seated bean can't be shoved")
	assert_eq(shove["error"], &"seated")
	# b takes the other stool, c is left standing: out, to the gallery.
	_near(g, b, 1)
	assert_true(fx.intent(b, &"minigame_action", {"kind": "sit"})["ok"])
	fx.run(0.3)
	var elim: Array[Dictionary] = fx.of_type(&"minigame_eliminated")
	assert_eq(elim.size(), 1)
	assert_eq(elim[0]["players"], [c])
	assert_true(g.gallery.has_point(fx.server.world.get_position(c)), "c watches from the gallery")
	var moved: bool = false
	for ev: Dictionary in fx.of_type(&"minigame_player_moved"):
		if int(ev["player"]) == c and g.gallery.has_point(Serializer.to_vec3(ev["pos"])):
			moved = true
	assert_true(moved, "the scene is told to move c")
