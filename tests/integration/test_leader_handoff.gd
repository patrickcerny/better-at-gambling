extends GutTest
## Patrick's playtest: when the party leader leaves, another connected human leads.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"duration": 5, "seed": 2})


func after_each() -> void:
	fx.server.free()


func test_leader_leaving_in_the_lobby_hands_over() -> void:
	fx.server.open_lobby()
	var host: int = fx.server.lobby.leader()
	assert_eq(host, fx.player_ids[0])
	fx.server.player_disconnected(host)
	assert_eq(fx.server.lobby.leader(), fx.player_ids[1])
	assert_eq(int(fx.of_type(&"leader_changed").back()["player"]), fx.player_ids[1])
	assert_eq(int(fx.server.get_snapshot()["lobby"]["leader"]), fx.player_ids[1])


func test_leader_leaving_mid_match_hands_over_and_new_leader_can_act() -> void:
	fx.server.start_match()
	fx.run(3.1)
	fx.server.player_disconnected(fx.player_ids[0])
	assert_eq(fx.server.lobby.leader(), fx.player_ids[1])
	fx.server.player_disconnected(fx.player_ids[1])
	assert_eq(fx.server.lobby.leader(), fx.player_ids[2])
	fx.server.player_reconnected(fx.player_ids[0])
	assert_eq(fx.server.lobby.leader(), fx.player_ids[2], "leadership sticks with the new leader")
