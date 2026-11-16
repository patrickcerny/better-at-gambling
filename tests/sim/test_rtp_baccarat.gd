extends GutTest
## Baccarat return to player, played through the real table logic (eight-deck shoe, the tableau,
## the commission, the quiet favour with its stochastic rounding): every bet returns a little more
## than it costs, inside the band every table is tuned to (100.5–102%), while the printed pays
## alone keep the usual house edge.

const LOW: float = 1.005
const HIGH: float = 1.02


## Plays `rounds` rounds with one $100 bet of `type`: {rtp, sigma}.
func _play(type: StringName, rounds: int, seed_value: int) -> Dictionary:
	var fx := TableFixture.new(seed_value, [1], 2_000_000_000)
	var t: BaccaratLogic = fx.make(BaccaratLogic.new(), &"sim") as BaccaratLogic
	t.join(1)
	var back: float = 0.0
	var sq: float = 0.0
	for i: int in rounds:
		var before: int = fx.economy.balance(1)
		t.place_bet(1, {"type": type, "amount": 100})
		t.auto_resolve()
		var ret: float = (100.0 + fx.economy.balance(1) - before) / 100.0
		back += ret
		sq += ret * ret
		t.tick(10.0)  # the next round opens
	var mean: float = back / rounds
	return {"rtp": mean, "sigma": sqrt(maxf(sq / rounds - mean * mean, 0.0) / rounds)}


## The exact return of each bet with the favour (probabilities for eight decks: Player 0.446247,
## Banker 0.458597, Tie 0.095156, a pair 31/415).
func test_exact_returns_sit_in_the_band() -> void:
	var cfg := BalanceConfig.new()
	var p_win: float = 0.4462466
	var b_win: float = 0.4585974
	var tie: float = 0.0951560
	var pair: float = 31.0 / 415.0
	var player: float = 2.0 * (1.0 + cfg.baccarat_player_favour) * p_win + tie
	var banker: float = (2.0 - cfg.baccarat_banker_commission) * (1.0 + cfg.baccarat_banker_favour) * b_win + tie
	var tie_r: float = (1.0 + cfg.baccarat_tie_pays) * (1.0 + cfg.baccarat_tie_favour) * tie
	var pair_r: float = (1.0 + cfg.baccarat_pair_pays) * (1.0 + cfg.baccarat_pair_favour) * pair
	gut.p("baccarat exact RTP: player %.4f banker %.4f tie %.4f pair %.4f" % [player, banker, tie_r, pair_r])
	for r: float in [player, banker, tie_r, pair_r]:
		assert_between(r, LOW, HIGH)
	# The printed pays alone keep a house edge.
	assert_lt(2.0 * p_win + tie, 1.0)
	assert_lt((2.0 - cfg.baccarat_banker_commission) * b_win + tie, 1.0)


func test_simulated_returns_agree() -> void:
	var line: String = "baccarat sim RTP:"
	var exact: Dictionary = {&"player": 1.011, &"banker": 1.011, &"tie": 1.011, &"player_pair": 1.011}
	for type: StringName in exact:
		var res: Dictionary = _play(type, 60_000, 4242)
		line += "  %s %.4f ± %.4f" % [type, res["rtp"], res["sigma"]]
		assert_almost_eq(float(res["rtp"]), float(exact[type]), 4.0 * float(res["sigma"]) + 0.002, String(type))
	gut.p(line)
