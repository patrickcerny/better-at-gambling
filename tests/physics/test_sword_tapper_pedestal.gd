extends GutTest
## The Sword Tapper pedestals in the real match scene: in every floor layout both pedestals stand
## where the layout says, side by side, clear of every other collider; the spot in front of each is
## free, picks that pedestal (not its neighbour) for the E prompt and is reachable over the navmesh
## from the lobby doors. Stepping up opens the overlay docked on the right with the bean still on
## its feet; a pull through the overlay plays the reveal on the pedestal and pays when it ends.

const SWORDS: Array[StringName] = [&"sword_1", &"sword_2"]
## Where a player walks up to, in the pedestal's frame: in front of the plinth, past the capsule.
const APPROACH: Vector3 = Vector3(0, 0, 1.25)

var scene: MatchScene


func before_each() -> void:
	Vfx.force_enabled = true
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")


func after_each() -> void:
	Vfx.force_enabled = false


func _pedestal(sid: StringName) -> SwordTapperStation:
	return scene.map.stations.get(sid, null) as SwordTapperStation


func _approach(st: StationBase) -> Vector3:
	var p: Vector3 = st.to_global(APPROACH)
	p.y = 0.0
	return p


func _wait_navmesh() -> void:
	var t: float = 0.0
	await wait_physics_frames(3)
	while not scene.map.navmesh_ready and t < 8.0:
		await wait_seconds(0.2)
		t += 0.2
	assert_true(scene.map.navmesh_ready, "navmesh baked")


## The pedestal's solid colliders touch nothing but its own parts and the floor.
func _check_no_overlaps(label: String, st: StationBase) -> void:
	var space: PhysicsDirectSpaceState3D = scene.map.get_world_3d().direct_space_state
	var checked: int = 0
	for body: Node in st.find_children("*", "StaticBody3D", true, false):
		for cs: Node in body.get_children():
			if not cs is CollisionShape3D:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = (cs as CollisionShape3D).shape
			q.transform = (cs as CollisionShape3D).global_transform.translated(Vector3(0, 0.03, 0))
			q.collision_mask = 1
			checked += 1
			for hit: Dictionary in space.intersect_shape(q, 16):
				var other: Node = hit["collider"]
				if st.is_ancestor_of(other) or other.name == "Floor":
					continue
				fail_test("%s: %s/%s overlaps %s" % [label, st.name, body.name, other.get_path()])
	assert_gt(checked, 0, "%s: %s is solid" % [label, st.station_id])


func _check_stand_spot(label: String, st: StationBase) -> void:
	var spot: Vector3 = _approach(st)
	var q := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 1.4
	q.shape = cyl
	q.transform = Transform3D(Basis(), spot + Vector3(0, 0.8, 0))
	q.collision_mask = 1
	var hits: Array[Dictionary] = scene.map.get_world_3d().direct_space_state.intersect_shape(q)
	assert_eq(hits.size(), 0, "%s: nothing solid where you walk up to %s (%s)" % [label, st.station_id, hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).get_path()))])
	var range_m: float = Registry.maps[&"lucky_lounge"].interact_range
	var best: StationBase = null
	var best_d: float = INF
	for sid: StringName in scene.map.stations:
		var o: StationBase = scene.map.stations[sid]
		var d: float = Vector2(o.global_position.x - spot.x, o.global_position.z - spot.z).length()
		if d < best_d and d <= range_m and absf(o.global_position.y) < 1.5:
			best_d = d
			best = o
	assert_eq(best, st, "%s: from in front of %s the E prompt picks it" % [label, st.station_id])
	var nav: RID = scene.map.nav_region.get_navigation_map()
	var near: Vector3 = NavigationServer3D.map_get_closest_point(nav, spot)
	assert_lt(Vector2(near.x - spot.x, near.z - spot.z).length(), 0.5, "%s: walkable floor in front of %s (%s)" % [label, st.station_id, near])
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, Vector3(0, 0, 6.5), near, true)
	assert_gt(path.size(), 1, "%s: a path from the lobby doors to %s" % [label, st.station_id])
	if path.size() > 0:
		assert_lt(path[path.size() - 1].distance_to(near), 0.3, "%s: and it gets to %s" % [label, st.station_id])


## The full floor and a few drawn ones (docs/FLOOR_PLAN.md).
func _floors() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = [scene.server.full_floor_layout()]
	for s: int in [11, 22, 33, 44, 55]:
		out.append(scene.server.draw_floor(s))
	return out


func test_both_pedestals_fit_and_are_reachable_in_every_layout() -> void:
	var def: MapDefinition = scene.server.map_def
	var geo: FloorGeometry = FloorGeometry.of_map(def, Registry.floor_plan.gap)
	assert_true(geo.rects.has(&"sword_tapper"), "the pedestal is measured for the fit check")
	for layout: FloorLayout in _floors():
		var label: String = String(layout.id)
		assert_eq(FloorPlan.problems(layout, Registry.floor_plan, Registry.games, geo), [] as Array[String], "%s fits" % label)
		scene.map.apply_floor_plan(layout.wire_stations())
		await _wait_navmesh()
		var plan: Dictionary = layout.wire_stations()
		for sid: StringName in SWORDS:
			assert_true(plan.has(sid), "%s has %s" % [label, sid])
			var st: SwordTapperStation = _pedestal(sid)
			assert_not_null(st, "%s: %s is built" % [label, sid])
			if st == null:
				continue
			assert_almost_eq(st.global_position, FloorPlan.pos_of(plan[sid]), Vector3.ONE * 0.01, "%s: %s where the layout says" % [label, sid])
			assert_almost_eq(wrapf(st.global_rotation.y - FloorPlan.yaw_of(plan[sid]), -PI, PI), 0.0, 0.001)
			_check_no_overlaps(label, st)
			_check_stand_spot(label, st)
		if _pedestal(&"sword_1") != null and _pedestal(&"sword_2") != null:
			var gap: float = _pedestal(&"sword_1").global_position.distance_to(_pedestal(&"sword_2").global_position)
			assert_between(gap, 1.6, 2.6, "%s: the two pedestals stand side by side" % label)


func test_step_up_and_pull_through_the_scene() -> void:
	var st: SwordTapperStation = _pedestal(&"sword_1")
	assert_not_null(st)
	assert_string_contains(st.prompt_text(10), "Pull the sword")
	var spot: Vector3 = _approach(st)
	scene.local.teleport(spot, 0.0)
	scene.server.set_server_position(scene.local_id, spot)
	await wait_physics_frames(2)
	var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": &"sword_1"}))
	assert_true(res["ok"], "step up: %s" % res)
	await wait_physics_frames(3)
	assert_true(scene.current_ui is SwordTapperUi, "the overlay opens")
	var ui: SwordTapperUi = scene.current_ui as SwordTapperUi
	assert_true(ui.visible)
	assert_true(ui._dock_column(), "docked in the right-hand column")
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED, "at the pedestal")
	assert_false(scene.local.visuals.sitting, "the bean stands (there is no stool)")
	var before: int = scene.server.economy.balance(scene.local_id)
	assert_true(ui.pull(), "PULL")
	await wait_seconds(0.4)
	assert_true(scene.server.stations.has_stake(scene.local_id), "the pull is open")
	assert_true(st.revealing(), "the pedestal plays the reveal")
	assert_eq(st.shown_serial, 1)
	assert_true(ui.pull_btn.disabled, "no second pull while the sword moves")
	await wait_seconds(Registry.balance.sword_reveal_time + 0.4)
	assert_false(scene.server.stations.has_stake(scene.local_id), "paid when the reveal ended")
	assert_false(st.revealing())
	var res_ev: Array = scene.server.event_log.filter(func(e: Dictionary) -> bool: return e["type"] == &"round_result" and StringName(e["station"]) == &"sword_1")
	assert_eq(res_ev.size(), 1)
	if res_ev.size() == 1:
		var returned: int = int(res_ev[0]["returned"])
		assert_eq(scene.server.economy.balance(scene.local_id), before - int(res_ev[0]["stake"]) + returned)
		var free: bool = bool((res_ev[0]["details"]["pull"] as Dictionary)["free"])
		assert_eq(st.lit.size(), (res_ev[0]["details"]["pull"]["gems"] as Array).size() if free else 0, "the lit gems are the server's")
	await wait_until(func() -> bool: return ui.result_label.text != "", 2.0)
	assert_ne(ui.result_label.text, "", "the result shows once the reveal is over")
	assert_false(ui.pull_btn.disabled, "ready for the next pull")


## Pedestals by the lobby wall stand far enough from it that nobody in the entrance hall gets their
## prompt or steps up to them through the wall (the interact range is a plain distance).
func test_never_reached_through_the_lobby_wall() -> void:
	for layout: FloorLayout in _floors():
		scene.map.apply_floor_plan(layout.wire_stations())
		await wait_physics_frames(2)
		for spot: Vector3 in LuckyLounge.LOBBY_SPAWNS:
			scene.local.teleport(spot, 0.0)
			await wait_physics_frames(2)
			scene._update_prompt()
			assert_false(scene.nearest_station is SwordTapperStation, "%s: no pedestal from the entrance hall at %s" % [layout.id, spot])
