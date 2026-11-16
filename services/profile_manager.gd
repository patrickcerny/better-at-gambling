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
## Developer mode's "every cosmetic" (`DevMode.set_unlock_all`), kept across `reload`, never saved.
var dev_unlock_all: bool = false


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
	profile.dev_all = dev_unlock_all
	changed.emit()


## Developer mode: every cosmetic owned (on) or back to what the player really has (off).
func set_dev_unlock_all(on: bool) -> void:
	if on == dev_unlock_all:
		return
	dev_unlock_all = on
	profile.dev_all = on
	if not on:
		profile.sanitize()  # take off pieces that were only lent
		save()
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


## Pays out a Daily Spin prize kept in the profile (red Coins, a mystery piece: `DailyWheel`) and
## saves. Returns {coins, piece}.
func add_wheel_prize(kind: StringName, amount: int) -> Dictionary:
	var piece: StringName = DailyWheel.mystery_piece(profile, randf()) if kind == DailyWheel.KIND_PIECE else &""
	var got: Dictionary = profile.add_wheel_prize(kind, amount, piece)
	save()
	changed.emit()
	return got


## Adds `turns` full turns of the main menu logo (`Logo3DView`) and saves. Returns the new total.
## No `changed`: nothing on screen shows it, and it fires several times a second while spinning.
func add_logo_spins(turns: int) -> int:
	if turns > 0:
		profile.logo_spins = mini(profile.logo_spins + turns, PlayerProfile.MAX_STAT)
		save()
	return profile.logo_spins


## Remembers a Daily Spin at `when` (unix seconds) and saves.
func mark_daily_spin(when: int) -> void:
	profile.daily_last = maxi(when, 0)
	save()
	changed.emit()


## Steam had no spin yet although the profile's timer said so (spun on another PC, or Steam wants
## a little playtime first): try again in `retry_s`.
func mark_daily_retry(now: int, retry_s: int = 15 * 60) -> void:
	var as_if: int = now - DailyWheel.COOLDOWN_S + retry_s
	if as_if > profile.daily_last:
		mark_daily_spin(as_if)


## Spins the wheel without Steam (`DailyWheel.roll_local`: red Coins and mystery pieces) at `now`
## and pays the prize. Returns {index, coins, piece, gold}, or {} while the wheel is on cooldown.
func spin_local(now: int, r: float = randf()) -> Dictionary:
	if DailyWheel.wait_s(profile.daily_last, now) > 0:
		return {}
	var i: int = DailyWheel.roll_local(r)
	var seg: Dictionary = DailyWheel.segment(i)
	profile.daily_last = now
	var got: Dictionary = add_wheel_prize(seg["kind"], int(seg["amount"]))  # saves
	return {"index": i, "coins": got["coins"], "piece": got["piece"], "gold": 0}


## Collects a reward from the shop's COLLECT tab (`PlayerProfile.collect`) and saves.
func collect(id: StringName) -> bool:
	if not profile.collect(id):
		return false
	save()
	changed.emit()
	return true


## Collects everything the COLLECT tab holds. Returns what was collected.
func collect_all() -> Array[StringName]:
	var got: Array[StringName] = []
	for id: StringName in profile.collectable():
		if profile.collect(id):
			got.append(id)
	if not got.is_empty():
		save()
		changed.emit()
	return got


## Achievements Steam says this player holds (`SteamSvc.sync_achievements`): their rewards wait in
## the COLLECT tab.
func note_achieved(ids: Array[StringName]) -> void:
	if profile.note_achieved(ids):
		save()
		changed.emit()


## Buys a cosmetic (see `PlayerProfile.buy`) at today's price (`DailyDeals`, or the deal of `day`
## the buyer was shown); &"" on success.
func buy(id: StringName, day: int = -1) -> StringName:
	var err: StringName = profile.buy(id, day if day >= 0 else DailyDeals.today())
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
