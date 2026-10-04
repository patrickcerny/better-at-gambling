class_name TableFixture
extends RefCounted
## Builds station logic with its dependencies for tests.

var balance: BalanceConfig
var economy: Economy = Economy.new()
var modifiers: ModifierStack
var rng: SeededRng
var jackpot: ProgressiveJackpot


func _init(seed_value: int = 1, players: Array[int] = [1], money: int = 1000) -> void:
	balance = BalanceConfig.new()
	modifiers = ModifierStack.new(balance.luck_clamp)
	rng = SeededRng.new(seed_value)
	jackpot = ProgressiveJackpot.new(balance.jackpot_feed_rate, balance.jackpot_seed)
	for p: int in players:
		economy.add_player(p, money)


## Sets up a station logic instance.
func make(logic: StationLogicBase, station_id: StringName = &"test") -> StationLogicBase:
	logic.setup(station_id, balance, economy, modifiers, rng, jackpot)
	return logic


## Adds a luck modifier to a player.
func give_luck(player: int, amount: int, game_id: StringName = &"") -> void:
	var m := Modifier.new()
	m.id = &"test_luck"
	m.luck = amount
	m.game_id = game_id
	modifiers.add(player, m)
