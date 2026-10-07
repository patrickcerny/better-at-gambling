extends GutTest
## Lobby panel (Patrick's playtest #17: "Ready sometimes can't be pressed while the Tab panel is
## open"): the slot rows update in place so READY never moves under the cursor, Tab does not move
## focus, Tab closes the panel again, and READY sends the state the button shows.


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
	var rect: Rect2 = panel._ready_button.get_global_rect()
	state.players[4] = {"name": "P4", "color": 4, "ready": true, "connected": true}
	state.players_changed.emit()
	await wait_process_frames(2)
	assert_eq(panel._slots.get_children(), rows_before, "same row nodes after a snapshot")
	assert_eq(panel._slots.get_child_count(), Protocol.MAX_PLAYERS)
	assert_eq(panel._ready_button.get_global_rect(), rect, "READY did not move")
	assert_eq((panel._rows[3]["name"] as Label).text.strip_edges(), "P4")
	assert_true((panel._rows[4]["empty"] as Label).visible, "slot 5 is open")


func test_ready_clicks_land_while_tab_is_held_and_snapshots_arrive() -> void:
	panel.open()
	await wait_process_frames(1)
	assert_true(panel.visible)
	# Hold Tab: the press that opened the panel and the key repeats must neither close it nor move focus.
	panel._opened_frame = Engine.get_process_frames()
	_key(true)
	for i: int in 5:
		_key(true, true)
	await wait_process_frames(1)
	assert_true(panel.visible, "held Tab keeps the panel open")
	for i: int in 3:
		state.players[2]["ready"] = i % 2 == 0
		state.players_changed.emit()  # snapshot refresh between clicks
		await wait_process_frames(1)
		_click(panel._ready_button)
		await wait_process_frames(1)
		var want: bool = i % 2 == 0
		assert_eq(fake.sent.size(), i + 1, "click %d reached READY" % i)
		assert_eq(fake.sent[-1]["type"], &"set_ready")
		assert_eq(bool(fake.sent[-1]["ready"]), want, "explicit ready state %s" % want)
		# The server's answer arrives.
		state.players[1]["ready"] = want
		state.players_changed.emit()
		await wait_process_frames(1)
		assert_eq(panel._ready_button.button_pressed, want)
	_key(false)


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
