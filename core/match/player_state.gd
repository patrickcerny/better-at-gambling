class_name PlayerState
extends RefCounted
## Per-player match data (money lives in Economy; position in the presentation layer).

var id: int = 0
## Stable identity: SteamID64 or a persisted UUID (dev).
var uid: String = ""
var display_name: String = ""
var color_index: int = 0
var hat: StringName = &"none"
var is_bot: bool = false
var bot_difficulty: StringName = &"normal"
var connected: bool = true
var ready: bool = false
var inventory: Array[StringName] = []
var quiz_points: int = 0
var quiz_correct_time: float = 0.0
var biggest_win: int = 0
var station: StringName = &""
var position: Vector3 = Vector3.ZERO


## Wire dictionary.
func to_wire() -> Dictionary:
	return {
		"id": id, "uid": uid, "name": display_name, "color": color_index, "hat": hat, "bot": is_bot,
		"bot_difficulty": bot_difficulty, "connected": connected, "ready": ready, "inventory": inventory.duplicate(),
		"quiz_points": quiz_points, "quiz_time": quiz_correct_time, "biggest_win": biggest_win, "station": station,
		"pos": Serializer.vec3(position),
	}


## Rebuilds from a wire dictionary.
static func from_wire(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.id = int(d.get("id", 0))
	p.uid = str(d.get("uid", ""))
	p.display_name = str(d.get("name", ""))
	p.color_index = int(d.get("color", 0))
	p.hat = StringName(d.get("hat", "none"))
	p.is_bot = bool(d.get("bot", false))
	p.bot_difficulty = StringName(d.get("bot_difficulty", "normal"))
	p.connected = bool(d.get("connected", true))
	p.ready = bool(d.get("ready", false))
	for item: Variant in d.get("inventory", []):
		p.inventory.append(StringName(item))
	p.quiz_points = int(d.get("quiz_points", 0))
	p.quiz_correct_time = float(d.get("quiz_time", 0.0))
	p.biggest_win = int(d.get("biggest_win", 0))
	p.station = StringName(d.get("station", ""))
	p.position = Serializer.to_vec3(d.get("pos", []))
	return p
