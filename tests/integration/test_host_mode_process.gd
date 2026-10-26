extends GutTest
## Host mode, the host's side for real (minus Steam): `SteamParty.spawn_room_server` starts this
## game again as a headless `--server --host-mode` process on a loopback port, the host's game
## joins it over ENet as party leader with its Steam uid, and leaving the session kills the
## process again (no orphan servers on the host's PC).


func after_each() -> void:
	Net.stop()
	Net.steam_party.stop_hosting()


func test_the_room_server_process_starts_admits_the_host_and_stops_with_the_session() -> void:
	var party: SteamParty = Net.steam_party
	var port: int = await party.spawn_room_server("steam:76561190000000101")
	assert_gt(port, 0, party.last_error)
	if port == 0:
		return
	assert_true(party.hosting)
	var pid: int = party.server_pid
	assert_true(_alive(pid), "the room server runs")
	assert_eq(party.join_own_party("Patrick", {"color": 2}), OK)
	var welcomed: Array[bool] = [false]
	Net.connected.connect(func() -> void: welcomed[0] = true, CONNECT_ONE_SHOT)
	var waited: float = 0.0
	while not welcomed[0] and waited < 90.0 and Net.mode == Net.Mode.CLIENT:
		await wait_seconds(0.25)
		waited += 0.25
	assert_true(welcomed[0], "the host's game is welcomed by its own room server")
	assert_true(Net.room.get("host_mode", false))
	assert_eq(str(Net.room.get("host", "")), "127.0.0.1")
	var snap: Dictionary = Net.request_snapshot()
	assert_eq(int(snap.get("lobby", {}).get("leader", -1)), Net.local_player_id, "the host leads the party")
	Net.stop()  # leaving the party ends hosting
	assert_false(party.hosting)
	assert_eq(party.server_pid, 0)
	waited = 0.0
	while _alive(pid) and waited < 10.0:
		await wait_seconds(0.25)
		waited += 0.25
	assert_false(_alive(pid), "the room server process is gone")


## Linux (CI): is `pid` a live process? (`OS.is_process_running` would reap it.)
func _alive(pid: int) -> bool:
	var out: Array = []
	OS.execute("ps", ["-o", "stat=", "-p", str(pid)], out)
	var stat: String = str(out[0]).strip_edges() if not out.is_empty() else ""
	return stat != "" and not stat.begins_with("Z")  # a zombie is gone too
