extends GutTest
## Scratch-card panel: the card big in the middle with its prize table printed, foil over the
## symbols; dragging the mouse over the foil scratches it off cell by cell, REVEAL ALL scratches
## the rest, and the prize stamp only shows once the whole card is bare.

const SID: StringName = &"scratch_1"
const S := ScratchLogic.Sym
## Three bells on the top row and a "$" (a $25 card pays 4× + $10).
const CARD: Array = [S.BELL, S.BELL, S.BELL, S.LEMON, S.CASH, S.CHERRY, S.SEVEN, S.CHERRY, S.LEMON]

var root: Control
var ui: ScratchUi
var st: ClientMatchState


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = ScratchUi.new()
	root.add_child(ui)
	st = ClientMatchState.new()
	st.stations[SID] = _pub([], -1, 0, 0)
	st.balances[1] = 1000
	ui.open(SID, 1, st)
	await wait_process_frames(3)


func _pub(card: Array, tier: int, stake: int, serial: int, last: Dictionary = {}) -> Dictionary:
	return {"game": &"scratch", "player": 1, "card": card, "tier": tier, "stake": stake, "serial": serial, "last": last}


func _buy(card: Array, tier: int, serial: int) -> void:
	var stake: int = Registry.balance.scratch_prices[tier]
	ui.update_state(_pub(card, tier, stake, serial), {})


## Drags the mouse over a cell in close strokes, through the viewport like a real player.
func _scratch_cell(cell: int) -> void:
	var r: Rect2 = ScratchCardView.cell_rect(cell)
	# GUT's own result window is drawn over the game in the runner: hidden while we scratch.
	var hidden: Array[CanvasLayer] = []
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var l: CanvasLayer = n
		if l.visible:
			l.visible = false
			hidden.append(l)
	var origin: Vector2 = ui.card_view.get_global_rect().position
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = origin + r.position + Vector2(8, 8)
	down.global_position = down.position
	get_viewport().push_input(down, true)
	var y: float = r.position.y + 8.0
	var left: bool = true
	while y < r.end.y:
		for x: float in [r.position.x + 8.0, r.end.x - 8.0] if left else [r.end.x - 8.0, r.position.x + 8.0]:
			var mm := InputEventMouseMotion.new()
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			mm.position = origin + Vector2(x, y)
			mm.global_position = mm.position
			get_viewport().push_input(mm, true)
		left = not left
		y += 18.0
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = origin + r.end - Vector2(8, 8)
	up.global_position = up.position
	get_viewport().push_input(up, true)
	for l: CanvasLayer in hidden:
		l.visible = true
	await wait_process_frames(2)


func test_the_card_is_big_and_the_strip_sells_three_cards() -> void:
	var card: Rect2 = ui.card_view.get_global_rect()
	assert_eq(card.size, ScratchCardView.CARD_SIZE, "the card is big on screen")
	assert_almost_eq(card.get_center().x, root.size.x * 0.5, 1.0, "in the middle")
	assert_false(card.intersects(ui.panel.get_global_rect()), "clear of the buy strip: %s vs %s" % [card, ui.panel.get_global_rect()])
	assert_true(card.position.y >= 0.0)
	assert_eq(ui.buy_buttons.size(), 3)
	for t: int in 3:
		assert_string_contains(ui.buy_buttons[t].text, "$%d" % Registry.balance.scratch_prices[t])
		assert_string_contains(ui.buy_buttons[t].text, ScratchStation.TIER_NAMES[t])
		assert_true(ui.buy_buttons[t].visible)
	assert_false(ui.reveal_btn.visible, "nothing to reveal yet")
	assert_false(ui.card_view.interactive, "a sample card cannot be scratched")
	assert_false(ui.card_view.prize_label.visible)
	assert_true(ui.wants_camera_lock())
	assert_string_contains(ui.info_label.text, "$1,000")
	assert_eq(StationUi.rejection_text(&"card_open"), "Scratch your card first")


func test_scratching_reveals_cell_by_cell_and_the_prize_waits_for_the_last() -> void:
	_buy(CARD, 1, 1)
	await wait_process_frames(1)
	assert_true(ui.card_open())
	assert_true(ui.card_view.interactive)
	assert_true(ui.reveal_btn.visible)
	for t: int in 3:
		assert_false(ui.buy_buttons[t].visible, "one card at a time")
	var want: Array[int] = []
	want.assign(CARD)
	assert_eq(ui.card_view.symbols, want, "the server's card under the foil")
	await _scratch_cell(4)
	assert_true(ui.card_view.revealed[4], "the scratched cell is bare")
	assert_eq(ui.card_view.foil_left(4), 0.0)
	for i: int in [0, 1, 2, 3, 5, 6, 7, 8]:
		assert_false(ui.card_view.revealed[i], "cell %d still under foil" % i)
		assert_almost_eq(ui.card_view.foil_left(i), 1.0, 0.001)
	assert_gt(ui.card_view.flakes.size(), 0, "foil flakes fly")
	assert_false(ui.card_view.prize_label.visible, "no prize before the card is bare")
	for i: int in [0, 1, 2, 3, 5, 6, 7]:
		await _scratch_cell(i)
	assert_false(ui.card_view.prize_label.visible, "one cell left: still no prize")
	assert_false(ui.revealed)
	await _scratch_cell(8)
	assert_true(ui.card_view.is_fully_revealed())
	assert_true(ui.revealed)
	assert_true(ui.reported, "the server is told to pay")
	assert_true(ui.card_view.prize_label.visible)
	assert_eq(ui.card_view.prize_label.text, "WIN $110!", "bells 4× $25 + the $ on a $25 card")
	assert_false(ui.card_view.interactive)


func test_reveal_all_scratches_the_rest_then_shows_the_prize() -> void:
	_buy(CARD, 0, 1)
	await wait_process_frames(1)
	await _scratch_cell(0)
	ui.reveal_btn.pressed.emit()
	await wait_process_frames(2)
	assert_false(ui.card_view.is_fully_revealed(), "one cell after another")
	assert_false(ui.card_view.prize_label.visible)
	await wait_seconds(ScratchCardView.REVEAL_STEP * 9 + 0.3)
	assert_true(ui.card_view.is_fully_revealed())
	assert_true(ui.card_view.prize_label.visible)
	assert_eq(ui.card_view.prize_label.text, "WIN $35!", "$10 card: bells 3× + $5")
	assert_false(ui.reveal_btn.visible)
	assert_true(ui.buy_buttons[0].visible, "buy the next one")


func test_a_blank_says_no_win() -> void:
	_buy([S.CHERRY, S.LEMON, S.BELL, S.BELL, S.SEVEN, S.CHERRY, S.LEMON, S.BELL, S.CHERRY], 2, 1)
	await wait_process_frames(1)
	ui.card_view.reveal_all(true)
	await wait_process_frames(1)
	assert_eq(ui.card_view.prize_label.text, "NO WIN")


func test_server_paid_card_opens_and_refund_resets() -> void:
	_buy(CARD, 1, 3)
	await wait_process_frames(1)
	# Paid without us (left too long): the card scratches itself open.
	ui.update_state(_pub([], -1, 0, 3, {"card": CARD, "tier": 1, "stake": 25, "returned": 110}), {})
	await wait_process_frames(1)
	assert_true(ui.card_view.is_fully_revealed())
	assert_true(ui.card_view.prize_label.visible)
	# A refunded card (minigame) goes back to the sample, no prize.
	_buy(CARD, 2, 4)
	await wait_process_frames(1)
	assert_true(ui.card_open())
	ui.update_state(_pub([], -1, 0, 4), {})
	await wait_process_frames(1)
	assert_false(ui.card_open())
	assert_eq(ui.status_label.text, "Card refunded")
	assert_false(ui.card_view.prize_label.visible)
	assert_true(ui.card_view.symbols.is_empty())


func test_cards_over_the_balance_go_all_in() -> void:
	st.balances[1] = 30
	await wait_process_frames(2)
	assert_false(ui.buy_buttons[0].disabled)
	assert_false(ui.buy_buttons[1].disabled, "the $25 card still sells")
	assert_string_contains(ui.buy_buttons[1].text, "$25")
	assert_false(ui.buy_buttons[2].disabled)
	assert_string_contains(ui.buy_buttons[2].text, "$30 ALL IN", "the $50 card sells for everything")
	st.balances[1] = 9
	await wait_process_frames(2)
	for t: int in 3:
		assert_true(ui.buy_buttons[t].disabled, "under the cheapest card nothing sells")


func test_the_printed_table_matches_the_logic() -> void:
	var cfg: BalanceConfig = Registry.balance
	for t: int in 3:
		var price: int = cfg.scratch_prices[t]
		for row: Dictionary in ScratchCardView.prize_rows(cfg, t, price):
			var sym: int = int(row["symbol"])
			var c: Array[int] = [S.CHERRY, S.LEMON, S.BELL, S.BELL, S.SEVEN, S.CHERRY, S.LEMON, S.BELL, S.CHERRY]
			if sym == S.CASH:
				c[0] = S.CASH
			else:
				c = [sym, sym, sym, -1, -1, -1, -1, -1, -1]
			assert_eq(ScratchUi.prize_of(c, t, price), int(row["amount"]))
		assert_not_null(ScratchCardView.symbol_texture(S.DIAMOND))
		assert_null(ScratchCardView.symbol_texture(S.CASH), "the $ is drawn as a coin")
