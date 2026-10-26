extends Node
## `ProfileManager` autoload: the local player's `PlayerProfile` (XP, level, Coins, owned and
## preferred cosmetics, lifetime stats) in user://profile.cfg, like `Settings` keeps
## user://settings.cfg. Every change saves at once and fires `changed`. The match scene hands it
## the results event (`apply_results`), the cosmetics shop buys and equips through it, and the
## pedestal colour panel sets the preferred colour.

signal changed

const PATH: String = "user://profile.cfg"

var profile: PlayerProfile
## Where this one saves (tests point it elsewhere).
var path: String = PATH


func _ready() -> void:
	reload()


## Reads the file again (missing: a fresh profile).
func reload() -> void:
	profile = PlayerProfile.new()
	var err: Error = profile.load_from(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Log.warn(&"profile", "could not load %s (error %d), starting fresh" % [path, err])
	changed.emit()


func save() -> void:
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


## Buys a cosmetic (see `PlayerProfile.buy`); &"" on success.
func buy(id: StringName) -> StringName:
	var err: StringName = profile.buy(id)
	if err == &"":
		save()
		changed.emit()
	return err


## Sets the preferred bean colour (owned colours only).
func set_preferred_color(index: int) -> bool:
	if index == profile.preferred_color:
		return true
	if not profile.set_preferred_color(index):
		return false
	save()
	changed.emit()
	return true
