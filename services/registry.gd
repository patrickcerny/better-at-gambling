extends Node
## `Registry` autoload: indexes registered games, items, minigames, maps and modes from
## `data/registry/*.tres` (§3.6). The only place new content is registered.

var games: Dictionary[StringName, GameDefinition] = {}
var items: Dictionary[StringName, ItemDefinition] = {}
var minigames: Dictionary[StringName, MinigameDefinition] = {}
var maps: Dictionary[StringName, MapDefinition] = {}
var balance: BalanceConfig
var presets: MatchPresets
var loot: LootTableConfig


func _ready() -> void:
	reload()


## (Re)loads every registry list.
func reload() -> void:
	games.clear()
	items.clear()
	minigames.clear()
	maps.clear()
	_index("res://data/registry/games.tres", games)
	_index("res://data/registry/items.tres", items)
	_index("res://data/registry/minigames.tres", minigames)
	_index("res://data/registry/maps.tres", maps)
	balance = load("res://data/balance/balance.tres") as BalanceConfig
	presets = load("res://data/balance/match_presets.tres") as MatchPresets
	loot = load("res://data/items/loot_tables.tres") as LootTableConfig
	Log.info(&"registry", "%d games, %d items, %d minigames, %d maps" % [games.size(), items.size(), minigames.size(), maps.size()])


## Game id → logic Script, for the StationManager.
func game_logic_scripts() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in games:
		out[id] = games[id].logic_script
	return out


func _index(path: String, into: Dictionary) -> void:
	if not ResourceLoader.exists(path):
		return
	var list: RegistryList = load(path) as RegistryList
	if list == null:
		Log.error(&"registry", "%s is not a RegistryList" % path)
		return
	for entry: Resource in list.entries:
		if entry == null or not "id" in entry:
			Log.error(&"registry", "entry without id in %s" % path)
			continue
		var id: StringName = entry.get("id")
		if into.has(id):
			Log.error(&"registry", "duplicate id %s in %s" % [id, path])
		into[id] = entry
