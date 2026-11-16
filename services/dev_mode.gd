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

## SteamID64s that may use developer mode: Patrick only ("Dev rechte hab nur ich", 2026-11-16; his account, from his Steam account page
## 2026-11-15; more from him: "gebe dieser nummer access all. Es werden noch mehr steam ids kommen").
const STEAM_IDS: Array[int] = [
	76561198325616486,  # Patrick
]
## SteamID64s that own every cosmetic and the developer skins, but get NO developer mode (Patrick
## 2026-11-15: "nicht entwickelermodus. Skin unlock all nur und den neuen dev skin. Keine dev sachen").
const COSMETIC_IDS: Array[int] = [
	76561198111162215,
	76561198872557870,
	76561199081785301,
	76561198971147660,
	76561198358513331,
	76561198138593759,
	76561198124973959,
	76561198355845610,  # had developer mode until 0.10.8 (Patrick 2026-11-16: "der zweite soll unlock all haben aber nicht dev rechte. Dev rechte hab nur ich")
]
## The one account that counts as "the dev" for Beat the Dev (Patrick only).
const THE_DEV: int = 76561198325616486

## Tests: 1 forces it on, 0 off, -1 asks Steam.
static var forced: int = -1
## Tests: 1 forces `all_cosmetics` on, 0 off, -1 asks Steam.
static var forced_cosmetics: int = -1
## Something dev was used this run (achievements stay off until the game restarts).
static var used: bool = false


## Whether this player may use developer mode.
static func allowed() -> bool:
	if forced >= 0:
		return forced == 1
	return is_dev_id(SteamSvc.get_steam_id() if SteamSvc.is_available() else 0)


## Whether this player owns every cosmetic for good: the developers (`STEAM_IDS`, Patrick
## 2026-11-16: "Unlock all mich für immer weil im shop zeigt immer noch an dass es halt kaufbar
## ist") and `COSMETIC_IDS`. Nothing is bought or saved, the shop just shows every piece as owned.
## Unlike the DEV panel's toggle it doesn't count as dev use, so achievements stay on.
static func all_cosmetics() -> bool:
	if forced_cosmetics >= 0:
		return forced_cosmetics == 1
	if forced >= 0 or ProfileManager.dev_as_player:
		return false
	return owns_everything(SteamSvc.get_steam_id() if SteamSvc.is_available() else 0)


## Whether `steam_id` owns every cosmetic for good (developers and `COSMETIC_IDS`).
static func owns_everything(steam_id: int) -> bool:
	return steam_id != 0 and (steam_id in STEAM_IDS or steam_id in COSMETIC_IDS)


## The achievements a developer account gets on start (Patrick 2026-11-16: "Gib mir auch alle
## achievements"): all of them, except Beat the Dev for a developer who isn't `THE_DEV`, since
## Beat the Dev spreads to whoever beats a holder and Patrick's second account would hand it out.
static func granted_achievements(steam_id: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_dev_id(steam_id):
		return out
	for id: StringName in Achievements.DEFS:
		if id == Achievements.BEAT_THE_DEV and not is_the_dev(steam_id):
			continue
		out.append(id)
	return out


## Whether this player may wear the developer-only pieces (developers and `COSMETIC_IDS`).
static func dev_skins() -> bool:
	return allowed() or all_cosmetics()


## Whether `steam_id` is on the list.
static func is_dev_id(steam_id: int) -> bool:
	return steam_id != 0 and steam_id in STEAM_IDS


## Whether `steam_id` is the developer himself (Beat the Dev).
static func is_the_dev(steam_id: int) -> bool:
	return steam_id != 0 and steam_id == THE_DEV


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


## Play as a normal player (on): the developer's own-everything and the Steam inventory are ignored
## until the game closes, so removed pieces really are gone. Off: own everything again.
static func set_as_player(on: bool) -> void:
	ProfileManager.set_dev_as_player(on)


static func as_player() -> bool:
	return ProfileManager.dev_as_player


## Sets the Coins to `amount` (saved).
static func set_coins(amount: int) -> void:
	mark_used()
	ProfileManager.profile.coins = clampi(amount, 0, PlayerProfile.MAX_COINS)
	_save()


## The pieces this profile holds for itself (bought with Coins, collected, won on the wheel), in
## shop order: what REMOVE can take away. Free and level pieces aren't listed (the level decides).
static func removable() -> Array[StringName]:
	var p: PlayerProfile = ProfileManager.profile
	var out: Array[StringName] = []
	for d: CosmeticDef in p.shop.items:
		if d.id in p.owned or d.id in p.collected or d.id in p.unseen:
			out.append(d.id)
	return out


## Takes piece `id` away again: no longer bought, collected or waiting in COLLECT (an achievement
## or level piece shows up in COLLECT again). Worn: taken off.
static func remove_cosmetic(id: StringName) -> void:
	mark_used()
	var p: PlayerProfile = ProfileManager.profile
	p.owned.erase(id)
	p.collected.erase(id)
	p.unseen.erase(id)
	p.sanitize()
	_save()


## Takes every bought, collected and won piece away (what's worn falls back to free pieces).
static func remove_all_cosmetics() -> void:
	mark_used()
	var p: PlayerProfile = ProfileManager.profile
	p.owned.clear()
	p.collected.clear()
	p.unseen.clear()
	p.sanitize()
	_save()


## Forgets the achievements this profile knows of (until Steam syncs them on the next start), so
## their COLLECT rewards disappear; collected achievement pieces go too.
static func clear_achievements() -> void:
	mark_used()
	var p: PlayerProfile = ProfileManager.profile
	p.achieved.clear()
	var keep: Array[StringName] = []
	for id: StringName in p.collected:
		var d: CosmeticDef = p.shop.find(id)
		if d != null and d.achievement == &"":
			keep.append(id)
	p.collected = keep
	p.sanitize()
	_save()


## Lifetime stats and match counts back to zero.
static func reset_stats() -> void:
	mark_used()
	var p: PlayerProfile = ProfileManager.profile
	p.lifetime.clear()
	p.matches = 0
	p.wins = 0
	p.online_wins = 0
	p.biggest_win = 0
	_save()


## A fresh profile (`ProfileManager.dev_reset_profile`).
static func reset_profile() -> void:
	mark_used()
	ProfileManager.dev_reset_profile()


static func _save() -> void:
	ProfileManager.save()
	ProfileManager.changed.emit()


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
