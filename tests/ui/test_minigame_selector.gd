extends GutTest
## Minigame selector (lobby settings → MINIGAMES): the leader opens it from the lobby panel, sees a
## tile per registered minigame with its picture, toggles send `minigame_pool`, ALL / NONE work,
## the last game can't be turned off, and everyone else sees the same tiles read-only.


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
	for pid: int in [1, 2]:
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


func _open(local: int) -> MinigameSelector:
	panel.bind(state, local)
	panel.open(&"settings")
	panel.minigames_button.pressed.emit()
	return panel.selector


## What the server would answer: the setting lands in the mirror.
func _apply(pool: String) -> void:
	state.lobby_settings["minigame_pool"] = pool
	state.lobby_changed.emit()


func _last_pool() -> String:
	var last: Dictionary = fake.sent.back()
	assert_eq(last["type"], &"lobby_setting")
	assert_eq(last["key"], "minigame_pool")
	return str(last["value"])


func _toggle(sel: MinigameSelector, id: StringName) -> Button:
	return sel.tiles[id]["toggle"]


func test_host_opens_it_from_the_settings_with_every_game_and_its_picture() -> void:
	var sel: MinigameSelector = _open(1)
	assert_true(sel.visible)
	assert_eq(panel.minigames_button.text, "PICK MINIGAMES: ALL %d" % Registry.minigames.size())
	assert_eq(sel.tiles.size(), Registry.minigames.size())
	for id: StringName in Registry.minigames:
		assert_not_null((sel.tiles[id]["picture"] as TextureRect).texture, "%s has a picture" % id)
		assert_true(_toggle(sel, id).button_pressed, "%s on by default" % id)
		assert_false(_toggle(sel, id).disabled)
	assert_eq(MinigameSelector.first_sentence("One. Two. Three."), "One.")


func test_toggles_write_the_pool_and_the_last_game_stays_on() -> void:
	var sel: MinigameSelector = _open(1)
	_toggle(sel, &"quiz").button_pressed = false
	var pool: PackedStringArray = _last_pool().split(",")
	assert_eq(pool.size(), Registry.minigames.size() - 1)
	assert_false(pool.has("quiz"))
	_apply("quiz,spy")
	assert_eq(panel.minigames_button.text, "PICK MINIGAMES: 2 OF %d" % Registry.minigames.size())
	_toggle(sel, &"lonely_number").button_pressed = true
	assert_eq(_last_pool(), "quiz,lonely_number,spy", "registry order")
	_apply("quiz")
	assert_true(_toggle(sel, &"quiz").disabled, "the last game can't be turned off")
	var before: int = fake.sent.size()
	sel._on_toggled(false, "quiz")
	assert_eq(fake.sent.size(), before, "nothing sent for the last game")
	assert_true(_toggle(sel, &"quiz").button_pressed)
	assert_true(sel.none_button.disabled)


func test_all_and_none() -> void:
	var sel: MinigameSelector = _open(1)
	assert_true(sel.all_button.disabled, "already all on")
	sel.none_button.pressed.emit()
	assert_eq(_last_pool(), String(Registry.minigames.keys()[0]), "NONE keeps one game on")
	_apply("vote_race,spy")
	sel.none_button.pressed.emit()
	assert_eq(_last_pool(), "vote_race", "the first game that is on (registry order) stays")
	assert_false(sel.all_button.disabled)
	sel.all_button.pressed.emit()
	assert_eq(_last_pool(), "", "ALL = every game")


func test_read_only_for_everyone_but_the_leader() -> void:
	state.lobby_settings["minigame_pool"] = "quiz,spy"
	var sel: MinigameSelector = _open(2)
	assert_true(sel.visible, "non-hosts can look")
	assert_eq(panel.minigames_button.text, "MINIGAMES: 2 OF %d" % Registry.minigames.size())
	assert_true(sel.all_button.disabled)
	assert_true(sel.none_button.disabled)
	for id: StringName in sel.tiles:
		assert_true(_toggle(sel, id).disabled)
		assert_eq(_toggle(sel, id).button_pressed, id in [&"quiz", &"spy"])
	sel._on_toggled(true, "lonely_number")
	sel._send(PackedStringArray())
	assert_eq(fake.sent.size(), 0, "nothing sent")


func test_closing_the_lobby_panel_closes_the_selector() -> void:
	var sel: MinigameSelector = _open(1)
	sel.back_button.pressed.emit()
	assert_false(sel.visible)
	assert_true(panel.visible, "BACK returns to the lobby panel")
	panel.minigames_button.pressed.emit()
	panel.close()
	assert_false(sel.visible)
