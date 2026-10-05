class_name OnlineService
extends Node
## Client side of the room orchestrator (§4.0.1): create a party, join by room code, rejoin the
## last room. Hands the resulting {host, port, join_token} to `Net.join_server`. Tickets are
## `dev:<name>` until Steam auth lands (M8). The last room is kept in `user://last_room.cfg`.

const LAST_ROOM_PATH: String = "user://last_room.cfg"
const CONFIG_PATH: String = "res://data/online/online_config.tres"

var http: HttpJson
## Error text of the last failed call (player-facing).
var last_error: String = ""


func _ready() -> void:
	http = HttpJson.new()
	http.name = "Http"
	add_child(http)


## Base URL of the orchestrator (`--orchestrator` wins over the config resource).
func orchestrator_url() -> String:
	var cmd: Cmdline = SceneRouter.cmdline if SceneRouter.cmdline != null else Cmdline.from_os()
	if cmd.has("orchestrator"):
		return cmd.get_string("orchestrator")
	var cfg: OnlineConfig = load(CONFIG_PATH) as OnlineConfig
	return cfg.orchestrator_url if cfg != null else "http://127.0.0.1:8080"


## Creates a room. Returns {room_id, room_code, host, port, join_token} or {} (see `last_error`).
func create_party(display_name: String) -> Dictionary:
	var res: Dictionary = await http.post(orchestrator_url().path_join("v1/rooms"), {"ticket": _ticket(display_name), "build": Protocol.BUILD_ID, "display_name": display_name})
	return _room_or_error(res)


## Joins a room by its 5-character code (or rejoins one we were in by id).
func join_party(display_name: String, room_code: String = "", room_id: String = "") -> Dictionary:
	var body: Dictionary = {"ticket": _ticket(display_name), "build": Protocol.BUILD_ID}
	if room_id != "":
		body["room_id"] = room_id
	else:
		body["room_code"] = room_code.strip_edges().to_upper()
	var res: Dictionary = await http.post(orchestrator_url().path_join("v1/rooms/join"), body)
	return _room_or_error(res)


## Connects to a room returned by `create_party`/`join_party`.
func connect_room(room: Dictionary, display_name: String, cosmetics: Dictionary = {}, opts: Dictionary = {}) -> Error:
	var hello: Dictionary = {"join_token": room["join_token"], "name": display_name, "color": int(cosmetics.get("color", -1)), "hat": StringName(cosmetics.get("hat", "none"))}
	var err: Error = Net.join_server(str(room["host"]), int(room["port"]), hello, opts)
	if err == OK:
		Net.room = {"room_id": room.get("room_id", ""), "room_code": room.get("room_code", ""), "host": room["host"], "port": room["port"]}
		save_last_room(Net.room)
	return err


## The room we were last in ({} if none).
func last_room() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(LAST_ROOM_PATH) != OK:
		return {}
	return {"room_id": cfg.get_value("room", "room_id", ""), "room_code": cfg.get_value("room", "room_code", "")}


func save_last_room(room: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("room", "room_id", room.get("room_id", ""))
	cfg.set_value("room", "room_code", room.get("room_code", ""))
	cfg.save(LAST_ROOM_PATH)


func _ticket(display_name: String) -> String:
	# Steam Web API tickets replace this in M8 (SteamService.get_auth_ticket).
	var clean: String = display_name.strip_edges().substr(0, 24)
	return "dev:%s" % (clean if clean != "" else "Player")


func _room_or_error(res: Dictionary) -> Dictionary:
	if res["status"] == 200:
		last_error = ""
		return res["body"]
	var body: Dictionary = res["body"]
	last_error = str(body.get("message", "The party service did not answer."))
	Log.warn(&"online", "orchestrator call failed (%d %s)" % [res["status"], body.get("error", "")])
	return {}
