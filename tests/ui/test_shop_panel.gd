extends GutTest
## Old fix batch: "shop window closing before the purchase is confirmed". Online `Net.send_intent`
## only says the request went out; the Gift Shop window must stay open until the server confirms
## the buy (`shop_bought`) or refuses it (`intent_rejected`, the reason shown in the window).

var panel: ShopPanel
var state: ClientMatchState
var closed_count: int = 0


func before_each() -> void:
	closed_count = 0
	Net.stop()
	Net.mode = Net.Mode.CLIENT  # online, without a transport: requests go nowhere
	Net._welcomed = true
	state = ClientMatchState.new()
	state.players[1] = {"id": 1, "name": "Ann"}
	state.balances[1] = 1000
	state.shop_offers = [{"item": &"lucky_clover", "price": 150, "rarity": 0}, {"item": &"beer", "price": 80, "rarity": 0}]
	panel = ShopPanel.new()
	add_child_autofree(panel)
	panel.bind(state, 1)
	panel.closed.connect(func() -> void: closed_count += 1)
	panel.open()


func after_each() -> void:
	Net._welcomed = false
	Net.stop()


func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c: Node in panel._rows.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out


func test_the_window_waits_for_the_server_to_confirm() -> void:
	panel.buy(0)
	assert_true(panel.visible, "still open: the server has not answered yet")
	assert_eq(closed_count, 0)
	assert_eq(panel._note.text, "Buying…")
	for b: Button in _buttons():
		assert_true(b.disabled, "no second buy while the first is on its way")
	Net.event_received.emit(GameEvents.make(&"shop_bought", {"player": 2, "item": &"beer", "price": 80}))
	assert_true(panel.visible, "someone else's purchase does not close it")
	Net.event_received.emit(GameEvents.make(&"shop_bought", {"player": 1, "item": &"lucky_clover", "price": 150}))
	assert_false(panel.visible, "closed once the purchase is confirmed")
	assert_eq(closed_count, 1)


func test_a_refused_buy_stays_open_and_says_why() -> void:
	panel.buy(1)
	Net.event_received.emit(GameEvents.make(&"intent_rejected", {"player": 1, "intent": &"use_item", "error": &"cooldown"}))
	assert_eq(panel._note.text, "Buying…", "another intent's refusal is not the answer")
	Net.event_received.emit(GameEvents.make(&"intent_rejected", {"player": 1, "intent": &"shop_buy", "error": &"too_far"}))
	assert_true(panel.visible, "a refused buy keeps the window open")
	assert_eq(panel._note.text, ItemController.rejection_text(&"too_far"))
	await wait_process_frames(1)
	var enabled: int = 0
	for b: Button in _buttons():
		if not b.disabled:
			enabled += 1
	assert_eq(enabled, 2, "the offers can be bought again")
