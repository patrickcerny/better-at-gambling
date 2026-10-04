class_name Modifier
extends RefCounted
## One active effect on a player (from an item, Hot Table, etc.). Games never know the source;
## they ask the ModifierStack for luck / multipliers / refunds.

## Identifier of the effect kind, e.g. &"lucky_clover".
var id: StringName
## Who caused it (player id), -1 for the house.
var source_player: int = -1
## Restrict to one game (&"" = all games).
var game_id: StringName = &""
## Added to the player's luck while active.
var luck: int = 0
## Multiplies winnings (profit) while active.
var payout_multiplier: float = 1.0
## Consumed by the first win it applies to.
var consume_on_win: bool = false
## Refunds the next losing bet, then is consumed.
var refund_on_loss: bool = false
## Remaining rounds (each played round at a matching game uses one); -1 = unlimited.
var rounds_left: int = -1
## Absolute expiry time in match seconds; INF = never.
var expires_at: float = INF
## Free-form flags read by specific systems (e.g. &"peek_dealer").
var flags: Dictionary = {}


## True if this modifier applies to `p_game_id`.
func applies_to(p_game_id: StringName) -> bool:
	return game_id == &"" or game_id == p_game_id
