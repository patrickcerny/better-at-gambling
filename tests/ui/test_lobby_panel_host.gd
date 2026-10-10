extends GutTest
## Lobby panel, host controls: a KICK button next to every other player for the party leader only
## (press twice: KICK → SURE?), the PUBLIC toggle for the server browser and the MODE toggle
## (casino / minigames only). Non-leaders see none of them enabled.


class FakeServer:
	extends MatchServer
	var sent: Array[Dictionary] = []

	func submit_intent(_player: int, intent: Dictionary) -> Dictionary:
		sent.append(intent)
		return {"ok": true, "error": &""}


var panel: LobbyPanel
var state: ClientMatchState
var fake: FakeServer
var _old_mode: int
var _old_server: MatchServer
var _old_pid: int


func before_each() -> void:
	_old_mode = Net.mode
	_old_server = Net.local_server
	_old_pid = Net.local_player_id
	fake = FakeServer.new()
	Net.mode = Net.Mode.LOCAL
	Net.local_server = fake
	Net.local_player_id = 1
	state = ClientMatchState.new()
	state.leader = 1
	state.lobby_settings = {"minigames": 5, "gamble_minutes": 3, "items_enabled": true, "mode": &"casino", "public": false}
	for pid: int in [1, 2, 3]:
		state.players[pid] = {"name": "P%d" % pid, "color": pid, "ready": false, "connected": true}
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	panel = LobbyPanel.new()
	layer.add_child(panel)


func after_each() -> void:
	Net.mode = _old_mode as Net.Mode
	Net.local_server = _old_server
	Net.local_player_id = _old_pid
	fake.free()


func _kick_button(slot: int) -> Button:
	return panel._rows[slot]["kick"]


func test_leader_sees_kick_next_to_every_other_player() -> void:
	panel.bind(state, 1)
	panel.open()
	await wait_process_frames(1)
	assert_false(_kick_button(0).visible, "no KICK next to yourself")
	assert_true(_kick_button(1).visible)
	assert_true(_kick_button(2).visible)
	assert_false(_kick_button(3).visible, "no KICK on an open slot")
	var row_rect: Rect2 = (panel._rows[1]["frame"] as Control).get_global_rect()
	assert_true(row_rect.encloses(_kick_button(1).get_global_rect()), "inside the player's row")


func test_kick_needs_a_second_press_and_sends_the_target() -> void:
	panel.bind(state, 1)
	panel.open()
	await wait_process_frames(1)
	_kick_button(2).pressed.emit()
	assert_eq(fake.sent.size(), 0, "the first press only arms it")
	assert_eq(_kick_button(2).text, "SURE?")
	_kick_button(2).pressed.emit()
	assert_eq(fake.sent.size(), 1)
	assert_eq(fake.sent[0]["type"], &"kick_player")
	assert_eq(int(fake.sent[0]["target"]), 3)
	assert_eq(_kick_button(2).text, "KICK")


func test_non_leaders_cannot_kick_or_change_mode_and_public() -> void:
	Net.local_player_id = 2
	panel.bind(state, 2)
	panel.open()
	await wait_process_frames(1)
	for i: int in 3:
		assert_false(_kick_button(i).visible, "no KICK for a non-leader (slot %d)" % i)
	assert_true(panel.public_button.disabled)
	assert_true(panel.mode_button.disabled)
	panel._on_kick_pressed(0)
	panel._on_kick_pressed(0)
	assert_eq(fake.sent.size(), 0)


func test_public_and_mode_toggles_send_lobby_settings() -> void:
	panel.bind(state, 1)
	panel.open()
	await wait_process_frames(1)
	assert_eq(panel.public_button.text, "PRIVATE")
	assert_string_contains(panel.mode_button.text, "CASINO")
	panel.public_button.pressed.emit()
	assert_eq(fake.sent[-1], {"type": &"lobby_setting", "key": "public", "value": true})
	panel.mode_button.pressed.emit()
	assert_eq(fake.sent[-1], {"type": &"lobby_setting", "key": "mode", "value": MatchMode.MINIGAMES})
	# The server's answer arrives.
	state.lobby_settings["public"] = true
	state.lobby_settings["mode"] = &"minigames"
	state.lobby_changed.emit()
	await wait_process_frames(1)
	assert_eq(panel.public_button.text, "PUBLIC")
	assert_true(panel.public_button.button_pressed)
	assert_string_contains(panel.mode_button.text, "MINIGAMES ONLY")
	assert_true((panel._steppers["gamble_minutes"]["plus"] as Button).disabled, "no gambling time in minigames only")
	assert_string_contains(panel._length_note.text, "back to back")
