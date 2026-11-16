extends GutTest
## The dev joins (Patrick 2026-11-16: "join ANY lobby not requiring it to be full, having -1 dollar
## and being able to play anything i want (moneywise) minigames i do not participate ... dev menu
## ingame to troll the players"): `MatchServer.gods`, `dev_troll`, the client's view of the dev.

var server: MatchServer
var events: Array[Dictionary] = []


func before_each() -> void:
	events.clear()
	server = MatchServer.new()
	server.configure({"minigames": 2, "gamble_seconds": 30.0, "seed": 5, "minigame_pool": "quiz", "minigame_briefing": 0.0}, Registry.balance, Registry.presets, Registry.game_logic_scripts(), Registry.maps[&"lucky_lounge"])
	server.event_emitted.connect(func(ev: Dictionary) -> void: events.append(ev))
	server.open_lobby()


func after_each() -> void:
	server.free()


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _troll(by: int, payload: Dictionary) -> Dictionary:
	return server.submit_intent(by, Intents.make(&"dev_troll", payload))


func test_only_patricks_steam_id_may_be_the_dev() -> void:
	assert_true(MatchServer.may_be_god("steam:%d" % DevMode.THE_DEV))
	assert_false(MatchServer.may_be_god("steam:76561190000000002"))
	assert_false(MatchServer.may_be_god("dev:Patrick"))


func test_the_dev_takes_no_slot_no_lead_and_no_rank() -> void:
	var host: int = server.add_player("dev:host", "Host")
	var dev: int = server.add_player("steam:%d" % DevMode.THE_DEV, "Patrick", -1, [], true)
	assert_true(server.is_god(dev))
	assert_true(server.state.players[dev].dev)
	assert_eq(server.occupied_slots(), 1, "the dev takes no seat")
	assert_false(server.lobby.has(dev), "never in the ready check")
	assert_eq(server.lobby.leader(), host)
	assert_eq(server.economy.balance(dev), MatchServer.GOD_MONEY)
	assert_eq(_of(&"dev_joined").size(), 1)
	for row: Dictionary in server.get_standings():
		assert_ne(int(row["player"]), dev, "not in the standings")
	assert_false(server._balances().has(dev), "not on the money graph")
	var res: Dictionary = server.submit_intent(host, Intents.make(&"kick_player", {"target": dev}))
	assert_true(server.state.players.has(dev), "nobody kicks the dev: %s" % str(res))


func test_endless_money_tops_itself_up() -> void:
	var dev: int = server.add_player("steam:%d" % DevMode.THE_DEV, "Patrick", -1, [], true)
	server.economy.take_up_to(dev, MatchServer.GOD_MONEY - 10, &"stake")
	server.advance(0.01)
	assert_eq(server.economy.balance(dev), MatchServer.GOD_MONEY)


func test_troll_tools_are_the_devs_alone() -> void:
	var bob: int = server.add_player("dev:bob", "Bob")
	var cat: int = server.add_player("dev:cat", "Cat")
	var dev: int = server.add_player("steam:%d" % DevMode.THE_DEV, "Patrick", -1, [], true)
	server.start_match()
	assert_false(_troll(bob, {"action": "knock", "target": cat})["ok"], "not the dev: refused")
	assert_eq(_troll(bob, {"action": "knock", "target": cat})["error"], &"not_dev")
	events.clear()
	assert_true(_troll(dev, {"action": "knock", "target": bob})["ok"])
	server.advance(0.05)
	var down: Array[Dictionary] = _of(&"player_knocked_down")
	assert_eq(down.size(), 1)
	assert_eq(int(down[0]["target"]), bob)
	assert_false(_troll(dev, {"action": "knock", "target": dev})["ok"], "never himself")
	var before: int = server.economy.balance(cat)
	assert_true(_troll(dev, {"action": "give_money", "target": cat, "amount": 500})["ok"])
	assert_eq(server.economy.balance(cat), before + 500)
	assert_true(server.dev_used, "money tools make the match unranked")
	assert_true(_troll(dev, {"action": "take_money", "target": -2, "amount": 100})["ok"])
	assert_eq(server.economy.balance(cat), before + 400, "EVERYONE")
	assert_true(_troll(dev, {"action": "jail", "target": bob})["ok"])
	assert_gt(server.state.players[bob].jail_time_remaining, 0.0)
	assert_true(_troll(dev, {"action": "free", "target": bob})["ok"])
	assert_eq(server.state.players[bob].jail_time_remaining, 0.0)
	assert_true(_troll(dev, {"action": "say", "text": "hello losers"})["ok"])
	server.advance(0.05)
	assert_eq(str(_of(&"dev_message")[-1]["text"]), "hello losers")
	assert_false(_troll(dev, {"action": "give_item", "target": bob, "item": "nope"})["ok"])


func test_the_dev_watches_the_minigames() -> void:
	server.add_player("dev:bob", "Bob")
	server.add_player("dev:cat", "Cat")
	var dev: int = server.add_player("steam:%d" % DevMode.THE_DEV, "Patrick", -1, [], true)
	server.start_match()
	for i: int in 50:
		server.advance(0.1)
		if server.phases.phase == Phase.Id.CASINO:
			break
	assert_true(_troll(dev, {"action": "minigame", "item": "quiz"})["ok"])
	for i: int in 400:
		server.advance(0.1)
		if not _of(&"minigame_started").is_empty():
			break
	var started: Array[Dictionary] = _of(&"minigame_started")
	assert_eq(started.size(), 1)
	if started.is_empty():
		return
	assert_false(dev in (started[0]["players"] as Array), "the minigame runs without the dev")
	assert_eq((started[0]["players"] as Array).size(), 2)


func test_the_client_keeps_the_devs_money_out_of_the_ranks() -> void:
	var st := ClientMatchState.new()
	var bob := PlayerState.new()
	bob.id = 1
	var dev := PlayerState.new()
	dev.id = 2
	dev.dev = true
	st.apply_snapshot({"players": {1: bob.to_wire(), 2: dev.to_wire()}, "balances": {1: 1000, 2: MatchServer.GOD_MONEY}})
	assert_true(st.is_dev(2))
	assert_false(st.balances.has(2), "no rank, no crown, no Tab row")
	assert_eq(st.balance(2), MatchServer.GOD_MONEY, "his bets still see the money")
	assert_eq(st.rank_of(1), 1)


func test_troll_panel_sends_intents() -> void:
	var st := ClientMatchState.new()
	var bob := PlayerState.new()
	bob.id = 1
	bob.display_name = "Bob"
	var dev := PlayerState.new()
	dev.id = 2
	dev.dev = true
	st.apply_snapshot({"players": {1: bob.to_wire(), 2: dev.to_wire()}, "balances": {1: 1000, 2: 5}})
	var panel := DevTrollPanel.new()
	panel.send_to_server = false
	panel.setup(st, 2)
	add_child_autofree(panel)
	panel.open()
	assert_eq(panel.target_pick.item_count, 2, "EVERYONE and Bob, not the dev")
	panel.target_pick.select(1)
	panel.buttons[&"knock"].pressed.emit()
	assert_eq(panel.sent[-1]["type"], &"dev_troll")
	assert_eq(int(panel.sent[-1]["target"]), 1)
	assert_true(Intents.validate(panel.sent[-1]).is_empty(), str(Intents.validate(panel.sent[-1])))
	panel.amount_spin.value = 700
	panel.buttons[&"give_money"].pressed.emit()
	assert_eq(int(panel.sent[-1]["amount"]), 700)
	panel.say_edit.text = "hi"
	panel.buttons[&"say"].pressed.emit()
	assert_eq(str(panel.sent[-1]["text"]), "hi")
	assert_true(Intents.validate(panel.sent[-1]).is_empty())
