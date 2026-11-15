class_name DevMode
extends RefCounted
## Developer mode (Patrick: "add a developer mode for me so i can check out everything fast. IDK
## how to do that smartly so not everyone can do it"): a DEV entry in the main menu
## (`DevPanel`: Coins, levels, every cosmetic, a practice casino with dummies, any minigame
## straight away) and DEV TOOLS in the pause menu of a Practice match (`DevMatchPanel`: money,
## any item, the next minigame or Last Call now).
##
## Who gets it: only the Steam accounts in `STEAM_IDS` (SteamID64, read from the running Steam
## client, which friends can't fake without hacking their own game). No command-line flag, no
## settings key and no hidden key combo turns it on, so a friend's copy never shows it. It only
## touches this PC: the Coins and levels live in the local profile anyway (user://profile.cfg has
## no DRM), unlocked cosmetics last until the game closes, and the in-match tools only work in
## Practice, whose server runs on this PC; online matches never offer them.
## Once anything dev was used, Steam achievements stay off until the game restarts (`used`), so
## a dev level or dev money never unlocks a real achievement.

## SteamID64s that may use developer mode (Patrick's account).
const STEAM_IDS: Array[int] = []

## Tests: 1 forces it on, 0 off, -1 asks Steam.
static var forced: int = -1
## Something dev was used this run (achievements stay off until the game restarts).
static var used: bool = false


## Whether this player may use developer mode.
static func allowed() -> bool:
	if forced >= 0:
		return forced == 1
	return is_dev_id(SteamSvc.get_steam_id() if SteamSvc.is_available() else 0)


## Whether `steam_id` is on the list.
static func is_dev_id(steam_id: int) -> bool:
	return steam_id != 0 and steam_id in STEAM_IDS


## Marks the run as touched by dev tools (no achievements from here on).
static func mark_used() -> void:
	if not used:
		used = true
		Log.info(&"dev", "developer mode used: Steam achievements are off until restart")


# --- Profile ------------------------------------------------------------------------------------

## Adds `amount` Coins to the local profile (saved).
static func add_coins(amount: int) -> void:
	mark_used()
	var p: PlayerProfile = ProfileManager.profile
	p.coins = clampi(p.coins + amount, 0, PlayerProfile.MAX_COINS)
	ProfileManager.save()
	ProfileManager.changed.emit()


## Sets the profile to level `level` (start of it; saved).
static func set_level(level: int) -> void:
	mark_used()
	var p: PlayerProfile = ProfileManager.profile
	p.xp = p.config.xp_for_level(clampi(level, 1, p.config.max_level))
	p.level = p.config.level_for_xp(p.xp)
	ProfileManager.save()
	ProfileManager.changed.emit()


## Every cosmetic owned (Coins and real-money ones) until the game closes; nothing is saved or
## bought.
static func set_unlock_all(on: bool) -> void:
	if on:
		mark_used()
	ProfileManager.set_dev_unlock_all(on)


static func unlock_all() -> bool:
	return ProfileManager.dev_unlock_all


# --- Practice -----------------------------------------------------------------------------------

## The practice settings for a casino match with `dummies` standing beans and the dev tools on.
static func casino_settings(dummies: int) -> Dictionary:
	return {"mode": MatchMode.CASINO, "dummies": clampi(dummies, 0, 7), "dev": true}


## The practice settings that drop straight into minigame `id` (minigames only, just that one),
## with enough dummies for it to run.
static func minigame_settings(id: StringName, dummies: int) -> Dictionary:
	var def: MinigameDefinition = Registry.minigames.get(id, null)
	var need: int = (def.min_players - 1) if def != null else 1
	return {"mode": MatchMode.MINIGAMES, "minigames": 1, "minigame_pool": String(id), "dummies": clampi(maxi(dummies, need), 0, 7), "dev": true}
