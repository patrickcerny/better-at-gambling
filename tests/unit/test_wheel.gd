extends GutTest
## Wheel of Fortune (Big Six): 54 segments ($1 ×24, $2 ×15, $5 ×7, $10 ×4, $20 ×2, Joker and Logo),
## bets on symbols pay the odds printed on the layout, the countdown starts with the first bet,
## bets close when the dealer spins, the segment is told only when the wheel slows onto it, and
## the house rule (0.9.6) quietly favours the bettors without a trace on the wire.

var fx: TableFixture
var wl: WheelLogic


func before_each() -> void:
	fx = TableFixture.new(3, [1, 2, 3], 1000)
	wl = fx.make(WheelLogic.new(), &"w1") as WheelLogic
	wl.join(1)
	wl.join(2)


func _types(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Runs the wheel until the spin is paid.
func _run_to_result() -> void:
	var guard: int = 0
	while wl.state != WheelLogic.State.RESULT and guard < 2000:
		wl.tick(0.05)
		guard += 1


## The first segment carrying `symbol`.
func _segment_of(symbol: int) -> int:
	return WheelLogic.LAYOUT.find(symbol)


func test_the_wheel_has_the_big_six_segments() -> void:
	assert_eq(WheelLogic.LAYOUT.size(), WheelLogic.SEGMENTS)
	assert_eq(WheelLogic.SEGMENTS, 54)
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	for s: int in WheelLogic.LAYOUT:
		counts[s] += 1
	assert_eq(counts, WheelLogic.COUNTS, "$1 ×24, $2 ×15, $5 ×7, $10 ×4, $20 ×2, Joker ×1, Logo ×1")
	assert_eq(WheelLogic.COUNTS, [24, 15, 7, 4, 2, 1, 1] as Array[int])
	assert_eq(WheelLogic.PAYS, [1, 2, 5, 10, 20, 40, 40] as Array[int], "a symbol pays its face value, Joker and Logo 40:1")
	assert_eq(WheelLogic.odds_text(2), "5:1")
	assert_eq(WheelLogic.odds_text(6), "40:1")
	# Joker and Logo face each other; no two of the rarer symbols touch.
	assert_eq(absi(WheelLogic.LAYOUT.find(5) - WheelLogic.LAYOUT.find(6)), 27)
	for i: int in WheelLogic.SEGMENTS:
		var a: int = WheelLogic.LAYOUT[i]
		var b: int = WheelLogic.symbol_at(i + 1)
		assert_false(a != 0 and a == b, "segments %d and %d are not both %s" % [i, i + 1, WheelLogic.LABELS[a]])
	assert_eq(WheelLogic.symbol_at(-1), WheelLogic.LAYOUT[53], "wraps round")


func test_countdown_starts_with_the_first_bet_and_bets_close_at_the_spin() -> void:
	assert_eq(wl.state, WheelLogic.State.BETTING)
	wl.tick(60.0)
	assert_eq(wl.state, WheelLogic.State.BETTING, "no spin without a bet")
	assert_false(wl.counting)
	assert_true(wl.place_bet(1, {"symbol": 0, "amount": 20})["ok"])
	assert_true(wl.counting)
	assert_almost_eq(wl.timer, fx.balance.wheel_countdown, 0.001)
	wl.tick(fx.balance.wheel_countdown - 0.1)
	assert_true(wl.place_bet(2, {"symbol": 5, "amount": 10})["ok"], "still open just before the spin")
	wl.drain_events()
	wl.tick(0.2)
	assert_eq(wl.state, WheelLogic.State.SPINNING)
	var evs: Array[Dictionary] = wl.drain_events()
	assert_eq(_types(evs, &"wheel_spin_started").size(), 1)
	assert_false(_types(evs, &"wheel_spin_started")[0].has("segment"), "the result is not told at the spin")
	assert_eq(int(wl.get_public_state()["segment"]), -1, "nor in the state while it spins at full speed")
	assert_eq(wl.place_bet(1, {"symbol": 0, "amount": 10})["error"], &"betting_closed")
	assert_eq(wl.player_action(1, &"clear_bets")["error"], &"betting_closed")
	assert_eq(fx.economy.balance(1), 980, "the stake is in")
	assert_true(wl.has_stake(1))
	# Full speed for `wheel_spin_time`, then the segment is announced and the wheel slows onto it.
	wl.tick(fx.balance.wheel_spin_time + 0.01)
	var res: Array[Dictionary] = _types(wl.drain_events(), &"wheel_result")
	assert_eq(res.size(), 1)
	assert_almost_eq(float(res[0]["seconds"]), WheelLogic.LAND_TIME, 0.001)
	assert_eq(int(res[0]["symbol"]), WheelLogic.symbol_at(int(res[0]["segment"])))
	var pub: Dictionary = wl.get_public_state()
	assert_true(bool(pub["landing"]))
	assert_eq(int(pub["segment"]), int(res[0]["segment"]), "a late joiner can slow onto it too")
	assert_eq(fx.economy.balance(1), 980, "nothing paid until the pointer rests")
	wl.tick(WheelLogic.LAND_TIME - 0.1)
	assert_eq(wl.state, WheelLogic.State.SPINNING)
	wl.tick(0.2)
	assert_eq(wl.state, WheelLogic.State.RESULT, "paid as the wheel stops")


func test_bet_rules() -> void:
	assert_eq(wl.place_bet(1, {"symbol": 7, "amount": 10})["error"], &"invalid_symbol")
	assert_eq(wl.place_bet(1, {"symbol": -1, "amount": 10})["error"], &"invalid_symbol")
	assert_eq(wl.place_bet(1, {"amount": 10})["error"], &"invalid_symbol")
	assert_eq(wl.place_bet(1, {"symbol": 0, "amount": 5})["error"], &"below_min")
	assert_eq(wl.place_bet(3, {"symbol": 0, "amount": 10})["error"], &"not_seated")
	assert_true(wl.place_bet(1, {"symbol": 0, "amount": 100})["ok"])
	assert_true(wl.place_bet(1, {"symbol": 5, "amount": 50})["ok"], "several symbols at once")
	assert_true(wl.place_bet(1, {"symbol": 0, "amount": 50})["ok"], "more on the same symbol")
	assert_eq(wl.place_bet(1, {"symbol": 3, "amount": 10})["error"], &"above_max", "$200 per spin in all")
	assert_eq(wl.player_total(1), 200)
	assert_true(wl.player_action(1, &"clear_bets")["ok"])
	assert_eq(fx.economy.balance(1), 1000)
	assert_false(wl.counting, "everyone took their chips back: wait for a new first bet")
	wl.limits_multiplier = 2.0
	assert_eq(wl.limits(), Vector2i(20, 400), "limits rise with the segment like every table")
	fx.economy.take_up_to(2, 995, &"test")
	assert_eq(wl.place_bet(2, {"symbol": 0, "amount": 20})["error"], &"insufficient_funds")


## Sets the drawn segment before it is announced (bypassing the draw) and runs to the payout.
func _force(seg: int) -> void:
	wl.tick(fx.balance.wheel_countdown + 0.01)
	assert_eq(wl.state, WheelLogic.State.SPINNING)
	wl._pending = seg
	wl.drain_events()
	_run_to_result()


func test_payouts_are_the_odds_on_the_layout() -> void:
	for symbol: int in WheelLogic.SYMBOLS.size():
		var f := TableFixture.new(5, [1, 2], 10000)
		wl = f.make(WheelLogic.new(), &"w1") as WheelLogic
		wl.join(1)
		wl.join(2)
		assert_true(wl.place_bet(1, {"symbol": symbol, "amount": 10})["ok"])
		var other: int = (symbol + 1) % WheelLogic.SYMBOLS.size()
		assert_true(wl.place_bet(2, {"symbol": other, "amount": 30})["ok"])
		_force(_segment_of(symbol))
		assert_eq(wl.segment, _segment_of(symbol))
		var pays: int = WheelLogic.PAYS[symbol]
		assert_eq(f.economy.balance(1), 10000 - 10 + 10 * (pays + 1), "%s pays %d:1" % [WheelLogic.LABELS[symbol], pays])
		assert_eq(f.economy.balance(2), 10000 - 30, "the other symbol loses its stake to the house")
		var results: Array[Dictionary] = _types(wl.drain_events(), &"round_result")
		assert_eq(results.size(), 2)
		for r: Dictionary in results:
			assert_eq(int(r["net"]), 10 * pays if int(r["player"]) == 1 else -30)
			assert_eq(int(r["details"]["segment"]), _segment_of(symbol))
			assert_eq(int(r["details"]["won"]), symbol)
		assert_eq(int(wl.history[0]), symbol, "the board's newest result")


func test_several_bets_one_player_settle_each() -> void:
	assert_true(wl.place_bet(1, {"symbol": 0, "amount": 50})["ok"])
	assert_true(wl.place_bet(1, {"symbol": 2, "amount": 20})["ok"])
	assert_true(wl.place_bet(1, {"symbol": 6, "amount": 10})["ok"])
	_force(_segment_of(2))
	assert_eq(fx.economy.balance(1), 1000 - 80 + 20 * 6, "the $5 bet pays 5:1, the others go")
	var mine: Array[Dictionary] = _types(wl.drain_events(), &"round_result")
	assert_eq(mine.size(), 3, "one result per bet")
	assert_false(wl.has_stake(1))
	assert_eq(wl.return_for(1, _segment_of(2)), 0, "the bets are cleared once paid")


func test_hot_table_and_items_multiply_the_winnings_only() -> void:
	wl.hot_multiplier = 1.25
	assert_true(wl.place_bet(1, {"symbol": 1, "amount": 40})["ok"])
	_force(_segment_of(1))
	assert_eq(fx.economy.balance(1), 1000 - 40 + 40 + int(floor(80 * 1.25)), "$2 pays 2:1, the Hot Table ×1.25 on the winnings")
	var r: Dictionary = _types(wl.drain_events(), &"round_result")[0]
	assert_almost_eq(float(r["details"]["multiplier"]), 1.25, 0.0001)


## Counts how many of `n` draws (fresh bets each time) land on `symbol`.
func _wins(n: int, bets: Array[Dictionary], symbol: int) -> int:
	var won: int = 0
	for _i: int in n:
		wl.bets.assign(bets.duplicate(true))
		if WheelLogic.symbol_at(wl._draw_segment()) == symbol:
			won += 1
	return won


func test_the_bettors_are_quietly_favoured() -> void:
	var bets: Array[Dictionary] = [{"player": 1, "symbol": 2, "amount": 10}]
	var n: int = 6000
	fx.balance.wheel_favour = 0.0
	fx.rng.reseed(777)
	var plain: int = _wins(n, bets, 2)
	fx.balance.wheel_favour = 1.0
	fx.rng.reseed(777)
	var favoured: int = _wins(n, bets, 2)
	var p: float = WheelLogic.chance_of(2)
	gut.p("$5: %d plain, %d with a sure redraw of %d (honest %.0f, redraw %.0f)" % [plain, favoured, n, n * p, n * (p + (1.0 - p) * p)])
	assert_almost_eq(plain / float(n), p, 0.015, "without the favour the wheel is honest")
	assert_almost_eq(favoured / float(n), p + (1.0 - p) * p, 0.015, "one redraw of a losing spin, never more")
	# Nothing on the wire says so: no favour in the events or the state.
	wl.bets.clear()
	fx.balance.wheel_favour = 1.0
	wl.place_bet(1, {"symbol": 2, "amount": 10})
	wl.tick(fx.balance.wheel_countdown + fx.balance.wheel_spin_time + 0.05)
	for ev: Dictionary in wl.drain_events():
		for key: Variant in ev:
			assert_false(String(key).contains("favour") or String(key).contains("redraw") or String(key).contains("pending"), "%s carries nothing of the draw" % ev["type"])
	for key: Variant in wl.get_public_state():
		assert_false(String(key).contains("favour") or String(key).contains("pending"))
	assert_eq(_types(wl.drain_events(), &"luck_flourish").size(), 0, "the favour is no luck flourish")


func test_a_spin_someone_wins_is_never_redrawn() -> void:
	# Bets on every symbol: whatever comes up, somebody wins, so the favour never redraws.
	fx.balance.wheel_favour = 1.0
	var bets: Array[Dictionary] = []
	for s: int in WheelLogic.SYMBOLS.size():
		bets.append({"player": 1 + s % 2, "symbol": s, "amount": 10})
	var hits: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	fx.rng.reseed(4)
	for _i: int in 5400:
		wl.bets.assign(bets.duplicate(true))
		hits[WheelLogic.symbol_at(wl._draw_segment())] += 1
	for s: int in hits.size():
		assert_almost_eq(hits[s] / 5400.0, WheelLogic.chance_of(s), 0.015, "%s comes up at its honest rate" % WheelLogic.LABELS[s])


func test_luck_rerolls_the_spin_like_the_other_tables() -> void:
	fx.balance.wheel_favour = 0.0
	var bets: Array[Dictionary] = [{"player": 1, "symbol": 1, "amount": 10}]
	wl.luck.reroll_per_point = 1.0 / 3.0  # +3 luck: always a second draw
	fx.give_luck(1, 3)
	fx.rng.reseed(99)
	var lucky: int = _wins(4000, bets, 1)
	wl.luck.reroll_per_point = 0.0
	fx.rng.reseed(99)
	var plain: int = _wins(4000, bets, 1)
	var p: float = WheelLogic.chance_of(1)
	gut.p("$2 with +3 luck forced: %d vs %d of 4000" % [lucky, plain])
	assert_almost_eq(lucky / 4000.0, 1.0 - (1.0 - p) * (1.0 - p), 0.025, "the better of two draws")
	assert_gt(lucky, plain)
	# Jinxed: the worse of two.
	fx.modifiers.remove_by_id(1, &"test_luck")
	fx.give_luck(1, -3)
	wl.luck.reroll_per_point = 1.0 / 3.0
	fx.rng.reseed(99)
	var jinxed: int = _wins(4000, bets, 1)
	assert_almost_eq(jinxed / 4000.0, p * p, 0.02, "the worse of two draws")
	# A flourish shows only when the reroll changed the outcome (as at every table).
	wl.bets.clear()
	fx.modifiers.remove_by_id(1, &"test_luck")
	fx.give_luck(1, 3)
	wl.drain_events()
	var flourishes: int = 0
	for _i: int in 200:
		wl.bets.assign(bets.duplicate(true))
		wl._draw_segment()
		flourishes += _types(wl.drain_events(), &"luck_flourish").size()
	assert_between(flourishes, 20, 120, "the clover shows on the spins it turned (%d of 200)" % flourishes)


func test_luck_compares_what_the_spin_pays_the_player() -> void:
	wl.bets.assign([{"player": 1, "symbol": 0, "amount": 50}, {"player": 1, "symbol": 4, "amount": 10}, {"player": 2, "symbol": 5, "amount": 10}] as Array[Dictionary])
	assert_eq(wl.return_for(1, _segment_of(0)), 100)
	assert_eq(wl.return_for(1, _segment_of(4)), 210, "$20 pays 20:1")
	assert_eq(wl.return_for(1, _segment_of(5)), 0, "another player's Joker pays player 1 nothing")
	assert_eq(wl.return_for(2, _segment_of(5)), 410)


func test_the_draw_is_deterministic_from_the_seed() -> void:
	var a: Array[int] = []
	var b: Array[int] = []
	for run: int in 2:
		var f := TableFixture.new(2026, [1, 2], 1000)
		var w: WheelLogic = f.make(WheelLogic.new(), &"w1") as WheelLogic
		w.join(1)
		w.join(2)
		f.give_luck(2, 2)
		for spin: int in 12:
			w.place_bet(1, {"symbol": spin % 7, "amount": 10})
			w.place_bet(2, {"symbol": (spin + 3) % 7, "amount": 20})
			for _t: int in 600:
				w.tick(0.05)
				if w.state == WheelLogic.State.RESULT:
					break
			(a if run == 0 else b).append(w.segment)
			w.tick(f.balance.wheel_result_time + 0.1)
	assert_eq(a, b, "the same seed spins the same segments")
	assert_gt(a.size(), 11)


func test_refund_and_auto_resolve() -> void:
	wl.place_bet(1, {"symbol": 3, "amount": 40})
	wl.tick(fx.balance.wheel_countdown + 0.01)
	assert_eq(wl.state, WheelLogic.State.SPINNING)
	wl.drain_events()
	wl.refund_all()
	assert_eq(fx.economy.balance(1), 1000, "a minigame gives the stake back mid-spin")
	assert_eq(wl.state, WheelLogic.State.IDLE)
	var evs: Array[Dictionary] = wl.drain_events()
	assert_eq(_types(evs, &"bets_refunded").size(), 1)
	assert_eq(int(_types(evs, &"bets_refunded")[0]["amount"]), 40)
	assert_eq(_types(evs, &"table_reset").size(), 1)
	assert_eq(_types(evs, &"round_result").size(), 0, "no win, no loss")
	wl.tick(0.1)
	assert_eq(wl.state, WheelLogic.State.BETTING, "players still seated: a new round")
	wl.place_bet(2, {"symbol": 0, "amount": 20})
	wl.auto_resolve()
	assert_eq(wl.state, WheelLogic.State.RESULT, "the match end spins at once")
	assert_eq(_types(wl.drain_events(), &"wheel_result").size(), 1, "the segment is still announced")
	assert_eq(fx.economy.balance(2), 980 + (40 if WheelLogic.symbol_at(wl.segment) == 0 else 0))


func test_refund_mid_landing_and_fake_cash_never_turns_into_money() -> void:
	var m := Modifier.new()
	m.id = &"fake_cash"
	m.flags[&"fake_cash"] = true
	fx.modifiers.add(1, m)
	assert_true(wl.place_bet(1, {"symbol": 0, "amount": 30})["ok"])
	assert_eq(fx.economy.balance(1), 1000, "Fake Cash paid this stake")
	wl.tick(fx.balance.wheel_countdown + 0.01)
	wl.tick(fx.balance.wheel_spin_time + 0.01)
	assert_true(bool(wl.get_public_state()["landing"]), "the wheel is slowing down")
	wl.refund_all()
	assert_eq(fx.economy.balance(1), 1000, "nothing comes back for the Fake Cash part")


func test_leaving_mid_spin_still_settles() -> void:
	wl.place_bet(1, {"symbol": 0, "amount": 10})
	wl.tick(fx.balance.wheel_countdown + 0.01)
	wl.leave(1)
	wl.leave(2)
	_run_to_result()
	assert_eq(wl.state, WheelLogic.State.RESULT)
	assert_eq(fx.economy.balance(1), 990 + (20 if WheelLogic.symbol_at(wl.segment) == 0 else 0))
	wl.tick(fx.balance.wheel_result_time + 0.1)
	assert_eq(wl.state, WheelLogic.State.IDLE, "an empty wheel rests")


func test_energy_drink_hurries_the_waiting_not_the_slow_down() -> void:
	var m := Modifier.new()
	m.id = &"energy_drink"
	m.flags[&"fast_tables"] = true
	fx.modifiers.add(1, m)
	wl.leave(2)
	wl.place_bet(1, {"symbol": 0, "amount": 10})
	wl.tick(fx.balance.wheel_countdown * 0.5 + 0.01)
	assert_eq(wl.state, WheelLogic.State.SPINNING, "the countdown runs twice as fast alone")
	wl.tick(fx.balance.wheel_spin_time * 0.5 + 0.01)
	assert_true(bool(wl.get_public_state()["landing"]))
	wl.tick(WheelLogic.LAND_TIME * 0.6)
	assert_eq(wl.state, WheelLogic.State.SPINNING, "the slow-down runs at its real pace on every client")


func test_round_seconds_cover_the_spin() -> void:
	assert_almost_eq(wl.round_seconds(), fx.balance.wheel_countdown + fx.balance.wheel_spin_time + WheelLogic.LAND_TIME, 0.001)
	assert_true(wl.can_join(3))
	for p: int in [3, 4, 5]:
		wl.join(p)
	assert_false(wl.can_join(6), "five stools")
	assert_eq(wl.join(6)["error"], &"seat_taken")


func test_exact_rtp_with_the_favour() -> void:
	var line: String = "wheel RTP at favour %.2f:" % fx.balance.wheel_favour
	var sum: float = 0.0
	for s: int in WheelLogic.SYMBOLS.size():
		var honest: float = WheelLogic.exact_rtp(s, 0.0)
		var rtp: float = WheelLogic.exact_rtp(s, fx.balance.wheel_favour)
		line += " %s %.4f (honest %.4f)" % [WheelLogic.LABELS[s], rtp, honest]
		assert_lt(honest, 0.9, "the printed odds alone keep a Big Six house edge")
		assert_between(rtp, 0.98, 1.05, WheelLogic.LABELS[s])
		sum += rtp
	gut.p(line)
	assert_between(sum / WheelLogic.SYMBOLS.size(), 1.005, 1.02, "over the seven symbols the wheel is in the casino's band")
