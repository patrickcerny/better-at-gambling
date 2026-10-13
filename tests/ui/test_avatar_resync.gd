extends GutTest
## Online, `ClientMatchView.resync` (every time someone sits down) applies the last snapshot and
## then replays the events since. Players who joined after that snapshot are missing for a moment,
## and the match scene used to free and respawn their avatars, taking each avatar's voice playback
## and its buffered audio with it (`tests/net -k voice`: four new playbacks, 16 frames lost).

var scene: MatchScene


func before_each() -> void:
	Net.stop()
	MatchScene.test_dummies = 2
	MatchScene.test_briefing = 0.0
	MatchScene.test_curtain_fast = true
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)


func after_each() -> void:
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = -1.0
	MatchScene.test_curtain_fast = false


func _other() -> int:
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			return pid
	return -1


func test_a_resync_keeps_the_avatars_of_players_who_joined_later() -> void:
	var pid: int = _other()
	assert_gt(pid, 0, "someone else is in the match")
	var a: PlayerAvatar = scene.avatars[pid]
	var marker := Node.new()
	a.add_child(marker)  # stands in for their voice playback
	var players: Dictionary = scene.view.state.players
	var p: Dictionary = players[pid]
	# The snapshot without them, then their replayed `player_joined`.
	players.erase(pid)
	scene.view.state.players_changed.emit()
	players[pid] = p
	scene.view.state.players_changed.emit()
	await wait_process_frames(2)
	assert_eq(scene.avatars.get(pid, null), a, "the same avatar")
	assert_true(is_instance_valid(a) and not a.is_queued_for_deletion(), "not freed")
	assert_true(is_instance_valid(marker) and marker.get_parent() == a, "with what hangs off it")


func test_a_player_who_is_really_gone_loses_the_avatar() -> void:
	var pid: int = _other()
	var a: PlayerAvatar = scene.avatars[pid]
	scene.view.state.players.erase(pid)
	scene.view.state.players_changed.emit()
	await wait_process_frames(2)
	assert_false(scene.avatars.has(pid))
	assert_true(not is_instance_valid(a) or a.is_queued_for_deletion(), "their avatar goes")
