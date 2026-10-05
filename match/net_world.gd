class_name NetWorld
extends Node
## Replicates the physical world (§4.1 "Replication model"). On the dedicated server it builds
## the 20 Hz world packet from the scene (avatars, server-simulated ragdolls, guards, moving
## props). On online clients it buffers those packets and drives every remote body 100 ms in the
## past through `InterpBuffer`s; the local avatar only takes ragdoll poses from it (the server owns
## the body while we're knocked out or thrown, we own it while standing).

## Remote bodies render this far behind the newest server time (absorbs jitter and 20 Hz steps).
const INTERP_DELAY: float = 0.1
## Props keep streaming this long after they stop, so clients see where they came to rest.
const PROP_SETTLE_TAIL: float = 0.5

var scene: MatchScene

## Client buffers: player id → InterpBuffer(x, y, z, yaw); ragdoll poses; guards; props.
var _players: Dictionary[int, InterpBuffer] = {}
var _rags: Dictionary[int, InterpBuffer] = {}
var _guards: Array[InterpBuffer] = []
var _guard_states: Array[int] = []
var _props: Dictionary[int, InterpBuffer] = {}
var _server_states: Dictionary[int, int] = {}
var _airborne: Dictionary[int, bool] = {}
var _prop_moving_at: Dictionary[int, float] = {}
var _suppress_until: Dictionary[int, float] = {}
var _last_t: float = 0.0
## Packets received (tests and the debug overlay).
var packets: int = 0


func setup(p_scene: MatchScene) -> void:
	scene = p_scene
	if Net.is_client():
		Net.world_received.connect(_on_world)
		# Props are server-simulated: on clients they become kinematic and follow the stream.
		for body: RigidBody3D in _prop_bodies():
			body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			body.freeze = true


func _exit_tree() -> void:
	if Net.world_received.is_connected(_on_world):
		Net.world_received.disconnect(_on_world)


# --- Server ------------------------------------------------------------------------------------

## The world dictionary for `WorldCodec` (server side).
func build() -> Dictionary:
	var players: Dictionary = {}
	for pid: int in scene.avatars:
		var a: PlayerAvatar = scene.avatars[pid]
		var p: Dictionary = {"state": a.state, "pos": a.global_position, "yaw": a.yaw}
		match a.drive:
			PlayerAvatar.Drive.PUPPET:
				p["airborne"] = a.puppet_airborne
			_:
				p["airborne"] = not a.is_on_floor()
		if a.state == PlayerAvatar.State.RAGDOLL and a.ragdoll != null and is_instance_valid(a.ragdoll) and not a.ragdoll.puppet:
			p["rag"] = a.ragdoll.pose()
		players[pid] = p
	var guards: Array = []
	for g: Guard in scene.guards:
		guards.append({"pos": g.global_position, "yaw": g.yaw, "state": g.state})
	var props: Dictionary = {}
	var now: float = Net.server_time()
	var bodies: Array[RigidBody3D] = _prop_bodies()
	for i: int in bodies.size():
		var b: RigidBody3D = bodies[i]
		if not b.sleeping and b.linear_velocity.length() + b.angular_velocity.length() > 0.05:
			_prop_moving_at[i] = now
		if now - _prop_moving_at.get(i, -INF) <= PROP_SETTLE_TAIL:
			props[i] = {"pos": b.global_position, "rot": b.global_basis.get_rotation_quaternion()}
	return {"players": players, "guards": guards, "props": props}


# --- Client ------------------------------------------------------------------------------------

func _on_world(w: Dictionary) -> void:
	packets += 1
	var t: float = float(w["t"])
	_last_t = maxf(_last_t, t)
	var players: Dictionary = w["players"]
	for pid: Variant in players:
		var id: int = int(pid)
		var p: Dictionary = players[pid]
		_server_states[id] = int(p["state"])
		_airborne[id] = bool(p["airborne"])
		if not _players.has(id):
			_players[id] = InterpBuffer.new(PackedInt32Array([3]))
		var pos: Vector3 = p["pos"]
		_players[id].push(t, PackedFloat32Array([pos.x, pos.y, pos.z, float(p["yaw"])]))
		if p.has("rag"):
			if not _rags.has(id):
				_rags[id] = InterpBuffer.new()
			var r: Dictionary = p["rag"]
			var v := PackedFloat32Array()
			var rp: Vector3 = r["pos"]
			var rq: Quaternion = r["rot"]
			v.append_array([rp.x, rp.y, rp.z, rq.x, rq.y, rq.z, rq.w])
			for part: Vector3 in r["parts"]:
				v.append_array([part.x, part.y, part.z])
			_rags[id].push(t, v)
		elif _rags.has(id):
			_rags.erase(id)
	var guards: Array = w["guards"]
	for i: int in guards.size():
		while _guards.size() <= i:
			_guards.append(InterpBuffer.new(PackedInt32Array([3])))
			_guard_states.append(0)
		var g: Dictionary = guards[i]
		var gp: Vector3 = g["pos"]
		_guards[i].push(t, PackedFloat32Array([gp.x, gp.y, gp.z, float(g["yaw"])]))
		_guard_states[i] = int(g["state"])
	var props: Dictionary = w["props"]
	for idx: Variant in props:
		var i: int = int(idx)
		if not _props.has(i):
			_props[i] = InterpBuffer.new()
		var pr: Dictionary = props[idx]
		var pp: Vector3 = pr["pos"]
		var pq: Quaternion = pr["rot"]
		_props[i].push(t, PackedFloat32Array([pp.x, pp.y, pp.z, pq.x, pq.y, pq.z, pq.w]))


func _process(_delta: float) -> void:
	if scene == null or not Net.is_client() or _players.is_empty():
		return
	# Render in the past; if our clock estimate runs ahead of the stream, fall back to its newest time.
	var render_t: float = minf(Net.server_time(), _last_t + 0.05) - INTERP_DELAY
	for pid: int in scene.avatars:
		var a: PlayerAvatar = scene.avatars[pid]
		_reconcile_state(pid, a)
		if a.state == PlayerAvatar.State.RAGDOLL and a.ragdoll != null and a.ragdoll.puppet and _rags.has(pid):
			var r: PackedFloat32Array = _rags[pid].sample(render_t)
			if r.size() >= 19:
				var parts: Array[Vector3] = []
				for k: int in 4:
					parts.append(Vector3(r[7 + k * 3], r[8 + k * 3], r[9 + k * 3]))
				a.ragdoll.apply_pose(Vector3(r[0], r[1], r[2]), Quaternion(r[3], r[4], r[5], r[6]).normalized(), parts)
			continue
		if pid == scene.local_id or a.drive != PlayerAvatar.Drive.PUPPET or not _players.has(pid):
			continue
		var s: PackedFloat32Array = _players[pid].sample(render_t)
		if s.size() >= 4:
			a.target_position = Vector3(s[0], s[1], s[2])
			a.target_yaw = s[3]
			a.puppet_airborne = _airborne.get(pid, false)
	for i: int in mini(_guards.size(), scene.guards.size()):
		var g: PackedFloat32Array = _guards[i].sample(render_t)
		if g.size() >= 4:
			scene.guards[i].apply_net(Vector3(g[0], g[1], g[2]), g[3], _guard_states[i])
	if not _props.is_empty():
		var bodies: Array[RigidBody3D] = _prop_bodies()
		for i: int in _props:
			if i >= bodies.size():
				continue
			var v: PackedFloat32Array = _props[i].sample(render_t)
			if v.size() >= 7:
				bodies[i].global_position = Vector3(v[0], v[1], v[2])
				bodies[i].quaternion = Quaternion(v[3], v[4], v[5], v[6]).normalized()


## Catches up with states we may have missed events for (joined mid-ragdoll, thrown out).
func _reconcile_state(pid: int, a: PlayerAvatar) -> void:
	if Time.get_ticks_msec() / 1000.0 < _suppress_until.get(pid, -INF):
		return  # an event just changed this body; older packets may still be in flight
	var s: int = _server_states.get(pid, -1)
	if s == PlayerAvatar.State.AWAY and a.state != PlayerAvatar.State.AWAY:
		a.set_away(true)
	elif s == PlayerAvatar.State.RAGDOLL and a.state != PlayerAvatar.State.RAGDOLL and _rags.has(pid) and a.state != PlayerAvatar.State.AWAY:
		a.start_ragdoll(Vector3.ZERO, 60.0, true)


## Snaps a player's buffer (teleport: respawn, got up) so it doesn't slide across the room, and
## ignores stale body states for a moment.
func reset_player(pid: int) -> void:
	if _players.has(pid):
		_players[pid].clear()
	_rags.erase(pid)
	_suppress_until[pid] = Time.get_ticks_msec() / 1000.0 + 1.0


## Newest position the server streamed for a player (Vector3.INF if none).
func server_position(pid: int) -> Vector3:
	if not _players.has(pid) or _players[pid].is_empty():
		return Vector3.INF
	var s: PackedFloat32Array = _players[pid].sample(_players[pid].newest_time())
	return Vector3(s[0], s[1], s[2]) if s.size() >= 3 else Vector3.INF


## Newest server state seen for a player (-1 if none).
func server_state(pid: int) -> int:
	return _server_states.get(pid, -1)


func _prop_bodies() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	if scene == null or scene.map == null or scene.map.props_parent == null:
		return out
	for c: Node in scene.map.props_parent.get_children():
		if c is RigidBody3D:
			out.append(c)
	return out
