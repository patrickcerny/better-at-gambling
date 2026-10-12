extends GutTest
## Minigame selector, server side: the lobby setting `minigame_pool` (leader only, unknown ids
## dropped, empty or everything = "" = all) and the director drawing only from the pool, with the
## min-players filter still applied.

const KNOWN: PackedStringArray = ["quiz", "lonely_number", "spy", "vote_race"]


func _lobby() -> LobbyController:
	var l := LobbyController.new()
	l.known_minigames = KNOWN
	l.join(1, 0.0)
	l.join(2, 1.0)
	return l


func test_normalize_drops_unknown_and_keeps_registry_order() -> void:
	assert_eq(LobbyController.normalize_pool("spy, nope,quiz,spy", KNOWN), "quiz,spy")
	assert_eq(LobbyController.normalize_pool(["vote_race", "lonely_number"], KNOWN), "lonely_number,vote_race")
	assert_eq(LobbyController.normalize_pool("", KNOWN), "", "empty = all")
	assert_eq(LobbyController.normalize_pool("nope,also_nope", KNOWN), "", "nothing known = all")
	assert_eq(LobbyController.normalize_pool("vote_race,spy,lonely_number,quiz", KNOWN), "", "every game = all")


func test_only_the_leader_sets_the_pool_and_bad_types_are_refused() -> void:
	var l: LobbyController = _lobby()
	assert_eq(l.settings["minigame_pool"], "", "defaults to every minigame")
	assert_eq(l.set_setting(2, "minigame_pool", "quiz"), &"not_leader")
	assert_eq(l.set_setting(1, "minigame_pool", 5), &"bad_value")
	assert_eq(l.set_setting(1, "minigame_pool", "quiz,bogus,spy"), &"")
	assert_eq(l.settings["minigame_pool"], "quiz,spy")
	assert_eq(l.set_setting(1, "minigame_pool", ""), &"")
	assert_eq(l.settings["minigame_pool"], "")


func test_pool_defs_filters_and_empty_is_all() -> void:
	var all: Dictionary = Registry.minigames
	var two: Array[MinigameDefinition] = MinigameDirector.pool_defs(all, "quiz,lonely_number")
	assert_eq(two.map(func(d: MinigameDefinition) -> StringName: return d.id), [&"quiz", &"lonely_number"])
	assert_eq(MinigameDirector.pool_defs(all, "").size(), all.size())
	assert_eq(MinigameDirector.pool_defs(all, "bogus").size(), all.size(), "nothing known falls back to all")


func test_director_draws_only_from_the_pool_and_keeps_min_players() -> void:
	var d := MinigameDirector.new(MinigameDirector.pool_defs(Registry.minigames, "quiz,spy,lonely_number"), Registry.quiz_bank)
	var rng := SeededRng.new(7)
	var seen: Dictionary = {}
	for i: int in 30:
		var def: MinigameDefinition = d.pick(rng, 3)
		d.record(def)
		seen[def.id] = true
	assert_eq(seen.keys().size(), 2, "spy needs 4 players")
	assert_true(seen.has(&"quiz") and seen.has(&"lonely_number"))
	d.set_defs(MinigameDirector.pool_defs(Registry.minigames, "lonely_number"))
	for i: int in 5:
		assert_eq(d.pick(rng, 3).id, &"lonely_number", "a changed pool applies to the next pick")
