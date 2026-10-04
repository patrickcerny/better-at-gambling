class_name ServerFixture
extends RefCounted
## Builds a configured in-process MatchServer with N players (no scene tree needed for logic).

var server: MatchServer
var events: Array[Dictionary] = []
var player_ids: Array[int] = []


func _init(player_count: int = 2, settings: Dictionary = {"duration": 5, "seed": 1}) -> void:
	server = MatchServer.new()
	server.configure(settings, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
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
