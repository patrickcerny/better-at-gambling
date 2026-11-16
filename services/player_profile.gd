class_name PlayerProfile
extends RefCounted
## The local player's progression (docs/GDD.md "Progression", "Cosmetics shop"): XP and level,
## Coins, the cosmetics they own and wear, and lifetime stats. There are no accounts, so it lives in a ConfigFile on this machine (`ProfileManager` keeps the
## one in user://profile.cfg). Loading sanity-checks every value (clamped, unknown items dropped,
## the level recomputed from the XP), so a hand-edited or damaged file can't break anything; there
## is no DRM. Coins are never in-match money: the tables take $ only, which resets every match.

const SECTION: String = "profile"
## The most Coins a profile can hold.
const MAX_COINS: int = 9_999_999
## How many applied match ids are remembered (`apply_match` adds a match's row once).
const MAX_APPLIED: int = 32
## The lifetime statistics `lifetime` keeps (saved under [lifetime]).
const LIFETIME_KEYS: Array[StringName] = [&"podiums", &"online_matches", &"best_money", &"online_winnings",
	&"winnings", &"losses", &"hands", &"minigames_won", &"jackpot_won", &"knockouts_dealt",
	&"knockouts_suffered", &"biggest_bet", &"quiz_points", &"thrown_out"]
## A lifetime number never passes this (a hand-edited file can't overflow anything).
const MAX_STAT: int = 2_000_000_000
## One match can add at most this much to a lifetime number (a sane match is far below).
const MAX_STAT_PER_MATCH: int = 1_000_000

var xp: int = 0
var level: int = 1
var coins: int = 0
## The bean colour to wear when joining (`Palette.player_color`; -1 = whatever the server gives).
var preferred_color: int = -1
## Bought cosmetics (`CosmeticDef.id`); free ones are always owned and not listed.
var owned: Array[StringName] = []
## Pieces in the player's Steam inventory (bought with real money). Not saved: Steam is the
## record (`SteamSvc` fills it on start and after each purchase), so a hand-edited file can't add any.
var steam_owned: Array[StringName] = []
## Developer mode (`DevMode`): every cosmetic counts as owned. Never saved.
var dev_all: bool = false
## The outfit worn from the next join on: `CosmeticDef.OUTFIT_KINDS` kind -> owned item id.
var outfit: Dictionary[StringName, StringName] = {}
var matches: int = 0
var wins: int = 0
## Matches won online against at least one other player (Practice wins don't count; achievements).
var online_wins: int = 0
## Biggest single win at a table ($, in any match).
var biggest_win: int = 0
## Lifetime statistics across every match (the MY STATS page, `LeaderboardPanel`): `LIFETIME_KEYS`
## -> number. Practice counts too, except the `online_` / `best_money` ones (ranked online matches
## only, the global leaderboards' totals: `LeaderboardRules`).
var lifetime: Dictionary[StringName, int] = {}
## Match ids already applied (newest last).
var applied: Array[String] = []
## The last Daily Spin (unix seconds, Steam's clock when Steam runs; 0 = never), `DailyWheel`.
var daily_last: int = 0
## Achievements this player holds (from Steam, `SteamSvc.sync_achievements`), so their rewards can
## be collected (Patrick 2026-11-16: "Each achievement should also unlock something").
var achieved: Array[StringName] = []
## Rewards collected in the shop's COLLECT tab: achievement pieces (only owned once collected) and
## level-pass pieces (owned from their level on; collecting just takes them out of the tab).
var collected: Array[StringName] = []
## Daily Spin pieces won but not looked at in the COLLECT tab yet (owned already).
var unseen: Array[StringName] = []

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

## Free items, ones unlocked by level, ones bought with Coins and ones in the Steam inventory.
func owns(id: StringName) -> bool:
	var d: CosmeticDef = shop.find(id)
	if d != null and d.dev_only:
		return DevMode.dev_skins()
	return d != null and (dev_all or DevMode.all_cosmetics() or d.is_free() or (d.level > 0 and level >= d.level) or id in owned or id in steam_owned or (d.achievement != &"" and id in collected))


## What waits in the shop's COLLECT tab (Patrick 2026-11-16: "There should be a collect stuff (from
## wheel achievements etc) in the shop"), in shop order: achievement rewards whose achievement this
## player holds (also ones earned before rewards existed), level-pass pieces reached and Daily Spin
## pieces won. The menu's shop buttons show how many.
func collectable() -> Array[StringName]:
	var out: Array[StringName] = []
	for d: CosmeticDef in shop.items:
		if can_collect(d.id):
			out.append(d.id)
	return out


func can_collect(id: StringName) -> bool:
	var d: CosmeticDef = shop.find(id)
	if d == null or id in collected:
		return false
	if d.achievement != &"":
		return d.achievement in achieved
	if d.level > 0 and level >= d.level and not id in owned and not id in steam_owned:
		return true
	return id in unseen


## Collects `id` from the COLLECT tab. Returns whether it was there.
func collect(id: StringName) -> bool:
	if not can_collect(id):
		return false
	var d: CosmeticDef = shop.find(id)
	unseen.erase(id)
	if d.achievement != &"" or d.level > 0:
		collected.append(id)
	return true


## Adds achievements this player holds. Returns whether any was new.
func note_achieved(ids: Array[StringName]) -> bool:
	var fresh: bool = false
	for id: StringName in ids:
		if id != &"" and not id in achieved:
			achieved.append(id)
			fresh = true
	return fresh


## Whether every piece of pack `pack` is owned.
func owns_pack(pack: CosmeticPack) -> bool:
	for id: StringName in pack.pieces:
		if not owns(id):
			return false
	return true


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


## Buys `id` with (red) Coins. Returns &"" when bought, else why not: &"unknown", &"owned",
## &"gold" (premium: Gold Coins through Steam), &"level" (only unlocked by levelling up) or
## &"not_enough_coins". Nothing changes on a refusal.
func buy(id: StringName) -> StringName:
	var d: CosmeticDef = shop.find(id)
	if d == null:
		return &"unknown"
	if owns(id):
		return &"owned"
	if not d.coin_buyable():
		return &"gold" if d.premium() else &"level"
	if coins < d.price:
		return &"not_enough_coins"
	coins -= d.price
	owned.append(id)
	return &""


## Pays out a Daily Spin prize that lives in the profile (`DailyWheel`): red Coins, or a mystery
## piece (`piece` from `DailyWheel.mystery_piece`; &"" when everything is owned pays
## `DailyWheel.PIECE_FALLBACK_COINS`). Returns {coins, piece}: what was added.
func add_wheel_prize(kind: StringName, amount: int, piece: StringName = &"") -> Dictionary:
	if kind == DailyWheel.KIND_COINS:
		return {"coins": add_coins(amount), "piece": &""}
	if kind == DailyWheel.KIND_PIECE:
		var d: CosmeticDef = shop.find(piece)
		if d != null and d.coin_buyable() and not owns(piece):
			owned.append(piece)
			unseen.append(piece)
			return {"coins": 0, "piece": piece}
		return {"coins": add_coins(DailyWheel.PIECE_FALLBACK_COINS), "piece": &""}
	return {"coins": 0, "piece": &""}


## Adds (red) Coins (developer mode, tests), up to MAX_COINS. Returns how many were added.
func add_coins(amount: int) -> int:
	var before: int = coins
	coins = clampi(coins + maxi(amount, 0), 0, MAX_COINS)
	return coins - before


## Wears colour `index` from the next join on (and now, in a lobby). Only owned colours; -1 clears.
func set_preferred_color(index: int) -> bool:
	if index != -1 and not owns_color(index):
		return false
	preferred_color = index
	return true


## Wears outfit piece `id` in its slot (owned pieces only). Returns false when refused.
func wear(id: StringName) -> bool:
	var d: CosmeticDef = shop.find(id)
	if d == null or not d.kind in CosmeticDef.OUTFIT_KINDS or not owns(id):
		return false
	outfit[d.kind] = id
	return true


## Takes off whatever is worn in slot `kind`.
func take_off(kind: StringName) -> void:
	outfit.erase(kind)


## Whether piece `id` is worn now (and owned: a Steam piece counts once the inventory says so).
func is_worn(id: StringName) -> bool:
	return id != &"" and id in outfit.values() and owns(id)


## The outfit for the hello and `set_outfit` (`Cosmetics.sanitize_outfit` order): owned pieces
## only (a Steam piece stays in the saved outfit while the inventory loads, but is not shown).
func outfit_wire() -> PackedStringArray:
	var out := PackedStringArray()
	for kind: StringName in CosmeticDef.OUTFIT_KINDS:
		var id: StringName = outfit.get(kind, &"")
		out.append(String(id) if owns(id) else "")
	return out


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
	var bonus: int = config.level_coins_between(from_level, level)
	coins = mini(coins + match_coins + bonus, MAX_COINS)
	matches += 1
	if int(row.get("rank", 0)) == 1:
		wins += 1
		if Achievements.counts_as_online_win(row):
			online_wins += 1
	biggest_win = maxi(biggest_win, int(row.get("biggest_win", 0)))
	_add_lifetime(row)
	if match_id != "":
		applied.append(match_id)
		if applied.size() > MAX_APPLIED:
			applied = applied.slice(applied.size() - MAX_APPLIED)
	return {"xp": gained, "coins": match_coins + bonus, "level_bonus": bonus, "level_from": from_level, "level_to": level, "xp_from": from_xp}


## Adds one match's row to `lifetime` (each number capped per match).
func _add_lifetime(row: Dictionary) -> void:
	var raw: Variant = row.get("stats", {})
	var st: Dictionary = raw if raw is Dictionary else {}
	var profit: int = clampi(int(st.get("profit", 0)), -MAX_STAT_PER_MATCH, MAX_STAT_PER_MATCH)
	if int(row.get("rank", 0)) in [1, 2, 3] and int(row.get("players", 1)) >= 2:
		_bump(&"podiums", 1)
	if profit > 0:
		_bump(&"winnings", profit)
	elif profit < 0:
		_bump(&"losses", -profit)
	_bump(&"hands", _per(st, "hands"))
	_bump(&"minigames_won", clampi(int(row.get("minigames_won", 0)), 0, MAX_STAT_PER_MATCH))
	_bump(&"jackpot_won", _per(st, "jackpot_won"))
	_bump(&"knockouts_dealt", _per(st, "knockouts_dealt"))
	_bump(&"knockouts_suffered", _per(st, "knockouts_suffered"))
	_bump(&"quiz_points", _per(st, "quiz_points"))
	_bump(&"thrown_out", _per(st, "thrown_out"))
	lifetime[&"biggest_bet"] = maxi(int(lifetime.get(&"biggest_bet", 0)), _per(st, "biggest_bet"))
	if bool(row.get("ranked", false)) and LeaderboardRules.plausible(row):
		_bump(&"online_matches", 1)
		lifetime[&"best_money"] = maxi(int(lifetime.get(&"best_money", 0)), int(row.get("money", 0)))
		if profit > 0:
			_bump(&"online_winnings", profit)


static func _per(st: Dictionary, key: String) -> int:
	return clampi(_int(st.get(key, 0)), 0, MAX_STAT_PER_MATCH)


func _bump(key: StringName, amount: int) -> void:
	lifetime[key] = clampi(int(lifetime.get(key, 0)) + maxi(amount, 0), 0, MAX_STAT)


## A lifetime statistic (0 when never counted).
func stat(key: StringName) -> int:
	return int(lifetime.get(key, 0))


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
	for kind: StringName in CosmeticDef.OUTFIT_KINDS:
		cfg.set_value("outfit", String(kind), String(outfit.get(kind, &"")))
	cfg.set_value("stats", "matches", matches)
	cfg.set_value("stats", "wins", wins)
	cfg.set_value("stats", "online_wins", online_wins)
	cfg.set_value("stats", "biggest_win", biggest_win)
	cfg.set_value("stats", "applied", PackedStringArray(applied))
	for key: StringName in LIFETIME_KEYS:
		cfg.set_value("lifetime", String(key), int(lifetime.get(key, 0)))
	cfg.set_value("daily", "last_spin", daily_last)
	cfg.set_value("rewards", "achieved", _strings(achieved))
	cfg.set_value("rewards", "collected", _strings(collected))
	cfg.set_value("rewards", "unseen", _strings(unseen))


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
	outfit.clear()
	for kind: StringName in CosmeticDef.OUTFIT_KINDS:
		var worn: Variant = cfg.get_value("outfit", String(kind), "")
		if typeof(worn) in [TYPE_STRING, TYPE_STRING_NAME] and str(worn) != "":
			outfit[kind] = StringName(str(worn))
	matches = _int(cfg.get_value("stats", "matches", 0))
	wins = _int(cfg.get_value("stats", "wins", 0))
	online_wins = _int(cfg.get_value("stats", "online_wins", 0))
	biggest_win = _int(cfg.get_value("stats", "biggest_win", 0))
	daily_last = _int(cfg.get_value("daily", "last_spin", 0))
	lifetime.clear()
	for key: StringName in LIFETIME_KEYS:
		lifetime[key] = _int(cfg.get_value("lifetime", String(key), 0))
	achieved = _names(cfg.get_value("rewards", "achieved", PackedStringArray()))
	unseen = _names(cfg.get_value("rewards", "unseen", PackedStringArray()))
	if cfg.has_section_key("rewards", "collected"):
		collected = _names(cfg.get_value("rewards", "collected", PackedStringArray()))
	else:
		# A profile from before the COLLECT tab: the level pieces it already has stay out of the tab.
		collected.clear()
		var lv: int = config.level_for_xp(clampi(xp, 0, config.max_xp()))
		for d: CosmeticDef in shop.items:
			if d.level > 0 and d.level <= lv:
				collected.append(d.id)
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
		if d != null and d.coin_buyable() and not id in clean:
			clean.append(id)
	owned = clean
	if preferred_color != -1 and not owns_color(preferred_color):
		preferred_color = -1
	var worn: Dictionary[StringName, StringName] = {}
	for kind: StringName in outfit:
		var d: CosmeticDef = shop.find(outfit[kind])
		# Steam pieces stay put: the Steam inventory arrives after the profile is loaded.
		if kind in CosmeticDef.OUTFIT_KINDS and d != null and d.kind == kind and (owns(d.id) or d.steam_item > 0 or d.dev_only):
			worn[kind] = d.id
	outfit = worn
	matches = maxi(matches, 0)
	wins = clampi(wins, 0, matches)
	online_wins = clampi(online_wins, 0, wins)
	biggest_win = maxi(biggest_win, 0)
	daily_last = maxi(daily_last, 0)
	var got: Array[StringName] = []
	for id: StringName in collected:
		var d: CosmeticDef = shop.find(id)
		if d != null and (d.achievement != &"" or d.level > 0) and not id in got:
			got.append(id)
	collected = got
	var news: Array[StringName] = []
	for id: StringName in unseen:
		if id in owned and not id in news:
			news.append(id)
	unseen = news
	var held: Array[StringName] = []
	for id: StringName in achieved:
		if not id in held:
			held.append(id)
	achieved = held
	var life: Dictionary[StringName, int] = {}
	for key: StringName in LIFETIME_KEYS:
		life[key] = clampi(int(lifetime.get(key, 0)), 0, MAX_STAT)
	lifetime = life
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


static func _strings(ids: Array[StringName]) -> PackedStringArray:
	var out: PackedStringArray = []
	for id: StringName in ids:
		out.append(String(id))
	return out


static func _names(v: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if v is PackedStringArray or v is Array:
		for id: Variant in v:
			out.append(StringName(str(id)))
	return out


static func _int(v: Variant) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0
