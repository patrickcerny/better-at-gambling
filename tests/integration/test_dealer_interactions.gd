extends GutTest
## Dealer interactions (v0.8.4): attacking dealers sends player to jail, cancels bets, refunds all.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 42})


func after_each() -> void:
	fx.server.free()


func _start_at_blackjack() -> void:
	fx.server.start_match()
	fx.run(3.1)
	# Sit at blackjack table
	fx.intent(fx.player_ids[0], &"sit", {"station": &"blackjack_1"})
	fx.intent(fx.player_ids[1], &"sit", {"station": &"blackjack_1"})
	fx.run(0.5)


func _start_at_roulette() -> void:
	fx.server.start_match()
	fx.run(3.1)
	# Sit at roulette table
	fx.intent(fx.player_ids[0], &"sit", {"station": &"roulette_1"})
	fx.intent(fx.player_ids[1], &"sit", {"station": &"roulette_1"})
	fx.run(0.5)


func test_dealer_shove_sends_player_to_jail() -> void:
	_start_at_blackjack()
	var attacker: int = fx.player_ids[0]

	# Place player in world (required for dealer range detection)
	fx.place_all(Vector3(1.0, 0.5, 0.5))

	# Place bet (sits player)
	fx.intent(attacker, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 100}})
	fx.run(0.5)

	# Stand up to shove
	fx.intent(attacker, &"stand")
	fx.run(0.1)

	# Shove the dealer
	fx.intent(attacker, &"shove", {"aim": [0, 0, -1]})
	fx.run(0.1)

	# Check if player went to jail
	var p_state: PlayerState = fx.server.state.players[attacker]
	assert_gt(p_state.jail_time_remaining, 0.0, "Player should be in jail after attacking dealer")
	assert_eq(p_state.catch_count, 1, "Catch count should be 1")


func test_dealer_shove_refunds_all_bets() -> void:
	_start_at_blackjack()
	var p1: int = fx.player_ids[0]
	var p2: int = fx.player_ids[1]
	var initial_p1: int = fx.server.economy.balance(p1)
	var initial_p2: int = fx.server.economy.balance(p2)

	# Place players in world (required for dealer range detection)
	fx.place_all(Vector3(1.0, 0.5, 0.5))

	# Both players place bets
	fx.intent(p1, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 200}})
	fx.intent(p2, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 150}})
	fx.run(1.0)

	# Check that bets were taken
	var after_bet_p1: int = fx.server.economy.balance(p1)
	var after_bet_p2: int = fx.server.economy.balance(p2)
	assert_eq(after_bet_p1, initial_p1 - 200)
	assert_eq(after_bet_p2, initial_p2 - 150)

	# P1 stands up and shoves the dealer
	fx.intent(p1, &"stand")
	fx.run(0.1)
	fx.intent(p1, &"shove", {"aim": [0, 0, -1]})
	fx.run(0.1)

	# Check refund events
	var refund_events: Array[Dictionary] = fx.of_type(&"bets_refunded")
	assert_gt(refund_events.size(), 0, "Should have refund events")

	# Check balances were restored (minus jail fine)
	var after_refund_p1: int = fx.server.economy.balance(p1)
	var after_refund_p2: int = fx.server.economy.balance(p2)
	# P1 gets refunded minus jail fine (100)
	assert_eq(after_refund_p1, initial_p1 - 100, "P1 should get bet refunded minus jail fine")
	# P2 gets full refund (no jail)
	assert_eq(after_refund_p2, initial_p2, "P2 should get full bet refund")


func test_dealer_shove_cancels_hand() -> void:
	_start_at_blackjack()
	var p: int = fx.player_ids[0]

	# Place player in world (required for dealer range detection)
	fx.place_all(Vector3(1.0, 0.5, 0.5))

	# Place bet and let hand start
	fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 100}})
	fx.run(2.0)  # Wait for dealing

	# Get the logic
	var logic: BlackjackLogic = fx.server.stations.logics.get(&"blackjack_1") as BlackjackLogic
	var hands_before: int = logic.hands.size()
	assert_gt(hands_before, 0, "Should have active hands")

	# Stand and shove the dealer
	fx.intent(p, &"stand")
	fx.run(0.1)
	fx.intent(p, &"shove", {"aim": [0, 0, -1]})
	fx.run(0.1)

	# Check hand was cancelled
	var hands_after: int = logic.hands.size()
	assert_eq(hands_after, 0, "Hands should be cleared after dealer attack")


func test_roulette_dealer_shove_refunds_bets() -> void:
	_start_at_roulette()
	var p1: int = fx.player_ids[0]
	var p2: int = fx.player_ids[1]
	var initial_p1: int = fx.server.economy.balance(p1)
	var initial_p2: int = fx.server.economy.balance(p2)

	# Place players in world (required for dealer range detection)
	fx.place_all(Vector3(1.0, 0.5, 0.5))

	# Both players place bets
	fx.intent(p1, &"place_bet", {"station": &"roulette_1", "bet": {"type": &"red", "amount": 100}})
	fx.intent(p2, &"place_bet", {"station": &"roulette_1", "bet": {"type": &"black", "amount": 75}})
	fx.run(0.5)

	# Check bets were taken
	assert_eq(fx.server.economy.balance(p1), initial_p1 - 100)
	assert_eq(fx.server.economy.balance(p2), initial_p2 - 75)

	# P1 stands and shoves the dealer
	fx.intent(p1, &"stand")
	fx.run(0.1)
	fx.intent(p1, &"shove", {"aim": [0, 0, -1]})
	fx.run(0.1)

	# Check refunds
	var refund_events: Array[Dictionary] = fx.of_type(&"bets_refunded")
	assert_gt(refund_events.size(), 0, "Should have refund events")

	# P1 in jail, P2 should be refunded
	assert_eq(fx.server.economy.balance(p2), initial_p2, "P2 should get full refund")


func test_multiple_dealer_attacks_increase_jail_time() -> void:
	_start_at_blackjack()
	var p: int = fx.player_ids[0]

	# Place player in world (required for dealer range detection)
	fx.place_all(Vector3(1.0, 0.5, 0.5))

	# First attack
	fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 50}})
	fx.run(1.0)
	fx.intent(p, &"stand")
	fx.run(0.1)
	fx.intent(p, &"shove", {"aim": [0, 0, -1]})
	var jail_time_1: float = fx.server.state.players[p].jail_time_remaining
	fx.run(0.1)

	# Wait for release
	fx.run(jail_time_1 + 0.5)
	assert_eq(fx.server.state.players[p].jail_time_remaining, 0.0, "Should be released")

	# Second attack
	fx.intent(p, &"sit", {"station": &"blackjack_1"})  # Re-sit
	fx.run(0.5)
	fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 50}})
	fx.run(1.0)
	fx.intent(p, &"stand")
	fx.run(0.1)
	fx.intent(p, &"shove", {"aim": [0, 0, -1]})
	var jail_time_2: float = fx.server.state.players[p].jail_time_remaining

	# Second jail should be longer
	assert_gt(jail_time_2, jail_time_1, "Second jail time should be longer than first")
	assert_eq(fx.server.state.players[p].catch_count, 2, "Catch count should be 2")
