extends GutTest
## Scratch cards, Monte Carlo through the real station logic (§7): every tier's RTP at neutral luck
## (house rule included) lies in 100.5–102%, the simulation agrees with the exact expectation, and
## RTP rises strictly with luck from −3 to +3 (the simulation agrees with the luck model at +2).

const LOW: float = 1.005
const HIGH: float = 1.02
const CARDS: int = 200_000

var cfg: BalanceConfig = BalanceConfig.new()


## Buys and reveals `cards` cards of `tier`; {wagered, returned, rtp, hits}.
static func play(cards: int, tier: int, luck: int, seed_value: int) -> Dictionary:
	var fx: TableFixture = SimHelpers.fixture(seed_value, luck, &"scratch")
	var sc: ScratchLogic = fx.make(ScratchLogic.new()) as ScratchLogic
	sc.join(1)
	var hits: int = 0
	var price: int = sc.prices()[tier]
	for i: int in cards:
		sc.place_bet(1, {"tier": tier})
		sc.player_action(1, &"reveal")
		if int(sc.last["returned"]) > 0:
			hits += 1
		sc.events.clear()
	var wagered: int = cards * price
	var returned: int = fx.economy.balance(1) - SimHelpers.BANKROLL + wagered
	return {"wagered": wagered, "returned": returned, "rtp": returned / float(wagered), "hits": hits / float(cards)}


## Exact RTP at a luck level: the favoured outcome distribution with one luck reroll.
func _luck_rtp(tier: int, luck: int) -> float:
	var probs: Array[float] = ScratchLogic.outcome_probs(cfg, tier)
	var pays: Array[float] = []
	for i: int in probs.size():
		pays.append(ScratchLogic.outcome_multiplier(cfg, tier, i))
	var r: float = cfg.luck_reroll_per_point * absi(luck)
	var single: float = 0.0
	var paired: float = 0.0
	for i: int in pays.size():
		single += probs[i] * pays[i]
		for j: int in pays.size():
			var best: float = maxf(pays[i], pays[j]) if luck > 0 else minf(pays[i], pays[j])
			paired += probs[i] * probs[j] * best
	return (1.0 - r) * single + r * paired


## σ of one card's return (in card prices) under the favoured distribution.
func _sigma(tier: int) -> float:
	var probs: Array[float] = ScratchLogic.outcome_probs(cfg, tier)
	var m: float = 0.0
	var m2: float = 0.0
	for i: int in probs.size():
		var x: float = ScratchLogic.outcome_multiplier(cfg, tier, i)
		m += probs[i] * x
		m2 += probs[i] * x * x
	return sqrt(m2 - m * m)


func test_rtp_per_tier_monte_carlo() -> void:
	for tier: int in cfg.scratch_prices.size():
		var exact: Dictionary = ScratchLogic.exact_rtp(cfg, tier)
		var r: Dictionary = play(CARDS, tier, 0, 20261016 + tier)
		var tol: float = 3.0 * _sigma(tier) / sqrt(float(CARDS))
		gut.p("scratch $%d: exact %.4f  sim %.4f (±%.4f, 3σ)  hit exact %.3f sim %.3f" % [cfg.scratch_prices[tier], exact["rtp"], r["rtp"], tol, exact["hit_rate"], r["hits"]])
		assert_between(float(exact["rtp"]), LOW, HIGH, "tier %d exact" % tier)
		assert_almost_eq(float(r["rtp"]), float(exact["rtp"]), tol, "tier %d sim" % tier)
		assert_almost_eq(float(r["hits"]), float(exact["hit_rate"]), 0.006, "tier %d hit rate" % tier)


func test_luck_monotonic() -> void:
	for tier: int in cfg.scratch_prices.size():
		var prev: float = -1.0
		var line: String = "scratch $%d by luck:" % cfg.scratch_prices[tier]
		for luck: int in range(-3, 4):
			var rtp: float = _luck_rtp(tier, luck)
			line += " %d:%.3f" % [luck, rtp]
			assert_gt(rtp, prev, "tier %d luck %d" % [tier, luck])
			prev = rtp
		gut.p(line)
	var exact2: float = _luck_rtp(0, 2)
	var sim2: float = float(play(100_000, 0, 2, 7)["rtp"])
	gut.p("scratch $10 at luck +2: exact %.4f  sim %.4f" % [exact2, sim2])
	assert_almost_eq(sim2, exact2, 3.0 * _sigma(0) / sqrt(100_000.0) + 0.005)
