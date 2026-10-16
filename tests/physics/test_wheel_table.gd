extends GutTest
## The Wheel of Fortune on a client: the wheel spins up when the dealer spins, slows without a
## jolt onto the segment the server drew and stops with that segment under the clicker, exactly
## when the server pays; a late joiner catches up from the state. Chips go into the symbol's box
## on the layout, the seat view sees wheel and layout, and in the real casino the table stands
## clear of everything with its dealer beside the wheel and the stools reachable on foot.

var view: SubViewport
var wh: WheelStation


func before_each() -> void:
	Vfx.force_enabled = true
	view = SubViewport.new()
	view.size = Vector2i(1920, 1080)
	add_child_autofree(view)
	wh = WheelStation.new()
	view.add_child(wh)
	await wait_process_frames(1)


func after_each() -> void:
	Vfx.force_enabled = false


## The segment whose writing is highest on the wheel right now (the one at the top, under the clicker).
func _top_label_segment() -> int:
	var best: int = -1
	var best_y: float = -INF
	for i: int in wh.face_labels.size():
		var y: float = wh.face_labels[i].global_position.y
		if y > best_y:
			best_y = y
			best = i
	return best


func test_the_wheel_is_built_from_the_layout() -> void:
	assert_eq(wh.face_labels.size(), WheelLogic.SEGMENTS, "every segment has its symbol written on it")
	for i: int in WheelLogic.SEGMENTS:
		assert_eq(wh.face_labels[i].text, WheelStation.FACE_TEXT[WheelLogic.LAYOUT[i]])
	assert_not_null(wh.pointer, "the clicker")
	assert_eq(wh.seats.size(), 5, "five stools")
	for s: Node3D in wh.seats:
		assert_gt(s.position.z, WheelStation.TABLE_D * 0.5, "the stools face the layout from the south")
	assert_eq(wh.spot_labels.size(), 7)
	assert_eq(_top_label_segment(), 0, "at rest at 0 the first segment is at the top")
	assert_eq(WheelStation.pointer_segment(0.0), 0)
	for seg: int in [1, 13, 27, 53]:
		wh.snap_to(seg)
		await wait_process_frames(1)
		assert_eq(WheelStation.pointer_segment(wh.angle), seg)
		assert_eq(_top_label_segment(), seg, "segment %d's writing is the one under the clicker" % seg)


func test_spins_up_then_stops_on_the_servers_segment() -> void:
	var dt: float = 1.0 / 60.0
	for seg: int in [WheelLogic.LAYOUT.find(5), WheelLogic.LAYOUT.find(6), 3, 40, 17]:
		wh.start_spin()
		var t: float = 0.0
		while t < 3.0:
			wh._tick(dt)
			t += dt
		assert_almost_eq(wh.speed, WheelStation.SPIN_SPEED, 0.001, "full speed while the server spins")
		var clicks_before: int = wh.clicks
		var v_before: float = wh.speed
		var wait: float = wh.land(seg, WheelLogic.LAND_TIME)
		assert_almost_eq(wait, WheelLogic.LAND_TIME, 0.001, "the result waits for the wheel to stop")
		var last: float = wh.angle
		wh._tick(dt)
		assert_almost_eq(wh.speed, v_before, 0.2, "no jolt when it starts slowing")
		var elapsed: float = dt
		var slowest_flap: float = 0.0
		while wh.mode == WheelStation.Mode.LAND:
			assert_gte(wh.angle, last - 0.000001, "never turns backwards")
			last = wh.angle
			wh._tick(dt)
			elapsed += dt
			slowest_flap = maxf(slowest_flap, wh.flap)
			assert_lt(elapsed, WheelLogic.LAND_TIME + 0.1, "stops in time")
		assert_almost_eq(elapsed, WheelLogic.LAND_TIME, dt * 1.5, "it rests as the server pays")
		assert_eq(wh.mode, WheelStation.Mode.REST)
		assert_eq(wh.speed, 0.0)
		assert_eq(WheelStation.pointer_segment(wh.angle), seg, "segment %d under the clicker" % seg)
		assert_eq(wh.landed_segment, seg)
		await wait_process_frames(1)
		assert_eq(_top_label_segment(), seg, "and its writing is at the top of the wheel")
		var turns: float = (wh.clicks - clicks_before) / float(WheelLogic.SEGMENTS)
		assert_between(turns, 1.0, 3.0, "a turn or two on the slow-down (%.2f)" % turns)
		assert_gt(slowest_flap, 0.3, "the pegs flick the clicker")
		# The wheel stands still now.
		var at: float = wh.angle
		for _i: int in 30:
			wh._tick(dt)
		assert_eq(wh.angle, at)


func test_late_joiner_lands_from_the_state() -> void:
	var seg: int = 22
	wh.show_state({"state": WheelLogic.State.SPINNING, "landing": false, "segment": -1, "timer": 1.5})
	assert_eq(wh.mode, WheelStation.Mode.SPIN, "joined during the spin: it spins")
	wh.show_state({"state": WheelLogic.State.SPINNING, "landing": true, "segment": seg, "timer": 1.2})
	assert_eq(wh.mode, WheelStation.Mode.LAND)
	assert_almost_eq(wh.land(seg, WheelLogic.LAND_TIME), 1.2, 0.001, "the event after the state keeps the slow-down it has")
	var t: float = 0.0
	while wh.mode == WheelStation.Mode.LAND and t < 2.0:
		# The same state arriving again does not restart the slow-down.
		wh.show_state({"state": WheelLogic.State.SPINNING, "landing": true, "segment": seg, "timer": maxf(1.2 - t, 0.0)})
		wh._tick(0.05)
		t += 0.05
	assert_almost_eq(t, 1.2, 0.06, "on the server's clock")
	assert_eq(WheelStation.pointer_segment(wh.angle), seg)
	wh.show_state({"state": WheelLogic.State.RESULT, "segment": 9, "history": [WheelLogic.LAYOUT[9]]})
	assert_eq(WheelStation.pointer_segment(wh.angle), 9, "joined on the result: the wheel shows it")
	assert_string_contains(wh.board_label.text, WheelLogic.LABELS[WheelLogic.LAYOUT[9]], "the sign lists the last spins")
	wh.start_spin()
	for _i: int in 20:
		wh._tick(0.05)
	wh.reset_table()
	assert_eq(wh.mode, WheelStation.Mode.COAST, "a spin called off coasts to a stop")
	for _i: int in 80:
		wh._tick(0.05)
	assert_eq(wh.mode, WheelStation.Mode.REST)


func test_the_angle_stays_precise_over_a_long_match() -> void:
	wh.start_spin()
	for _i: int in 6000:  # ~70 turns at full speed
		wh._tick(0.1)
	assert_lt(absf(wh.angle), WheelStation.WRAP + 1.0, "wrapped back")
	var clicks: int = wh.clicks
	wh._tick(0.01)
	assert_lte(wh.clicks - clicks, 1, "the wrap does not fire a burst of clicks")
	wh.land(31, WheelLogic.LAND_TIME)
	while wh.mode == WheelStation.Mode.LAND:
		wh._tick(1.0 / 30.0)
	assert_eq(WheelStation.pointer_segment(wh.angle), 31)


func test_seat_camera_sees_the_wheel_and_the_layout() -> void:
	var cam := Camera3D.new()
	cam.fov = 75.0
	view.add_child(cam)
	cam.global_transform = wh.camera_anchor.global_transform
	var rect := Rect2(Vector2.ZERO, Vector2(view.size))
	# The overlay strip covers the bottom ~380 px: the layout's boxes stay above it.
	var above_panel := Rect2(Vector2.ZERO, Vector2(view.size.x, view.size.y - 400))
	var points: Array[Vector3] = [
		Vector3(0, WheelStation.WHEEL_Y + WheelStation.WHEEL_R, WheelStation.WHEEL_Z),
		Vector3(-WheelStation.WHEEL_R, WheelStation.WHEEL_Y, WheelStation.WHEEL_Z),
		Vector3(WheelStation.WHEEL_R, WheelStation.WHEEL_Y, WheelStation.WHEEL_Z),
		wh.pointer.position,
	]
	for p: Vector3 in points:
		var g: Vector3 = wh.to_global(p)
		assert_false(cam.is_position_behind(g))
		assert_true(rect.has_point(cam.unproject_position(g)), "the seat sees %s" % p)
	for s: int in [0, 6]:
		var g: Vector3 = wh.to_global(WheelStation.bet_spot(s))
		assert_true(above_panel.has_point(cam.unproject_position(g)), "symbol %d's box clear of the panel: %s" % [s, cam.unproject_position(g)])
	cam.free()


func test_chips_go_into_the_symbol_boxes() -> void:
	var w := Node3D.new()
	view.add_child(w)
	var fx := TableFx.new()
	add_child_autofree(fx)
	fx.setup({&"w": wh}, func(_p: int) -> PlayerAvatar: return null, 1, null, w,
		func(pid: int) -> Color: return Palette.player_color(pid - 1), func(_sid: StringName) -> int: return 10)
	fx.on_event({"type": &"bet_placed", "player": 1, "station": &"w", "amount": 50, "details": {"game": "wheel", "type": &"wheel", "value": 5, "symbol": 5}})
	fx.on_event({"type": &"bet_placed", "player": 2, "station": &"w", "amount": 20, "details": {"game": "wheel", "type": &"wheel", "value": 0, "symbol": 0}})
	fx.on_event({"type": &"bet_placed", "player": 1, "station": &"w", "amount": 10, "details": {"game": "wheel", "type": &"wheel", "value": 0, "symbol": 0}})
	await wait_seconds(0.8)
	var boxes: Dictionary = {}
	for c: Node in wh.get_children():
		if not c is ChipStack:
			continue
		var p: Vector3 = (c as ChipStack).position
		for s: int in WheelLogic.SYMBOLS.size():
			var spot: Vector3 = WheelStation.bet_spot(s)
			if absf(p.x - spot.x) < WheelStation.SPOT_SIZE.x * 0.5 and absf(p.z - spot.z) < WheelStation.SPOT_SIZE.y * 0.5:
				boxes[s] = int(boxes.get(s, 0)) + 1
				assert_gte(p.y, WheelStation.FELT_Y - 0.001, "on the felt, not in it")
	assert_eq(boxes, {0: 2, 5: 1}, "every stack in its symbol's box (two on $1, stacked)")
	# The wheel stops on the result, then the chips settle (the dealer takes the losers).
	fx.on_event({"type": &"wheel_spin_started", "station": &"w"})
	assert_eq(wh.mode, WheelStation.Mode.SPIN)
	fx.on_event({"type": &"wheel_result", "station": &"w", "segment": 0, "symbol": 5, "seconds": 0.5})
	assert_eq(wh.mode, WheelStation.Mode.LAND)
	assert_almost_eq(fx._delay_for(&"w"), 0.5, 0.05, "the results show once the wheel rests")


## The real casino: the wheel at its spot in the Lucky Lounge, no collider overlapping another,
## the dealer standing beside the wheel on the floor, the stools reachable over the navmesh.
func test_in_the_casino_clear_of_everything() -> void:
	Vfx.force_enabled = false
	Net.stop()
	var scene: MatchScene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	var st: WheelStation = scene.map.stations.get(&"wheel_1", null) as WheelStation
	assert_not_null(st, "the lounge builds wheel_1")
	if st == null:
		return
	assert_eq(st.global_position, LuckyLounge.STATIONS[&"wheel_1"][1])
	var mine: Array[AABB] = []
	var others: Array[AABB] = []
	for n: Node in scene.map.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = n
		if cs.shape == null or cs.disabled:
			continue
		var body: Node = cs.get_parent()
		if body is RigidBody3D or body is CharacterBody3D or (body is CollisionObject3D and (body as CollisionObject3D).collision_layer & 1 == 0):
			continue  # stools, players and NPCs move; areas are not walls
		var box: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		if st.is_ancestor_of(cs):
			mine.append(box)
		else:
			others.append(box)
	assert_gt(mine.size(), 1, "table body and wheel cabinet are solid")
	for a: AABB in mine:
		for o: AABB in others:
			if o.size.y < 0.05:
				continue  # floor slabs
			assert_false(a.grow(-0.02).intersects(o), "the wheel overlaps a collider at %s" % o)
	# The dealer beside the wheel, on the floor, facing the table.
	var dealer: Dealer = scene.casino_floor.dealers.get(&"wheel_1", null)
	assert_not_null(dealer, "a dealer at the wheel")
	if dealer != null:
		var local: Vector3 = st.to_local(dealer.global_position)
		assert_gt(local.x, WheelStation.CAB_SIZE.x * 0.5 + 0.42, "beside the cabinet, not in it")
		assert_lt(local.z, -WheelStation.TABLE_D * 0.5 - 0.42, "behind the table")
		assert_almost_eq(dealer.global_position.y, 0.0, 0.05, "on the floor")
		assert_almost_eq(scene.server.dealers[&"wheel_1"].where(), dealer.global_position, Vector3.ONE * 0.05, "server and scene agree")
	# Each stool can be walked up to.
	var t: float = 0.0
	while not scene.map.navmesh_ready and t < 5.0:
		await wait_seconds(0.2)
		t += 0.2
	assert_true(scene.map.navmesh_ready)
	var nav: RID = scene.map.nav_region.get_navigation_map()
	for from: Vector3 in [Vector3(12, 0, -8), Vector3(0, 0, 7), LuckyLounge.SHOP_POS]:
		for i: int in st.seats.size():
			var front: Vector3 = st.to_global(Vector3(WheelStation.SEAT_XS[i], 0, WheelStation.SEAT_Z + 0.7))
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, front, true)
			assert_gt(path.size(), 1, "a path to stool %d" % i)
			if path.size() > 0:
				var end: Vector3 = path[path.size() - 1]
				assert_lt(Vector2(end.x - front.x, end.z - front.z).length(), 0.6, "path from %s ends at stool %d" % [from, i])
	# Sit down through the scene: the wheel's overlay opens.
	scene.local.teleport(st.global_position + Vector3(0, 0, 2.4), 0.0)
	await wait_physics_frames(3)
	assert_eq(scene.nearest_station, st, "prompt targets the wheel")
	scene._on_interact()
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)
	assert_true(scene.current_ui is WheelUi, "the wheel's overlay opens")
	var bet: Dictionary = Net.send_intent(Intents.make(&"place_bet", {"station": &"wheel_1", "bet": {"symbol": 0, "amount": 20}}))
	assert_true(bet["ok"], "bet: %s" % bet)
	await wait_seconds(0.5)  # the next snapshot
	assert_string_contains(Hud.in_play_text(scene.view.state, scene.local_id), "Wheel 1 $20", "the HUD counts the chips on the wheel")
