extends GutTest


func test_feed_accumulates_fractions() -> void:
	var j := ProgressiveJackpot.new(0.01, 500)
	for i: int in 10:
		j.feed(10)
	assert_eq(j.pot, 501)
	j.feed(250)
	assert_eq(j.pot, 503)


func test_award_pays_and_reseeds() -> void:
	var e := Economy.new()
	e.add_player(1, 0)
	var j := ProgressiveJackpot.new(0.01, 500)
	j.feed(10000)
	assert_eq(j.award(e, 1, &"slot1", 2.0), 600)
	assert_eq(e.balance(1), 600)
	assert_eq(j.pot, 1000)
	assert_eq(e.ledger.entries[-1]["reason"], &"jackpot")
