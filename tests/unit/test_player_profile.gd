extends GutTest
## The local profile (`PlayerProfile`, user://profile.cfg through `ProfileManager`): buying with
## Coins (and the refusal when they don't reach), the preferred colour, a match's row applied
## exactly once with the level-up bonus, and a save/load round trip that clamps a damaged or
## hand-edited file back into range.

const PATH: String = "user://test_player_profile.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _fresh() -> PlayerProfile:
	return PlayerProfile.new()


func test_a_fresh_profile() -> void:
	var p: PlayerProfile = _fresh()
	assert_eq(p.level, 1)
	assert_eq(p.coins, 0)
	assert_eq(p.preferred_color, -1, "no wish: the server's slot colour")
	assert_eq(p.owned_colors().size(), Cosmetics.SLOT_COLORS, "the 8 free colours")
	for c: int in Cosmetics.SLOT_COLORS:
		assert_true(p.owns_color(c))
	assert_false(p.owns_color(Cosmetics.SLOT_COLORS), "bought colours are not owned yet")
	assert_false(p.owns_color(-1))
	assert_false(p.owns_color(Cosmetics.COLOR_COUNT))


func test_buying_spends_coins_and_refuses_when_short() -> void:
	var p: PlayerProfile = _fresh()
	var mint: CosmeticDef = p.shop.find(&"color_mint")
	assert_not_null(mint)
	assert_gt(mint.price, 0)
	p.coins = mint.price - 1
	assert_eq(p.buy(&"color_mint"), &"not_enough_coins")
	assert_eq(p.coins, mint.price - 1, "nothing taken on a refusal")
	assert_false(p.owns(&"color_mint"))
	assert_false(p.set_preferred_color(mint.color_index), "can't wear what you don't own")
	p.coins = mint.price + 10
	assert_eq(p.buy(&"color_mint"), &"")
	assert_eq(p.coins, 10)
	assert_true(p.owns(&"color_mint"))
	assert_true(p.owns_color(mint.color_index))
	assert_true(mint.color_index in p.owned_colors())
	assert_eq(p.buy(&"color_mint"), &"owned", "never twice")
	assert_eq(p.coins, 10)
	assert_eq(p.buy(&"color_orange"), &"owned", "free colours are always owned")
	assert_eq(p.buy(&"rainbow_hat"), &"unknown")
	assert_true(p.set_preferred_color(mint.color_index))
	assert_eq(p.preferred_color, mint.color_index)
	assert_true(p.set_preferred_color(-1))


func test_a_match_row_applies_once_with_the_level_bonus() -> void:
	var p: PlayerProfile = _fresh()
	var row: Dictionary = Progression.breakdown(p.config, 1, 1, 800, 12, false, 600)
	var first: Dictionary = p.apply_match("m-1", row)
	assert_eq(first["xp"], row["xp"])
	assert_eq(p.xp, int(row["xp"]))
	assert_eq(first["level_from"], 1)
	assert_eq(first["level_to"], p.config.level_for_xp(p.xp))
	assert_gt(first["level_to"], 1, "a good first match levels up")
	var bonus: int = (int(first["level_to"]) - 1) * p.config.level_up_coins
	assert_eq(first["level_bonus"], bonus)
	assert_eq(p.coins, int(row["coins"]) + bonus, "Coins from the row plus the level-up bonus")
	assert_eq(p.matches, 1)
	assert_eq(p.wins, 1, "1st place counts as a win")
	assert_eq(p.biggest_win, 600)
	assert_eq(p.apply_match("m-1", row), {}, "the same match never counts twice")
	assert_eq(p.matches, 1)
	var second: Dictionary = p.apply_match("m-2", Progression.breakdown(p.config, 3, 0, -100, 0))
	assert_false(second.is_empty())
	assert_eq(p.matches, 2)
	assert_eq(p.wins, 1)
	assert_eq(p.apply_match("m-3", {}), {}, "no row, nothing")


func test_a_server_row_is_capped() -> void:
	var p: PlayerProfile = _fresh()
	p.apply_match("evil", {"xp": 10_000_000, "coins": 10_000_000})
	assert_eq(p.xp, Progression.MAX_MATCH_XP)
	assert_lte(p.coins, Progression.coins_for_xp(p.config, Progression.MAX_MATCH_XP) + p.config.level_up_coins * p.level)


func test_save_and_load_round_trip() -> void:
	var p: PlayerProfile = _fresh()
	p.coins = 1000
	p.buy(&"color_gold")
	p.set_preferred_color(15)
	p.apply_match("a", Progression.breakdown(p.config, 2, 1, 300, 8, false, 220))
	assert_eq(p.save(PATH), OK)
	var q: PlayerProfile = _fresh()
	assert_eq(q.load_from(PATH), OK)
	assert_eq(q.xp, p.xp)
	assert_eq(q.level, p.level)
	assert_eq(q.coins, p.coins)
	assert_eq(q.preferred_color, 15)
	assert_eq(q.owned, [&"color_gold"] as Array[StringName])
	assert_eq(q.matches, 1)
	assert_eq(q.biggest_win, 220)
	assert_eq(q.apply_match("a", Progression.breakdown(p.config, 2, 1, 300, 8)), {}, "applied ids survive a restart")
	assert_eq(_fresh().load_from("user://no_such_profile.cfg"), ERR_FILE_NOT_FOUND)


func test_loading_clamps_a_tampered_file() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "xp", -50)
	cfg.set_value("profile", "level", 77)
	cfg.set_value("profile", "coins", 1e15)
	cfg.set_value("profile", "preferred_color", 13)  # Onyx, not owned
	cfg.set_value("profile", "owned", PackedStringArray(["color_orange", "dragon_wings", "color_lime", "color_lime"]))
	cfg.set_value("stats", "matches", 3)
	cfg.set_value("stats", "wins", 9)
	cfg.set_value("stats", "biggest_win", -4)
	cfg.set_value("stats", "applied", "not a list")
	cfg.save(PATH)
	var p: PlayerProfile = _fresh()
	assert_eq(p.load_from(PATH), OK)
	assert_eq(p.xp, 0)
	assert_eq(p.level, 1, "the level follows the XP, not the file")
	assert_eq(p.coins, PlayerProfile.MAX_COINS)
	assert_eq(p.owned, [&"color_lime"] as Array[StringName], "unknown, free and duplicate entries dropped")
	assert_eq(p.preferred_color, -1, "an unowned colour is not worn")
	assert_eq(p.wins, 3, "never more wins than matches")
	assert_eq(p.biggest_win, 0)
	assert_true(p.applied.is_empty())
	cfg.set_value("profile", "xp", "lots")
	cfg.set_value("profile", "preferred_color", 12)  # Lime: owned above
	cfg.save(PATH)
	var q: PlayerProfile = _fresh()
	q.load_from(PATH)
	assert_eq(q.xp, 0, "junk types read as 0")
	assert_eq(q.preferred_color, 12)
	var huge := ConfigFile.new()
	huge.set_value("profile", "xp", 999_999_999)
	huge.save(PATH)
	var r: PlayerProfile = _fresh()
	r.load_from(PATH)
	assert_eq(r.xp, r.config.max_xp())
	assert_eq(r.level, r.config.max_level)


func test_the_autoload_stays_in_memory_under_tests() -> void:
	assert_false(ProfileManager.persist, "GUT never writes the player's real profile")
	assert_true(ProfileManager.is_test_run())
