extends GutTest
## XP and Coins (Patrick: "Create a XP level and an ingame currency"): the level curve reaches level
## 10 after about 8 matches and slows down after, and a match's breakdown counts placement,
## minigames won, money won and hands played (Practice at half rate). Data:
## data/progression/progression.tres.

var cfg: ProgressionConfig


func before_each() -> void:
	cfg = ProgressionConfig.default()


func test_the_shipped_config_loads_from_data() -> void:
	assert_eq(cfg.resource_path, ProgressionConfig.PATH)
	assert_eq(cfg.soft_cap_level, 10)
	assert_gt(cfg.max_level, 10)


func test_level_curve_basics() -> void:
	assert_eq(cfg.level_for_xp(0), 1)
	assert_eq(cfg.xp_for_level(1), 0)
	assert_eq(cfg.xp_to_next(1), 100)
	assert_eq(cfg.level_for_xp(99), 1)
	assert_eq(cfg.level_for_xp(100), 2, "exactly enough XP is the next level")
	for l: int in range(1, 30):
		assert_eq(cfg.level_for_xp(cfg.xp_for_level(l)), l, "level %d starts at its own XP" % l)
		assert_eq(cfg.level_for_xp(cfg.xp_for_level(l + 1) - 1), l)
		assert_gt(cfg.xp_to_next(l + 1), cfg.xp_to_next(l) - 1, "never gets cheaper")
	assert_eq(cfg.level_for_xp(cfg.max_xp() + 5000), cfg.max_level, "capped")
	assert_eq(cfg.xp_to_next(cfg.max_level), 0)


func test_level_10_takes_about_8_matches_and_it_slows_after() -> void:
	# A typical match: 2nd of 4, one minigame won, $600 up, 20 hands.
	var typical: int = int(Progression.breakdown(cfg, 2, 1, 600, 20)["xp"])
	assert_between(typical, 220, 320, "a typical match: %d XP" % typical)
	var matches: float = float(cfg.xp_for_level(10)) / typical
	assert_between(matches, 7.0, 9.5, "level 10 after ~8 matches (%.1f)" % matches)
	assert_eq(cfg.xp_for_level(10), 2160)
	assert_gt(cfg.xp_to_next(10), cfg.xp_to_next(9) + 50, "the curve slows past level 10")
	var to_20: float = float(cfg.xp_for_level(20) - cfg.xp_for_level(10)) / typical
	assert_gt(to_20, 20.0, "levels 10 to 20 take far longer (%.1f matches)" % to_20)


func test_breakdown_counts_every_part() -> void:
	var row: Dictionary = Progression.breakdown(cfg, 1, 2, 1000, 10, false, 450)
	var by_id: Dictionary = {}
	for p: Dictionary in row["parts"]:
		by_id[p["id"]] = int(p["xp"])
	assert_eq(by_id[&"match"], 100)
	assert_eq(by_id[&"placement"], 120, "1st place")
	assert_eq(by_id[&"minigames"], 60, "two minigames won")
	assert_eq(by_id[&"money"], 50, "$1000 profit at $20 per XP")
	assert_eq(by_id[&"hands"], 20)
	assert_eq(row["xp"], 350)
	assert_eq(row["coins"], 35, "a tenth of the XP")
	assert_eq(row["rank"], 1)
	assert_eq(row["biggest_win"], 450)
	assert_false(row["practice"])


func test_breakdown_caps_and_leaves_out_nothing_earned() -> void:
	var row: Dictionary = Progression.breakdown(cfg, 7, 0, -300, 0)
	var ids: Array = (row["parts"] as Array).map(func(p: Dictionary) -> StringName: return p["id"])
	assert_eq(ids, [&"match", &"placement"], "no money, no minigames, no hands: no lines for them")
	assert_eq(row["xp"], 100 + 20, "places past the table get its last entry")
	var rich: Dictionary = Progression.breakdown(cfg, 1, 0, 1_000_000, 999)
	var by_id: Dictionary = {}
	for p: Dictionary in rich["parts"]:
		by_id[p["id"]] = int(p["xp"])
	assert_eq(by_id[&"money"], cfg.xp_money_cap)
	assert_eq(by_id[&"hands"], cfg.xp_hands_cap)
	assert_lte(int(rich["xp"]), Progression.MAX_MATCH_XP)


func test_practice_earns_half() -> void:
	var online: Dictionary = Progression.breakdown(cfg, 1, 1, 500, 10)
	var practice: Dictionary = Progression.breakdown(cfg, 1, 1, 500, 10, true)
	assert_true(practice["practice"])
	assert_almost_eq(float(practice["xp"]), float(online["xp"]) * 0.5, 3.0)
	assert_lt(int(practice["coins"]), int(online["coins"]))


func test_ordinals() -> void:
	assert_eq(Progression.ordinal(1), "1st")
	assert_eq(Progression.ordinal(2), "2nd")
	assert_eq(Progression.ordinal(3), "3rd")
	assert_eq(Progression.ordinal(4), "4th")
	assert_eq(Progression.ordinal(11), "11th")
	assert_eq(Progression.ordinal(22), "22nd")
