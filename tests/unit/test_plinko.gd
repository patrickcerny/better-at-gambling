extends GutTest

var cfg: BalanceConfig = BalanceConfig.new()


func test_rows_have_13_symmetric_slots() -> void:
	for risk: StringName in PlinkoLogic.RISKS:
		var m: PackedFloat32Array = cfg.plinko_multipliers(risk)
		var w: PackedInt32Array = cfg.plinko_weights(risk)
		assert_eq(m.size(), 13)
		assert_eq(w.size(), 13)
		for i: int in 6:
			assert_eq(m[i], m[12 - i])
			assert_eq(w[i], w[12 - i])
	assert_eq(cfg.plinko_mult_high[0], 60.0)


func test_exact_rtp_per_row_in_band() -> void:
	for risk: StringName in PlinkoLogic.RISKS:
		assert_between(PlinkoLogic.exact_rtp(cfg, risk), 1.005, 1.02, str(risk))


func test_drop_flow_cooldown_and_payout() -> void:
	var fx := TableFixture.new(5, [1, 2, 3], 1000)
	var pl: PlinkoLogic = fx.make(PlinkoLogic.new(), &"pl1") as PlinkoLogic
	assert_true(pl.join(1)["ok"])
	assert_true(pl.join(2)["ok"])
	assert_false(pl.join(3)["ok"])
	assert_eq(pl.place_bet(1, {"amount": 10, "risk": &"insane"})["error"], &"invalid_risk")
	assert_true(pl.place_bet(1, {"amount": 100, "risk": &"medium"})["ok"])
	assert_eq(pl.place_bet(1, {"amount": 100, "risk": &"medium"})["error"], &"cooldown")
	var slot: int = pl.drops[0]["slot"]
	var flight: float = fx.balance.plinko_flight_time
	assert_almost_eq(flight, 2.0, 0.001, "faster drop (Patrick's #7)")
	pl.tick(flight - 0.5)
	assert_eq(pl.drops.size(), 1, "still flying")
	pl.tick(0.5)
	assert_eq(pl.drops.size(), 0)
	var mult: float = fx.balance.plinko_mult_medium[slot]
	assert_eq(fx.economy.balance(1), 900 + int(floor(100 * mult + 0.000001)))
	pl.tick(maxf(fx.balance.plinko_drop_cooldown - flight, 0.0) + 0.05)
	assert_true(pl.place_bet(1, {"amount": 10, "risk": &"low"})["ok"])


func test_slot_distribution_follows_weights() -> void:
	var fx := TableFixture.new(11, [1], 100000000)
	var pl: PlinkoLogic = fx.make(PlinkoLogic.new()) as PlinkoLogic
	pl.join(1)
	var counts: Array[int] = []
	counts.resize(13)
	var n: int = 5000
	for i: int in n:
		pl.place_bet(1, {"amount": 10, "risk": &"low"})
		counts[pl.drops[-1]["slot"]] += 1
		pl.auto_resolve()
		pl.cooldowns[1] = 0.0
	var w: PackedInt32Array = fx.balance.plinko_weights_low
	var tw: float = 0.0
	for x: int in w:
		tw += x
	assert_almost_eq(counts[6] / float(n), w[6] / tw, 0.02)
	assert_almost_eq(counts[0] / float(n), w[0] / tw, 0.01)


func test_auto_resolve_lands_everything() -> void:
	var fx := TableFixture.new(5, [1], 1000)
	var pl: PlinkoLogic = fx.make(PlinkoLogic.new()) as PlinkoLogic
	pl.join(1)
	pl.place_bet(1, {"amount": 10, "risk": &"high"})
	pl.auto_resolve()
	assert_true(pl.drops.is_empty())
