extends GutTest
## Hi-Lo return to player, played through the real table logic (shared single deck, reshuffles,
## the quiet favour, pays rounded down to the cent): whatever side a player calls, a hand returns
## a little more than it costs, inside the band every table is tuned to (100.5–102%), while the
## printed pays alone keep a house edge. Luck moves it up and down like at every table.

const LOW: float = 1.005
const HIGH: float = 1.02


## Plays `hands` hands of $100 for one player: {rtp, hit, expect, printed, sigma}. `pick` chooses the call from the
## hand's odds: &"best" (likelier side), &"worst" (the long shot, when it can come in) or &"random".
## `rides`: right calls before cashing out (1 = cash out after the first).
func _play(hands: int, pick: StringName, rides: int, luck_points: int, seed_value: int) -> Dictionary:
	var fx := TableFixture.new(seed_value, [1], 2_000_000_000)
	var t: HiLoLogic = fx.make(HiLoLogic.new(), &"sim") as HiLoLogic
	t.join(1)
	if luck_points != 0:
		fx.give_luck(1, luck_points)
	var r := SeededRng.new(seed_value ^ 0x5EED)
	var staked: float = 0.0
	var back: float = 0.0
	var sq: float = 0.0
	# The exact expected return of every first call as it was offered: pay × p × (1 + favour × (1 − p)).
	var expect: float = 0.0
	var printed: float = 0.0
	var f: float = fx.balance.hilo_favour
	var hits: int = 0
	for i: int in hands:
		var before: int = fx.economy.balance(1)
		t.place_bet(1, {"amount": 100})
		var first_call: bool = true
		while t.has_stake(1):
			var h: Dictionary = t.hands[1]
			if int(h["rung"]) >= rides:
				t.player_action(1, &"cash_out")
				break
			var o: Dictionary = h["odds"]
			var hi: float = float(o["higher"])
			var lo: float = float(o["lower"])
			var call: StringName = &"higher" if hi >= lo else &"lower"
			if pick == &"worst" and minf(hi, lo) > 0.0:
				call = &"lower" if hi >= lo else &"higher"
			elif pick == &"random":
				call = &"higher" if (r.chance(0.5) and hi > 0.0) or lo <= 0.0 else &"lower"
			if first_call:
				var p: float = float(o[String(call)])
				var pay: float = minf(float(h["pays"][String(call)]), fx.balance.hilo_pot_cap)
				expect += pay * p * (1.0 + f * (1.0 - p))
				printed += pay * p
				first_call = false
			t.player_action(1, call)
		var net: int = fx.economy.balance(1) - before
		var ret: float = (100.0 + net) / 100.0
		staked += 100.0
		back += 100.0 + net
		sq += ret * ret
		if net > 0:
			hits += 1
		t.tick(10.0)  # clears the finished hand
	var mean: float = back / staked
	var sigma: float = sqrt(maxf(sq / hands - mean * mean, 0.0) / hands)
	return {"rtp": mean, "hit": float(hits) / hands, "expect": expect / hands, "printed": printed / hands, "sigma": sigma}


func test_every_way_to_play_returns_a_little_more_than_it_costs() -> void:
	var line: String = "hi-lo RTP:"
	for pick: StringName in [&"best", &"random", &"worst"]:
		var res: Dictionary = _play(120_000, pick, 1, 0, 9001)
		line += "  %s: sim %.4f ± %.4f, expected %.4f (hit %.3f)" % [pick, res["rtp"], res["sigma"], res["expect"], res["hit"]]
		# What the calls were worth as offered (no luck of the draw in it) sits in the band...
		assert_between(float(res["expect"]), LOW, HIGH, "%s: the offered calls" % pick)
		# ...and what the table actually paid agrees with it within 3.5 standard errors.
		assert_almost_eq(float(res["rtp"]), float(res["expect"]), 3.5 * float(res["sigma"]), "%s: the realised return" % pick)
	gut.p(line)


func test_riding_the_ladder_stays_close_to_the_band() -> void:
	# Each ride is one more call at the same return, so a long ride compounds a little.
	var line: String = "hi-lo rides:"
	for rides: int in [2, 3]:
		var res: Dictionary = _play(120_000, &"best", rides, 0, 4242 + rides)
		line += "  best x%d %.4f (hit %.3f)" % [rides, res["rtp"], res["hit"]]
		assert_between(float(res["rtp"]), LOW, 1.06, "ride %d" % rides)
	gut.p(line)


func test_the_printed_pays_alone_keep_a_house_edge() -> void:
	# The printed pays never exceed the fair odds: at the printed chances the house keeps an edge
	# (the quiet favour is what lifts the table over 100%).
	for pick: StringName in [&"best", &"random", &"worst"]:
		var res: Dictionary = _play(20_000, pick, 1, 0, 777)
		gut.p("hi-lo %s: the printed pays at the printed chances return %.4f" % [pick, res["printed"]])
		assert_between(float(res["printed"]), 0.90, 0.995, "%s: the printed pays alone" % pick)


func test_luck_moves_the_return() -> void:
	var prev: float = -1.0
	var line: String = "hi-lo by luck:"
	for lk: int in [-3, 0, 3]:
		var rtp: float = float(_play(60_000, &"best", 1, lk, 5150)["rtp"])
		line += " %d:%.3f" % [lk, rtp]
		assert_gt(rtp, prev, "luck %d" % lk)
		prev = rtp
	gut.p(line)
