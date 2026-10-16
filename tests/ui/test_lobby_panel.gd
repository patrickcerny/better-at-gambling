extends GutTest
## Lobby panel (the settings tablet's 2D mirror): the slot rows update in place so the buttons
## never move under the cursor, Tab does not move focus, Tab closes the panel again, and there is
## no READY button any more (Patrick: "They have to be on the podest").


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
var _hidden_layers: Array[CanvasLayer] = []


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
	for pid: int in [1, 2, 3]:
		state.players[pid] = {"name": "P%d" % pid, "color": pid, "ready": false, "connected": true}
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	panel = LobbyPanel.new()
	layer.add_child(panel)
	panel.bind(state, 1)
	# GUT's own result window is drawn over everything in the runner; hidden while we click.
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var l: CanvasLayer = n
		if l.visible and l != layer:
			l.visible = false
			_hidden_layers.append(l)
	await wait_process_frames(2)


func after_each() -> void:
	Net.mode = _old_mode as Net.Mode
	Net.local_server = _old_server
	Net.local_player_id = _old_pid
	fake.free()
	for l: CanvasLayer in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers.clear()


func _key(pressed: bool, echo: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.keycode = KEY_TAB
	ev.pressed = pressed
	ev.echo = echo
	get_viewport().push_input(ev)


## A real click through the viewport: anything drawn over READY would swallow it.
func _click(c: Control) -> void:
	var pos: Vector2 = c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.relative = Vector2(10, 0)
	get_viewport().push_input(mm, true)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)


func test_tab_has_no_focus_binding() -> void:
	assert_true(InputMap.has_action(&"ui_focus_next"))
	assert_eq(InputMap.action_get_events(&"ui_focus_next").size(), 0, "Tab must not move GUI focus")


func test_rows_update_in_place() -> void:
	panel.open()
	await wait_process_frames(2)
	var rows_before: Array[Node] = panel._slots.get_children()
	var rect: Rect2 = panel._close_button.get_global_rect()
	state.players[4] = {"name": "P4", "color": 4, "ready": true, "connected": true}
	state.players_changed.emit()
	await wait_process_frames(2)
	assert_eq(panel._slots.get_children(), rows_before, "same row nodes after a snapshot")
	assert_eq(panel._slots.get_child_count(), Protocol.MAX_PLAYERS)
	assert_eq(panel._close_button.get_global_rect(), rect, "CLOSE did not move")
	assert_eq((panel._rows[3]["name"] as Label).text.strip_edges(), "P4")
	assert_true((panel._rows[4]["empty"] as Label).visible, "slot 5 is open")


func test_no_ready_control_only_the_pedestal_sets_ready() -> void:
	panel.open()
	await wait_process_frames(2)
	assert_false("_ready_button" in panel, "the READY toggle is gone")
	for n: Node in panel.find_children("*", "BaseButton", true, false):
		var b: BaseButton = n
		if b is Button:
			assert_false((b as Button).text.contains("READY"), "no READY button (%s)" % b.name)
	# Ready states still show, read-only.
	state.players[2]["ready"] = true
	state.players_changed.emit()
	await wait_process_frames(1)
	assert_eq((panel._rows[1]["ready"] as Label).text, "READY")
	assert_eq((panel._rows[0]["ready"] as Label).text, "NOT READY")
	# Clicking around the slots never sends set_ready.
	for r: Dictionary in panel._rows:
		_click(r["frame"] as Control)
	await wait_process_frames(1)
	for intent: Dictionary in fake.sent:
		assert_ne(intent["type"], &"set_ready")
	assert_true(panel._close_button.has_focus(), "focus lands on CLOSE")


func test_tab_closes_the_open_panel() -> void:
	panel.open()
	await wait_process_frames(2)
	var closed: Array = []
	panel.closed.connect(func() -> void: closed.append(true))
	_key(true)
	await wait_process_frames(1)
	_key(false)
	assert_false(panel.visible, "Tab closes the lobby panel")
	assert_eq(closed.size(), 1)


func test_a_steam_hosted_party_offers_invite_instead_of_public() -> void:
	panel._refresh()
	assert_true(panel.public_button.visible, "orchestrator party: PUBLIC toggle")
	assert_false(panel.invite_button.visible)
	var old_room: Dictionary = Net.room
	Net.room = {"steam_lobby": 109775240000000001, "host_mode": true}
	panel._refresh()
	assert_false(panel.public_button.visible, "no server browser for a Steam party")
	assert_true(panel.invite_button.visible, "INVITE FRIENDS opens the Steam overlay")
	assert_string_contains(panel._title.text, "STEAM")
	panel.invite_button.pressed.emit()  # no Steam here: nothing happens, nothing breaks
	Net.room = old_room
