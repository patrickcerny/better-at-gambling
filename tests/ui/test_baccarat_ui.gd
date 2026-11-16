extends GutTest
## Baccarat overlay: a column in the right third (the seat camera frames the felt on the left).
## While bets are open: the five bets with their pays, chips put down by clicking or by key, your
## amount on each and the others' dots. While dealing: the bets lock and the two hands fill in.
## At the result: the winner and what you won or lost, and the last rounds along the bottom.

const SID: StringName = &"baccarat_1"

var root: Control
var ui: BaccaratUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = BaccaratUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.players[1] = {"name": "Ada", "color": 0}
	st.players[2] = {"name": "Bert", "color": 1}
	st.stations[SID] = _pub(BaccaratLogic.State.BETTING)
	st.balances[1] = 1000
	ui.open(SID, 1, st)
	await wait_process_frames(3)


func _pub(state: int, extra: Dictionary = {}) -> Dictionary:
	var pub: Dictionary = {"game": &"baccarat", "state": state, "timer": 7.2, "players": [1, 2], "bets": [], "player_cards": [], "banker_cards": [], "winner": &"", "history": []}
	pub.merge(extra, true)
	return pub


func _assert_right_column(what: String) -> void:
	var r: Rect2 = ui.panel.get_global_rect()
	assert_gt(r.position.x, 1920 * 0.6, "%s: the panel starts in the right third: %s" % [what, r])
	assert_lte(r.end.x, 1920.0, "%s: on screen" % what)
	assert_lte(r.end.y, 1080.0, "%s: on screen" % what)
	for n: Node in ui.panel.find_children("*", "Control", true, false):
		var c: Control = n
		if not c.is_visible_in_tree() or c.get_parent() is Button:
			continue
		var cr: Rect2 = c.get_global_rect()
		assert_true(r.grow(0.5).encloses(cr), "%s: %s stays inside the panel (%s)" % [what, c.name, cr])


func test_betting_shows_every_bet_with_its_pay() -> void:
	assert_string_contains(ui.status_label.text, "PLACE YOUR BETS")
	assert_eq(ui.buttons.size(), 5)
	assert_string_contains(ui.buttons[BaccaratLogic.BANKER].text, "less 5%")
	assert_string_contains(ui.buttons[BaccaratLogic.TIE].text, "9:1")
	assert_string_contains(ui.buttons[BaccaratLogic.PLAYER_PAIR].text, "11:1")
	for t: StringName in ui.buttons:
		assert_false(ui.buttons[t].disabled)
	assert_true(ui.bet_panel.visible)
	assert_true(ui.wants_camera_lock())
	_assert_right_column("betting")


func test_chips_on_the_spots() -> void:
	ui.update_state(_pub(BaccaratLogic.State.BETTING, {"bets": [
		{"player": 1, "type": &"banker", "amount": 25}, {"player": 1, "type": &"banker", "amount": 25},
		{"player": 2, "type": &"tie", "amount": 10},
	]}), {})
	assert_true(ui._badges[BaccaratLogic.BANKER].visible)
	assert_eq(ui._badges[BaccaratLogic.BANKER].text, "$50")
	assert_false(ui._badges[BaccaratLogic.PLAYER].visible)
	assert_true(ui._dots[BaccaratLogic.TIE].visible, "Bert's chips on the tie")
	assert_string_contains(ui.my_bets.text, "BANKER $50")


func test_dealing_locks_the_bets_and_fills_the_hands() -> void:
	ui.update_state(_pub(BaccaratLogic.State.DEALING, {"player_cards": [Card.make(9), Card.make(13, 1)], "banker_cards": [Card.make(3, 2)], "player_total": 9, "banker_total": 3}), {})
	for t: StringName in ui.buttons:
		assert_true(ui.buttons[t].disabled)
	assert_false(ui.bet_panel.visible)
	assert_eq(ui.player_total.text, "9")
	assert_eq(ui.banker_total.text, "3")
	assert_string_contains(ui.player_cards.text, "9♠")
	assert_false(ui.wants_camera_lock())
	_assert_right_column("dealing")


func test_result_and_the_road() -> void:
	ui.update_state(_pub(BaccaratLogic.State.RESULT, {
		"player_cards": [Card.make(9), Card.make(13, 1)], "banker_cards": [Card.make(3, 2), Card.make(2)], "player_total": 9, "banker_total": 5,
		"winner": &"player", "results": {1: 20}, "history": [&"banker", &"tie", &"player"],
	}), {})
	assert_string_contains(ui.result_label.text, "PLAYER WINS  9 to 5")
	assert_string_contains(ui.result_label.text, "YOU WIN  +$20")
	assert_string_contains(ui.road_label.text, "B")
	assert_string_contains(ui.status_label.text, "Next round")
	_assert_right_column("result")


func test_rules_fold_away() -> void:
	assert_not_null(ui.rules_toggle)
	assert_false(ui.rules_label.visible)
	assert_string_contains(ui.rules_label.text, "closer to 9")
