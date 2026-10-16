extends GutTest
## Monte-Carlo RTP of the Wheel of Fortune through the real `WheelLogic` (§7). The layout pays the
## honest Big Six odds (76–89% on their own); the house rule's favour redraw (`wheel_favour`) lifts
## a lone bettor to 98–105% per symbol and to the casino's 100.5–102% band over the seven symbols,
## and luck from −3 to +3 orders the return strictly.

const BANKROLL: int = 1_000_000_000

var cfg: BalanceConfig = BalanceConfig.new()


## One player alone at the wheel, `spins` spins of `bet` on `symbol`. Returns {rtp, hits}.
func _play(symbol: int, spins: int, luck: int, seed_value: int, bet: int = 100) -> Dictionary:
	var fx := TableFixture.new(seed_value, [1], BANKROLL)
	fx.economy.record_history = false
	if luck != 0:
		fx.give_luck(1, luck, &"wheel")
	var wl: WheelLogic = fx.make(WheelLogic.new(), &"wheel_sim") as WheelLogic
	wl.join(1)
	var hits: int = 0
	for i: int in spins:
		wl.place_bet(1, {"symbol": symbol, "amount": bet})
		wl.auto_resolve()
		if WheelLogic.symbol_at(wl.segment) == symbol:
			hits += 1
		wl.events.clear()
		wl.tick(cfg.wheel_result_time + 0.01)  # the next round opens
	var wagered: int = spins * bet
	var returned: int = fx.economy.balance(1) - BANKROLL + wagered
	return {"rtp": returned / float(wagered), "hits": hits / float(spins)}


## Exact chance a lone bettor's symbol comes up with the favour redraw and luck `luck`: the luck
## reroll draws a plain second segment and keeps the better one (worse when jinxed).
func _win_chance(symbol: int, luck: int) -> float:
	var p: float = WheelLogic.chance_of(symbol)
	var fav: float = p + (1.0 - p) * cfg.wheel_favour * p
	var r: float = cfg.luck_reroll_per_point * absi(clampi(luck, -cfg.luck_clamp, cfg.luck_clamp))
	if luck > 0:
		return fav + r * (1.0 - fav) * p
	if luck < 0:
		return fav * (1.0 - r * (1.0 - p))
	return fav


func test_every_symbol_monte_carlo() -> void:
	var spins: Array[int] = [100_000, 100_000, 150_000, 150_000, 200_000, 200_000, 200_000]
	var mean: float = 0.0
	var line: String = "wheel (favour %.2f):" % cfg.wheel_favour
	for s: int in WheelLogic.SYMBOLS.size():
		var exact: float = WheelLogic.exact_rtp(s, cfg.wheel_favour)
		var r: Dictionary = _play(s, spins[s], 0, 9000 + s)
		var k: float = WheelLogic.PAYS[s] + 1.0
		var pw: float = _win_chance(s, 0)
		var sigma: float = sqrt(k * k * pw * (1.0 - pw) / spins[s])
		line += "  %s exact %.4f sim %.4f (honest %.4f)" % [WheelLogic.LABELS[s], exact, r["rtp"], WheelLogic.exact_rtp(s, 0.0)]
		assert_almost_eq(exact, k * pw, 0.000001)
		assert_almost_eq(float(r["rtp"]), exact, 3.0 * sigma, "%s: the sim agrees with the exact return (3σ = %.4f)" % [WheelLogic.LABELS[s], 3.0 * sigma])
		assert_between(exact, 0.98, 1.05, "%s: favoured a bit, never a sure thing" % WheelLogic.LABELS[s])
		mean += exact / WheelLogic.SYMBOLS.size()
	gut.p(line)
	gut.p("wheel mean over the seven symbols: %.4f" % mean)
	assert_between(mean, 1.005, 1.02, "the casino's band over the seven symbols")


func test_without_the_favour_the_wheel_is_honest_big_six() -> void:
	var fx := TableFixture.new(5, [1], BANKROLL)
	fx.balance.wheel_favour = 0.0
	var wl: WheelLogic = fx.make(WheelLogic.new(), &"wheel_sim") as WheelLogic
	wl.join(1)
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	var n: int = 135_000
	for i: int in n:
		wl.place_bet(1, {"symbol": 0, "amount": 10})
		wl.auto_resolve()
		counts[WheelLogic.symbol_at(wl.segment)] += 1
		wl.events.clear()
		wl.tick(fx.balance.wheel_result_time + 0.01)
	for s: int in counts.size():
		var p: float = WheelLogic.chance_of(s)
		assert_almost_eq(counts[s] / float(n), p, 4.0 * sqrt(p * (1.0 - p) / n), "%s comes up on %d of 54 segments" % [WheelLogic.LABELS[s], WheelLogic.COUNTS[s]])
	# The $1 bet alone pays 2 × 24/54 = 88.9%: the favour is what makes the wheel generous.
	assert_almost_eq(WheelLogic.exact_rtp(0, 0.0), 2.0 * 24.0 / 54.0, 0.000001)


func test_luck_monotonic_and_the_sim_agrees_at_plus_two() -> void:
	for s: int in WheelLogic.SYMBOLS.size():
		var prev: float = -1.0
		for luck: int in range(-3, 4):
			var rtp: float = (WheelLogic.PAYS[s] + 1.0) * _win_chance(s, luck)
			assert_gt(rtp, prev, "%s luck %d" % [WheelLogic.LABELS[s], luck])
			prev = rtp
	var line: String = "$2 by luck:"
	for luck: int in range(-3, 4):
		line += " %d:%.3f" % [luck, 3.0 * _win_chance(1, luck)]
	gut.p(line)
	var n: int = 100_000
	var r: Dictionary = _play(1, n, 2, 77)
	var pw: float = _win_chance(1, 2)
	assert_almost_eq(float(r["hits"]), pw, 3.0 * sqrt(pw * (1.0 - pw) / n), "+2 luck on $2: the sim agrees with the luck model")
	var j: Dictionary = _play(1, n, -2, 78)
	var pj: float = _win_chance(1, -2)
	assert_almost_eq(float(j["hits"]), pj, 3.0 * sqrt(pj * (1.0 - pj) / n), "−2 luck on $2")
