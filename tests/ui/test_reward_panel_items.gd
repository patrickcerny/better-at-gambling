extends GutTest
## Round results in a match without items (Minigames Only, or items off): the rows show the cash
## only, no empty item card next to it.

const ROWS: Array = [
	{"player": 1, "placement": 1, "cash": 300, "item": &""},
	{"player": 2, "placement": 2, "cash": 150, "item": &""},
]


func _panel(settings: Dictionary) -> RewardPanel:
	var st := ClientMatchState.new()
	st.players[1] = {"id": 1, "name": "Patrick", "color": 0}
	st.players[2] = {"id": 2, "name": "Chip", "color": 1}
	st.lobby_settings = settings
	var p := RewardPanel.new()
	add_child_autofree(p)
	p.bind(st, 1)
	p.open(ROWS, 5.0, true)
	return p


func _card_boxes(p: RewardPanel) -> Array:
	var out: Array = []
	for r: Dictionary in p._rows:
		out.append((r["card"] as Label).get_parent().get_parent())
	return out


func test_minigames_only_rows_have_no_item_card() -> void:
	var p: RewardPanel = _panel({"mode": MatchMode.MINIGAMES, "items_enabled": true})
	assert_eq(p._rows.size(), 2)
	for box: Control in _card_boxes(p):
		assert_false(box.visible, "no item field in Minigames Only")
	assert_true((p._rows[0]["cash"] as Label).visible, "the cash stays")


func test_items_off_casino_hides_it_too_and_casino_shows_it() -> void:
	for box: Control in _card_boxes(_panel({"mode": MatchMode.CASINO, "items_enabled": false})):
		assert_false(box.visible)
	for box: Control in _card_boxes(_panel({"mode": MatchMode.CASINO, "items_enabled": true})):
		assert_true(box.visible)
	assert_true(RewardPanel.shows_items({}), "defaults: casino with items")
	assert_false(RewardPanel.shows_items({"mode": "minigames"}))


func test_minigames_only_hides_the_item_bar_in_the_match_scene() -> void:
	Net.stop()
	MatchScene.test_dummies = 1
	var scene: MatchScene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)
	assert_true(scene.hud.items.visible, "casino: the item slots")
	scene.view.state.lobby_settings = {"mode": MatchMode.MINIGAMES}
	scene._apply_mode_hud()
	assert_false(scene.hud.items.visible, "minigames only: no item slots")
	scene.view.state.lobby_settings = {"mode": MatchMode.CASINO}
	scene._apply_mode_hud()
	assert_true(scene.hud.items.visible)
	MatchScene.test_dummies = 0
