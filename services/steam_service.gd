extends Node
## `SteamSvc` autoload: the game's door to Steam through the GodotSteam GDExtension
## (addons/godotsteam). The autoload is named `SteamSvc`, not `Steam`, because GodotSteam registers
## an engine singleton called `Steam` (docs/DECISIONS.md).
##
## Steam is optional: the game is the GitHub zip and Steam only has to be running for host mode
## (host a party on this PC, friends join through the Steam relay, App ID 480 until we have our
## own). Without a Steam client (the headless tests, the dedicated server, `--no-steam`, a PC
## without Steam) `is_available()` is false, nothing else is called and one info line says why.
##
## Lobbies: the host's party is a friends-only Steam lobby carrying {game, build, name}; friends
## join it from the overlay invite or "Join game" in their friends list (`join_requested`), or the
## game is launched with `+connect_lobby <id>` (Steam starts it that way when it wasn't running).
## The lobby owner's Steam ID is where the joiner connects (`SteamTransport`).

## A friend chose "Join game" / accepted an invite (or the game was launched to join a lobby).
signal join_requested(lobby_id: int)
## `create_lobby` finished: the lobby id, or 0 with `last_error` set.
signal lobby_ready(lobby_id: int)
## `join_lobby` finished: {lobby_id, owner, ok, error}.
signal lobby_entered(result: Dictionary)
## Someone entered or left our lobby.
signal lobby_members_changed(lobby_id: int)

## Free test App ID ("Spacewar") until the game has its own; friends see "Spacewar" as the game.
const APP_ID: int = 480
const LOBBY_GAME: String = "better_at_gambling"
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1
const FRIEND_FLAG_IMMEDIATE: int = 4

## The GodotSteam singleton (null when the extension is missing).
var steam: Object = null
## Lobby we are in (0 = none) and whether we own it.
var lobby_id: int = 0
var lobby_owner: bool = false
## A lobby to join that arrived before anyone could act on it (launch argument, or a join request
## while a match was loading). The main menu picks it up.
var pending_lobby: int = 0
var last_error: String = ""

var _available: bool = false
var _steam_id: int = 0
var _persona: String = ""


func _ready() -> void:
	pending_lobby = _launch_lobby(OS.get_cmdline_args())
	var why: String = _skip_reason()
	if why != "":
		Log.info(&"steam", "Steam off: %s" % why)
		return
	steam = Engine.get_singleton("Steam")
	if not bool(steam.call("isSteamRunning")):
		Log.info(&"steam", "Steam off: the Steam client is not running")
		steam = null
		return
	var res: Dictionary = steam.call("steamInitEx", APP_ID, false)
	if int(res.get("status", 1)) != 0:
		Log.info(&"steam", "Steam off: %s" % str(res.get("verbal", "init failed")))
		steam = null
		return
	_available = true
	_steam_id = int(steam.call("getSteamID"))
	_persona = str(steam.call("getPersonaName"))
	steam.call("initRelayNetworkAccess")  # warm up the relay network before anyone hosts or joins
	steam.connect(&"join_requested", _on_join_requested)
	steam.connect(&"lobby_created", _on_lobby_created)
	steam.connect(&"lobby_joined", _on_lobby_joined)
	steam.connect(&"lobby_chat_update", _on_lobby_chat_update)
	Log.info(&"steam", "Steam on: %s (app %d)" % [_persona, APP_ID])


func _process(_delta: float) -> void:
	if _available:
		steam.call("run_callbacks")


func _exit_tree() -> void:
	if _available:
		leave_lobby()
		steam.call("steamShutdown")
		_available = false


## Why Steam stays off in this process ("" = try it).
func _skip_reason() -> String:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if "--no-steam" in user_args:
		return "--no-steam"
	if "--server" in user_args:
		return "dedicated server"
	if DisplayServer.get_name() == "headless":
		return "headless"
	if not Engine.has_singleton("Steam"):
		return "GodotSteam extension not loaded"
	return ""


## `+connect_lobby <id>` from the engine's command line (0 if absent).
static func _launch_lobby(args: PackedStringArray) -> int:
	var i: int = args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		return int(args[i + 1])
	return 0


## True when a Steam client is running and the API initialised.
func is_available() -> bool:
	return _available


## Steam persona name, or the OS user name as a stand-in.
func get_persona_name() -> String:
	if _available and _persona != "":
		return _persona
	var user: String = OS.get_environment("USER")
	if user.is_empty():
		user = OS.get_environment("USERNAME")
	return user if not user.is_empty() else "Player"


## Our Steam ID (0 without Steam).
func get_steam_id() -> int:
	return _steam_id


## Creates our friends-only party lobby; `lobby_ready` follows. Returns false without Steam.
func create_lobby(party_name: String, max_members: int) -> bool:
	if not _available:
		last_error = "Start Steam to host."
		return false
	leave_lobby()
	lobby_owner = true
	steam.call("createLobby", LOBBY_TYPE_FRIENDS_ONLY, max_members)
	set_meta(&"party_name", party_name)
	return true


## Joins a friend's lobby; `lobby_entered` follows.
func join_lobby(id: int) -> bool:
	if not _available or id == 0:
		last_error = "Start Steam to join friends."
		return false
	leave_lobby()
	lobby_owner = false
	steam.call("joinLobby", id)
	return true


func leave_lobby() -> void:
	if _available and lobby_id != 0:
		steam.call("leaveLobby", lobby_id)
		steam.call("clearRichPresence")
	lobby_id = 0
	lobby_owner = false


## Opens the Steam overlay's invite dialog for our lobby.
func invite_friends() -> bool:
	if not _available or lobby_id == 0:
		return false
	steam.call("activateGameOverlayInviteDialog", lobby_id)
	return true


## Lobby data of any lobby we know ("" if unknown).
func lobby_data(id: int, key: String) -> String:
	return str(steam.call("getLobbyData", id, key)) if _available else ""


## The lobby's owner (the host's Steam ID).
func lobby_owner_of(id: int) -> int:
	return int(steam.call("getLobbyOwner", id)) if _available else 0


func member_count() -> int:
	return int(steam.call("getNumLobbyMembers", lobby_id)) if _available and lobby_id != 0 else 0


## Friends playing this App ID inside a lobby: [{steam_id, name, lobby, party}] ("party" is the
## lobby's name once Steam has its data; lobbies of other "Spacewar" games are left out once known).
func friend_lobbies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _available:
		return out
	var n: int = int(steam.call("getFriendCount", FRIEND_FLAG_IMMEDIATE))
	for i: int in n:
		var fid: int = int(steam.call("getFriendByIndex", i, FRIEND_FLAG_IMMEDIATE))
		var game: Dictionary = steam.call("getFriendGamePlayed", fid)
		if int(game.get("id", 0)) != APP_ID or int(game.get("lobby", 0)) == 0:
			continue
		var lid: int = int(game["lobby"])
		var kind: String = lobby_data(lid, "game")
		if kind == "":
			steam.call("requestLobbyData", lid)  # arrives later; the list refreshes
		elif kind != LOBBY_GAME:
			continue
		out.append({"steam_id": fid, "name": str(steam.call("getFriendPersonaName", fid)), "lobby": lid, "party": lobby_data(lid, "name"), "build": lobby_data(lid, "build")})
	return out


# --- callbacks ---------------------------------------------------------------------------------

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1 or id == 0:
		last_error = "Steam could not create the party lobby (error %d)." % result
		Log.warn(&"steam", last_error)
		lobby_owner = false
		lobby_ready.emit(0)
		return
	lobby_id = id
	var party: String = str(get_meta(&"party_name", "%s's party" % get_persona_name()))
	steam.call("setLobbyData", id, "game", LOBBY_GAME)
	steam.call("setLobbyData", id, "build", Protocol.BUILD_ID)
	steam.call("setLobbyData", id, "name", party)
	steam.call("setLobbyJoinable", id, true)
	steam.call("setRichPresence", "status", party)
	Log.info(&"steam", "party lobby %d created" % id)
	lobby_ready.emit(id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if lobby_owner:
		return  # our own lobby: `lobby_created` handled it
	if response != CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		last_error = "Could not join the party (Steam says %s)." % _enter_text(response)
		lobby_entered.emit({"lobby_id": id, "ok": false, "error": last_error})
		return
	lobby_id = id
	var owner: int = lobby_owner_of(id)
	lobby_entered.emit({"lobby_id": id, "ok": true, "owner": owner, "game": lobby_data(id, "game"), "build": lobby_data(id, "build"), "name": lobby_data(id, "name")})


func _on_lobby_chat_update(id: int, _changed: int, _making_change: int, _state: int) -> void:
	if id == lobby_id:
		lobby_members_changed.emit(id)


func _on_join_requested(id: int, _friend: int) -> void:
	Log.info(&"steam", "join requested: lobby %d" % id)
	pending_lobby = id
	join_requested.emit(id)


static func _enter_text(response: int) -> String:
	match response:
		2:
			return "the party no longer exists"
		3:
			return "you are not allowed in"
		4:
			return "the party is full"
		6:
			return "you are banned"
	return "error %d" % response
