class_name MinigameDirector
extends RefCounted
## Picks and runs the minigame between casino segments (§2.9): weighted random among the
## registered minigames as a shuffled bag: no game comes a second time before every other game
## this many players can play has come once (Patrick, 0.9.2 playtest), and never twice in a row.
## Feeds it the server clock and intents, and hands its ranking to the reward phase.

var defs: Array[MinigameDefinition] = []
var bank: QuestionBank
## Question ids asked this match (no repeats within a match).
var used_questions: Dictionary = {}
var current: MinigameLogicBase = null
var current_def: MinigameDefinition = null
var _last_id: StringName = &""
## Games played since the bag was last refilled.
var _played: Dictionary[StringName, bool] = {}


func _init(p_defs: Array[MinigameDefinition], p_bank: QuestionBank) -> void:
	defs = p_defs
	bank = p_bank


## The definitions of `all` (id → definition, registry order) in `pool` (comma-separated ids as
## LobbyController.normalize_pool stores them; "" or nothing known = every one).
static func pool_defs(all: Dictionary, pool: String) -> Array[MinigameDefinition]:
	var ids: PackedStringArray = pool.split(",", false)
	var out: Array[MinigameDefinition] = []
	for id: Variant in all:
		if ids.has(str(id)):
			out.append(all[id])
	if out.is_empty():
		for id: Variant in all:
			out.append(all[id])
	return out


## Swaps the rotation (lobby `minigame_pool`); games left out simply stop being drawn.
func set_defs(p_defs: Array[MinigameDefinition]) -> void:
	defs = p_defs


## True if there is anything to play.
func has_minigames() -> bool:
	return not defs.is_empty()


## Chooses the next definition, filtered for `player_count`.
func pick(rng: SeededRng, player_count: int = 2) -> MinigameDefinition:
	if defs.is_empty():
		return null
	var playable: Array[MinigameDefinition] = defs.filter(func(d: MinigameDefinition) -> bool: return player_count >= d.min_players)
	if playable.is_empty():
		return null
	# The bag: games not played since the last refill. Empty (everyone has come) -> refill.
	var pool: Array[MinigameDefinition] = playable.filter(func(d: MinigameDefinition) -> bool: return not _played.has(d.id))
	if pool.is_empty():
		_played.clear()
		pool = playable
	# Never the same game twice in a row (a fresh bag could start with the one just played), unless
	# it is the only one this many players can play (solo practice).
	if pool.size() > 1:
		pool = pool.filter(func(d: MinigameDefinition) -> bool: return d.id != _last_id)
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
	record(current_def)
	current = current_def.logic_script.new() as MinigameLogicBase
	current.half_rtt = half_rtt
	current.setup(players, rng, balance, current_def.params, {"bank": bank, "used": used_questions, "stats": stats})
	return current


## Remembers `def` as played: out of the bag until every other playable game has come.
func record(def: MinigameDefinition) -> void:
	_last_id = def.id
	_played[def.id] = true


## Ends the current minigame.
func end() -> void:
	current = null


## Forgets per-match memory (rematch).
func reset() -> void:
	used_questions.clear()
	current = null
	current_def = null
	_last_id = &""
	_played.clear()
