extends GutTest
## Sword Tapper, Monte Carlo through the real station logic (§7, docs/GDD.md): the RTP at neutral
## luck (house rule included) lies in 100.5–102%, the simulation agrees with the exact expectation
## (every subset of the ring counted, `SwordTapperLogic.payout_probs`), the shape of the game is
## the designed one (about 1 pull in 4 frees the sword, the best pull is 100×), and RTP rises
## strictly with luck from −3 to +3 (the simulation agrees with the luck model at +2 and −2).

const LOW: float = 1.005
const HIGH: float = 1.02
const PULLS: int = 400_000
const STAKE: int = 100

var cfg: BalanceConfig = BalanceConfig.new()
var _probs: Dictionary = {}


func before_all() -> void:
	_probs = SwordTapperLogic.payout_probs(cfg)


## Pulls the sword `pulls` times at $100 through the real logic: {rtp, free, even, ten, fifty, top}.
static func play(pulls: int, luck: int, seed_value: int) -> Dictionary:
	var fx: TableFixture = SimHelpers.fixture(seed_value, luck, &"sword_tapper")
	var st: SwordTapperLogic = fx.make(SwordTapperLogic.new()) as SwordTapperLogic
	st.join(1)
	var free: int = 0
	var even: int = 0
	var ten: int = 0
	var fifty: int = 0
	var top: int = 0
	for i: int in pulls:
		st.place_bet(1, {"amount": STAKE})
		st.auto_resolve()
		var back: int = int(st.last["returned"])
		if bool(st.last["pull"]["free"]):
			free += 1
		if back >= STAKE:
			even += 1
		if back >= STAKE * 10:
			ten += 1
		if back >= STAKE * 50:
			fifty += 1
		top = maxi(top, back)
		st.events.clear()
	var wagered: int = pulls * STAKE
	var returned: int = fx.economy.balance(1) - SimHelpers.BANKROLL + wagered
	var n: float = float(pulls)
	return {"rtp": returned / float(wagered), "free": free / n, "even": even / n, "ten": ten / n, "fifty": fifty / n, "top": top / float(STAKE)}


## Exact RTP at a luck level: one luck reroll keeps the better (luck > 0) or the worse of two pulls.
func _luck_rtp(luck: int) -> float:
	var keys: Array = _probs.keys()
	keys.sort()
	var single: float = 0.0
	var paired: float = 0.0
	var below: float = 0.0  # P(X < x) as the sorted payouts go up
	for c: Variant in keys:
		var x: float = int(c) / 100.0
		var p: float = float(_probs[c])
		single += p * x
		# P(max = x) = P(X ≤ x)² − P(X < x)²; P(min = x) = P(X ≥ x)² − P(X > x)².
		var upto: float = below + p
		if luck > 0:
			paired += x * (upto * upto - below * below)
		else:
			paired += x * ((1.0 - below) * (1.0 - below) - (1.0 - upto) * (1.0 - upto))
		below = upto
	var r: float = cfg.luck_reroll_per_point * absi(luck)
	return (1.0 - r) * single + r * paired if luck != 0 else single


## σ of one pull's return (in stakes) at neutral luck.
func _sigma() -> float:
	var m: float = 0.0
	var m2: float = 0.0
	for c: Variant in _probs:
		var x: float = int(c) / 100.0
		m += float(_probs[c]) * x
		m2 += float(_probs[c]) * x * x
	return sqrt(m2 - m * m)


## P(a pull pays at least `multiple` × the stake) at neutral luck.
func _at_least(multiple: float) -> float:
	var p: float = 0.0
	for c: Variant in _probs:
		if int(c) >= roundi(multiple * 100.0):
			p += float(_probs[c])
	return p


func test_the_distribution_is_whole() -> void:
	var total: float = 0.0
	for c: Variant in _probs:
		total += float(_probs[c])
	assert_almost_eq(total, 1.0, 0.000001, "every pull is counted once")
	assert_almost_eq(float(_probs[0]), 1.0 - SwordTapperLogic.free_chance(cfg), 0.000001, "a stuck pull pays nothing")


func test_rtp_monte_carlo() -> void:
	var exact: Dictionary = SwordTapperLogic.exact_rtp(cfg)
	var t0: int = Time.get_ticks_msec()
	var r: Dictionary = play(PULLS, 0, 20261019)
	var tol: float = 3.0 * _sigma() / sqrt(float(PULLS))
	gut.p("sword tapper: exact RTP %.4f  sim %.4f (±%.4f, 3σ, %d pulls in %d ms)  free exact %.4f sim %.4f  ≥1× %.4f  ≥10× %.4f  ≥50× %.5f  top %.1f×" % [
		exact["rtp"], r["rtp"], tol, PULLS, Time.get_ticks_msec() - t0, exact["free"], r["free"], r["even"], r["ten"], r["fifty"], r["top"]])
	assert_between(float(exact["rtp"]), LOW, HIGH, "exact RTP at neutral luck, house rule included")
	assert_between(float(r["rtp"]), LOW, HIGH, "the real draw code lands in the band too")
	assert_almost_eq(float(r["rtp"]), float(exact["rtp"]), tol, "the simulation agrees with the exact expectation")
	assert_almost_eq(float(r["free"]), float(exact["free"]), 0.004, "the sword comes free as often as designed")


func test_the_shape_of_the_game() -> void:
	var exact: Dictionary = SwordTapperLogic.exact_rtp(cfg)
	gut.p("sword tapper shape: free %.4f  ≥1× %.4f  ≥10× %.4f (1 in %d)  ≥50× %.5f (1 in %d)  max %.0f×" % [
		exact["free"], _at_least(1.0), _at_least(10.0), roundi(1.0 / _at_least(10.0)), _at_least(50.0), roundi(1.0 / _at_least(50.0)), exact["max"]])
	assert_between(float(exact["free"]), 0.24, 0.27, "about 1 pull in 4 frees the sword")
	assert_almost_eq(float(exact["max"]), 100.0, 0.001, "the best pull: the nine biggest gems (10×) times 10")
	var open: BalanceConfig = BalanceConfig.new()
	open.sword_max_pay = 1000.0
	assert_almost_eq(float(SwordTapperLogic.exact_rtp(open)["max"]), float(exact["max"]), 0.001, "the safety clamp never cuts a pull")
	assert_almost_eq(float(SwordTapperLogic.exact_rtp(open)["rtp"]), float(exact["rtp"]), 0.000001)
	assert_between(_at_least(1.0), 0.17, 0.22, "about one pull in five pays at least the stake")
	assert_between(_at_least(10.0), 0.012, 0.022, "about one pull in 60 pays 10× or more")
	assert_between(_at_least(50.0), 0.0001, 0.0006, "a 50× pull is rare")
	var without: BalanceConfig = BalanceConfig.new()
	without.sword_favour = 0.0
	var plain: float = float(SwordTapperLogic.exact_rtp(without)["rtp"])
	gut.p("sword tapper without the house rule: %.4f" % plain)
	assert_lt(plain, 1.0, "the printed odds alone keep a house edge; the quiet favour lifts it over 100%")


func test_luck_monotonic() -> void:
	var prev: float = -1.0
	var line: String = "sword tapper by luck:"
	for luck: int in range(-3, 4):
		var rtp: float = _luck_rtp(luck)
		line += " %d:%.3f" % [luck, rtp]
		assert_gt(rtp, prev, "luck %d" % luck)
		prev = rtp
	gut.p(line)
	for luck: int in [2, -2]:
		var exact: float = _luck_rtp(luck)
		var sim: float = float(play(150_000, luck, 7 + luck)["rtp"])
		gut.p("sword tapper at luck %+d: exact %.4f  sim %.4f" % [luck, exact, sim])
		assert_almost_eq(sim, exact, 3.0 * _sigma() / sqrt(150_000.0) + 0.005, "luck %d" % luck)
