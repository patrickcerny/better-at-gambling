class_name LobbyController
extends RefCounted
## The entrance-hall lobby's rules (§2.2), server side: unique colors, hats, ready state (pad or
## panel), the party leader (longest-connected player), leader-only settings and the 3-second
## start countdown. Pure logic: the MatchServer feeds it and turns its notes into events.

const COUNTDOWN_SECONDS: float = 3.0

## Host settings shown on the board and the 2D panel: match length as a number of minigames and
## the gambling minutes before each one (Patrick's note #12), items on/off, quiz category, the
## party mode (`MatchMode`: casino or minigames only) and whether the party is listed in the
## server browser (`public`), and which minigames are in the rotation (`minigame_pool`: ids
## comma-separated, "" = every registered minigame; see `normalize_pool`).
var settings: Dictionary = {"minigames": 5, "gamble_minutes": 3, "items_enabled": true, "quiz_category": &"all", "mode": MatchMode.CASINO, "public": false, "minigame_pool": ""}
## Registered minigame ids in registry order (the server fills it); `minigame_pool` keeps only these.
var known_minigames: PackedStringArray = []
## Defaults and bounds for the match length (data/balance/match_presets.tres).
var presets: MatchPresets = MatchPresets.new()
## Seconds left on the start countdown (-1 when not counting).
var countdown: float = -1.0
var min_participants: int = 2

## player id → {connected: bool, joined_at: float, pad: bool, panel: bool}
var _members: Dictionary[int, Dictionary] = {}
var _leader: int = -1


## Registers a participant. `at` orders leadership (earliest connected player leads).
func join(player: int, at: float) -> void:
	_members[player] = {"connected": true, "joined_at": at, "pad": false, "panel": false, "pad_ignored": false}
	_elect()


## Marks a player connected or not (a disconnected player never blocks the start).
func set_connected(player: int, connected: bool, at: float) -> void:
	if not _members.has(player):
		return
	_members[player]["connected"] = connected
	if connected:
		_members[player]["joined_at"] = at
	else:
		_members[player]["pad"] = false
		_members[player]["panel"] = false
		_members[player]["pad_ignored"] = false
	_elect()


## Removes a participant.
func remove(player: int) -> void:
	_members.erase(player)
	_elect()


func has(player: int) -> bool:
	return _members.has(player)


## Current party leader (-1 if nobody is connected).
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
	if not on:
		_members[player]["pad_ignored"] = false  # stepping off and back on readies again
	return true


## Ready from the 2D panel toggle.
func set_panel_ready(player: int, on: bool) -> void:
	if _members.has(player):
		_members[player]["panel"] = on
		# NOT READY wins over standing on the pad (it used to do nothing while you stood there,
		# e.g. right after a reconnect put you back on your pad).
		_members[player]["pad_ignored"] = not on and _members[player]["pad"]


func is_ready(player: int) -> bool:
	if not _members.has(player):
		return false
	var m: Dictionary = _members[player]
	return m["panel"] or (m["pad"] and not m.get("pad_ignored", false))


## True when every connected player is ready and there are enough of them.
func all_ready() -> bool:
	var participants: int = 0
	for id: int in _members:
		if not _members[id]["connected"]:
			continue
		participants += 1
		if not is_ready(id):
			return false
	return participants >= maxi(min_participants, 1)


## Validates and applies a leader setting. Returns &"" or an error.
func set_setting(player: int, key: String, value: Variant) -> StringName:
	if player != _leader:
		return &"not_leader"
	match key:
		"minigames":
			if not _is_whole(value) or not presets.is_valid_minigames(int(value)):
				return &"bad_value"
			settings["minigames"] = int(value)
		"gamble_minutes":
			if not _is_whole(value) or not presets.is_valid_gamble_minutes(int(value)):
				return &"bad_value"
			settings["gamble_minutes"] = int(value)
		"items_enabled":
			settings["items_enabled"] = bool(value)
		"quiz_category":
			settings["quiz_category"] = StringName(value)
		"mode":
			if not MatchMode.is_valid(value):
				return &"bad_value"
			settings["mode"] = StringName(value)
		"public":
			if typeof(value) != TYPE_BOOL:
				return &"bad_value"
			settings["public"] = value
		"minigame_pool":
			if not typeof(value) in [TYPE_STRING, TYPE_STRING_NAME, TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
				return &"bad_value"
			settings["minigame_pool"] = normalize_pool(value, known_minigames)
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


## Number of connected participants.
func participant_count() -> int:
	var n: int = 0
	for id: int in _members:
		if _members[id]["connected"]:
			n += 1
	return n


## A minigame pool as stored: the known ids from `value` (a comma-separated String or an array of
## ids) in `known` order, unknown ids and duplicates dropped. "" (= every minigame) when nothing
## known is left or every known game is in it, so games added later join an all-on rotation.
static func normalize_pool(value: Variant, known: PackedStringArray) -> String:
	var wanted: PackedStringArray = []
	if typeof(value) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		for v: Variant in value:
			wanted.append(str(v).strip_edges())
	else:
		for part: String in str(value).split(",", false):
			wanted.append(part.strip_edges())
	var kept: PackedStringArray = []
	for id: String in known:
		if wanted.has(id):
			kept.append(id)
	if kept.size() == known.size():
		return ""
	return ",".join(kept)


static func _is_whole(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))))


func to_wire() -> Dictionary:
	return {"leader": _leader, "settings": settings.duplicate(), "countdown": snappedf(countdown, 0.01)}


func _elect() -> void:
	var best: int = -1
	var best_at: float = INF
	if _members.has(_leader) and _members[_leader]["connected"]:
		return  # leadership sticks until the leader leaves
	for id: int in _members:
		var m: Dictionary = _members[id]
		if m["connected"] and m["joined_at"] < best_at:
			best_at = m["joined_at"]
			best = id
	_leader = best
