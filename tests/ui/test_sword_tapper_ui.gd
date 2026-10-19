extends GutTest
## Sword Tapper overlay: a compact column at the right of the screen (the pedestal fills the rest;
## 0.9.14, Patrick: "this ui field of sword tapper is very weird. make it better, probably also a
## bit smaller (make the ui the same as the game / the 3d model)") with the pedestal top drawn as
## it is (the gems round the ring, sized like the lamps, the ruby at the top, the prize for the
## picked stake beside each, the multiplier rule on the stone, the pedestal's lit gems lit), then
## the stake chips and PULL, the result of your last pull once its reveal is over and the last
## pulls. PULL greys out while the sword moves and under the minimum; a chip worth more than you
## have pulls with everything (all-in).

const SID: StringName = &"sword_1"

var root: Control
var ui: SwordTapperUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = SwordTapperUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.stations[SID] = _pub(false, {}, [])
	st.balances[1] = 1000
	ui.open(SID, 1, st)
	await wait_process_frames(3)


func _pub(pulling: bool, last: Dictionary, history: Array, serial: int = 0) -> Dictionary:
	return {"game": &"sword_tapper", "player": 1, "pulling": pulling, "pull": {}, "stake": 25 if pulling else 0, "serial": serial,
		"reveal_left": 2.0 if pulling else 0.0, "last": last, "history": history}


func _free_last(serial: int) -> Dictionary:
	return {"pull": {"free": true, "gems": [0, 3, 8, 9, 12, 14, 16], "mult": 3}, "stake": 25, "returned": 445, "serial": serial}


## Nothing of the overlay reaches into the left two thirds, where the seat camera frames the pedestal.
func _assert_right_column(what: String) -> void:
	var r: Rect2 = ui.panel.get_global_rect()
	assert_gt(r.position.x, 1920 * 0.6, "%s: the panel starts in the right third: %s" % [what, r])
	assert_lte(r.end.x, 1920.0, "%s: on screen" % what)
	assert_gte(r.position.y, 150.0, "%s: under the HUD's clock" % what)
	assert_lte(r.end.y, 1080.0 - 90.0, "%s: over the HUD's rank" % what)
	for n: Node in ui.panel.find_children("*", "Control", true, false):
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		var cr: Rect2 = c.get_global_rect()
		assert_true(r.grow(0.5).encloses(cr), "%s: %s stays inside the panel (%s)" % [what, c.name, cr])
		assert_gt(cr.position.x, 1920 * 2.0 / 3.0 - 1.0, "%s: %s keeps off the left two thirds" % [what, c.name])


func test_chips_pull_and_the_ring() -> void:
	assert_true(ui._dock_column())
	_assert_right_column("idle")
	assert_eq(ui.bet_panel.chips, [10, 25, 50, 100] as Array[int], "chips from the minimum to the maximum")
	assert_eq(ui.bet_panel.min_bet, Registry.balance.sword_min_bet)
	assert_eq(ui.bet_panel.max_bet, Registry.balance.sword_max_bet)
	assert_eq(ui.stake(), 25, "a $25 pull to start")
	assert_false(ui.pull_btn.disabled)
	assert_string_contains(ui.pull_btn.text, "PULL  $25")
	assert_true(ui.wants_camera_lock(), "the head stays on the pedestal while picking a stake")
	assert_string_contains(ui.status_label.text, "PULL")
	var n: int = Registry.balance.sword_ring.size()
	assert_eq(ui.ring.prizes.size(), n, "a prize beside every gem of the ring")
	assert_true(SwordTapperStation.is_ruby(0), "the ruby is gem 0")
	assert_eq(ui.ring.prizes[0], "$125", "the ruby pays 5× on $25")
	assert_eq(ui.ring.prizes.count("$2.50"), 6, "six gems of 0.1×")
	assert_eq(ui.ring_title.text, "PRIZES AT $25", "short")
	assert_string_contains(ui.ring.centre_text, "≤9 GEMS", "the multiplier rule on the stone")
	assert_string_contains(ui.ring.centre_text, "×10")
	assert_eq(ui.result_label.text, "", "no result before the first pull")
	ui.bet_panel.select_chip(3)
	assert_eq(ui.stake(), 100)
	assert_eq(ui.ring.prizes[0], "$500", "the ring follows the stake")
	assert_eq(ui.ring.prizes.count("$10"), 6)
	assert_string_contains(ui.pull_btn.text, "$100")


func test_pull_sends_the_stake_and_every_key_pulls() -> void:
	Net.stop()  # no server: the tap goes out and comes back refused
	watch_signals(ui)
	assert_false(ui.pull(), "PULL")
	assert_signal_emit_count(ui, "rejected", 1)
	ui.bet_panel.confirmed.emit(25)  # Space / Enter / gamepad A
	assert_signal_emit_count(ui, "rejected", 2)
	var e := InputEventAction.new()
	e.action = &"interact"
	e.pressed = true
	ui._unhandled_input(e)
	assert_signal_emit_count(ui, "rejected", 3, "E pulls again")
	assert_eq(StationUi.rejection_text(&"pulling"), "The sword is still moving")


func test_greyed_while_pulling_and_under_the_minimum() -> void:
	ui.update_state(_pub(true, {}, [], 1), {})
	assert_true(ui.pull_btn.disabled, "no second pull while the sword moves")
	assert_string_contains(ui.status_label.text, "MOVING")
	assert_false(ui.wants_camera_lock(), "watch the sword with the head free")
	assert_false(ui.pull(), "a greyed PULL sends nothing")
	ui.update_state(_pub(false, {}, []), {})
	assert_false(ui.pull_btn.disabled)
	st.balances[1] = 5
	ui.update_state(_pub(false, {}, []), {})
	assert_true(ui.pull_btn.disabled, "under the minimum")
	assert_string_contains(ui.status_label.text, "Not enough")


func test_a_chip_over_the_balance_goes_all_in() -> void:
	st.balances[1] = 60
	ui.update_state(_pub(false, {}, []), {})
	ui.bet_panel.select_chip(3)
	assert_eq(ui.stake(), 60, "pulls with everything you have")
	assert_string_contains(ui.pull_btn.text, "PULL  $60")
	assert_eq(ui.pull_btn.tooltip_text, StationUi.all_in_text(60))
	assert_eq(ui.ring.prizes[0], "$300", "the ring prints the prizes for what goes in")
	Net.stop()
	watch_signals(ui)
	ui.pull()
	assert_true(ui.bet_panel.all_in)
	assert_signal_emitted_with_parameters(ui, "notice", [StationUi.all_in_text(60)])
	ui.bet_panel.select_chip(1)
	assert_eq(ui.stake(), 25, "a chip you can pay is the chip")
	assert_eq(ui.pull_btn.tooltip_text, "")


func test_the_result_shows_after_the_reveal() -> void:
	ui.update_state(_pub(true, {}, [], 1), {})
	assert_eq(ui.result_label.text, "", "never spoils the reveal")
	var history: Array = [{"free": true, "gems": 7, "mult": 3, "stake": 25, "returned": 445}, {"free": false, "gems": 0, "mult": 1, "stake": 25, "returned": 0}]
	ui.update_state(_pub(false, _free_last(1), history, 1), {})
	assert_eq(ui.result_label.text, "FREE!  7 GEMS  ×3  +$420")
	assert_eq(ui.history_label.text, "LAST PULLS  $445 ×3  —")
	assert_eq(ui.ring.lit, [0, 3, 8, 9, 12, 14, 16] as Array[int], "the pull's gems lit on the ring")
	assert_true(ui.result_label.visible)
	ui.update_state(_pub(true, _free_last(1), history, 2), {})
	assert_eq(ui.result_label.text, "", "the next pull hides it again")
	assert_false(ui.result_label.visible, "no empty line")
	assert_eq(ui.ring.lit, [] as Array[int], "the ring goes dark for the next pull")
	ui.update_state(_pub(false, {"pull": SwordTapperLogic.stuck(), "stake": 25, "returned": 0, "serial": 2}, history, 2), {})
	assert_eq(ui.result_label.text, "STUCK!  −$25")
	await wait_process_frames(2)
	_assert_right_column("with a result and the last pulls")


func test_an_old_result_is_not_news() -> void:
	ui.close()
	st.stations[SID] = _pub(false, _free_last(4), [])
	ui.open(SID, 1, st)
	await wait_process_frames(2)
	assert_eq(ui.result_label.text, "", "a pull from before you stepped up is not shown as yours")


func test_texts() -> void:
	assert_eq(SwordTapperUi.result_text({"pull": {"free": true, "gems": [1, 2, 3], "mult": 1}, "stake": 100, "returned": 40}), "FREE!  3 GEMS  −$60")
	assert_eq(SwordTapperUi.result_text({"pull": {"free": true, "gems": [1, 2, 3, 4], "mult": 1}, "stake": 10, "returned": 10}), "FREE!  4 GEMS  stake back")
	assert_eq(SwordTapperUi.history_text([]), "")
	assert_eq(SwordTapperUi.stone_text(Registry.balance), "≤9 GEMS\n×2 ×3 ×5 ×10")
	assert_eq(SwordTapperUi.lit_gems({"pull": SwordTapperLogic.stuck()}), [] as Array[int])
	assert_eq(SwordTapperStation.cents_text(1000), "$10")
	assert_eq(SwordTapperStation.cents_text(250), "$2.50")


## The panel is smaller than the old full-height column and draws the ring like the pedestal:
## every dot where its lamp is, the ruby the biggest and red, the others warm white, gold when lit;
## the dots never cover each other or the prizes.
func test_the_ring_looks_like_the_pedestal() -> void:
	await wait_process_frames(2)
	var r: Rect2 = ui.panel.get_global_rect()
	assert_lte(r.size.x, SwordTapperUi.PANEL_WIDTH + 1.0, "narrower than the old 600 px column")
	assert_lt(r.size.y, 1080.0 - StationUi.COLUMN_MARGIN.y - StationUi.COLUMN_BOTTOM, "only as tall as it needs")
	var ring: SwordRingView = ui.ring
	var n: int = Registry.balance.sword_ring.size()
	var c: Vector2 = ring.size * 0.5
	var top: Vector2 = ring.gem_point(0)
	assert_almost_eq(top.x, c.x, 0.5, "the ruby at the top, as on the pedestal")
	assert_lt(top.y, c.y)
	assert_gt(ring.gem_point(n / 4).x, c.x, "then clockwise")
	for i: int in n:
		if i > 0:
			assert_lte(ring.gem_px(i), ring.gem_px(0), "the ruby is the biggest (gem %d)" % i)
			assert_eq(ring.gem_color(i), SwordTapperStation.GEM_IDLE.darkened(0.25), "warm white while dark")
		var j: int = (i + 1) % n
		assert_gt(ring.gem_point(i).distance_to(ring.gem_point(j)), ring.gem_px(i) + ring.gem_px(j), "dots %d and %d apart" % [i, j])
	assert_eq(ring.gem_color(0), SwordTapperStation.RUBY, "the ruby is red")
	assert_gt(ring.gem_px(0), ring.gem_px(n - 1), "bigger than the small prizes")
	ring.set_lit([2] as Array[int])
	assert_eq(ring.gem_color(2), SwordTapperStation.GEM_LIT, "lit gold")
	_assert_right_column("compact")


## A pull on the pedestal lights the same gems in the panel, as they light.
func test_lit_gems_follow_the_pedestal() -> void:
	Vfx.force_enabled = true  # a client's pedestal, lamps and all
	var node := SwordTapperStation.new()
	node.station_id = SID
	add_child_autofree(node)
	Vfx.force_enabled = false
	await wait_process_frames(1)
	node.play_pull({"free": true, "gems": [0, 5, 9], "mult": 1, "serial": 7, "stake": 25}, true, SwordTapperStation.gem_time(1, 3) + 0.01)
	await wait_process_frames(1)
	assert_eq(ui.ring.lit, node.lit, "the panel shows what the pedestal shows")
	assert_eq(ui.ring.lit, [0, 5] as Array[int], "two of three lit so far")
