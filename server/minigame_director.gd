class_name MinigameDirector
extends RefCounted
## Picks and runs the minigame between casino segments (§2.9): weighted random among the
## registered minigames without an immediate repeat (V1: only the quiz is registered), feeds it
## the server clock and intents, and hands its ranking to the reward phase.

var defs: Array[MinigameDefinition] = []
var bank: QuestionBank
## Question ids asked this match (no repeats within a match).
var used_questions: Dictionary = {}
var current: MinigameLogicBase = null
var current_def: MinigameDefinition = null
var _last_id: StringName = &""


func _init(p_defs: Array[MinigameDefinition], p_bank: QuestionBank) -> void:
	defs = p_defs
	bank = p_bank


## True if there is anything to play.
func has_minigames() -> bool:
	return not defs.is_empty()


## Chooses the next definition, filtered for `player_count`.
func pick(rng: SeededRng, player_count: int = 2) -> MinigameDefinition:
	if defs.is_empty():
		return null
	var pool: Array[MinigameDefinition] = defs.filter(func(d: MinigameDefinition) -> bool: return (d.id != _last_id or defs.size() == 1) and player_count >= d.min_players)
	if pool.is_empty():
		return null
	var weights: Array = []
	for d: MinigameDefinition in pool:
		weights.append(maxf(d.weight, 0.0))
	var i: int = rng.weighted_index(weights)
	return pool[maxi(i, 0)]


## Starts a minigame for `players`. Returns the running logic.
func begin(players: Array[int], rng: SeededRng, balance: BalanceConfig, stats: Dictionary, half_rtt: Callable) -> MinigameLogicBase:
	current_def = pick(rng, players.size())
	if current_def == null or current_def.logic_script == null:
		return null
	_last_id = current_def.id
	current = current_def.logic_script.new() as MinigameLogicBase
	current.half_rtt = half_rtt
	current.setup(players, rng, balance, current_def.params, {"bank": bank, "used": used_questions, "stats": stats})
	return current


## Ends the current minigame.
func end() -> void:
	current = null


## Forgets per-match memory (rematch).
func reset() -> void:
	used_questions.clear()
	current = null
	current_def = null
	_last_id = &""
