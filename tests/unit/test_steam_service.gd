extends GutTest
## SteamSvc without a Steam client (the headless tests, the dedicated server): unavailable, no
## crash, every call a safe no-op; `+connect_lobby <id>` launch arguments are read; host-mode
## lobby checks and the room server's command line.


func test_no_steam_client_means_unavailable_and_safe_calls() -> void:
	assert_false(SteamSvc.is_available())
	assert_eq(SteamSvc.get_steam_id(), 0)
	assert_ne(SteamSvc.get_persona_name(), "", "a stand-in name")
	assert_false(SteamSvc.create_lobby("x", 8))
	assert_eq(SteamSvc.last_error, "Start Steam to host.")
	assert_false(SteamSvc.join_lobby(123))
	assert_false(SteamSvc.invite_friends())
	assert_eq(SteamSvc.friend_lobbies().size(), 0)
	assert_eq(SteamSvc.lobby_data(1, "game"), "")
	SteamSvc.leave_lobby()
	assert_eq(SteamSvc.lobby_id, 0)


func test_host_mode_refuses_politely_without_steam() -> void:
	var port: int = await Net.steam_party.start_hosting("Patrick")
	assert_eq(port, 0)
	assert_eq(Net.steam_party.last_error, "Start Steam to host.")
	assert_false(Net.steam_party.hosting)
	assert_eq(Net.steam_party.server_pid, 0)


func test_connect_lobby_launch_argument() -> void:
	var svc: GDScript = load("res://services/steam_service.gd")
	assert_eq(svc.call(&"_launch_lobby", PackedStringArray(["--path", ".", "+connect_lobby", "109775240000000042"])), 109775240000000042)
	assert_eq(svc.call(&"_launch_lobby", PackedStringArray(["+connect_lobby"])), 0)
	assert_eq(svc.call(&"_launch_lobby", PackedStringArray(["--headless"])), 0)


func test_lobby_checks() -> void:
	var ok: Dictionary = {"game": SteamSvc.LOBBY_GAME, "build": Protocol.BUILD_ID, "owner": 76561190000000001}
	assert_eq(SteamParty.check_lobby(ok, 76561190000000002), "")
	var other_game: Dictionary = ok.duplicate()
	other_game["game"] = ""
	assert_string_contains(SteamParty.check_lobby(other_game, 2), "not a Better at Gambling lobby", "App 480 is shared with other games")
	var old: Dictionary = ok.duplicate()
	old["build"] = "0.0.1"
	assert_string_contains(SteamParty.check_lobby(old, 2), "same version")
	assert_string_contains(SteamParty.check_lobby(ok, 76561190000000001), "your own lobby")


func test_room_server_command_line() -> void:
	var args: PackedStringArray = SteamParty.server_args(31337, "steam:7", "/tmp/ready.txt")
	assert_true("--headless" in args)
	var user: PackedStringArray = args.slice(args.find("--") + 1)
	assert_eq(user, PackedStringArray(["--server", "--host-mode", "--port", "31337", "--host-uid", "steam:7", "--ready-file", "/tmp/ready.txt", "--empty-timeout", "120"]))
	assert_true("--path" in args, "dev runs (no export template) point the engine at the project")
	var port: int = SteamParty.free_loopback_port()
	assert_between(port, 1024, 65535)
