extends Node
## `Net` autoload: the client's single door to the server. In local mode (Practice/Tutorial) it
## talks to an in-process MatchServer; in M3 the same API goes over ENet. Presentation code only
## ever calls `send_intent` and listens to `event_received`.

## Emitted for every server event, in sequence order.
signal event_received(event: Dictionary)
## Emitted when a connection to a server is established.
signal connected
## Emitted when the connection drops or fails.
signal disconnected(reason: String)

enum Mode { NONE, LOCAL, CLIENT, SERVER }

var mode: Mode = Mode.NONE
## This client's player id on the server (-1 when not connected).
var local_player_id: int = -1
## The in-process server in LOCAL (and SERVER) mode.
var local_server: MatchServer = null


## Starts an in-process session with `server` and joins it as `display_name`.
func start_local(server: MatchServer, display_name: String) -> int:
	stop()
	mode = Mode.LOCAL
	local_server = server
	server.event_emitted.connect(_on_local_event)
	local_player_id = server.add_player("local", display_name)
	connected.emit()
	return local_player_id


## Leaves the current session.
func stop() -> void:
	if local_server != null and local_server.event_emitted.is_connected(_on_local_event):
		local_server.event_emitted.disconnect(_on_local_event)
	local_server = null
	local_player_id = -1
	mode = Mode.NONE


## Sends an intent to the server. Returns the server's {ok, error} in local mode, OK otherwise.
func send_intent(intent: Dictionary) -> Dictionary:
	match mode:
		Mode.LOCAL:
			return local_server.submit_intent(local_player_id, intent)
	return StationLogicBase.fail(&"not_connected")


## Requests a full snapshot (immediate in local mode).
func request_snapshot() -> Dictionary:
	if mode == Mode.LOCAL:
		return local_server.get_snapshot()
	return {}


## Private snapshot for this player (own station secrets).
func request_private_snapshot() -> Dictionary:
	if mode == Mode.LOCAL:
		return local_server.get_private_snapshot(local_player_id)
	return {}


## True while this process runs as the dedicated server.
func is_server() -> bool:
	return mode == Mode.SERVER


func _on_local_event(ev: Dictionary) -> void:
	event_received.emit(ev)
