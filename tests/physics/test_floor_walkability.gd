extends GutTest
## Can people walk the casino floor? (Patrick, 0.9.16: "The floorlayouts are sometimes stupid to
## walk through. test them.") Every floor layout is built in the real match scene and walked on
## navmeshes baked the way the game bakes its own (`LuckyLounge.nav_template`: the same colliders,
## the same settings), docs/FLOOR_PLAN.md "Walking the floor":
##
## - the game's own navmesh (the guards and the waiter) and one baked for a bean (the player's
##   capsule radius): from the entrance hall to every chair of every station and back, and from
##   every chair to every other station;
## - one baked for two beans side by side (twice the radius): every chair has a walkway that wide
##   right by it, joined to the hall, and so do the doorways, the jail door, the Gift Shop, Odd Jobs
##   and the megaphone; and walking between two neighbouring stations on it is never more than
##   `DETOUR` times the straight line (no table in the way, no gap too narrow to pass).

## Where people come from: the entrance hall, in front of the pedestals.
const HALL: Vector3 = LuckyLounge.RESPAWN_POS
## Navmesh cells for the test bakes: the radii divide into them exactly (0.42 = 3 cells, 0.84 = 6).
const CELL: float = 0.14
## How close to a chair the walkable floor must be (the bean's mesh), and the two-bean walkway.
const SEAT_REACH: float = 1.2
const PAIR_REACH: float = 1.35
## A path counts as arriving when it ends this close to where it was sent.
const ARRIVE: float = 0.3
## Neighbouring stations: each station's nearest few in plain sight of each other. Their walk may be
## at most DETOUR times the straight line (lines under DETOUR_MIN count as that long).
const NEIGHBOURS: int = 3
const DETOUR: float = 1.6
const DETOUR_MIN: float = 2.0
## Height of the bean swept along a straight line (`_in_sight`): its ball reaches down to the stools.
const SIGHT_Y: float = 0.7
## Drawn floors walked, from the floor stream of this match seed.
const DRAWS: int = 16
const SEED: int = 9160

static var scene: MatchScene
var _maps: Array[RID] = []


func before_all() -> void:
	Net.stop()
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = 0.0
	MatchScene.test_floor = "full"
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child(scene)
	await wait_seconds(3.0)


func after_all() -> void:
	MatchScene.test_briefing = -1.0
	MatchScene.test_floor = ""
	if scene != null:
		scene.queue_free()
		scene = null


func after_each() -> void:
	for m: RID in _maps:
		NavigationServer3D.free_rid(m)
	_maps.clear()


## The floors under test, [label, plan (wire form)]: the full floor, the canonical floor without a
## table game (what stands when every draw of a round fails), and DRAWS rounds' floors as the
## server draws them (`MatchServer.draw_floor`, seeds from the floor stream of match seed SEED).
func _layouts() -> Array[Array]:
	var srv: MatchServer = scene.server
	var out: Array[Array] = [["full floor", LuckyLounge.full_floor_plan()]]
	var games: Dictionary = srv._floor_games(true)
	games.erase(&"craps")
	var canon: FloorLayout = FloorGenerator.full(srv.map_def.floor_site, games, null, srv.floor_config)
	out.append(["canonical floor without craps", canon.wire_stations()])
	var rotation := FloorRotation.new(SeededRng.new(SEED ^ 0xF1002))
	for i: int in DRAWS:
		var l: FloorLayout = srv.draw_floor(rotation.next_seed())
		out.append([String(l.id), l.wire_stations()])
	return out


func _wait_navmesh() -> void:
	var t: float = 0.0
	await wait_physics_frames(3)
	while not scene.map.navmesh_ready and t < 10.0:
		await wait_seconds(0.2)
		t += 0.2


## Bakes the map's navigation sources for an agent of `radius` onto a navigation map of its own.
func _bake(radius: float) -> RID:
	var nm: NavigationMesh = LuckyLounge.nav_template(radius, CELL)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, scene.map)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	# Hand the server a fresh copy (the baked resource itself never reaches it headless).
	var fresh := NavigationMesh.new()
	fresh.cell_size = nm.cell_size
	fresh.cell_height = nm.cell_height
	fresh.vertices = nm.get_vertices()
	for i: int in nm.get_polygon_count():
		fresh.add_polygon(nm.get_polygon(i))
	var m: RID = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(m, CELL)
	NavigationServer3D.map_set_cell_height(m, nm.cell_height)
	NavigationServer3D.map_set_active(m, true)
	var r: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(r, m)
	NavigationServer3D.region_set_navigation_mesh(r, fresh)
	_maps.append(r)
	_maps.append(m)
	return m


## True once `nav` has synchronised with its region's mesh (it has floor in the entrance hall).
static func _synced(nav: RID) -> bool:
	if NavigationServer3D.map_get_iteration_id(nav) == 0:
		return false
	return _flat(NavigationServer3D.map_get_closest_point(nav, HALL)).distance_to(_flat(HALL)) <= 0.5


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _length(path: PackedVector3Array) -> float:
	var out: float = 0.0
	for i: int in range(1, path.size()):
		out += _flat(path[i]).distance_to(_flat(path[i - 1]))
	return out


## The walk from `a` to `b` on `nav` (empty when it does not get there).
static func _walk(nav: RID, a: Vector3, b: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, a, b, true)
	if path.size() < 2 or path[path.size() - 1].distance_to(b) > ARRIVE or path[0].distance_to(a) > ARRIVE:
		return PackedVector3Array()
	return path


## The walkable floor by a point on `nav` (Vector3.INF when there is none within `reach`, or the
## nearest is a table top).
static func _floor_near(nav: RID, p: Vector3, reach: float) -> Vector3:
	var near: Vector3 = NavigationServer3D.map_get_closest_point(nav, p * Vector3(1, 0, 1))
	if near.y > 0.8 or _flat(near).distance_to(_flat(p)) > reach:
		return Vector3.INF
	return near


## How close to `p` a walk from `from` on `nav` gets (the floor nearest `p` that can be walked to
## from there: a pocket of walkable floor nobody can get into doesn't count). Vector3.INF when
## that is farther than `reach`, or a table top.
static func _reach(nav: RID, from: Vector3, p: Vector3, reach: float) -> Vector3:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, from, p * Vector3(1, 0, 1), true)
	if path.is_empty():
		return Vector3.INF
	var end: Vector3 = path[path.size() - 1]
	if end.y > 0.8 or _flat(end).distance_to(_flat(p)) > reach:
		return Vector3.INF
	return end


## Every station of the floor that people walk to: the layout's, plus the VIP lounge and the Race
## Hall (not the waiting room, behind its own door).
func _stations() -> Array[StringName]:
	var out: Array[StringName] = []
	for sid: StringName in scene.map.stations:
		if not FunRoom.is_fun(sid):
			out.append(sid)
	out.sort()
	return out


func _seats(sid: StringName) -> Array[Vector3]:
	var st: StationBase = scene.map.stations[sid]
	var out: Array[Vector3] = []
	for i: int in st.seats.size():
		out.append(st.seat_position(i))
	return out


## Points that must stay open two beans wide: inside the lobby doors, the VIP door, the Race Hall
## archway, outside the jail gate, the Gift Shop and Odd Jobs spots and by the megaphone stand.
static func _doorways() -> Dictionary:
	return {
		"lobby doors": Vector3(0, 0, 7.4), "VIP door": Vector3(0, 0, -15.0), "Race Hall archway": Vector3(21.0, 0, -13.25),
		"jail gate": LuckyLounge.JAIL_DOOR + Vector3(-0.9, 0, 0), "Gift Shop": LuckyLounge.SHOP_POS, "Odd Jobs": LuckyLounge.ODD_JOBS_POS,
		"megaphone": MegaphoneLogic.STAND_POS + Vector3(-1.2, 0, 0),
	}


## Everything wrong with walking the floor standing now (empty when all is well).
func _walk_problems(label: String) -> Array[String]:
	var out: Array[String] = []
	var game_nav: RID = scene.map.nav_region.get_navigation_map()
	var bean_nav: RID = _bake(PlayerAvatar.BODY_RADIUS)
	var pair_nav: RID = _bake(PlayerAvatar.BODY_RADIUS * 2.0)
	# Wait for both maps to take their meshes in (a query before a map's first sync is an error).
	var waited: int = 0
	while waited < 120 and not (_synced(bean_nav) and _synced(pair_nav)):
		await wait_physics_frames(1)
		waited += 1
	var navs: Dictionary = {"game": game_nav, "bean": bean_nav}
	var hall: Dictionary = {}
	for k: String in navs:
		hall[k] = NavigationServer3D.map_get_closest_point(navs[k], HALL)
	hall["pair"] = NavigationServer3D.map_get_closest_point(pair_nav, HALL)
	for k: String in hall:
		if _flat(hall[k]).distance_to(_flat(HALL)) > 0.5:
			out.append("%s: no %s floor in the entrance hall (%s)" % [label, k, hall[k]])
			return out
	# Chairs: on each mesh, from the hall and back.
	var spots: Dictionary = {}  # station → its chairs' floor on the bean's mesh
	var fronts: Dictionary = {}  # station → its chairs' two-bean walkway
	var stations: Array[StringName] = _stations()
	for sid: StringName in stations:
		spots[sid] = [] as Array[Vector3]
		fronts[sid] = [] as Array[Vector3]
		var seats: Array[Vector3] = _seats(sid)
		for i: int in seats.size():
			for k: String in navs:
				var near: Vector3 = _floor_near(navs[k], seats[i], SEAT_REACH)
				if near == Vector3.INF:
					out.append("%s: %s chair %d has no %s floor within %.1f m" % [label, sid, i, k, SEAT_REACH])
					continue
				if _walk(navs[k], hall[k], near).is_empty():
					out.append("%s: %s chair %d can't be walked to from the hall (%s mesh)" % [label, sid, i, k])
				elif _walk(navs[k], near, hall[k]).is_empty():
					out.append("%s: %s chair %d: no way back to the hall (%s mesh)" % [label, sid, i, k])
				elif k == "bean":
					(spots[sid] as Array[Vector3]).append(near)
			var wide: Vector3 = _reach(pair_nav, hall["pair"], seats[i], PAIR_REACH)
			if wide == Vector3.INF:
				out.append("%s: %s chair %d: no walkway two beans wide from the hall within %.2f m" % [label, sid, i, PAIR_REACH])
			else:
				(fronts[sid] as Array[Vector3]).append(wide)
	# From every chair to every other station (the bean's mesh).
	for a: StringName in stations:
		for p: Vector3 in spots[a]:
			for b: StringName in stations:
				if b == a or (spots[b] as Array).is_empty():
					continue
				if _walk(bean_nav, p, (spots[b] as Array)[0]).is_empty():
					out.append("%s: no way from a chair of %s to %s" % [label, a, b])
	# Doorways and services, two beans wide, from the hall.
	var doors: Dictionary = _doorways()
	for name: String in doors:
		var p: Vector3 = doors[name]
		if _reach(pair_nav, hall["pair"], p, 0.6) == Vector3.INF:
			out.append("%s: the %s is not open two beans wide from the hall" % [label, name])
	# The guards' and the waiter's route points (the game's mesh).
	var points: Array[Vector3] = []
	points.append_array(CasinoFloor.WAITER_ROUTE)
	for route: Array in LuckyLounge.GUARD_ROUTES:
		for p: Vector3 in route:
			points.append(p)
	for p: Vector3 in points:
		var near: Vector3 = _floor_near(game_nav, p, 0.6)
		if near == Vector3.INF or _walk(game_nav, hall["game"], near).is_empty():
			out.append("%s: patrol point %s is off the walkways" % [label, p])
	out.append_array(_detours(label, pair_nav, fronts))
	return out


## Neighbouring casino-floor stations: no walk between them longer than DETOUR times the straight
## line on the two-bean walkways.
func _detours(label: String, pair_nav: RID, fronts: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var space: PhysicsDirectSpaceState3D = scene.map.get_world_3d().direct_space_state
	var ids: Array[StringName] = []
	for sid: StringName in fronts:
		if scene.map.stations[sid].has_meta(&"floor") and not (fronts[sid] as Array).is_empty():
			ids.append(sid)
	var seen: Dictionary = {}
	for a: StringName in ids:
		# Its nearest stations, by the nearest pair of walkway spots.
		var near: Array = []
		for b: StringName in ids:
			if b == a:
				continue
			var best: Array = [INF, Vector3.ZERO, Vector3.ZERO]
			for pa: Vector3 in fronts[a]:
				for pb: Vector3 in fronts[b]:
					var d: float = _flat(pa).distance_to(_flat(pb))
					if d < float(best[0]):
						best = [d, pa, pb]
			near.append([best[0], b, best[1], best[2]])
		near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var taken: int = 0
		for n: Array in near:
			if taken >= NEIGHBOURS:
				break
			var b: StringName = n[1]
			var pa: Vector3 = n[2]
			var pb: Vector3 = n[3]
			if not _in_sight(space, pa, pb):
				continue  # a bean can't walk straight there: not a neighbour
			taken += 1
			var key: String = "%s|%s" % ([a, b] if String(a) < String(b) else [b, a])
			if seen.has(key):
				continue
			seen[key] = true
			var straight: float = float(n[0])
			var path: PackedVector3Array = _walk(pair_nav, pa, pb)
			if path.is_empty():
				out.append("%s: %s and %s are neighbours but there is no two-bean walk between them" % [label, a, b])
				continue
			var walked: float = _length(path)
			if walked > DETOUR * maxf(straight, DETOUR_MIN):
				out.append("%s: %s to %s is %.1f m walked for %.1f m straight (more than %.1fx)" % [label, a, b, walked, straight, DETOUR])
	return out


## True when a bean could walk the straight line from `a` to `b` (a bean-wide sphere swept along
## it at waist height touches nothing standing on the floor).
static func _in_sight(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = PlayerAvatar.BODY_RADIUS
	q.shape = ball
	q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY, Vector3(a.x, SIGHT_Y, a.z))
	q.motion = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var hit: PackedFloat32Array = space.cast_motion(q)
	return hit.size() == 2 and hit[0] >= 1.0


func test_every_layout_can_be_walked() -> void:
	var layouts: Array[Array] = _layouts()
	assert_gt(layouts.size(), 0, "layouts to walk")
	for row: Array in layouts:
		var label: String = row[0]
		scene.map.apply_floor_plan(row[1])
		await _wait_navmesh()
		assert_true(scene.map.navmesh_ready, "%s: navmesh baked" % label)
		var t0: int = Time.get_ticks_msec()
		var why: Array[String] = await _walk_problems(label)
		gut.p("%s: walked in %d ms, %d problems" % [label, Time.get_ticks_msec() - t0, why.size()])
		for w: String in why:
			gut.p("  " + w)
		assert_eq(why.size(), 0, "%s can be walked (%s)" % [label, "; ".join(why.slice(0, 6))])
		after_each()


## The full floor is drawn before any map measures its games (`FloorGenerator.NOMINAL`): those
## sizes are the measured ones.
func test_the_nominal_sizes_are_the_measured_ones() -> void:
	var geo: FloorGeometry = FloorGeometry.of_map(scene.server.map_def, Registry.floor_plan.gap)
	var measured := FloorGenerator.new(null, {}, geo, null, null)
	var nominal := FloorGenerator.new(null, {}, null, null, null)
	for game: StringName in FloorGenerator.NOMINAL:
		assert_true(geo.rects.has(game), "%s measured" % game)
		assert_lt(_diff(measured.size_of(game), nominal.size_of(game)), 0.03, "%s: nominal floor %s is the measured %s" % [game, nominal.size_of(game), measured.size_of(game)])
		assert_lt(_diff(measured.solid_of(game), nominal.solid_of(game)), 0.03, "%s: nominal solid part %s is the measured %s" % [game, nominal.solid_of(game), measured.solid_of(game)])


static func _diff(a: Rect2, b: Rect2) -> float:
	return maxf(maxf(absf(a.position.x - b.position.x), absf(a.position.y - b.position.y)), maxf(absf(a.end.x - b.end.x), absf(a.end.y - b.end.y)))
