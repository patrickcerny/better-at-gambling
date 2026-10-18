extends GutTest
## Jackpot Climb's course on the real collision with a real bean (Patrick 2026-10-18: "you can get
## stuck on climb game. Actually make the climb game not a jump an run its a run"). A
## `ClimbRunner` drives a `PlayerAvatar` with the game's walking speed, gravity and jump, steered by
## `ChipTowers.guide` and watched by the server's `JackpotClimbLogic`:
## - every way up (each lane of every segment) runs from the apron to the pad, the steady lanes
##   without a single jump, in about the old clean-run time;
## - from every respawn spot of every flag the bean runs on to the next flag;
## - **no trap**: the bean is dropped on every walkable spot of a grid over the whole hall (every
##   layer: under a slab too) and from each it reaches the next checkpoint above where it landed (or
##   the pad), or falls far enough to be sent back to its flag, within `CAP` seconds.

## The old course (0.9.10, 40 hops, `tools/dev/jackpot_climb_bot.gd` walking): 30.1 to 33.7 s by
## lane, 31.5 s all left. A clean run now stays within 20 % of that.
const OLD_CLEAN_RUN: float = 31.5
const CAP: float = 30.0
## Grid over the hall (local x, z) and its spacing.
const GRID: float = 1.25
## How high over a landing spot the bean is let go (where there is room).
const DROP: float = 1.0

var holder: Node3D


func before_all() -> void:
	holder = Node3D.new()
	holder.name = "ClimbCourse"
	add_child(holder)
	ClimbRoom.build(holder, "towers")
	await wait_physics_frames(3)


func after_all() -> void:
	holder.free()


func _spawn() -> Vector3:
	return (ClimbRoom.layout("towers")["spawns"] as Array)[0]


func _run(sides: Array[bool], jumps: bool) -> Dictionary:
	var r := ClimbRunner.new(holder)
	r.bold = sides
	r.jumps_allowed = jumps
	r.place(_spawn())
	var flags: PackedStringArray = []
	var ok: bool = await r.run_until(func(x: ClimbRunner) -> bool:
		var c: int = int(x.logic.checkpoint.get(ClimbRunner.PLAYER, 0))
		if flags.size() < c:
			flags.append("%d at %.1f s" % [c, x.clock])
		return x.finished(), 90.0)
	var out: Dictionary = {"ok": ok, "time": r.clock, "jumps": r.jumps, "stuck": r.stuck_jumps, "respawns": r.respawns,
		"flags": ", ".join(flags), "at": r.local(), "log": ", ".join(r.jump_log)}
	r.free_bean()
	return out


func test_every_way_up_is_a_run() -> void:
	await wait_process_frames(1)
	var ways: Array = [[false, false, false, false], [true, true, true, true], [false, true, false, true], [true, false, true, false]]
	var hops: int = 0
	for l: Dictionary in ChipTowers.lanes():
		if l["kind"] == &"bold":
			hops += ChipTowers.risers(l).size()
	for w: Array in ways:
		var sides: Array[bool] = []
		sides.assign(w)
		var steady: bool = not sides.has(true)
		var res: Dictionary = await _run(sides, not steady)
		var tag: String = "bold per segment %s" % [sides]
		gut.p("%s: %s in %.1f s, %d jumps (%d unplanned), %d respawns; flags %s; jumps %s" % [tag, "pad" if res["ok"] else "STUCK at %s" % res["at"], res["time"], res["jumps"], res["stuck"], res["respawns"], res["flags"], res["log"]])
		assert_true(res["ok"], "%s reaches the pad (ended at %s)" % [tag, res["at"]])
		assert_eq(int(res["respawns"]), 0, "%s: a clean run never falls back" % tag)
		assert_eq(int(res["stuck"]), 0, "%s: never stuck" % tag)
		assert_between(float(res["time"]), OLD_CLEAN_RUN * 0.8, OLD_CLEAN_RUN * 1.2, "%s: about the old clean run (%.1f s)" % [tag, res["time"]])
		if steady:
			assert_eq(int(res["jumps"]), 0, "the steady lanes: never a jump")
		elif not sides.has(false):
			assert_eq(int(res["jumps"]), hops, "the bold lanes: one jump per hop (%d)" % hops)


func test_every_flag_leads_on() -> void:
	await wait_process_frames(1)
	var r := ClimbRunner.new(holder)
	for cp: Dictionary in ChipTowers.checkpoints():
		var k: int = int(cp["index"])
		for i: int in (cp["spots"] as Array).size():
			for b: bool in [false, true]:
				r.bold = [b, b, b, b]
				r.place(WalkableLogicBase.ROOM_ORIGIN + ((cp["spots"] as Array)[i] as Vector3), k)
				var ok: bool = await r.run_until(func(x: ClimbRunner) -> bool: return x.finished() or ChipTowers.checkpoint_at(x.local()) > k, CAP)
				assert_true(ok, "from flag %d spot %d (%s lane) to the next tier: ended at %s" % [k, i, "bold" if b else "steady", r.local()])
				assert_eq(r.respawns, 0, "flag %d spot %d: no fall" % [k, i])
	r.free_bean()


## Every spot a bean can stand on in the column at local (x, z): the tops of everything there,
## top to bottom, where the bean's capsule fits (under a slab too), world, as the drop point.
func _landings(space: PhysicsDirectSpaceState3D, x: float, z: float, capsule: Shape3D) -> Array[Vector3]:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var out: Array[Vector3] = []
	var y: float = ClimbRoom.TOWER_TOP_Y + 6.0
	for guard: int in 12:
		var q := PhysicsRayQueryParameters3D.create(o + Vector3(x, y, z), o + Vector3(x, -1.0, z))
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			break
		var at: Vector3 = hit["position"]
		if (hit["normal"] as Vector3).y > 0.7 and _fits(space, capsule, at + Vector3(0, 0.06, 0)):
			# Dropped from a metre up where there is room for that, else set down on it.
			out.append(at + Vector3(0, DROP if _fits(space, capsule, at + Vector3(0, DROP, 0)) else 0.05, 0))
		y = at.y - 0.25
	return out


## True if the bean's capsule standing with its feet at `feet` overlaps nothing.
func _fits(space: PhysicsDirectSpaceState3D, capsule: Shape3D, feet: Vector3) -> bool:
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = capsule
	sq.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, 0.85, 0))
	return space.intersect_shape(sq, 1).is_empty()


func test_no_spot_on_the_course_is_a_trap() -> void:
	await wait_physics_frames(1)
	var space: PhysicsDirectSpaceState3D = holder.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.66
	var spots: Array[Vector3] = []
	var x: float = -ChipTowers.HALL_HALF_X + 0.6
	while x <= ChipTowers.HALL_HALF_X - 0.6:
		var z: float = ChipTowers.FAR_Z + 0.6
		while z <= 0.0:
			spots.append_array(_landings(space, x, z, cap))
			z += GRID
		x += GRID
	gut.p("%d landing spots on a %.2f m grid" % [spots.size(), GRID])
	await wait_process_frames(1)
	var r := ClimbRunner.new(holder)
	var traps: PackedStringArray = []
	var by_ring: Dictionary[int, int] = {}
	var respawned: int = 0
	var unplanned: int = 0
	var worst: float = 0.0
	var total: float = 0.0
	for at: Vector3 in spots:
		var p: Vector3 = at - WalkableLogicBase.ROOM_ORIGIN
		if ChipTowers.flat_r(p) < ChipTowers.PAD_R and p.y > ChipTowers.TOP_Y - 0.5:
			by_ring[4] = by_ring.get(4, 0) + 1
			continue
		var on: Dictionary = ChipTowers.lane_under(p)
		# Where it landed sets how far it climbed: a bean on ring j has passed flag j.
		var ring: int = int(ChipTowers.lanes()[int(on["lane"])]["seg"]) if not on.is_empty() else 0
		by_ring[ring] = by_ring.get(ring, 0) + 1
		r.bold = [false, false, false, false]
		r.place(at, ring)
		var ok: bool = await r.run_until(func(b: ClimbRunner) -> bool: return b.respawns > 0 or b.finished() or ChipTowers.checkpoint_at(b.local()) > ring, CAP)
		if not ok:
			traps.append("%s (ring %d) -> stuck at %s" % [p, ring, r.local()])
		elif r.respawns > 0:
			respawned += 1
		unplanned += r.stuck_jumps
		worst = maxf(worst, r.clock)
		total += r.clock
	r.free_bean()
	gut.p("per ring (4: the pad) %s; %d sent back to their flag; %d unplanned jumps; mean %.1f s, worst %.1f s to the next checkpoint" % [by_ring, respawned, unplanned, total / maxf(spots.size(), 1.0), worst])
	assert_gt(spots.size(), 400, "the grid covers the course")
	for k: int in 4:
		assert_gt(int(by_ring.get(k, 0)), 10, "spots on ring %d" % k)
	assert_eq(traps.size(), 0, "no trap: %s" % "; ".join(traps.slice(0, 12)))
