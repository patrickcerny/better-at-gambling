extends GutTest
## Monte-Carlo RTP checks (§7): each game's RTP at neutral luck lies in 100.5–102%, the
## simulation agrees with the exact expectation, and RTP rises strictly with luck from −3 to +3.

const LOW: float = 1.005
const HIGH: float = 1.02

var cfg: BalanceConfig = BalanceConfig.new()


## Exact RTP of a discrete payout distribution under luck rerolls.
static func _luck_rtp(pays: Array[float], probs: Array[float], luck: int, per_point: float) -> float:
	var r: float = per_point * absi(luck)
	var single: float = 0.0
	var paired: float = 0.0
	for i: int in pays.size():
		single += probs[i] * pays[i]
		for j: int in pays.size():
			var best: float = maxf(pays[i], pays[j]) if luck > 0 else minf(pays[i], pays[j])
			paired += probs[i] * probs[j] * best
	return (1.0 - r) * single + r * paired


func _slot_distribution() -> Array:
	var w: PackedInt32Array = cfg.slots_reel_weights
	var tw: float = 0.0
	for x: int in w:
		tw += x
	var by_pay: Dictionary = {}
	for a: int in w.size():
		for b: int in w.size():
			for c: int in w.size():
				var m: float = SlotsLogic.payout_multiplier([a, b, c] as Array[int], cfg)
				by_pay[m] = by_pay.get(m, 0.0) + (w[a] / tw) * (w[b] / tw) * (w[c] / tw)
	var pays: Array[float] = []
	var probs: Array[float] = []
	for m: float in by_pay:
		pays.append(m)
		probs.append(by_pay[m])
	return [pays, probs]


func _plinko_distribution(risk: StringName) -> Array:
	var w: PackedInt32Array = cfg.plinko_weights(risk)
	var m: PackedFloat32Array = cfg.plinko_multipliers(risk)
	var tw: float = 0.0
	for x: int in w:
		tw += x
	var pays: Array[float] = []
	var probs: Array[float] = []
	for i: int in w.size():
		pays.append(m[i])
		probs.append(w[i] / tw)
	return [pays, probs]


func test_slots_rtp_monte_carlo_1m_spins() -> void:
	var exact: Dictionary = SlotsLogic.exact_rtp(cfg)
	var r: Dictionary = SimHelpers.slots(1_000_000, 0, 20261004)
	gut.p("slots: exact %.4f  sim %.4f  hit %.3f" % [exact["rtp"], r["rtp"], r["hits"]])
	assert_between(float(exact["rtp"]), LOW, HIGH)
	# σ of one spin's return ≈ 3.2 bets -> 3σ over 1M spins ≈ 0.0096
	assert_almost_eq(float(r["rtp"]), float(exact["rtp"]), 0.0096)
	assert_between(float(r["hits"]), 0.30, 0.40)


func test_slots_luck_monotonic() -> void:
	var d: Array = _slot_distribution()
	var prev: float = -1.0
	var line: String = "slots by luck:"
	for luck: int in range(-3, 4):
		var rtp: float = _luck_rtp(d[0], d[1], luck, cfg.luck_reroll_per_point)
		line += " %d:%.3f" % [luck, rtp]
		assert_gt(rtp, prev, "luck %d" % luck)
		prev = rtp
	gut.p(line)
	# Simulation agrees with the exact luck model at L = +2.
	var exact2: float = _luck_rtp(d[0], d[1], 2, cfg.luck_reroll_per_point)
	assert_almost_eq(float(SimHelpers.slots(200_000, 2, 7)["rtp"]), exact2, 0.025)


func test_plinko_rtp_and_luck() -> void:
	for risk: StringName in PlinkoLogic.RISKS:
		var exact: float = PlinkoLogic.exact_rtp(cfg, risk)
		assert_between(exact, LOW, HIGH, str(risk))
		var r: Dictionary = SimHelpers.plinko(200_000, risk, 0, 99)
		var tol: float = {&"low": 0.006, &"medium": 0.012, &"high": 0.035}[risk]
		gut.p("plinko %s: exact %.4f  sim %.4f" % [risk, exact, r["rtp"]])
		assert_almost_eq(float(r["rtp"]), exact, tol, str(risk))
		var d: Array = _plinko_distribution(risk)
		var prev: float = -1.0
		for luck: int in range(-3, 4):
			var lr: float = _luck_rtp(d[0], d[1], luck, cfg.luck_reroll_per_point)
			assert_gt(lr, prev, "%s luck %d" % [risk, luck])
			prev = lr


func test_roulette_exact_rtp_every_bet_type() -> void:
	var bets: Array = [[&"straight", 7], [&"red", 0], [&"black", 0], [&"odd", 0], [&"even", 0], [&"low", 0], [&"high", 0], [&"dozen", 1], [&"column", 3]]
	for b: Array in bets:
		var total: float = 0.0
		for n: int in 37:
			if RouletteLogic.wins(b[0], b[1], n):
				total += (RouletteLogic.RATIOS[b[0]] + 1) * (1.0 + cfg.roulette_generosity)
		var rtp: float = total / 37.0
		assert_between(rtp, LOW, HIGH, str(b[0]))


func test_roulette_monte_carlo_500k_per_core_type() -> void:
	var exact: float = 36.0 * (1.0 + cfg.roulette_generosity) / 37.0
	var red: Dictionary = SimHelpers.roulette(500_000, &"red", 0, 0, 3)
	var straight: Dictionary = SimHelpers.roulette(500_000, &"straight", 17, 0, 4)
	gut.p("roulette: exact %.4f  red %.4f  straight %.4f" % [exact, red["rtp"], straight["rtp"]])
	assert_almost_eq(float(red["rtp"]), exact, 0.0045)  # 3σ, σ≈1.0/√n
	assert_almost_eq(float(straight["rtp"]), exact, 0.026)  # 3σ, σ≈6.0/√n


func test_roulette_luck_monotonic() -> void:
	# Combined luck effect on a straight + an even-money bet (the two luck rules).
	var g: float = 1.0 + cfg.roulette_generosity
	var prev: float = -1.0
	for luck: int in range(-3, 4):
		var r: float = cfg.luck_reroll_per_point * absi(luck)
		var straight: float = 36.0 * g / 37.0
		var even: float = 18.0 / 37.0 * 2.0 * g
		if luck > 0:
			straight += 2.0 / 37.0 * r * (1.0 + cfg.roulette_lucky_neighbor_ratio)
		elif luck < 0:
			even = 18.0 / 37.0 * ((1.0 - r) * 2.0 * g + r * (1.0 + cfg.roulette_jinx_ratio))
		var combined: float = (straight + even) / 2.0
		assert_gt(combined, prev, "luck %d" % luck)
		prev = combined


func test_blackjack_rtp_basic_strategy_400k_hands() -> void:
	var r: Dictionary = SimHelpers.blackjack(400_000, 0, 11)
	gut.p("blackjack: sim %.4f over 400k hands (basic strategy with splits)" % r["rtp"])
	assert_between(float(r["rtp"]), LOW, HIGH)


func test_blackjack_luck_monotonic() -> void:
	var prev: float = -1.0
	var line: String = "blackjack by luck:"
	for luck: int in range(-3, 4):
		var rtp: float = float(SimHelpers.blackjack(40_000, luck, 5)["rtp"])
		line += " %d:%.3f" % [luck, rtp]
		assert_gt(rtp, prev, "luck %d" % luck)
		prev = rtp
	gut.p(line)
