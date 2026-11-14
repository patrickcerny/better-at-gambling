extends Node
## `ProfileManager` autoload: the local player's `PlayerProfile` (XP, level, Coins, owned and
## preferred cosmetics, lifetime stats) in user://profile.cfg, like `Settings` keeps
## user://settings.cfg. Every change saves at once and fires `changed`. The match scene hands it
## the results event (`apply_results`), the cosmetics shop buys and equips through it, and the
## pedestal colour panel sets the preferred colour.
## Test runs never touch the player's real file: under GUT and in `--autoplay` game clients
## (network tests, bots) the profile starts fresh and stays in memory only.

signal changed

const PATH: String = "user://profile.cfg"

var profile: PlayerProfile
## Where this one saves (tests point it elsewhere).
var path: String = PATH
## Off: nothing is read or written, the profile lives in memory (tests, autoplay clients).
var persist: bool = true
## Pieces in the Steam inventory (`SteamSvc`), kept across `reload`.
var steam_owned: Array[StringName] = []


func _ready() -> void:
	persist = not is_test_run()
	reload()


## GUT or an `--autoplay` client: keep the player's real profile out of it.
static func is_test_run() -> bool:
	for a: String in OS.get_cmdline_args():
		if a.ends_with("gut_cmdln.gd") or a == "--autoplay":
			return true
	return false


## Reads the file again (missing, or not persisting: a fresh profile).
func reload() -> void:
	profile = PlayerProfile.new()
	var err: Error = profile.load_from(path) if persist else ERR_FILE_NOT_FOUND
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Log.warn(&"profile", "could not load %s (error %d), starting fresh" % [path, err])
	profile.steam_owned = steam_owned.duplicate()
	changed.emit()


## What the Steam inventory holds now (pieces bought with real money).
func set_steam_owned(ids: Array[StringName]) -> void:
	if ids == steam_owned:
		return
	steam_owned = ids.duplicate()
	profile.steam_owned = steam_owned.duplicate()
	changed.emit()


func save() -> void:
	if not persist:
		return
	var err: Error = profile.save(path)
	if err != OK:
		Log.warn(&"profile", "could not save %s (error %d)" % [path, err])


## Adds the local player's row of a `match_ended` event (`Progression`) to the profile, once per
## match id. Returns `PlayerProfile.apply_match`'s summary ({} when nothing was added).
func apply_results(ev: Dictionary, local_id: int) -> Dictionary:
	var rows: Dictionary = ev.get("progress", {})
	var row: Variant = rows.get(local_id, null)
	if not row is Dictionary:
		return {}
	var out: Dictionary = profile.apply_match(str(ev.get("match_id", "")), row as Dictionary)
	if not out.is_empty():
		save()
		changed.emit()
	return out


## Adds Coins bought with real money and saves. Returns how many were added.
func add_coins(amount: int) -> int:
	var added: int = profile.add_coins(amount)
	if added > 0:
		save()
		changed.emit()
	return added


## Buys a cosmetic (see `PlayerProfile.buy`); &"" on success.
func buy(id: StringName) -> StringName:
	var err: StringName = profile.buy(id)
	if err == &"":
		save()
		changed.emit()
	return err


## Wears an owned outfit piece in its slot.
func wear(id: StringName) -> bool:
	if profile.is_worn(id):
		return true
	if not profile.wear(id):
		return false
	save()
	changed.emit()
	return true


## Takes off the piece in slot `kind`.
func take_off(kind: StringName) -> void:
	if not profile.outfit.has(kind):
		return
	profile.take_off(kind)
	save()
	changed.emit()


## Sets the preferred bean colour (owned colours only).
func set_preferred_color(index: int) -> bool:
	if index == profile.preferred_color:
		return true
	if not profile.set_preferred_color(index):
		return false
	save()
	changed.emit()
	return true
