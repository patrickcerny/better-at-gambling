class_name LobbyInfo
extends RefCounted
## What BROWSE LOBBIES shows about a lobby before you join it (Patrick 2026-11-15: "was grad
## eingestellt ist und kleine anzeige von allen beans die grad drinnen sind mit namen"): the
## host's game writes its lobby settings and the beans in it to the Steam lobby data (`info`, a
## small JSON text), and every browsing game reads it back with `parse`, which trusts nothing
## (lengths clamped, outfits checked against the shop). Steam allows 8 KB per value; a full
## lobby is about 1.5 KB.

const KEY: String = "info"
const NAME_MAX: int = 24


## The info of the lobby the host's game mirrors: settings, phase and the connected beans
## (leader first, then by slot).
static func from_state(state: ClientMatchState) -> Dictionary:
	var presets: MatchPresets = Registry.presets
	var s: Dictionary = state.lobby_settings
	var pool: PackedStringArray = str(s.get("minigame_pool", "")).split(",", false)
	var all: int = Registry.minigames.size()
	var picked: int = 0
	for id: StringName in Registry.minigames:
		if pool.is_empty() or pool.has(String(id)):
			picked += 1
	var beans: Array = []
	var ids: Array = state.players.keys()
	ids.sort()
	if ids.has(state.leader):
		ids.erase(state.leader)
		ids.push_front(state.leader)
	for pid: int in ids:
		var p: Dictionary = state.players[pid]
		if not bool(p.get("connected", true)) or bool(p.get("dev", false)):
			continue
		var outfit: Array = Array(Cosmetics.sanitize_outfit(p.get("outfit", [])))
		while not outfit.is_empty() and str(outfit.back()) == "":
			outfit.pop_back()  # shorter text: empty slots at the end say nothing
		beans.append({"n": str(p.get("name", "?")).left(NAME_MAX), "c": int(p.get("bean_color", p.get("color", 0))), "o": outfit, "l": pid == state.leader})
	return {
		"mode": String(MatchMode.normalize(s.get("mode", MatchMode.CASINO))),
		"mg": int(s.get("minigames", presets.default_minigames)),
		"gm": int(s.get("gamble_minutes", presets.default_gamble_minutes)),
		"items": bool(s.get("items_enabled", true)),
		"picked": picked, "all": all,
		"playing": state.phase != Phase.Id.LOBBY,
		"beans": beans,
	}


static func to_text(info: Dictionary) -> String:
	return JSON.stringify(info)


## Reads lobby data back: {} when missing or garbled, else every field with a safe value.
static func parse(text: String) -> Dictionary:
	if text.is_empty() or text.length() > 8192:
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:  # (JSON.parse_string would log an engine error for junk)
		return {}
	var v: Variant = json.data
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	var beans: Array[Dictionary] = []
	var raw: Variant = d.get("beans", [])
	if raw is Array:
		for b: Variant in raw as Array:
			if beans.size() >= Protocol.MAX_PLAYERS:
				break
			if not b is Dictionary:
				continue
			var bd: Dictionary = b
			var name_: String = str(bd.get("n", "")).strip_edges().left(NAME_MAX)
			beans.append({"name": name_ if name_ != "" else "Player", "color": posmod(_int(bd.get("c", 0)), Palette.PLAYER_COLORS.size()),
				"outfit": Cosmetics.sanitize_outfit(bd.get("o", [])), "leader": bool(bd.get("l", false))})
	var mode: StringName = MatchMode.normalize(str(d.get("mode", "")))
	return {
		"mode": mode,
		"minigames": clampi(_int(d.get("mg", 0)), 0, 99),
		"gamble_minutes": clampi(_int(d.get("gm", 0)), 0, 99),
		"items": bool(d.get("items", true)),
		"picked": clampi(_int(d.get("picked", 0)), 0, 999),
		"all": clampi(_int(d.get("all", 0)), 0, 999),
		"playing": bool(d.get("playing", false)),
		"beans": beans,
	}


## "Casino · 5 minigames · 3 min gambling · items on" (or the minigames-only version).
static func settings_text(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var parts: PackedStringArray = []
	var minigames_only: bool = MatchMode.is_minigames_only({"mode": info.get("mode", MatchMode.CASINO)})
	parts.append(MatchMode.label(info.get("mode", MatchMode.CASINO)).capitalize())
	var mg: int = int(info.get("minigames", 0))
	parts.append("%d minigame%s" % [mg, "" if mg == 1 else "s"])
	if not minigames_only:
		parts.append("%d min gambling" % int(info.get("gamble_minutes", 0)))
	parts.append("items on" if bool(info.get("items", true)) else "no items")
	var picked: int = int(info.get("picked", 0))
	var all: int = int(info.get("all", 0))
	if all > 0 and picked < all:
		parts.append("%d of %d games" % [picked, all])
	return " · ".join(parts)


static func _int(v: Variant) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0
