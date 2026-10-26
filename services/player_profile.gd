class_name PlayerProfile
extends RefCounted
## The local player's progression (docs/GDD.md "Progression", "Cosmetics shop"): XP and level,
## Coins, the cosmetics they own and wear, and lifetime stats. There are no accounts (Steam test
## App ID, local play), so it lives in a ConfigFile on this machine (`ProfileManager` keeps the
## one in user://profile.cfg). Loading sanity-checks every value (clamped, unknown items dropped,
## the level recomputed from the XP), so a hand-edited or damaged file can't break anything; there
## is no DRM. Coins are never in-match money: the tables take $ only, which resets every match.

const SECTION: String = "profile"
## The most Coins a profile can hold.
const MAX_COINS: int = 9_999_999
## How many applied match ids are remembered (`apply_match` adds a match's row once).
const MAX_APPLIED: int = 32

var xp: int = 0
var level: int = 1
var coins: int = 0
## The bean colour to wear when joining (`Palette.player_color`; -1 = whatever the server gives).
var preferred_color: int = -1
## Bought cosmetics (`CosmeticDef.id`); free ones are always owned and not listed.
var owned: Array[StringName] = []
var matches: int = 0
var wins: int = 0
## Biggest single win at a table ($, in any match).
var biggest_win: int = 0
## Match ids already applied (newest last).
var applied: Array[String] = []

var config: ProgressionConfig
var shop: CosmeticShop


func _init(p_config: ProgressionConfig = null, p_shop: CosmeticShop = null) -> void:
	config = p_config if p_config != null else ProgressionConfig.default()
	shop = p_shop if p_shop != null else CosmeticShop.default()


# --- Levels -------------------------------------------------------------------------------------

## XP gained since the current level started, and how much the next level needs.
func xp_into_level() -> int:
	return xp - config.xp_for_level(level)


func xp_needed() -> int:
	return config.xp_to_next(level)


## 0..1 along the bar to the next level (1 at the max level).
func level_progress() -> float:
	var need: int = xp_needed()
	return 1.0 if need <= 0 else clampf(float(xp_into_level()) / float(need), 0.0, 1.0)


# --- Cosmetics ----------------------------------------------------------------------------------

## Free items and bought ones.
func owns(id: StringName) -> bool:
	var d: CosmeticDef = shop.find(id)
	return d != null and (d.is_free() or id in owned)


## Whether this profile may wear bean colour `index`.
func owns_color(index: int) -> bool:
	if not Cosmetics.is_valid_color(index):
		return false
	var d: CosmeticDef = shop.color_item(index)
	return Cosmetics.is_slot_color(index) if d == null else owns(d.id)


## Owned bean colours in shop order (the pedestal panel's swatches).
func owned_colors() -> Array[int]:
	var out: Array[int] = []
	for d: CosmeticDef in shop.of_kind(CosmeticDef.KIND_COLOR):
		if owns(d.id) and Cosmetics.is_valid_color(d.color_index):
			out.append(d.color_index)
	return out


## Buys `id` with Coins. Returns &"" when bought, else why not: &"unknown", &"owned" or
## &"not_enough_coins". Nothing changes on a refusal.
func buy(id: StringName) -> StringName:
	var d: CosmeticDef = shop.find(id)
	if d == null:
		return &"unknown"
	if owns(id):
		return &"owned"
	if coins < d.price:
		return &"not_enough_coins"
	coins -= d.price
	owned.append(id)
	return &""


## Wears colour `index` from the next join on (and now, in a lobby). Only owned colours; -1 clears.
func set_preferred_color(index: int) -> bool:
	if index != -1 and not owns_color(index):
		return false
	preferred_color = index
	return true


# --- Matches ------------------------------------------------------------------------------------

## Adds this player's row of a finished match (`Progression.breakdown`, sent by the server) once
## per `match_id`. Returns what happened: {xp, coins (match + level bonus), level_bonus,
## level_from, level_to, xp_from} — or {} when the id was applied before or the row is empty.
func apply_match(match_id: String, row: Dictionary) -> Dictionary:
	if row.is_empty() or (match_id != "" and match_id in applied):
		return {}
	var gained: int = clampi(int(row.get("xp", 0)), 0, Progression.MAX_MATCH_XP)
	var match_coins: int = clampi(int(row.get("coins", 0)), 0, Progression.coins_for_xp(config, Progression.MAX_MATCH_XP))
	var from_level: int = level
	var from_xp: int = xp
	xp = mini(xp + gained, config.max_xp())
	level = config.level_for_xp(xp)
	var bonus: int = maxi(level - from_level, 0) * config.level_up_coins
	coins = mini(coins + match_coins + bonus, MAX_COINS)
	matches += 1
	if int(row.get("rank", 0)) == 1:
		wins += 1
	biggest_win = maxi(biggest_win, int(row.get("biggest_win", 0)))
	if match_id != "":
		applied.append(match_id)
		if applied.size() > MAX_APPLIED:
			applied = applied.slice(applied.size() - MAX_APPLIED)
	return {"xp": gained, "coins": match_coins + bonus, "level_bonus": bonus, "level_from": from_level, "level_to": level, "xp_from": from_xp}


# --- Storage ------------------------------------------------------------------------------------

func to_config(cfg: ConfigFile) -> void:
	cfg.set_value(SECTION, "xp", xp)
	cfg.set_value(SECTION, "level", level)
	cfg.set_value(SECTION, "coins", coins)
	cfg.set_value(SECTION, "preferred_color", preferred_color)
	var ids: PackedStringArray = []
	for id: StringName in owned:
		ids.append(String(id))
	cfg.set_value(SECTION, "owned", ids)
	cfg.set_value("stats", "matches", matches)
	cfg.set_value("stats", "wins", wins)
	cfg.set_value("stats", "biggest_win", biggest_win)
	cfg.set_value("stats", "applied", PackedStringArray(applied))


## Reads a profile back and makes it sane (see `sanitize`).
func from_config(cfg: ConfigFile) -> void:
	xp = _int(cfg.get_value(SECTION, "xp", 0))
	coins = _int(cfg.get_value(SECTION, "coins", 0))
	preferred_color = _int(cfg.get_value(SECTION, "preferred_color", -1))
	owned.clear()
	var ids: Variant = cfg.get_value(SECTION, "owned", PackedStringArray())
	if ids is PackedStringArray or ids is Array:
		for id: Variant in ids:
			owned.append(StringName(str(id)))
	matches = _int(cfg.get_value("stats", "matches", 0))
	wins = _int(cfg.get_value("stats", "wins", 0))
	biggest_win = _int(cfg.get_value("stats", "biggest_win", 0))
	applied.clear()
	var ap: Variant = cfg.get_value("stats", "applied", PackedStringArray())
	if ap is PackedStringArray or ap is Array:
		for a: Variant in ap:
			applied.append(str(a))
	sanitize()


## Clamps every value into range: XP 0..max (the level always follows from the XP, whatever the
## file says), Coins 0..MAX_COINS, owned = known bought items without duplicates, the preferred
## colour one this profile owns, stats ≥ 0 and wins ≤ matches.
func sanitize() -> void:
	xp = clampi(xp, 0, config.max_xp())
	level = config.level_for_xp(xp)
	coins = clampi(coins, 0, MAX_COINS)
	var clean: Array[StringName] = []
	for id: StringName in owned:
		var d: CosmeticDef = shop.find(id)
		if d != null and not d.is_free() and not id in clean:
			clean.append(id)
	owned = clean
	if preferred_color != -1 and not owns_color(preferred_color):
		preferred_color = -1
	matches = maxi(matches, 0)
	wins = clampi(wins, 0, matches)
	biggest_win = maxi(biggest_win, 0)
	if applied.size() > MAX_APPLIED:
		applied = applied.slice(applied.size() - MAX_APPLIED)


func save(path: String) -> Error:
	var cfg := ConfigFile.new()
	to_config(cfg)
	return cfg.save(path)


## Loads `path` (a missing or unreadable file leaves a fresh profile). Returns the load error.
func load_from(path: String) -> Error:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var err: Error = cfg.load(path)
	if err == OK:
		from_config(cfg)
	return err


static func _int(v: Variant) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0
