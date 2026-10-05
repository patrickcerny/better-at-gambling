class_name MinigameLogicBase
extends RefCounted
## Server-side rules of one minigame (§2.9). Lifecycle: `setup` → `tick` until `is_finished` →
## `scores()`. Pure logic like the casino games: no nodes, no I/O; events go out via
## `drain_events`, per-player secrets via `private_state`.

## Participants (connected players) and everyone's display data.
var players: Array[int] = []
var rng: SeededRng
var balance: BalanceConfig
var params: Dictionary = {}
var events: Array[Dictionary] = []
var finished: bool = false
## Returns a player's smoothed half round-trip time in seconds (latency compensation).
var half_rtt: Callable = func(_p: int) -> float: return 0.0


## Wires the minigame. `context` carries match data some minigames need (the quiz's question bank
## and match stats).
func setup(p_players: Array[int], p_rng: SeededRng, p_balance: BalanceConfig, p_params: Dictionary, context: Dictionary) -> void:
	players = p_players.duplicate()
	rng = p_rng
	balance = p_balance
	params = p_params
	_on_setup(context)


## Hook for subclasses.
func _on_setup(_context: Dictionary) -> void:
	pass


## Advances the minigame by `delta` seconds; `now` is the server clock (for answer timing).
func tick(_delta: float, _now: float) -> void:
	pass


## A participant's input. Returns {ok, error}.
func submit(_player: int, _intent: Dictionary, _now: float) -> Dictionary:
	return StationLogicBase.fail(&"not_implemented")


## A participant dropped out mid-game (scores 0 from now on).
func remove_player(player: int) -> void:
	players.erase(player)


func is_finished() -> bool:
	return finished


## Final ranking: [{player, points, time, rank}] best first.
func ranking() -> Array[Dictionary]:
	return []


## Public state for snapshots (a client joining mid-minigame).
func get_public_state() -> Dictionary:
	return {}


## What only `player` may see.
func private_state(_player: int) -> Dictionary:
	return {}


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out
