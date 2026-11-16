class_name ModifierStack
extends RefCounted
## Per-player list of active modifiers (§3.6). Items register modifiers here; games query it.

## Emitted when a modifier is removed: reason is &"expired", &"consumed" or &"removed".
signal modifier_removed(player: int, mod: Modifier, reason: StringName)

var luck_clamp: int = 3
## Losing-streak luck (see BalanceConfig.luck_streak_*): points per counted loss, the cap, and the
## smallest stake that counts. Step 0 turns the streak off.
var streak_step: float = 0.0
var streak_cap: float = 0.0
var streak_min_stake: int = 0
## Game → share of the streak luck that counts there (BalanceConfig.luck_streak_scale).
var streak_scale: Dictionary = {}

var _mods: Dictionary[int, Array] = {}
## Player → [{mod, left}] put aside while a minigame is on (`pause_all`); `left` is the time
## that was left (INF = no time limit).
var _paused: Dictionary[int, Array] = {}
## Player → luck points from the current losing streak.
var _streak: Dictionary[int, float] = {}


func _init(p_luck_clamp: int = 3) -> void:
	luck_clamp = p_luck_clamp


## Turns the losing-streak luck on with the balance's numbers.
func use_streak(balance: BalanceConfig) -> ModifierStack:
	streak_step = balance.luck_streak_step
	streak_cap = balance.luck_streak_cap
	streak_min_stake = balance.luck_streak_min_stake
	streak_scale = balance.luck_streak_scale
	return self


## A bet was settled: a loss of at least `streak_min_stake` grows the streak luck, a win clears it,
## a push leaves it.
func note_result(player: int, stake: int, returned: int) -> void:
	if streak_step <= 0.0:
		return
	if returned > stake:
		_streak.erase(player)
	elif returned < stake and stake >= streak_min_stake:
		_streak[player] = minf(float(_streak.get(player, 0.0)) + streak_step, streak_cap)


## Luck points from the losing streak (0 = none).
func streak_luck(player: int) -> float:
	return float(_streak.get(player, 0.0))


## Adds a modifier to a player.
func add(player: int, mod: Modifier) -> void:
	if not _mods.has(player):
		_mods[player] = []
	_mods[player].append(mod)


## Active modifiers of a player (copy).
func get_mods(player: int) -> Array[Modifier]:
	var out: Array[Modifier] = []
	for m: Modifier in _mods.get(player, []):
		out.append(m)
	return out


## Clamped luck for a player at a game, in luck points (general + game-specific items + the
## losing streak). Fractional since 0.9.57 (the streak adds quarter points).
func get_luck(player: int, game_id: StringName = &"") -> float:
	var sum: float = streak_luck(player) * float(streak_scale.get(game_id, 1.0))
	for m: Modifier in _mods.get(player, []):
		if m.applies_to(game_id):
			sum += m.luck
	return clampf(sum, -luck_clamp, luck_clamp)


## Product of payout multipliers for a player at a game.
func get_payout_multiplier(player: int, game_id: StringName) -> float:
	var mult: float = 1.0
	for m: Modifier in _mods.get(player, []):
		if m.applies_to(game_id):
			mult *= m.payout_multiplier
	return mult


## True if any active modifier of the player carries `flag`.
func has_flag(player: int, flag: StringName, game_id: StringName = &"") -> bool:
	for m: Modifier in _mods.get(player, []):
		if m.applies_to(game_id) and m.flags.get(flag, false):
			return true
	return false


## Call after a win was paid: removes win-consumed modifiers that applied.
func consume_on_win(player: int, game_id: StringName) -> void:
	for m: Modifier in get_mods(player):
		if m.consume_on_win and m.applies_to(game_id):
			_remove(player, m, &"consumed")


## Call on a loss: consumes the first refund modifier and returns true if the stake is refunded.
func consume_on_loss(player: int, game_id: StringName) -> bool:
	for m: Modifier in get_mods(player):
		if m.refund_on_loss and m.applies_to(game_id):
			_remove(player, m, &"consumed")
			return true
	return false


## Call once per round played at a game: decrements round-limited modifiers for that game.
func consume_round(player: int, game_id: StringName) -> void:
	for m: Modifier in get_mods(player):
		if m.rounds_left > 0 and m.game_id == game_id:
			m.rounds_left -= 1
			if m.rounds_left == 0:
				_remove(player, m, &"consumed")


## Removes modifiers whose expiry time has passed.
func expire(now: float) -> void:
	for player: int in _mods.keys():
		for m: Modifier in get_mods(player):
			if now >= m.expires_at:
				_remove(player, m, &"expired")


## Uses up the first modifier of a player carrying `flag` (Bodyguard, Mirror). True if one was found.
func consume_flag(player: int, flag: StringName) -> bool:
	for m: Modifier in get_mods(player):
		if m.flags.get(flag, false):
			_remove(player, m, &"consumed")
			return true
	return false


## Ends every modifier (all players) carrying `flag`, e.g. &"segment_end" when a casino segment closes.
func expire_flag(flag: StringName) -> void:
	for player: int in _mods.keys():
		for m: Modifier in get_mods(player):
			if m.flags.get(flag, false):
				_remove(player, m, &"expired")


## Ends every modifier of every player (the match is over); paused ones are dropped silently.
func expire_all(reason: StringName = &"expired") -> void:
	_paused.clear()
	for player: int in _mods.keys():
		for m: Modifier in get_mods(player):
			_remove(player, m, reason)


## A minigame starts: every modifier is put aside with the time it had left, so it does nothing
## during the minigame and its clock stands still. No `modifier_removed` (nothing ran out).
## Returns [{player, mod}] of what was paused.
func pause_all(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for player: int in _mods.keys():
		for m: Modifier in get_mods(player):
			var left: float = m.expires_at - now if m.expires_at != INF else INF
			if left <= 0.0:
				continue  # ran out this very tick: `expire` ends it normally
			if not _paused.has(player):
				_paused[player] = []
			_paused[player].append({"mod": m, "left": left})
			_mods[player].erase(m)
			out.append({"player": player, "mod": m})
	return out


## Back in the casino: the paused modifiers run on with the time they had left.
## Returns [{player, mod}] of what was resumed.
func resume_all(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for player: int in _paused.keys():
		for e: Dictionary in _paused[player]:
			var m: Modifier = e["mod"]
			var left: float = float(e["left"])
			m.expires_at = now + left if left != INF else INF
			add(player, m)
			out.append({"player": player, "mod": m})
	_paused.clear()
	return out


## True while a player has effects put aside for a minigame.
func has_paused(player: int) -> bool:
	return not (_paused.get(player, []) as Array).is_empty()


## Hands the first modifier of `from` carrying `flag` over to `to` (Bad Luck Monkey). Returns it,
## or null if `from` had none.
func move_flag(from: int, to: int, flag: StringName) -> Modifier:
	for m: Modifier in get_mods(from):
		if m.flags.get(flag, false):
			_remove(from, m, &"passed")
			m.source_player = from
			add(to, m)
			return m
	return null


## Removes all modifiers with id `id` from a player.
func remove_by_id(player: int, id: StringName) -> void:
	for m: Modifier in get_mods(player):
		if m.id == id:
			_remove(player, m, &"removed")


func _remove(player: int, m: Modifier, reason: StringName) -> void:
	var list: Array = _mods.get(player, [])
	var idx: int = list.find(m)
	if idx >= 0:
		list.remove_at(idx)
		modifier_removed.emit(player, m, reason)
