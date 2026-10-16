extends GutTest
## The Tab list (`PlayerList`, Patrick: "make the tablist you press cooler... the skin, the color
## and stuff"): one row per player in the right order, the crown on the money leader, the local row
## highlighted, read-only ready states in the lobby (no READY control: "They have to be on the
## podest"), the talking speaker, and the skin portraits built only while the list is open.


class FakeServer:
	extends MatchServer
	var sent: Array[Dictionary] = []

	func submit_intent(_player: int, intent: Dictionary) -> Dictionary:
		sent.append(intent)
		return {"ok": true, "error": &""}


class FakeVoice:
	extends VoiceChannel
	var talking: Dictionary[int, bool] = {}

	func is_talking(pid: int) -> bool:
		return talking.get(pid, false)


var list: PlayerList
var state: ClientMatchState
var fake: FakeServer
var _old_mode: int
var _old_server: MatchServer
var _old_voice: VoiceChannel


func before_each() -> void:
	_old_mode = Net.mode
	_old_server = Net.local_server
	_old_voice = VoiceChannel.current
	fake = FakeServer.new()
	Net.mode = Net.Mode.LOCAL
	Net.local_server = fake
	state = ClientMatchState.new()
	state.room_mode = true
	state.leader = 1
	state.phase = Phase.Id.CASINO
	var skins: Array[String] = ["king", "wizard", "bean"]
	for pid: int in [1, 2, 3]:
		state.players[pid] = {"id": pid, "name": "P%d" % pid, "color": pid, "ready": pid == 2, "skin": skins[pid - 1], "connected": true}
	state.balances = {1: 400, 2: 1200, 3: 800}
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	list = PlayerList.new()
	layer.add_child(list)
	list.bind(state, 3)


func after_each() -> void:
	Net.mode = _old_mode as Net.Mode
	Net.local_server = _old_server
	if VoiceChannel.current is FakeVoice:
		VoiceChannel.current.free()
	VoiceChannel.current = _old_voice
	fake.free()


func _portrait_count() -> int:
	return list.find_children("*", "SkinPreviewView", true, false).size()


func _names() -> Array[String]:
	var out: Array[String] = []
	for c: Node in list.rows_box.get_children():
		out.append(str(c.find_child("Name", true, false).get("text")))
	return out


func test_match_rows_sorted_by_money_with_standings_and_crown() -> void:
	list.show_list(true)
	assert_eq(_names(), ["P2", "P3", "P1"] as Array[String], "richest first")
	assert_eq((list.rows[2]["rank"] as Label).text, "1ST")
	assert_eq((list.rows[3]["rank"] as Label).text, "2ND")
	assert_eq((list.rows[1]["rank"] as Label).text, "3RD")
	assert_eq((list.rows[2]["money"] as Label).text, "$1,200")
	assert_true((list.rows[2]["crown"] as Control).visible, "the leader wears the crown")
	assert_false((list.rows[3]["crown"] as Control).visible)
	assert_false((list.rows[1]["crown"] as Control).visible)
	assert_false((list.rows[2]["ready_box"] as Control).visible, "no ready states in the match")
	# Money moves: the order and the crown follow.
	state.balances[1] = 5000
	state.money_changed.emit(1, 4600, 5000, &"test")
	assert_eq(_names(), ["P1", "P2", "P3"] as Array[String])
	assert_true((list.rows[1]["crown"] as Control).visible)
	assert_false((list.rows[2]["crown"] as Control).visible)
	# A tie at the top: nobody gets the crown (same rule as the 3D crown).
	state.balances[2] = 5000
	state.money_changed.emit(2, 3800, 5000, &"test")
	assert_false((list.rows[1]["crown"] as Control).visible)
	assert_false((list.rows[2]["crown"] as Control).visible)


func test_rows_show_skin_colour_and_host() -> void:
	list.show_list(true)
	assert_eq((list.rows[1]["bar"] as ColorRect).color, Palette.player_color(1), "colour bar")
	assert_string_contains((list.rows[1]["info"] as Label).text, "King")
	assert_string_contains((list.rows[1]["info"] as Label).text, Palette.PLAYER_COLOR_NAMES[1])
	assert_string_contains((list.rows[2]["info"] as Label).text, "Wizard")
	assert_eq((list.rows[1]["portrait"] as SkinPreviewView).skin, &"king")
	assert_eq((list.rows[1]["portrait"] as SkinPreviewView).color, Palette.player_color(1))
	assert_true((list.rows[1]["host"] as Control).visible, "host badge on the leader")
	assert_false((list.rows[2]["host"] as Control).visible)
	# A skin change re-dresses the same portrait.
	var portrait: SkinPreviewView = list.rows[2]["portrait"]
	state.players[2]["skin"] = &"swat"
	state.players_changed.emit()
	assert_same(list.rows[2]["portrait"], portrait, "portrait reused")
	assert_eq(portrait.skin, &"swat")


func test_local_row_is_highlighted() -> void:
	list.show_list(true)
	var mine: StyleBoxFlat = (list.rows[3]["frame"] as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	var other: StyleBoxFlat = (list.rows[1]["frame"] as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_eq(mine.border_color, Palette.VIP_GOLD, "gold border on our row")
	assert_ne(other.border_color, Palette.VIP_GOLD)
	assert_eq((list.rows[3]["name"] as Label).get_theme_color(&"font_color"), Palette.VIP_GOLD)
	assert_string_contains((list.rows[3]["info"] as Label).text, "you")


func test_lobby_rows_keep_join_order_and_show_ready_read_only() -> void:
	state.phase = Phase.Id.LOBBY
	list.show_list(true)
	assert_eq(_names(), ["P1", "P2", "P3"] as Array[String], "join order in the lobby")
	assert_eq((list.rows[2]["ready"] as Label).text, "READY")
	assert_eq((list.rows[1]["ready"] as Label).text, "WAITING")
	assert_true((list.rows[1]["ready_box"] as Control).visible)
	assert_false((list.rows[1]["money"] as Control).visible, "no money in the lobby")
	assert_false((list.rows[2]["crown"] as Control).visible, "no money crown in the lobby")
	assert_string_contains(list.subtitle_label.text, "1 / 3 READY")
	# Readiness comes from the server (the pedestal), the list only mirrors it.
	state.players[1]["ready"] = true
	state.lobby_changed.emit()
	assert_eq((list.rows[1]["ready"] as Label).text, "READY")
	assert_string_contains(list.subtitle_label.text, "2 / 3 READY")


func test_no_ready_control_and_no_mouse() -> void:
	for phase: Phase.Id in [Phase.Id.LOBBY, Phase.Id.CASINO]:
		state.phase = phase
		list.show_list(true)
		assert_eq(list.find_children("*", "BaseButton", true, false).size(), 0, "nothing to press in the list")
		assert_eq(list.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the list never takes the mouse")
		list.show_list(false)
	assert_eq(fake.sent.size(), 0, "the list sends no intents")


func test_talking_speaker() -> void:
	var voice := FakeVoice.new()
	VoiceChannel.current = voice
	list.show_list(true)
	assert_false((list.rows[2]["talk"] as Control).visible)
	voice.talking[2] = true
	await wait_process_frames(2)
	assert_true((list.rows[2]["talk"] as Control).visible, "speaker while P2 talks")
	assert_false((list.rows[1]["talk"] as Control).visible)
	voice.talking[2] = false
	await wait_process_frames(2)
	assert_false((list.rows[2]["talk"] as Control).visible)


func test_portraits_live_only_while_open() -> void:
	assert_eq(_portrait_count(), 0, "nothing built while closed")
	list.show_list(true)
	assert_eq(_portrait_count(), 3, "one portrait per player")
	var before: Array[SkinPreviewView] = list.portraits()
	list.show_list(false)
	assert_eq(_portrait_count(), 0, "freed on close")
	for p: SkinPreviewView in before:
		assert_false(is_instance_valid(p), "portrait freed")
	for i: int in 5:
		list.show_list(true)
		list.show_list(false)
	assert_eq(_portrait_count(), 0, "no leak over open/close cycles")
	# Updates while closed build nothing.
	state.players_changed.emit()
	state.money_changed.emit(1, 1, 401, &"test")
	assert_eq(_portrait_count(), 0)
	assert_eq(list.rows_box.get_child_count(), 0)
	# A player leaving while open loses their row and portrait.
	list.show_list(true)
	state.players.erase(1)
	state.balances.erase(1)
	state.players_changed.emit()
	assert_eq(_portrait_count(), 2)
	assert_eq(list.rows_box.get_child_count(), 2)


func test_releasing_tab_closes_even_when_the_router_does_not_forward_it() -> void:
	list.show_list(true)
	Input.action_press(&"leaderboard")
	await wait_process_frames(2)
	assert_true(list.visible, "open while Tab is held")
	Input.action_release(&"leaderboard")
	await wait_process_frames(2)
	assert_false(list.visible, "closed on release")
	assert_eq(_portrait_count(), 0)


func test_hud_uses_the_player_list() -> void:
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.bind(state, 3)
	assert_true(hud.leaderboard is PlayerList)
	hud.show_leaderboard(true)
	assert_true(hud.leaderboard.visible)
	assert_eq(hud.leaderboard.rows.size(), 3)
	hud.show_leaderboard(false)
	assert_false(hud.leaderboard.visible)
	assert_eq(hud.leaderboard.rows.size(), 0)
