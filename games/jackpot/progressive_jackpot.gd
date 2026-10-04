class_name ProgressiveJackpot
extends RefCounted
## Casino-wide progressive jackpot (§2.5). Fed by the house with a fraction of slot and Plinko bets
## (not deducted from players, see DECISIONS.md); won by 3 Diamonds or a lucky High-row Plinko edge.

var feed_rate: float
var seed_amount: int
## Integer pot shown to players.
var pot: int = 0

var _fraction: float = 0.0


func _init(p_feed_rate: float = 0.01, p_seed_amount: int = 500) -> void:
	feed_rate = p_feed_rate
	seed_amount = p_seed_amount
	pot = p_seed_amount


## Adds `feed_rate` of a bet to the pot (fractional dollars carry over).
func feed(bet: int) -> void:
	_fraction += bet * feed_rate
	var whole: int = int(floor(_fraction + 0.000001))
	pot += whole
	_fraction -= whole


## Pays the pot to a player through the economy, reseeds, and returns the amount won.
func award(economy: Economy, player: int, station: StringName, reseed_multiplier: float = 1.0) -> int:
	var won: int = pot
	economy.apply(player, won, &"jackpot", station)
	pot = int(floor(seed_amount * reseed_multiplier))
	_fraction = 0.0
	return won
