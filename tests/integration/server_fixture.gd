class_name ServerFixture
extends RefCounted
## Builds a configured in-process MatchServer with N players (no scene tree needed for logic).

var server: MatchServer
var events: Array[Dictionary] = []
var player_ids: Array[int] = []


## Tests that count quiz events pin the minigame pool to the quiz; pass your own `minigame_pool`
## (or "" for every minigame) to change that. The map definition is a private copy, so a test may
## fill in station positions without leaking them into the next test.
func _init(player_count: int = 2, settings: Dictionary = {"minigames": 2, "gamble_seconds": 100.0, "seed": 1}) -> void:
	server = MatchServer.new()
	var s: Dictionary = settings.duplicate()
	if not s.has("minigame_pool"):
		s["minigame_pool"] = "quiz"
	var map: MapDefinition = Registry.maps[&"lucky_lounge"].duplicate() as MapDefinition
	map.station_positions = map.station_positions.duplicate()  # Resource.duplicate shares the dictionary
	server.configure(s, Registry.balance, Registry.presets, Registry.game_logic_scripts(), map)
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	for i: int in player_count:
		player_ids.append(server.add_player("uid-%d" % (i + 1), "P%d" % (i + 1)))


## Events of one type.
func of_type(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Places every player at `pos` (server-side).
func place_all(pos: Vector3 = Vector3.ZERO) -> void:
	for p: int in player_ids:
		server.world.set_transform(p, pos, 0.0)


## Shorthand intent.
func intent(player: int, type: StringName, payload: Dictionary = {}) -> Dictionary:
	return server.submit_intent(player, Intents.make(type, payload))


## Advances game time by `seconds` in 20 Hz steps.
func run(seconds: float) -> void:
	server.timescale = 1.0
	server.advance(seconds)
