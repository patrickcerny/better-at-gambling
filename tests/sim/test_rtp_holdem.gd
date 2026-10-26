extends GutTest
## Casino Hold'em return to player, played through the real table logic (a fresh deck per hand,
## the quiet house rule, luck): a lone player with the simple strategy (call with a pair or better
## or a flush or straight draw, fold with nothing) gets back a little more than they stake, inside
## the band every table is tuned to (100.5–102% of everything staked, ante and call), and so does
## the AA Bonus. Without the house rule both keep a house edge, as at a real table (Evolution's
## main game returns 97.8% of the ante with optimal play, the AA Bonus 93.7%).

const LOW: float = 1.005
const HIGH: float = 1.02


## Plays `hands` hands of a $10 ante (and a $10 AA Bonus when `bonus`) for one player with the
## simple strategy: {rtp (main game, returned ÷ staked), sigma, per_ante (net per ante + 1),
## bonus_rtp, bonus_sigma, called (share of hands called)}.
func _play(hands: int, favour: float, bonus_favour: float, bonus: bool, luck_points: int, seed_value: int) -> Dictionary:
	var fx := TableFixture.new(seed_value, [1], 2_000_000_000)
	fx.balance.holdem_favour = favour
	fx.balance.holdem_bonus_favour = bonus_favour
	var t: HoldemLogic = fx.make(HoldemLogic.new(), &"sim") as HoldemLogic
	t.join(1)
	if luck_points != 0:
		fx.give_luck(1, luck_points)
	var staked: float = 0.0
	var back: float = 0.0
	var sq: float = 0.0
	var b_back: float = 0.0
	var b_sq: float = 0.0
	var called: int = 0
	for i: int in hands:
		t.place_bet(1, {"amount": 10, "bonus": 10 if bonus else 0})
		t.tick(fx.balance.holdem_betting_window + 0.1)
		var h: Dictionary = t.hands[1]
		var call: bool = HoldemLogic.simple_call(h["hole"], t.board)
		if call:
			called += 1
		t.player_action(1, &"call" if call else &"fold")
		for e: Dictionary in t.drain_events():
			if e["type"] != &"round_result":
				continue
			var ret: float = float(e["returned"])
			if StringName(e["details"]["type"]) == &"bonus":
				b_back += ret
				b_sq += (ret / 10.0) * (ret / 10.0)
			else:
				staked += float(e["stake"])
				back += ret
				var r: float = (ret - float(e["stake"])) / 10.0  # net per ante
				sq += r * r
		t.tick(fx.balance.holdem_result_time + 0.1)
	var per_ante: float = (back - staked) / (10.0 * hands)
	var per_ante_sd: float = sqrt(maxf(sq / hands - per_ante * per_ante, 0.0) / hands)
	var avg_stake: float = staked / (10.0 * hands)
	var b_mean: float = b_back / (10.0 * hands)
	return {
		"rtp": back / staked, "sigma": per_ante_sd / avg_stake, "per_ante": 1.0 + per_ante, "called": float(called) / hands,
		"bonus_rtp": b_mean, "bonus_sigma": sqrt(maxf(b_sq / hands - b_mean * b_mean, 0.0) / hands),
	}


func test_the_main_game_returns_a_little_more_than_it_costs() -> void:
	var cfg := BalanceConfig.new()
	var plain: Dictionary = _play(60_000, 0.0, 0.0, false, 0, 1717)
	var tuned: Dictionary = _play(300_000, cfg.holdem_favour, 0.0, false, 0, 4242)
	gut.p("hold'em main game, simple strategy (calls %.1f%%): without the house rule %.4f ± %.4f of the stake (%.4f per ante); with holdem_favour %.3f %.4f ± %.4f (%.4f per ante)" % [
		float(tuned["called"]) * 100.0, plain["rtp"], plain["sigma"], plain["per_ante"], cfg.holdem_favour, tuned["rtp"], tuned["sigma"], tuned["per_ante"]])
	assert_between(float(plain["rtp"]), 0.95, 0.995, "the plain rules keep a house edge")
	assert_between(float(tuned["rtp"]), LOW, HIGH, "the house rule lifts it into the band")
	assert_lt(3.0 * float(tuned["sigma"]), 0.006, "and the estimate is tight enough to say so")


## The AA Bonus exactly, at neutral luck: every kind of hole cards (13 pairs, 78 suited, 78
## offsuit, weighted 6 / 4 / 12 of the 1,326 deals) against every one of the 19,600 flops left.
## With the house rule a losing flop is drawn again once with chance f, so hole cards that pay
## with chance p and return E on average return E · (1 + f · (1 − p)). {plain, favoured}.
func _exact_bonus(cfg: BalanceConfig, f: float) -> Dictionary:
	var plain: float = 0.0
	var favoured: float = 0.0
	for hi: int in range(2, 15):
		for lo: int in range(2, hi + 1):
			for suited: bool in [true, false]:
				if hi == lo and suited:
					continue
				var a: int = Card.make(1 if hi == 14 else hi, 0)
				var b: int = Card.make(1 if lo == 14 else lo, 0 if suited else 1)
				var weight: float = 6.0 if hi == lo else (4.0 if suited else 12.0)
				var rest: Array[int] = []
				for c: int in 52:
					if c != a and c != b:
						rest.append(c)
				var total: float = 0.0
				var wins: int = 0
				var n: int = 0
				var five: Array[int] = [a, b, 0, 0, 0]
				for i: int in rest.size():
					five[2] = rest[i]
					for j: int in range(i + 1, rest.size()):
						five[3] = rest[j]
						for k: int in range(j + 1, rest.size()):
							five[4] = rest[k]
							var pay: int = HoldemLogic.bonus_pay(HoldemHand.evaluate(five), cfg)
							n += 1
							if pay > 0:
								wins += 1
								total += 1.0 + pay
				var e: float = total / n
				var p: float = float(wins) / n
				plain += weight * e
				favoured += weight * e * (1.0 + f * (1.0 - p))
	return {"plain": plain / 1326.0, "favoured": favoured / 1326.0}


func test_the_aa_bonus_returns_a_little_more_than_it_costs() -> void:
	var cfg := BalanceConfig.new()
	var exact: Dictionary = _exact_bonus(cfg, cfg.holdem_bonus_favour)
	var sim: Dictionary = _play(200_000, 0.0, cfg.holdem_bonus_favour, true, 0, 1234)
	gut.p("hold'em AA Bonus, exact: without the house rule %.4f, with holdem_bonus_favour %.3f %.4f; through the table %.4f ± %.4f" % [exact["plain"], cfg.holdem_bonus_favour, exact["favoured"], sim["bonus_rtp"], sim["bonus_sigma"]])
	assert_almost_eq(float(exact["plain"]), 0.9374, 0.0005, "the printed paytable returns Evolution's 93.74%")
	assert_between(float(exact["favoured"]), LOW, HIGH, "the house rule lifts it into the band")
	assert_almost_eq(float(sim["bonus_rtp"]), float(exact["favoured"]), 3.5 * float(sim["bonus_sigma"]), "and the table pays what the sum says")


func test_luck_moves_the_return() -> void:
	var cfg := BalanceConfig.new()
	var prev: float = -1.0
	var line: String = "hold'em by luck:"
	for lk: int in [-3, 0, 3]:
		var rtp: float = float(_play(40_000, cfg.holdem_favour, cfg.holdem_bonus_favour, false, lk, 5150)["rtp"])
		line += " %d:%.3f" % [lk, rtp]
		assert_gt(rtp, prev, "luck %d" % lk)
		prev = rtp
	gut.p(line)
