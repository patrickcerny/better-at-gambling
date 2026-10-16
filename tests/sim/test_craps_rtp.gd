extends GutTest
## Craps RTP (§7, house rule 0.9.6): for a player alone at the table with one bet, every bet
## returns 100.5–102% at neutral luck with the quiet favour included; the real table logic agrees
## with the exact figure over many bets, and the return rises with luck from −3 to +3.

const LOW: float = 1.005
const HIGH: float = 1.02

var cfg: BalanceConfig = BalanceConfig.new()


## Plays `n` bets of `type` (100 each, one at a time) through the real CrapsLogic at `luck`.
## Returns {rtp, rolls}.
func _play(type: StringName, n: int, luck: int, seed_value: int) -> Dictionary:
	var fx := TableFixture.new(seed_value, [1], 1_000_000_000)
	var cr: CrapsLogic = fx.make(CrapsLogic.new(), &"sim") as CrapsLogic
	if luck != 0:
		fx.give_luck(1, luck)
	cr.join(1)
	var start: int = fx.economy.balance(1)
	var placed: int = 0
	var rolls: int = 0
	while placed < n or not cr.bets.is_empty():
		if cr.bets.is_empty():
			cr.place_bet(1, {"type": type, "amount": 100})
			placed += 1
		cr._throw(1)
		cr._resolve()
		cr._start_betting()
		cr.drain_events()
		rolls += 1
	return {"rtp": float(fx.economy.balance(1) - start + placed * 100) / float(placed * 100), "rolls": rolls}


func test_every_bet_returns_a_little_more_than_it_takes() -> void:
	for type: StringName in CrapsLogic.BET_TYPES:
		var exact: float = CrapsLogic.exact_rtp(cfg, type)
		gut.p("craps %s: exact %.4f" % [type, exact])
		assert_between(exact, LOW, HIGH, "%s: exact RTP in the band" % type)


func test_the_plain_odds_without_the_house_rule_are_the_real_casino_ones() -> void:
	var plain := BalanceConfig.new()
	plain.craps_favour = 0.0
	plain.craps_field_ratio = 1.0
	plain.craps_field_double_ratio = 2.0
	plain.craps_any_seven_ratio = 4.0
	assert_almost_eq(CrapsLogic.exact_rtp(plain, &"pass"), 1.0 - 0.0141414, 0.0001, "pass line: 1.41% edge")
	assert_almost_eq(CrapsLogic.exact_rtp(plain, &"dont_pass"), 1.0 - 0.0136364, 0.0001, "don't pass (bar 12): 1.36% edge")
	assert_almost_eq(CrapsLogic.exact_rtp(plain, &"field"), 34.0 / 36.0, 0.0001, "field 2:1 on 2 and 12: 5.56% edge")
	assert_almost_eq(CrapsLogic.exact_rtp(plain, &"any_seven"), 30.0 / 36.0, 0.0001, "any seven 4:1: 16.7% edge")


func test_monte_carlo_through_the_table_logic() -> void:
	# σ of one bet's return: line bets ≈ 1.0, field ≈ 1.03, any seven ≈ 2.0 (in stakes); 3σ bounds.
	var runs: Dictionary = {&"pass": [200_000, 0.0068], &"dont_pass": [200_000, 0.0068], &"field": [200_000, 0.007], &"any_seven": [200_000, 0.0135]}
	var seed_value: int = 20261016
	for type: StringName in runs:
		var n: int = int(runs[type][0])
		var r: Dictionary = _play(type, n, 0, seed_value)
		seed_value += 17
		var exact: float = CrapsLogic.exact_rtp(cfg, type)
		gut.p("craps %s: exact %.4f  sim %.4f over %d bets (%d rolls)" % [type, exact, r["rtp"], n, r["rolls"]])
		assert_almost_eq(float(r["rtp"]), exact, float(runs[type][1]), "%s: the table pays what the sums say" % type)
		assert_between(float(r["rtp"]), LOW - float(runs[type][1]), HIGH + float(runs[type][1]), "%s: in the band" % type)


func test_luck_raises_the_return_for_every_bet() -> void:
	for type: StringName in CrapsLogic.BET_TYPES:
		var prev: float = -1.0
		var line: String = "craps %s by luck:" % type
		for luck: int in range(-3, 4):
			var rtp: float = float(_play(type, 30_000, luck, 4242 + luck)["rtp"])
			line += " %d:%.3f" % [luck, rtp]
			assert_gt(rtp, prev, "%s luck %d" % [type, luck])
			prev = rtp
		gut.p(line)
