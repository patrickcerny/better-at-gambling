class_name BalanceConfig
extends Resource
## Every tunable balance number (§2.21). Logic code reads values from here, never literals.
## Defaults below are the design values; `data/balance/balance.tres` is the tuned instance.

@export_group("Economy")
@export var start_money: int = 1000
## House Comp for broke players by minigames played so far (Patrick, 2026-10-07): $300 at the
## start, +$150 after each minigame, $900 from the fourth minigame on (the last entry repeats).
@export var comp_amounts: PackedInt32Array = PackedInt32Array([300, 450, 600, 750, 900])
@export var comp_threshold: int = 10
@export var limits_multiplier_step: float = 0.5
@export var limits_multiplier_cap: float = 3.0
@export var last_call_seconds: float = 60.0
@export var last_call_multiplier: float = 1.5
@export var hot_table_multiplier: float = 1.25
@export var hot_table_interval_min: float = 45.0
@export var hot_table_interval_max: float = 60.0
@export var hot_table_duration: float = 30.0

@export_group("Luck")
@export var luck_reroll_per_point: float = 0.12
@export var luck_clamp: int = 3

@export_group("Blackjack")
@export var bj_decks: int = 6
@export var bj_penetration: float = 0.75
@export var bj_min_bet: int = 10
@export var bj_max_bet: int = 200
@export var bj_betting_window: float = 8.0
@export var bj_action_time: float = 10.0
@export var bj_result_time: float = 2.0
## A split gives the splitting player this many extra decision clocks (x bj_action_time) on top
## of what they had left, so both hands can be played (1.0 = the full decision time again).
@export var bj_split_time_bonus: float = 1.0
## Profit ratio paid on winning hands when the dealer busts (1.0 = plain 1:1).
@export var bj_dealer_bust_bonus: float = 1.07
@export var bj_blackjack_ratio: float = 1.5

@export_group("Roulette")
@export var roulette_min_bet: int = 10
@export var roulette_max_total: int = 300
@export var roulette_betting_time: float = 15.0
## Matched to Patrick's wheel recording: the ball rattles into a pocket 3.4 s in and the
## sound ends at 5.4 s (`RouletteWheelFx.DROP_TIME` covers the rest).
@export var roulette_spin_time: float = 3.4
@export var roulette_result_time: float = 3.0
## Extra fraction of the total return (stake + winnings) paid on every winning roulette bet.
@export var roulette_generosity: float = 0.04
@export var roulette_lucky_neighbor_ratio: float = 5.0
@export var roulette_jinx_ratio: float = 0.9

@export_group("Horse Race")
@export var horse_min_bet: int = 10
## Most one player may stake on one race (all on the one horse they back).
@export var horse_max_total: int = 100
## Profit ratio on the winning horse. The table says 1:4; Patrick wants it to pay "a bit better".
@export var horse_payout_ratio: float = 4.5
## Chance that a race nobody at the table would win is redrawn once (Patrick: "always favoured to
## win for you, by a bit, like the other games, but dont show it").
@export var horse_favour: float = 0.3
## Seconds from the first bet of a round until the gates open.
@export var horse_countdown: float = 12.0
## Seconds the result stays up after the winner crosses the line (the rest run out meanwhile).
@export var horse_result_time: float = 5.0

@export_group("Craps")
@export var craps_min_bet: int = 10
## Most one player may have on the craps felt at once (line bets riding a point included).
@export var craps_max_total: int = 200
## Profit ratios actually paid. The felt says Pass / Don't Pass 1:1, Field 1:1 (2 and 12 2:1) and
## Any Seven 4:1; the one-roll bets pay a little better (like the horse race's 1:4), so with the
## favour below every bet returns 100.5–102% to a player alone at the table (tests/sim).
@export var craps_line_ratio: float = 1.0
@export var craps_field_ratio: float = 1.08
@export var craps_field_double_ratio: float = 2.1
@export var craps_any_seven_ratio: float = 4.8
## Chance that a roll on which no bet at the table wins (and one would lose) is redrawn once
## (Patrick, 0.9.6: "always favoured to win for you, by a bit, like the other games, but dont
## show it").
@export var craps_favour: float = 0.055
## Seconds from the first chip on the felt (or from a roll while a point is on) until the stickman
## throws for a shooter who has not pressed SHOOT.
@export var craps_shoot_time: float = 12.0
## Seconds a betting window stays open before the shooter may throw (everyone gets a chance to bet).
@export var craps_shoot_lock: float = 2.0
## Seconds from the throw until the dice rest and the bets settle (the client throw rests by
## `CrapsDice.REST_TIME`, inside this).
@export var craps_throw_time: float = 2.6
## Seconds the roll stays up before the next betting window.
@export var craps_result_time: float = 2.0

@export_group("Wheel of Fortune")
@export var wheel_min_bet: int = 10
## Most one player may stake on one spin, over every symbol together.
@export var wheel_max_total: int = 200
## Chance that a spin nobody at the wheel would win is redrawn once (the house rule of 0.9.6:
## every table quietly favours its bettors a bit, never shown). The wheel pays its honest Big Six
## odds; 0.31 lifts a lone bettor's return to 98.8–104.9% depending on the symbol (101.3% over the
## seven symbols, `tests/sim/test_wheel_rtp.gd`).
@export var wheel_favour: float = 0.31
## Seconds from the first bet of a round until the dealer spins.
@export var wheel_countdown: float = 12.0
## Seconds the wheel spins at full speed before it starts slowing onto the result
## (`WheelLogic.LAND_TIME` covers the slowing down).
@export var wheel_spin_time: float = 3.0
## Seconds the result stays up before the next round opens.
@export var wheel_result_time: float = 4.0
@export_group("Hi-Lo")
@export var hilo_min_bet: int = 10
@export var hilo_max_bet: int = 100
## What a right call returns on average per $1 riding on it, the quiet favour counted in: the pays
## are set from this (`HiLoLogic.pay_for`) and never exceed the fair odds 1/p.
@export var hilo_return: float = 1.02
## Chance that a call which would lose has its card redrawn once (Patrick's house rule from 0.9.6:
## "favoured for you, by a bit, like the other games, but dont show it").
@export var hilo_favour: float = 0.15
## Most a single right call pays (stake included), however long the shot.
@export var hilo_max_pay: float = 25.0
## The streak ladder: right calls in one hand before it cashes out on its own, and the most a pot
## can grow to (times the ante).
@export var hilo_max_rungs: int = 6
@export var hilo_pot_cap: float = 50.0
## The single deck is reshuffled before an ante once fewer cards than this are left.
@export var hilo_reshuffle_at: int = 15
## Seconds to make a call (then the table calls for you) and how long a result stays up.
@export var hilo_action_time: float = 15.0
@export var hilo_result_time: float = 2.5

@export_group("Casino Hold'em")
## Ante limits (× limits); the call is always twice the ante.
@export var holdem_min_bet: int = 10
@export var holdem_max_bet: int = 100
## The optional AA Bonus side bet: 0, or between the table minimum and this (× limits).
@export var holdem_bonus_max_bet: int = 50
## What the ante pays (profit per $1, by `HoldemHand.Rank`, high card → royal flush) when the
## dealer does not qualify or the player's hand wins: the standard Casino Hold'em ante paytable
## (straight or lower 1:1, flush 2:1, full house 3:1, quads 10:1, straight flush 20:1, royal 100:1).
@export var holdem_ante_pays: PackedInt32Array = PackedInt32Array([1, 1, 1, 1, 1, 2, 3, 10, 20, 100])
## The AA Bonus on the player's first five cards (two hole cards + the flop), by `HoldemHand.Rank`:
## a pair pays only when it is aces (Evolution's paytable: pair of aces to straight 7:1, flush 20:1,
## full house 30:1, quads 40:1, straight flush 50:1, royal 100:1).
@export var holdem_bonus_pays: PackedInt32Array = PackedInt32Array([0, 7, 7, 7, 7, 20, 30, 40, 50, 100])
## Chance that a showdown no called hand at the table would win (and one would lose) has its
## unseen cards (turn, river, the dealer's two) drawn again once: the quiet house rule of 0.9.6
## ("always favoured to win for you, by a bit, like the other games, but dont show it"). Tuned so a
## lone player's simple strategy returns 100.5–102% (`tests/sim/test_rtp_holdem.gd`).
@export var holdem_favour: float = 0.1
## The same for the AA Bonus: a flop on which no bonus bet at the table pays is drawn again once
## with this chance (only while someone has a bonus bet out).
@export var holdem_bonus_favour: float = 0.1
## Seconds from the first ante until the cards are dealt (others can still ante).
@export var holdem_betting_window: float = 8.0
## Each player's clock to FOLD or CALL once the flop is out; out of time = fold (the real rule).
@export var holdem_action_time: float = 15.0
## Seconds the showdown stays up before the next hand.
@export var holdem_result_time: float = 4.0

@export_group("Slots")
@export var slots_bet_sizes: PackedInt32Array = PackedInt32Array([10, 25, 50, 100])
@export var slots_spin_time: float = 1.6
@export var slots_skip_after: float = 0.5
## Seconds after a spin ends (or is stopped) before the next pull is accepted: the reels settle.
@export var slots_settle_time: float = 1.7
## Symbol order: cherry, lemon, bell, bar, seven, clover (wild), diamond.
@export var slots_reel_weights: PackedInt32Array = PackedInt32Array([9, 11, 9, 7, 3, 1, 1])
## Three-of-a-kind multipliers, same symbol order (clover x3 pays as diamond).
@export var slots_three_pay: PackedInt32Array = PackedInt32Array([6, 8, 12, 20, 40, 100, 100])
@export var slots_two_cherry_pay: int = 2
@export var slots_one_cherry_pay: int = 1

@export_group("Scratch Cards")
## Card prices, cheapest first (× table limits). Each tier has its own printed prize table.
@export var scratch_prices: PackedInt32Array = PackedInt32Array([10, 25, 50])
## Three in a line pays this many times the card price, per tier, symbol order cherry, lemon,
## bell, clover, seven, diamond (the card prints these as dollar amounts).
@export var scratch_pays_low: PackedFloat32Array = PackedFloat32Array([1, 2, 3, 5, 15, 50])
@export var scratch_pays_mid: PackedFloat32Array = PackedFloat32Array([1, 2, 4, 8, 25, 100])
@export var scratch_pays_high: PackedFloat32Array = PackedFloat32Array([1, 3, 5, 10, 40, 200])
## A "$" anywhere on the card pays this many times the card price, per tier.
@export var scratch_cash_pays: PackedFloat32Array = PackedFloat32Array([0.5, 0.4, 0.5])
## How likely each card is, per tier: blank, "$" only, then three in a line of cherry, lemon,
## bell, clover, seven, diamond. The server draws the outcome and builds a card that shows it.
@export var scratch_odds_low: PackedInt32Array = PackedInt32Array([31300, 9000, 14000, 6000, 3000, 1400, 500, 100])
@export var scratch_odds_mid: PackedInt32Array = PackedInt32Array([40800, 8000, 12000, 6000, 2500, 1200, 400, 60])
@export var scratch_odds_high: PackedInt32Array = PackedInt32Array([52600, 7000, 11000, 4500, 2000, 1000, 300, 40])
## House rule (0.9.6): chance that a card that would be a total blank is drawn again once, never
## shown or sent (Patrick: "always favoured to win for you, by a bit, like the other games").
@export var scratch_favour: float = 0.25
## Seconds an unscratched card may lie on the counter before it scratches itself and pays.
@export var scratch_auto_reveal: float = 60.0

@export_group("Sword Tapper")
## Stake per pull (× table limits); chip buttons like Hi-Lo, all-in over the balance.
@export var sword_min_bet: int = 10
@export var sword_max_bet: int = 100
## Chance that a pull frees the sword (the panel says "about 1 pull in 4"; tuned so the RTP at
## neutral luck lands in 100.5–102%, `tests/sim/test_rtp_sword_tapper.gd`).
@export var sword_pull_chance: float = 0.24
## House rule (0.9.6): chance that a stuck pull is drawn again once, never shown or sent.
@export var sword_favour: float = 0.08
## The ring of 17 gem lamps, clockwise from the top (the big ruby): each pays this many times the
## stake when the sword lights it (all 17 together are 11×).
@export var sword_ring: PackedFloat32Array = PackedFloat32Array([5, 0.1, 0.2, 0.1, 0.5, 0.1, 0.3, 0.2, 1, 2, 0.2, 0.3, 0.1, 0.5, 0.1, 0.2, 0.1])
## How many gems a freed sword lights, weights for 3, 4, … 17 gems (which ones is a uniform
## random pick from the ring).
@export var sword_count_weights: PackedFloat32Array = PackedFloat32Array([40, 24, 13, 8, 5, 3.5, 2.5, 1.4, 0.9, 0.6, 0.4, 0.3, 0.2, 0.15, 0.05])
## The multiplier that may slam down on a win of `sword_mult_max_gems` gems or fewer, and its
## weights (×1 = none).
@export var sword_mult_values: PackedInt32Array = PackedInt32Array([1, 2, 3, 5, 10])
@export var sword_mult_weights: PackedFloat32Array = PackedFloat32Array([80, 12, 5, 2.5, 0.5])
@export var sword_mult_max_gems: int = 9
## Safety clamp on one pull's win, times the stake (the best pull, the nine biggest gems × 10, is
## exactly 100×: the clamp never cuts one).
@export var sword_max_pay: float = 100.0
## Seconds the reveal plays (sword, gems, multiplier) before the pull pays.
@export var sword_reveal_time: float = 2.5
## A pull paying at least this many times the stake is a big pull: a feed line and a golden light
## column over the pedestal that the whole floor sees.
@export var sword_big_win: float = 20.0

@export_group("Plinko")
@export var plinko_bet_sizes: PackedInt32Array = PackedInt32Array([10, 25, 50, 100])
@export var plinko_drop_cooldown: float = 2.5
@export var plinko_flight_time: float = 2.0
@export var plinko_mult_low: PackedFloat32Array = PackedFloat32Array([5, 2, 1.5, 1.1, 1, 0.6, 0.5, 0.6, 1, 1.1, 1.5, 2, 5])
@export var plinko_mult_medium: PackedFloat32Array = PackedFloat32Array([13, 4, 2, 1.4, 0.8, 0.5, 0.3, 0.5, 0.8, 1.4, 2, 4, 13])
@export var plinko_mult_high: PackedFloat32Array = PackedFloat32Array([60, 12, 3, 1.2, 0.4, 0.2, 0.2, 0.2, 0.4, 1.2, 3, 12, 60])
@export var plinko_weights_low: PackedInt32Array = PackedInt32Array([717, 1604, 3100, 5175, 7462, 9294, 10000, 9294, 7462, 5175, 3100, 1604, 717])
@export var plinko_weights_medium: PackedInt32Array = PackedInt32Array([285, 845, 2057, 4109, 6735, 9059, 10000, 9059, 6735, 4109, 2057, 845, 285])
@export var plinko_weights_high: PackedInt32Array = PackedInt32Array([113, 445, 1365, 3262, 6078, 8830, 10000, 8830, 6078, 3262, 1365, 445, 113])
@export var plinko_edge_jackpot_chance: float = 0.25

@export_group("Jackpot")
@export var jackpot_feed_rate: float = 0.01
@export var jackpot_seed: int = 500

@export_group("Movement")
@export var walk_speed: float = 5.5
@export var sprint_speed: float = 8.0
@export var sprint_stamina: float = 4.0
@export var stamina_regen_per_second: float = 0.5
@export var jump_height: float = 1.1
@export var acceleration: float = 30.0
@export var deceleration: float = 14.0
@export var held_speed_factor: float = 0.5
@export var soaked_seconds: float = 3.0
@export var soaked_speed_factor: float = 0.5
@export var mezzanine_fall_height: float = 2.5
@export var throw_out_respawn_seconds: float = 4.0

@export_group("Physical interaction")
@export var shove_cooldown: float = 1.2
@export var shove_knockdown_window: float = 1.5
@export var shove_knockout_count: int = 3
@export var shove_knockout_window: float = 4.0
@export var knockdown_time: float = 1.5
@export var knockout_time: float = 2.5
@export var knockout_immunity: float = 4.0
@export var spawn_protection: float = 3.0
@export var shake_fraction: float = 0.02
@export var shake_min: int = 10
@export var shake_cap_fraction: float = 0.08
@export var shake_cap_amount: int = 400
@export var shake_same_attacker_cooldown: float = 20.0
@export var guard_sight_range: float = 8.0
@export var guard_sight_half_angle_deg: float = 60.0
@export var grab_break_presses: int = 6
@export var grab_max_time: float = 3.0
@export var vip_entry_money: int = 2000

@export_group("Quiz")
@export var quiz_questions: int = 3
@export var quiz_answer_time: float = 12.0
@export var quiz_base_points: int = 500
@export var quiz_speed_points: int = 500
## Cash for each placement after any minigame (× table limits); places past the end get the last.
@export var quiz_cash_prizes: PackedInt32Array = PackedInt32Array([150, 100, 75, 50, 25])
## Phase timings inside one question: get ready, then answer window, then reveal.
@export var quiz_ready_time: float = 2.0
@export var quiz_reveal_time: float = 2.5
## Title card before the first question and final ranking after the last.
@export var quiz_intro_time: float = 3.0
@export var quiz_outro_time: float = 4.0
@export var quiz_dynamic_chance: float = 0.4

@export_group("Rewards")
## Reward reveal (Patrick's note #11, no draft): base seconds plus this much per player row (the
## rows flip their item cards one after another).
@export var reward_reveal_time: float = 3.0
@export var reward_row_time: float = 0.6
## Seconds everyone waits in the entrance hall after the rewards before the doors open (#10).
@export var regroup_time: float = 5.0
## Cash rewards are multiplied by this when items are disabled in the lobby (§2.10).
@export var cash_only_factor: float = 2.0

@export_group("Items")
## Seconds between any two item activations by one player (§2.8).
@export var item_cooldown: float = 3.0
## A player can be hit by at most one negative item per this many seconds.
@export var item_grace: float = 5.0
## Seconds to choose what to discard when an item arrives with a full inventory (default: oldest).
@export var discard_time: float = 5.0
## Bodyguard also absorbs a knockout from an attacker who used an item this recently.
@export var bodyguard_ko_window: float = 30.0
## Banana peel: trigger radius and how long the slip stuns.
@export var banana_radius: float = 0.9
@export var banana_stun: float = 1.2

@export_group("Results")
## Seconds the results screen stays up before an online room returns to its lobby on its own.
@export var results_return_time: float = 60.0


## House Comp after `minigames_played` minigames (the last `comp_amounts` entry from then on).
func comp_amount_for(minigames_played: int) -> int:
	if comp_amounts.is_empty():
		return 0
	return comp_amounts[clampi(minigames_played, 0, comp_amounts.size() - 1)]


## Limits multiplier for a casino segment index (0-based): 1 + step × index, capped.
func limits_multiplier(segment_index: int) -> float:
	return minf(1.0 + limits_multiplier_step * maxi(segment_index, 0), limits_multiplier_cap)


## Plinko multipliers for a risk row (&"low", &"medium", &"high").
func plinko_multipliers(risk: StringName) -> PackedFloat32Array:
	match risk:
		&"low":
			return plinko_mult_low
		&"medium":
			return plinko_mult_medium
		&"high":
			return plinko_mult_high
	return PackedFloat32Array()


## Plinko slot weights for a risk row.
func plinko_weights(risk: StringName) -> PackedInt32Array:
	match risk:
		&"low":
			return plinko_weights_low
		&"medium":
			return plinko_weights_medium
		&"high":
			return plinko_weights_high
	return PackedInt32Array()


## Scratch card prize table for a tier (0 = cheapest): line pays × the card price.
func scratch_pays(tier: int) -> PackedFloat32Array:
	match tier:
		0:
			return scratch_pays_low
		1:
			return scratch_pays_mid
		2:
			return scratch_pays_high
	return PackedFloat32Array()


## Scratch card outcome weights for a tier: blank, "$" only, then a line per symbol.
func scratch_odds(tier: int) -> PackedInt32Array:
	match tier:
		0:
			return scratch_odds_low
		1:
			return scratch_odds_mid
		2:
			return scratch_odds_high
	return PackedInt32Array()
