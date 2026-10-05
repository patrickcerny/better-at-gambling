class_name LobbyController
extends RefCounted
## The entrance-hall lobby's rules (§2.2), server side: unique colors, hats, ready state (pad or
## panel), the party leader (longest-connected human), leader-only settings, bot slots and the
## 3-second start countdown. Pure logic: the MatchServer feeds it and turns its notes into events.

const COUNTDOWN_SECONDS: float = 3.0
const DURATIONS: Array[int] = [5, 10, 15, 30]
const BOT_DIFFICULTIES: Array[StringName] = [&"easy", &"normal", &"hard"]

## Host settings shown on the board and the 2D panel.
var settings: Dictionary = {"duration": 10, "items_enabled": true, "bot_difficulty": &"normal", "quiz_category": &"all"}
## Seconds left on the start countdown (-1 when not counting).
var countdown: float = -1.0
var min_participants: int = 2

## player id → {human: bool, connected: bool, joined_at: float, pad: bool, panel: bool}
var _members: Dictionary[int, Dictionary] = {}
var _leader: int = -1


## Registers a participant. `at` orders leadership (earliest connected human leads).
func join(player: int, human: bool, at: float) -> void:
	_members[player] = {"human": human, "connected": true, "joined_at": at, "pad": false, "panel": false}
	_elect()


## Marks a player connected or not (a disconnected human never blocks the start).
func set_connected(player: int, connected: bool, at: float) -> void:
	if not _members.has(player):
		return
	_members[player]["connected"] = connected
	if connected:
		_members[player]["joined_at"] = at
	else:
		_members[player]["pad"] = false
		_members[player]["panel"] = false
	_elect()


## Removes a participant (bot slot cleared).
func remove(player: int) -> void:
	_members.erase(player)
	_elect()


func has(player: int) -> bool:
	return _members.has(player)


## Current party leader (-1 if no human is connected).
func leader() -> int:
	return _leader


## First free color, preferring `wanted`.
func free_color(taken: Array[int], wanted: int = -1) -> int:
	if Cosmetics.is_valid_color(wanted) and not wanted in taken:
		return wanted
	for c: int in Cosmetics.COLOR_COUNT:
		if not c in taken:
			return c
	return 0


## Ready from standing on the pad.
func set_on_pad(player: int, on: bool) -> bool:
	if not _members.has(player) or _members[player]["pad"] == on:
		return false
	_members[player]["pad"] = on
	return true


## Ready from the 2D panel toggle.
func set_panel_ready(player: int, on: bool) -> void:
	if _members.has(player):
		_members[player]["panel"] = on


func is_ready(player: int) -> bool:
	if not _members.has(player):
		return false
	var m: Dictionary = _members[player]
	return not m["human"] or m["pad"] or m["panel"]


## True when every connected human is ready and there are enough participants.
func all_ready() -> bool:
	var participants: int = 0
	var humans: int = 0
	for id: int in _members:
		var m: Dictionary = _members[id]
		if not m["human"]:
			participants += 1
			continue
		if not m["connected"]:
			continue
		humans += 1
		participants += 1
		if not is_ready(id):
			return false
	return humans >= 1 and participants >= min_participants


## Validates and applies a leader setting. Returns &"" or an error.
func set_setting(player: int, key: String, value: Variant) -> StringName:
	if player != _leader:
		return &"not_leader"
	match key:
		"duration":
			if not int(value) in DURATIONS:
				return &"bad_value"
			settings["duration"] = int(value)
		"items_enabled":
			settings["items_enabled"] = bool(value)
		"bot_difficulty":
			if not StringName(value) in BOT_DIFFICULTIES:
				return &"bad_value"
			settings["bot_difficulty"] = StringName(value)
		"quiz_category":
			settings["quiz_category"] = StringName(value)
		_:
			return &"bad_key"
	return &""


## Advances the countdown. Returns &"countdown_started", &"countdown_cancelled", &"start" or &"".
func tick(delta: float) -> StringName:
	var ready: bool = all_ready()
	if countdown < 0.0:
		if ready:
			countdown = COUNTDOWN_SECONDS
			return &"countdown_started"
		return &""
	if not ready:
		countdown = -1.0
		return &"countdown_cancelled"
	countdown -= delta
	if countdown <= 0.0:
		countdown = -1.0
		return &"start"
	return &""


## Number of participants (humans connected + bots).
func participant_count() -> int:
	var n: int = 0
	for id: int in _members:
		if not _members[id]["human"] or _members[id]["connected"]:
			n += 1
	return n


func to_wire() -> Dictionary:
	return {"leader": _leader, "settings": settings.duplicate(), "countdown": snappedf(countdown, 0.01)}


func _elect() -> void:
	var best: int = -1
	var best_at: float = INF
	if _members.has(_leader) and _members[_leader]["human"] and _members[_leader]["connected"]:
		return  # leadership sticks until the leader leaves
	for id: int in _members:
		var m: Dictionary = _members[id]
		if m["human"] and m["connected"] and m["joined_at"] < best_at:
			best_at = m["joined_at"]
			best = id
	_leader = best
