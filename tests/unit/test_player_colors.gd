extends GutTest
## PlayerColors: everything colour-coded per player uses the bean colour they picked, kept apart.

const SKIN_SLOT: int = 5  # CosmeticDef.OUTFIT_KINDS: hat, shirt, pants, cape, boots, skin, ...


func _outfit_with_skin(id: String) -> Array:
	var o: Array = ["", "", "", "", "", "", "", "", ""]
	o[SKIN_SLOT] = id
	return o


func test_skin_slot_index_matches_the_outfit_kinds() -> void:
	assert_eq(CosmeticDef.OUTFIT_KINDS[SKIN_SLOT], CosmeticDef.KIND_SKIN)


func test_own_colour_is_the_bean_colour_not_the_slot_colour() -> void:
	var p: Dictionary = {"color": 0, "bean_color": 11, "outfit": []}
	assert_eq(PlayerColors.own(p), Palette.player_color(11), "bean colour wins over slot colour")


func test_an_animated_skin_keeps_the_picked_bean_colour() -> void:
	# The dev skin's flat colour is near-black: the pedestals looked empty (Patrick 2026-11-16).
	var p: Dictionary = {"color": 0, "bean_color": 6, "outfit": _outfit_with_skin("skin_the_house")}
	assert_eq(PlayerColors.own(p), Palette.player_color(6), "the colour the player picked")


func test_players_far_apart_keep_their_own_colours() -> void:
	var players: Dictionary = {1: {"color": 0, "bean_color": 0}, 2: {"color": 1, "bean_color": 4}}
	assert_eq(PlayerColors.of_player(players, 1), Palette.player_color(0))
	assert_eq(PlayerColors.of_player(players, 2), Palette.player_color(4))


func test_close_colours_are_told_apart() -> void:
	# Cream and Champagne beans, Yellow and Gold, Orange.
	var players: Dictionary = {
		1: {"color": 0, "bean_color": 7}, 2: {"color": 1, "bean_color": 23},
		3: {"color": 2, "bean_color": 3}, 4: {"color": 3, "bean_color": 15}, 5: {"color": 4, "bean_color": 0},
	}
	var all: Dictionary = PlayerColors.of_all(players)
	assert_eq(all[1], Palette.player_color(7), "the first player keeps theirs")
	var ids: Array = all.keys()
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			assert_gt(PlayerColors.distance(all[ids[i]], all[ids[j]]), PlayerColors.MIN_DISTANCE - 0.001, "%s vs %s" % [ids[i], ids[j]])


func test_eight_random_lobbies_stay_readable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var skins: Array = ToonMaterial.SKIN_MODES.keys()
	for round_i: int in 40:
		var players: Dictionary = {}
		var used: Array[int] = []
		for pid: int in range(1, 9):
			var c: int = rng.randi_range(0, Cosmetics.COLOR_COUNT - 1)
			while c in used:
				c = rng.randi_range(0, Cosmetics.COLOR_COUNT - 1)
			used.append(c)
			var outfit: Array = _outfit_with_skin(str(skins[rng.randi_range(0, skins.size() - 1)])) if rng.randf() < 0.3 else []
			players[pid] = {"color": pid - 1, "bean_color": c, "outfit": outfit}
		var all: Dictionary = PlayerColors.of_all(players)
		var worst: float = INF
		for a: int in range(1, 9):
			for b: int in range(a + 1, 9):
				worst = minf(worst, PlayerColors.distance(all[a], all[b]))
		assert_gt(worst, 0.08, "lobby %d: no two players look the same" % round_i)


func test_pedestal_inlays_follow_the_players_colour() -> void:
	var map: LuckyLounge = (load("res://maps/lucky_lounge/lucky_lounge.tscn") as PackedScene).instantiate()
	map.bake_navmesh = false
	add_child_autofree(map)
	await wait_physics_frames(1)
	assert_eq(map.pedestal_inlays[0].albedo_color, LuckyLounge.PEDESTAL_EMPTY, "nobody: no player colour")
	var pink: Color = Palette.player_color(6)
	map.set_pedestal(0, "Patrick", false, pink)
	assert_eq(map.pedestal_inlays[0].albedo_color, pink, "the inlay wears the player's colour")
	assert_ne(map.pedestal_inlays[1].albedo_color, pink, "other pedestals keep theirs")
	map.set_pedestal(0, "", false)
	assert_eq(map.pedestal_inlays[0].albedo_color, LuckyLounge.PEDESTAL_EMPTY)
