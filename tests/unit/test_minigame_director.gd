extends GutTest
## The minigame picker is a shuffled bag (Patrick, 0.9.2 playtest: "don't let a game come twice
## before all the others came"): every game this many players can play comes once before any
## repeats, never the same game twice in a row, and games the table is too small for stay out.


func _def(id: String, min_players: int = 2) -> MinigameDefinition:
	var d := MinigameDefinition.new()
	d.id = StringName(id)
	d.min_players = min_players
	d.weight = 1.0
	return d


func _director(ids: Array, mins: Dictionary = {}) -> MinigameDirector:
	var defs: Array[MinigameDefinition] = []
	for id: String in ids:
		defs.append(_def(id, int(mins.get(id, 2))))
	return MinigameDirector.new(defs, null)


## `n` picks in a row, each recorded as played (what `begin` does).
func _draw(dir: MinigameDirector, rng: SeededRng, n: int, players: int = 8) -> Array:
	var out: Array = []
	for i: int in n:
		var d: MinigameDefinition = dir.pick(rng, players)
		assert_not_null(d, "pick %d" % i)
		dir.record(d)
		out.append(d.id)
	return out


## Ids as sorted Strings (StringName sorts by pointer, not by text).
func _sorted(a: Array) -> Array:
	var c: Array = []
	for id: Variant in a:
		c.append(String(id))
	c.sort()
	return c


func test_every_game_comes_once_before_any_repeats() -> void:
	var all: Array = ["a", "b", "c", "d", "e"]
	for seed_value: int in [1, 2, 3, 4, 5]:
		var seq: Array = _draw(_director(["a", "b", "c", "d", "e"]), SeededRng.new(seed_value), 25)
		for bag: int in 5:
			assert_eq(_sorted(seq.slice(bag * 5, bag * 5 + 5)), all, "bag %d complete (seed %d)" % [bag, seed_value])


func test_never_the_same_game_twice_in_a_row() -> void:
	for seed_value: int in [1, 2, 3, 4, 5]:
		var seq: Array = _draw(_director(["a", "b", "c"]), SeededRng.new(seed_value), 30)
		for i: int in range(1, seq.size()):
			assert_ne(seq[i], seq[i - 1], "pick %d repeats (seed %d)" % [i, seed_value])


func test_games_the_table_cannot_play_stay_out_of_the_bag() -> void:
	var dir: MinigameDirector = _director(["a", "b", "c", "big"], {"big": 4})
	var seq: Array = _draw(dir, SeededRng.new(3), 12, 3)
	assert_false(seq.has(&"big"), "a 4-player game never comes with 3 players")
	for bag: int in 4:
		assert_eq(_sorted(seq.slice(bag * 3, bag * 3 + 3)), ["a", "b", "c"], "bag %d complete" % bag)


func test_solo_practice_with_one_game_repeats_it() -> void:
	var seq: Array = _draw(_director(["quiz"], {"quiz": 1}), SeededRng.new(1), 3, 1)
	assert_eq(_sorted(seq), ["quiz", "quiz", "quiz"])


func test_reset_refills_the_bag() -> void:
	var dir: MinigameDirector = _director(["a", "b", "c"])
	_draw(dir, SeededRng.new(2), 2)
	dir.reset()
	assert_eq(_sorted(_draw(dir, SeededRng.new(2), 3)), ["a", "b", "c"], "a rematch starts with a full bag")
