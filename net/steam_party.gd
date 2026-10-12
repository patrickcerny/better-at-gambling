class_name SteamParty
extends Node
## Host mode (docs/DECISIONS.md "Host mode over Steam", like Pummel Party): host a party on this
## PC and let Steam friends in through Steam's relay, with no orchestrator and no port forwarding.
## Lives under `Net` as `Net.steam_party`.
##
## Hosting starts the party's room server as a second, headless process of this same game
## (`--server --host-mode`, listening on loopback only), so the room runs exactly the code a
## dedicated server runs; this game then joins it like any client, and a `HostBridge` connects
## friends arriving over Steam to it. The Steam lobby is the party's "code": friends join through
## the overlay invite or "Join game", which lands in `join` → `Net.join_server` over a
## `SteamTransport` to the lobby owner. Leaving the session tears it all down (server process,
## bridge, lobby).

## Seconds to wait for the room server process to start listening.
const SERVER_START_TIMEOUT: float = 60.0
## Seconds to wait for Steam to create or join a lobby.
const LOBBY_TIMEOUT: float = 20.0

var last_error: String = ""
## True while this PC hosts a party.
var hosting: bool = false
var bridge: HostBridge = null
var server_pid: int = 0
var server_port: int = 0

var _ready_file: String = ""


func _ready() -> void:
	Net.session_ended.connect(_on_session_ended)
	_hook_steam.call_deferred()  # SteamSvc is the next autoload: not in the tree yet


func _hook_steam() -> void:
	SteamSvc.join_requested.connect(_on_join_requested)


## A friend's invite was accepted / "Join game" clicked. The main menu joins `pending_lobby`; from
## a match (or anywhere else) we leave first and go there.
func _on_join_requested(_lobby_id: int) -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.scene_file_path == SceneRouter.MAIN_MENU:
		return  # the menu listens itself
	Net.stop()
	SceneRouter.goto(SceneRouter.MAIN_MENU)


func _process(_delta: float) -> void:
	if bridge != null:
		bridge.poll()


## Steps 1-3 of hosting: room server process, Steam lobby, bridge. Returns the loopback port to
## join (`join_own_party`), or 0 with `last_error` set.
func start_hosting(display_name: String) -> int:
	last_error = ""
	if not SteamSvc.is_available():
		last_error = "Start Steam to host."
		return 0
	stop_hosting()
	if await spawn_room_server("steam:%d" % SteamSvc.get_steam_id()) == 0:
		return 0
	if not SteamSvc.create_lobby("%s's lobby" % display_name, Protocol.MAX_PLAYERS):
		last_error = SteamSvc.last_error
		stop_hosting()
		return 0
	var lobby: int = await _wait_lobby_ready()
	if lobby == 0:
		last_error = SteamSvc.last_error if SteamSvc.last_error != "" else "Steam did not create the lobby."
		stop_hosting()
		return 0
	var outside := SteamTransport.new()
	if outside.listen(Protocol.MAX_PLAYERS + 4) != OK:
		last_error = "Steam networking is not available."
		stop_hosting()
		return 0
	var port: int = server_port
	bridge = HostBridge.new(outside,
		func() -> NetTransport: return TransportFactory.client("127.0.0.1", port),
		func(peer: int) -> String: return "steam:%d" % outside.steam_id_of(peer))
	return server_port


## Step 4: this game joins its own room server (call through the menu's `_connect`).
func join_own_party(display_name: String, cosmetics: Dictionary) -> Error:
	var hello: Dictionary = {"name": display_name, "uid": "steam:%d" % SteamSvc.get_steam_id(), "color": int(cosmetics.get("color", -1)), "skin": StringName(cosmetics.get("skin", "bean"))}
	var err: Error = Net.join_server("127.0.0.1", server_port, hello)
	if err == OK:
		Net.room = {"host": "127.0.0.1", "port": server_port, "steam_lobby": SteamSvc.lobby_id, "host_mode": true}
	return err


## Joining a friend: enters their Steam lobby and checks it. Returns the host's Steam ID, or 0
## with `last_error` set.
func enter_lobby(lobby_id: int) -> int:
	last_error = ""
	stop_hosting()
	if not SteamSvc.join_lobby(lobby_id):
		last_error = SteamSvc.last_error
		return 0
	var res: Dictionary = await _wait_lobby_entered()
	if not bool(res.get("ok", false)):
		last_error = str(res.get("error", "Steam did not answer."))
		SteamSvc.leave_lobby()
		return 0
	var problem: String = check_lobby(res, SteamSvc.get_steam_id())
	if problem != "":
		last_error = problem
		SteamSvc.leave_lobby()
		return 0
	return int(res["owner"])


## Connects to the lobby owner's game over Steam (call through the menu's `_connect`).
func join_host(host_steam_id: int, display_name: String, cosmetics: Dictionary) -> Error:
	var hello: Dictionary = {"name": display_name, "color": int(cosmetics.get("color", -1)), "skin": StringName(cosmetics.get("skin", "bean"))}
	var err: Error = Net.join_server("steam:%d" % host_steam_id, 0, hello, {"transport": "steam", "steam_id": host_steam_id})
	if err == OK:
		Net.room = {"host": "steam:%d" % host_steam_id, "port": 0, "steam_lobby": SteamSvc.lobby_id}
	return err


## Why a lobby can't be joined ("" = fine): another game on App 480, another build, or ourselves.
static func check_lobby(info: Dictionary, my_steam_id: int) -> String:
	if str(info.get("game", "")) != SteamSvc.LOBBY_GAME:
		return "That Steam lobby is not a Better at Gambling lobby."
	if str(info.get("build", "")) != Protocol.BUILD_ID:
		return "Your friend is on version %s, you are on %s. Both need the same version." % [str(info.get("build", "?")), Protocol.BUILD_ID]
	if int(info.get("owner", 0)) == 0:
		return "The lobby has no host any more."
	if int(info.get("owner", 0)) == my_steam_id:
		return "That is your own lobby."
	return ""


## Starts the party's room server process (loopback only) and waits until it listens. Returns its
## port, or 0 with `last_error` set. `hosting` is true from here on (`stop_hosting` ends it).
func spawn_room_server(host_uid: String) -> int:
	server_port = free_loopback_port()
	_ready_file = OS.get_user_data_dir().path_join("host_ready_%d.txt" % OS.get_process_id())
	DirAccess.remove_absolute(_ready_file)
	var args: PackedStringArray = server_args(server_port, host_uid, _ready_file)
	server_pid = OS.create_process(OS.get_executable_path(), args)
	if server_pid <= 0:
		last_error = "Could not start the lobby server on this PC."
		server_pid = 0
		return 0
	Log.info(&"host", "room server process %d starting on loopback port %d" % [server_pid, server_port])
	hosting = true
	var waited: float = 0.0
	while not FileAccess.file_exists(_ready_file):
		if waited > SERVER_START_TIMEOUT or not _server_running():
			last_error = "The lobby server did not start (see logs/host_server.log)."
			stop_hosting()
			return 0
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if not hosting:
			return 0  # cancelled
	return server_port


## True while the room server process runs. An exited process is reaped by the check, so it is
## asked only once after that (`server_pid` goes to 0).
func _server_running() -> bool:
	if server_pid <= 0:
		return false
	if OS.is_process_running(server_pid):
		return true
	server_pid = 0
	return false


## Command line for the room server process.
static func server_args(port: int, host_uid: String, ready_file: String) -> PackedStringArray:
	var args: PackedStringArray = []
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])  # dev: the editor binary
	args.append_array(["--headless", "--audio-driver", "Dummy", "--log-file", OS.get_user_data_dir().path_join("logs/host_server.log")])
	args.append_array(["--", "--server", "--host-mode", "--port", str(port), "--host-uid", host_uid, "--ready-file", ready_file, "--empty-timeout", "120"])
	return args


## A UDP port nobody on this PC uses.
static func free_loopback_port() -> int:
	for i: int in 50:
		var port: int = randi_range(30000, 60000)
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return Protocol.DEFAULT_PORT + 1


## Ends hosting: bridge, Steam lobby, room server process.
func stop_hosting() -> void:
	if bridge != null:
		bridge.close()
		bridge = null
	if server_pid > 0:
		var pid: int = server_pid
		if _server_running():
			OS.kill(pid)
		Log.info(&"host", "room server process %d stopped" % pid)
		server_pid = 0
	if _ready_file != "":
		DirAccess.remove_absolute(_ready_file)
		_ready_file = ""
	if hosting or SteamSvc.lobby_owner:
		SteamSvc.leave_lobby()
	hosting = false


func _on_session_ended() -> void:
	if hosting:
		stop_hosting()
	elif SteamSvc.lobby_id != 0:
		SteamSvc.leave_lobby()


func _exit_tree() -> void:
	stop_hosting()


func _wait_lobby_ready() -> int:
	var box: Array[int] = [-1]
	var cb: Callable = func(id: int) -> void: box[0] = id
	SteamSvc.lobby_ready.connect(cb, CONNECT_ONE_SHOT)
	var waited: float = 0.0
	while box[0] < 0 and waited < LOBBY_TIMEOUT:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if SteamSvc.lobby_ready.is_connected(cb):
		SteamSvc.lobby_ready.disconnect(cb)
	return maxi(box[0], 0)


func _wait_lobby_entered() -> Dictionary:
	var box: Array[Dictionary] = [{}]
	var cb: Callable = func(res: Dictionary) -> void: box[0] = res
	SteamSvc.lobby_entered.connect(cb, CONNECT_ONE_SHOT)
	var waited: float = 0.0
	while box[0].is_empty() and waited < LOBBY_TIMEOUT:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if SteamSvc.lobby_entered.is_connected(cb):
		SteamSvc.lobby_entered.disconnect(cb)
	return box[0] if not box[0].is_empty() else {"ok": false, "error": "Steam did not answer."}
