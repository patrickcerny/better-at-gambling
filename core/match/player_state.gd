class_name PlayerState
extends RefCounted
## Per-player match data (money lives in Economy; position in the presentation layer).

var id: int = 0
## Stable identity: SteamID64 or a persisted UUID (dev).
var uid: String = ""
var display_name: String = ""
## Player colour (`Palette.player_color`): name tag, HUD and the bean itself (`Cosmetics`).
var color_index: int = 0
## The bean's colour (`Palette.player_color`, 0 .. `Cosmetics.COLOR_COUNT`-1): the player's
## preferred colour unless another bean wears it (`Cosmetics.bean_color_for`).
var bean_color: int = 0
var connected: bool = true
var ready: bool = false
var inventory: Array[StringName] = []
var quiz_points: int = 0
var quiz_correct_time: float = 0.0
var biggest_win: int = 0
var station: StringName = &""
## Physical seat at that station (0-based, -1 = none): the server hands out the lowest free one so
## two players never share a chair.
var seat: int = -1
var position: Vector3 = Vector3.ZERO
## Jail system (v0.8.3): count of how many times caught; resets to 0 on Get Out of Jail Free item use.
var catch_count: int = 0
## Seconds remaining in jail (0 = not in jail).
var jail_time_remaining: float = 0.0
## Fine amount for the current jail stay (deducted when released).
var jail_fine: int = 0


## Wire dictionary.
func to_wire() -> Dictionary:
	return {
		"id": id, "uid": uid, "name": display_name, "color": color_index, "bean_color": bean_color,
		"connected": connected, "ready": ready, "inventory": inventory.duplicate(),
		"quiz_points": quiz_points, "quiz_time": quiz_correct_time, "biggest_win": biggest_win, "station": station, "seat": seat,
		"pos": Serializer.vec3(position),
		"catch_count": catch_count, "jail_time": snappedf(jail_time_remaining, 0.01), "jail_fine": jail_fine,
	}


## Rebuilds from a wire dictionary.
static func from_wire(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.id = int(d.get("id", 0))
	p.uid = str(d.get("uid", ""))
	p.display_name = str(d.get("name", ""))
	p.color_index = int(d.get("color", 0))
	p.bean_color = int(d.get("bean_color", p.color_index))
	p.connected = bool(d.get("connected", true))
	p.ready = bool(d.get("ready", false))
	for item: Variant in d.get("inventory", []):
		p.inventory.append(StringName(item))
	p.quiz_points = int(d.get("quiz_points", 0))
	p.quiz_correct_time = float(d.get("quiz_time", 0.0))
	p.biggest_win = int(d.get("biggest_win", 0))
	p.station = StringName(d.get("station", ""))
	p.seat = int(d.get("seat", -1))
	p.position = Serializer.to_vec3(d.get("pos", []))
	p.catch_count = int(d.get("catch_count", 0))
	p.jail_time_remaining = float(d.get("jail_time", 0.0))
	p.jail_fine = int(d.get("jail_fine", 0))
	return p
