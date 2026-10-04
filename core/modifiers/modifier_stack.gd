class_name ModifierStack
extends RefCounted
## Per-player list of active modifiers (§3.6). Items register modifiers here; games query it.

## Emitted when a modifier is removed: reason is &"expired", &"consumed" or &"removed".
signal modifier_removed(player: int, mod: Modifier, reason: StringName)

var luck_clamp: int = 3

var _mods: Dictionary[int, Array] = {}


func _init(p_luck_clamp: int = 3) -> void:
	luck_clamp = p_luck_clamp


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


## Clamped luck sum for a player at a game (general + game-specific).
func get_luck(player: int, game_id: StringName = &"") -> int:
	var sum: int = 0
	for m: Modifier in _mods.get(player, []):
		if m.applies_to(game_id):
			sum += m.luck
	return clampi(sum, -luck_clamp, luck_clamp)


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
