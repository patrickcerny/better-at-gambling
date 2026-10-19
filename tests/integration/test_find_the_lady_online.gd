extends GutTest
## Find the Lady end to end (Patrick, 0.9.9: "YOU NEED TO BE ABLE TO CLICK THE CARDS"): the
## authoritative server runs the minigame, the client stage sits inside the `PixelView` the way the
## match scene builds it, and a mouse click on a card in the window is the pick the server counts.

var fx: ServerFixture
var stage: FindTheLadyStage
var st: ClientMatchState
var pv: PixelView
var _fed: int = 0


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 1, "gamble_seconds": 20.0, "seed": 4, "minigame_pool": "find_the_lady"})
	st = ClientMatchState.new()
	for p: int in fx.player_ids:
		st.players[p] = {"id": p, "name": "P%d" % p, "color": p}


func after_each() -> void:
	fx.server.free()


## Every server event the stage has not seen yet, then the local player's private snapshot.
func _feed() -> void:
	while _fed < fx.events.size():
		stage.on_event(fx.events[_fed])
		_fed += 1
	stage.on_private(fx.server.get_private_snapshot(fx.player_ids[0]))


func _to_pick() -> FindTheLadyLogic:
	fx.server.start_match()
	fx.place_all(Vector3(0, 0, -4))
	var t: float = 0.0
	while fx.of_type(&"minigame_started").is_empty() and t < 200.0:
		fx.run(0.5)
		t += 0.5
	assert_eq(fx.of_type(&"minigame_started").size(), 1, "the minigame started")
	var g: FindTheLadyLogic = fx.server.minigame as FindTheLadyLogic
	assert_not_null(g, "Find the Lady is running")
	# The stage inside the world view (`PixelView`), its UI on the window, like the match scene.
	pv = PixelView.new()
	add_child_autofree(pv)
	pv.setup(false)
	pv.container.size = get_viewport().get_visible_rect().size  # headless: no window to size it from
	pv.container.scale = Vector2.ONE
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child_autofree(host)
	stage = FindTheLadyStage.new()
	stage.ui_host = host
	var me: int = fx.player_ids[0]
	stage.send_intent = func(i: Dictionary) -> Dictionary: return fx.server.submit_intent(me, i)
	pv.world.add_child(stage)
	_fed = fx.events.size()
	stage.begin(st, me, fx.of_type(&"minigame_started")[0], fx.server.get_snapshot()["minigame"])
	t = 0.0
	while g.phase != FindTheLadyLogic.Step.PICK and t < 60.0:
		fx.run(0.1)
		t += 0.1
	_feed()
	assert_eq(g.phase, FindTheLadyLogic.Step.PICK, "the pick window is open")
	assert_eq(stage.phase, "pick")
	return g


func test_a_click_on_a_card_in_the_window_is_the_pick_the_server_counts() -> void:
	var g: FindTheLadyLogic = _to_pick()
	var me: int = fx.player_ids[0]
	assert_true(stage.can_act(), "we may pick")
	await get_tree().process_frame
	var slot: int = 1
	var r: Rect2 = stage.slot_rect(slot)
	assert_true(r.size.x > 0.0, "card %d is on screen" % (slot + 1))
	var hidden: Array[CanvasLayer] = []  # GUT's own result window is drawn over the game
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var l: CanvasLayer = n
		if l.visible and l != stage.ui and not pv.is_ancestor_of(l):
			l.visible = false
			hidden.append(l)
	var mm := InputEventMouseMotion.new()
	mm.position = r.get_center()
	mm.global_position = r.get_center()
	mm.relative = Vector2(10, 0)
	get_viewport().push_input(mm, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = r.get_center()
	click.global_position = r.get_center()
	get_viewport().push_input(click, true)
	for l: CanvasLayer in hidden:
		if is_instance_valid(l):
			l.visible = true
	assert_eq(stage.my_pick, slot, "the stage shows our pick")
	assert_true(g.picks.has(me), "the server has our pick")
	assert_eq(int(g.picks.get(me, -1)), slot, "on the card we clicked")
	fx.run(0.1)
	_feed()
	assert_eq(int(fx.server.get_private_snapshot(me)["minigame"].get("picked", -1)), slot, "the private snapshot confirms it")
	assert_true(stage.picked_players.has(me))
	# The other two never clicked: the reveal counts exactly one pick.
	var t: float = 0.0
	while g.phase == FindTheLadyLogic.Step.PICK and t < 10.0:
		fx.run(0.1)
		t += 0.1
	_feed()
	var reveals: Array[Dictionary] = fx.of_type(&"find_the_lady_reveal")
	assert_eq(reveals.size(), 1, "one reveal")
	if reveals.size() == 1:
		var picks: Dictionary = reveals[0].get("picks", {})
		assert_eq(picks.size(), 1)
		assert_eq(int(picks.get(me, -1)), slot)
