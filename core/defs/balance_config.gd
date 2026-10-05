class_name BalanceConfig
extends Resource
## Every tunable balance number (§2.21). Logic code reads values from here, never literals.
## Defaults below are the design values; `data/balance/balance.tres` is the tuned instance.

@export_group("Economy")
@export var start_money: int = 1000
@export var comp_amount: int = 150
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
## Profit ratio paid on winning hands when the dealer busts (1.0 = plain 1:1).
@export var bj_dealer_bust_bonus: float = 1.07
@export var bj_blackjack_ratio: float = 1.5

@export_group("Roulette")
@export var roulette_min_bet: int = 10
@export var roulette_max_total: int = 300
@export var roulette_betting_time: float = 15.0
@export var roulette_spin_time: float = 4.0
@export var roulette_result_time: float = 3.0
## Extra fraction of the total return (stake + winnings) paid on every winning roulette bet.
@export var roulette_generosity: float = 0.04
@export var roulette_lucky_neighbor_ratio: float = 5.0
@export var roulette_jinx_ratio: float = 0.9

@export_group("Slots")
@export var slots_bet_sizes: PackedInt32Array = PackedInt32Array([10, 25, 50, 100])
@export var slots_spin_time: float = 1.6
@export var slots_skip_after: float = 0.5
## Symbol order: cherry, lemon, bell, bar, seven, clover (wild), diamond.
@export var slots_reel_weights: PackedInt32Array = PackedInt32Array([9, 11, 9, 7, 3, 1, 1])
## Three-of-a-kind multipliers, same symbol order (clover x3 pays as diamond).
@export var slots_three_pay: PackedInt32Array = PackedInt32Array([6, 8, 12, 20, 40, 100, 100])
@export var slots_two_cherry_pay: int = 2
@export var slots_one_cherry_pay: int = 1

@export_group("Plinko")
@export var plinko_bet_sizes: PackedInt32Array = PackedInt32Array([10, 25, 50, 100])
@export var plinko_drop_cooldown: float = 2.5
@export var plinko_flight_time: float = 3.0
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
@export var quiz_cash_prizes: PackedInt32Array = PackedInt32Array([150, 100, 50])
## Phase timings inside one question: get ready, then answer window, then reveal.
@export var quiz_ready_time: float = 2.0
@export var quiz_reveal_time: float = 2.5
## Title card before the first question and final ranking after the last.
@export var quiz_intro_time: float = 3.0
@export var quiz_outro_time: float = 4.0
@export var quiz_dynamic_chance: float = 0.4

@export_group("Rewards")
## Seconds to pick from the draft (default: first option).
@export var draft_time: float = 8.0
## Extra seconds for the reward screen after the draft closes.
@export var reward_outro_time: float = 2.0
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
