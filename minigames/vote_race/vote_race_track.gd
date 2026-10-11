class_name VoteRaceTrack
extends Node3D
## The Vote Race runway in 3D, under the cards: a red carpet with a lane per racer, a start line
## between velvet ropes, brass step plates 1-4 with warm bulbs and big numbers, and the gold
## CASHIER window (brass grille, bulb sign, a "$") at step 5. Every racer is a puppet bean with a
## name tag standing in their lane on their step; racers out of the race sit on a couch at the
## side. A step forward is a hop to the next plate with a sparkle and a ding; reaching the cashier
## lights the window up, pours coins and the bean cheers. At a reveal, an arc of beads in the
## voter's colour runs from every voter's bean to the bean they voted for.
## Purely presentation: the stage tells it who stands where.

const STEP_DX: float = 2.0
const X0: float = -5.4
const LANE_W: float = 0.95
const BEAN_SCALE: float = 0.72
const PLATE_TOP: float = 0.1
const HOP_TIME: float = 0.42
const ARC_BEADS: int = 18
const ARC_TIME: float = 0.38
const WARM_LIGHT: Color = Color("#FFD9A0")
const BULB: Color = Color("#FFE2A6")
const CARPET: Color = Color("#7A1E24")
const FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")

var track_length: int = 5
var local_id: int = -1
## Racers in lane order (back lane first).
var lanes: Array[int] = []
var benched: Array[int] = []
## player → {root: Node3D, bean: AvatarVisuals, puppet: BeanPuppet, tag: Label3D, step: int, lane: int}
var beans: Dictionary = {}
## The vote arcs shown now: {voter, target, node}.
var vote_arcs: Array[Dictionary] = []
var cashier_lit: bool = false
var camera: Camera3D

var _set_root: Node3D
var _lanes_built: int = -1
var _arcs_root: Node3D
var _bench_root: Node3D
var _cashier_light: OmniLight3D
var _cashier_glow: StandardMaterial3D
var _sign_bulbs: StandardMaterial3D
var _coins: CPUParticles3D
var _cam_home: Transform3D
var _cam_tween: Tween
var _mats: Dictionary = {}


func _ready() -> void:
	_arcs_root = Node3D.new()
	_arcs_root.name = "VoteArcs"
	add_child(_arcs_root)
	_bench_root = Node3D.new()
	_bench_root.name = "Bench"
	add_child(_bench_root)
	camera = Camera3D.new()
	camera.name = "TrackCamera"
	camera.fov = 44.0
	camera.far = 90.0  # the casino floor is 400 m away: keep it out
	add_child(camera)
	_build_set(2)
	_build_bench_couch()
	_build_lights()


## The x of a step's plate (0 = the start box, `track_length` = the cashier window).
func step_x(step: int) -> float:
	return X0 + STEP_DX * float(clampi(step, 0, track_length))


func lane_z(lane: int) -> float:
	return (float(lane) - float(lanes.size() - 1) * 0.5) * LANE_W


func _depth(n: int) -> float:
	return float(maxi(n, 2)) * LANE_W + 0.5


## Who races in which lane and who sits on the bench; `info` is player → {name, color, skin, steps}.
## Beans for new racers are placed on their step at once; racers who left are removed.
func set_racers(p_lanes: Array[int], p_bench: Array[int], info: Dictionary) -> void:
	lanes = p_lanes.duplicate()
	benched = p_bench.duplicate()
	if lanes.size() != _lanes_built:
		_build_set(lanes.size())
		_frame_camera()
	for p: Variant in beans.keys():
		if int(p) not in lanes and int(p) not in benched:
			(beans[p]["root"] as Node3D).queue_free()
			beans.erase(p)
	for i: int in lanes.size():
		var p: int = lanes[i]
		var d: Dictionary = info.get(p, {})
		if not beans.has(p):
			_make_bean(p, d)
		var b: Dictionary = beans[p]
		var was_benched: bool = int(b["lane"]) < 0
		b["lane"] = i
		if was_benched:
			(b["root"] as Node3D).reparent(self, false)
			b["step"] = -1
		var s: int = int(d.get("steps", b["step"]))
		if s != int(b["step"]) or was_benched:
			set_step(p, s, false)
		elif not b.has("hop"):
			_place(p)
	for i: int in benched.size():
		var p: int = benched[i]
		if not beans.has(p):
			_make_bean(p, info.get(p, {}))
		var b: Dictionary = beans[p]
		b["lane"] = -1
		var root: Node3D = b["root"]
		if root.get_parent() != _bench_root:
			root.reparent(_bench_root, false)
		_kill_hop(b)
		root.position = Vector3((float(i) - float(benched.size() - 1) * 0.5) * 0.78, 0.55, 0.0)
		root.rotation.y = 0.0
		(b["puppet"] as BeanPuppet).base = (b["bean"] as Node3D).position
		(b["puppet"] as BeanPuppet).set_mood(BeanPuppet.Mood.IDLE)
	_bench_root.visible = not benched.is_empty()


## Moves a racer to `step`: a hop with a sparkle and a ding when `animate`, else in place at once.
## Reaching the cashier lights the window up and makes the bean cheer.
func set_step(p: int, step: int, animate: bool) -> void:
	if not beans.has(p) or int(beans[p]["lane"]) < 0:
		return
	var b: Dictionary = beans[p]
	var from: int = int(b["step"])
	b["step"] = step
	_kill_hop(b)
	if not animate or from < 0 or from == step:
		_place(p)
		if step >= track_length:
			(b["puppet"] as BeanPuppet).set_mood(BeanPuppet.Mood.CHEER)
			set_cashier_lit(true, false)
		return
	var root: Node3D = b["root"]
	var a: Vector3 = root.position
	var z: Vector3 = _spot(p)
	var tw: Tween = create_tween()
	b["hop"] = tw
	tw.tween_method(func(k: float) -> void:
		root.position = a.lerp(z, k) + Vector3(0, sin(k * PI) * 0.75, 0), 0.0, 1.0, HOP_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_landed.bind(p))


## Every hop still in the air lands now (tests, skipping the show).
func land_all() -> void:
	for p: Variant in beans:
		var b: Dictionary = beans[p]
		if b.has("hop") and is_instance_valid(b["hop"]) and (b["hop"] as Tween).is_valid():
			_kill_hop(b)
			_landed(int(p))


func _kill_hop(b: Dictionary) -> void:
	var tw: Variant = b.get("hop", null)
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	b.erase("hop")


func _landed(p: int) -> void:
	if not beans.has(p):
		return
	var b: Dictionary = beans[p]
	b.erase("hop")
	_place(p)
	var at: Vector3 = (b["root"] as Node3D).position
	_burst(at + Vector3(0, 0.25, 0), int(b["step"]) >= track_length)
	if int(b["step"]) >= track_length:
		(b["puppet"] as BeanPuppet).set_mood(BeanPuppet.Mood.CHEER)
		set_cashier_lit(true, true)
		Audio.play(&"cash_register", &"UI", -6.0)
	else:
		(b["puppet"] as BeanPuppet).hop(0.18)
		Audio.play(&"chime", &"UI", -10.0, 1.0 + 0.08 * float(b["step"]))


## Where a racer stands: their lane on their step's plate, turned half towards the cashier.
func _spot(p: int) -> Vector3:
	var b: Dictionary = beans[p]
	var s: int = int(b["step"])
	var x: float = step_x(s) - (0.55 if s <= 0 else 0.0)
	return Vector3(x, PLATE_TOP if s > 0 else 0.03, lane_z(int(b["lane"])))


func _place(p: int) -> void:
	var b: Dictionary = beans[p]
	var root: Node3D = b["root"]
	root.position = _spot(p)
	root.rotation.y = 0.0


## The cashier window glows, its sign bulbs blaze and (with `pour`) coins rain from the window.
func set_cashier_lit(on: bool, pour: bool) -> void:
	cashier_lit = on
	_cashier_light.light_energy = 3.2 if on else 0.6
	_cashier_glow.emission_energy_multiplier = 2.4 if on else 0.35
	_sign_bulbs.emission_energy_multiplier = 3.0 if on else 1.0
	if on and pour and _coins != null:
		_coins.restart()
		_coins.emitting = true


## Who voted for whom: an arc of beads from each voter's bean to their target's, `stagger`
## seconds apart, drawn out over ARC_TIME. `instant` shows them complete.
func show_votes(cast: Dictionary, stagger: float, instant: bool) -> void:
	clear_votes()
	var voters: Array[int] = []
	for v: Variant in cast:
		voters.append(int(v))
	voters.sort()
	var i: int = 0
	for voter: int in voters:
		var target: int = int(cast[voter])
		if not beans.has(voter) or not beans.has(target):
			continue
		var node := _make_arc(voter, target, stagger * float(i), instant)
		vote_arcs.append({"voter": voter, "target": target, "node": node})
		i += 1


func clear_votes() -> void:
	for a: Dictionary in vote_arcs:
		if is_instance_valid(a["node"]):
			(a["node"] as Node3D).queue_free()
	vote_arcs.clear()


func _make_arc(voter: int, target: int, delay: float, instant: bool) -> Node3D:
	var node := Node3D.new()
	node.name = "Vote%d_%d" % [voter, target]
	_arcs_root.add_child(node)
	var a: Vector3 = (beans[voter]["root"] as Node3D).position + Vector3(0, 1.0, 0)
	var c: Vector3 = (beans[target]["root"] as Node3D).position + Vector3(0, 1.22, 0)
	var lift: float = 0.7 + a.distance_to(c) * 0.28
	var mid: Vector3 = (a + c) * 0.5 + Vector3(0, lift, 0)
	var col: Color = beans[voter]["color"]
	var mat: StandardMaterial3D = _mat(col, 0.0, 0.9)
	var bead := SphereMesh.new()
	bead.radius = 0.06 if voter != local_id else 0.08
	bead.height = bead.radius * 2.0
	bead.radial_segments = 8
	bead.rings = 4
	var tw: Tween = null if instant else node.create_tween()
	if tw != null:
		tw.tween_interval(delay)
	for k: int in ARC_BEADS:
		var t: float = float(k + 1) / float(ARC_BEADS + 1)
		var mi := MeshInstance3D.new()
		mi.mesh = bead
		mi.material_override = mat
		mi.position = _bez(a, mid, c, t)
		node.add_child(mi)
		if tw != null:
			mi.scale = Vector3.ZERO
			tw.tween_property(mi, "scale", Vector3.ONE, ARC_TIME / float(ARC_BEADS))
	# Arrowhead pointing down at the target, landing with a small chime.
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.15
	cone.height = 0.3
	cone.radial_segments = 8
	head.mesh = cone
	head.material_override = mat
	node.add_child(head)
	var dir: Vector3 = (c - _bez(a, mid, c, 0.92)).normalized()
	head.position = c - dir * 0.08
	head.basis = _basis_up(dir)
	if tw != null:
		head.scale = Vector3.ZERO
		tw.tween_property(head, "scale", Vector3.ONE, 0.08)
		tw.tween_callback(func() -> void: Audio.play(&"chip_clack", &"UI", -14.0, randf_range(0.9, 1.15)))
	return node


static func _bez(a: Vector3, m: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(m, t).lerp(m.lerp(c, t), t)


static func _basis_up(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y).normalized()).orthonormalized()


## The final ranking: the winner cheers, the two left on the track slump.
func show_result(ranking: Array) -> void:
	var last: int = 0
	for row: Variant in ranking:
		last = maxi(last, int((row as Dictionary).get("rank", 0)))
	for row: Variant in ranking:
		var p: int = int((row as Dictionary).get("player", -1))
		var rank: int = int((row as Dictionary).get("rank", 0))
		if not beans.has(p):
			continue
		var mood: BeanPuppet.Mood = BeanPuppet.Mood.IDLE
		if rank == 1:
			mood = BeanPuppet.Mood.CHEER
		elif rank == last and last > 1:
			mood = BeanPuppet.Mood.SAD
		(beans[p]["puppet"] as BeanPuppet).set_mood(mood)
	set_cashier_lit(true, false)


## A slow push-in towards the track during a reveal; `false` eases back.
func push_in(on: bool) -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	var to: Transform3D = _cam_home
	if on:
		to.origin = _cam_home.origin.lerp(Vector3(0.3, 0.8, 0.0), 0.07)
	_cam_tween = create_tween()
	_cam_tween.tween_property(camera, "transform", to, 2.8 if on else 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _frame_camera() -> void:
	var n: float = float(maxi(lanes.size(), 2))
	var pos := Vector3(-1.2, 8.6 + n * 0.58, 11.8 + n * 0.66)
	var look := Vector3(0.7, 3.0 + n * 0.2, -0.4)
	camera.transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	_cam_home = camera.transform


# --- Beans -------------------------------------------------------------------------------------

func _make_bean(p: int, d: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Racer%d" % p
	add_child(root)
	var color: Color = d.get("color", Palette.CREAM)
	var bean := AvatarVisuals.new()
	bean.scale = Vector3.ONE * BEAN_SCALE
	bean.rotation.y = PI + 0.55  # face the audience, turned towards the cashier
	root.add_child(bean)
	bean.set_color(color)
	bean.set_skin(StringName(d.get("skin", "bean")))
	var puppet: BeanPuppet = BeanPuppet.attach(bean)
	puppet.cheer_height = 0.25
	# A disc in their colour under their feet (gold ring for you).
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.34
	cm.height = 0.03
	cm.radial_segments = 20
	disc.mesh = cm
	disc.position.y = 0.015
	disc.material_override = _mat(color.darkened(0.15))
	root.add_child(disc)
	if p == local_id:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.36
		tm.outer_radius = 0.44
		tm.rings = 20
		ring.mesh = tm
		ring.position.y = 0.03
		ring.material_override = _mat(Palette.VIP_GOLD, 0.6, 1.2)
		root.add_child(ring)
	var tag := Label3D.new()
	tag.name = "Tag"
	var nm: String = String(d.get("name", "?"))
	tag.text = ("YOU" if p == local_id else (nm.left(10) + ("…" if nm.length() > 10 else ""))).to_upper()
	tag.font = FONT
	tag.font_size = 44
	tag.pixel_size = 0.0055
	tag.outline_size = 10
	tag.outline_modulate = Palette.CASINO_BLACK
	tag.modulate = Palette.VIP_GOLD if p == local_id else color.lightened(0.25)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 2
	tag.position = Vector3(0, 1.38, 0)
	root.add_child(tag)
	beans[p] = {"root": root, "bean": bean, "puppet": puppet, "tag": tag, "step": -1, "lane": -1, "color": color}


# --- The set -----------------------------------------------------------------------------------

## The carpet, plates, ropes, cashier and backdrop for `n` lanes (rebuilt when the field changes).
func _build_set(n: int) -> void:
	if _set_root != null:
		_set_root.queue_free()
	_lanes_built = n
	var depth: float = _depth(n)
	_set_root = Node3D.new()
	_set_root.name = "Set"
	add_child(_set_root)
	move_child(_set_root, 0)
	var r: Node3D = _set_root
	var front: float = depth * 0.5
	var x_start: float = X0 - 1.5
	var x_end: float = step_x(track_length) + 0.9
	# Stage floor and the velvet backdrop.
	_box(r, Vector3(44, 0.1, 30), Vector3(0, -0.05, 4), Color("#1E1512"))
	_box(r, Vector3(30, 0.04, 0.12), Vector3(0, 0.02, front + 2.4), Palette.WARM_GOLD, 0.7)
	var back_z: float = -front - 2.2
	for i: int in 64:
		var shade: Color = Palette.VIP_BURGUNDY.darkened(0.15 if i % 2 == 0 else 0.4)
		_box(r, Vector3(0.62, 14.0, 0.3 + 0.12 * float(i % 2)), Vector3(-19.5 + 0.62 * float(i), 7.0, back_z), shade)
	# The red carpet with gold edging.
	var len: float = x_end - x_start
	var cx: float = (x_start + x_end) * 0.5
	_box(r, Vector3(len, 0.05, depth), Vector3(cx, 0.025, 0), CARPET)
	for s: float in [-1.0, 1.0]:
		_box(r, Vector3(len, 0.06, 0.08), Vector3(cx, 0.03, s * (front + 0.04)), Palette.WARM_GOLD, 0.7)
	for i: int in range(1, n):
		var z: float = (float(i) - float(n) * 0.5) * LANE_W
		_box(r, Vector3(len - 0.4, 0.056, 0.025), Vector3(cx, 0.03, z), CARPET.darkened(0.35))
	# Start line, START lettering and velvet ropes on brass stanchions.
	_box(r, Vector3(0.14, 0.06, depth), Vector3(X0 + 0.3, 0.035, 0), Palette.CREAM)
	_floor_text(r, "START", Vector3(X0 - 0.75, 0.07, front + 0.65), 90, Palette.CREAM)
	for s: float in [-1.0, 1.0]:
		var z: float = s * (front + 0.22)
		var posts: Array[float] = [x_start + 0.15, X0 + 0.3]
		for k: int in range(1, track_length + 1):
			posts.append(step_x(k) - STEP_DX * 0.5)
		if s > 0.0:
			posts = [x_start + 0.15, X0 + 0.3]  # in front only at the start: keep the view open
		for k: int in posts.size():
			_stanchion(r, Vector3(posts[k], 0, z))
			if k > 0:
				_rope(r, Vector3(posts[k - 1], 0.62, z), Vector3(posts[k], 0.62, z))
	# Brass step plates with bulbs at both ends and their number on the floor in front.
	var bulb_mat: StandardMaterial3D = _mat(BULB, 0.0, 2.2)
	for k: int in range(1, track_length + 1):
		var x: float = step_x(k)
		var last: bool = k == track_length
		_box(r, Vector3(1.3, 0.08, depth - 0.1), Vector3(x, 0.06, 0), Palette.VIP_GOLD if last else Palette.WARM_GOLD, 0.75)
		_box(r, Vector3(1.1, 0.085, depth - 0.3), Vector3(x, 0.062, 0), (Palette.VIP_GOLD if last else Palette.WARM_GOLD).darkened(0.18), 0.6)
		for s: float in [-1.0, 1.0]:
			_bulb(r, Vector3(x - 0.55, 0.16, s * (front - 0.12)), bulb_mat)
			_bulb(r, Vector3(x + 0.55, 0.16, s * (front - 0.12)), bulb_mat)
		if not last:
			_floor_text(r, str(k), Vector3(x, 0.07, front + 0.75), 190, Palette.VIP_GOLD)
	_build_cashier(r, step_x(track_length) + 1.35, depth)
	# Footlights along the stage lip.
	for i: int in 24:
		_bulb(r, Vector3(-11.0 + float(i) * 0.95, 0.08, front + 2.3), bulb_mat)


func _build_cashier(r: Node3D, x: float, depth: float) -> void:
	var w: float = maxf(depth + 0.6, 2.6)
	var booth := Node3D.new()
	booth.name = "Cashier"
	booth.position = Vector3(x, 0, 0)
	r.add_child(booth)
	_box(booth, Vector3(1.0, 2.4, w), Vector3(0.3, 1.2, 0), Color("#3A1A16"))  # wood body
	_box(booth, Vector3(1.06, 0.12, w + 0.06), Vector3(0.3, 2.44, 0), Palette.WARM_GOLD, 0.7)
	_box(booth, Vector3(1.06, 0.12, w + 0.06), Vector3(0.3, 0.06, 0), Palette.WARM_GOLD, 0.7)
	# The window: a warm glowing pane behind a brass grille, a counter ledge in front.
	_cashier_glow = _mat(Color("#FFCF7A"), 0.0, 0.35)
	var pane := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.04, 1.0, w - 0.6)
	pane.mesh = pm
	pane.position = Vector3(-0.22, 1.45, 0)
	pane.material_override = _cashier_glow
	booth.add_child(pane)
	var bars: int = int((w - 0.6) / 0.22)
	for i: int in bars + 1:
		var z: float = -((w - 0.6) * 0.5) + float(i) * (w - 0.6) / float(bars)
		_cyl(booth, 0.025, 1.0, Vector3(-0.27, 1.45, z), Palette.WARM_GOLD)
	for y: float in [0.95, 1.95]:
		_box(booth, Vector3(0.08, 0.08, w - 0.5), Vector3(-0.27, y, 0), Palette.WARM_GOLD, 0.75)
	_box(booth, Vector3(0.45, 0.07, w - 0.4), Vector3(-0.35, 0.9, 0), Palette.VIP_GOLD, 0.75)
	_cashier_light = OmniLight3D.new()
	_cashier_light.position = Vector3(-0.9, 1.8, 0)
	_cashier_light.omni_range = 4.5
	_cashier_light.light_color = WARM_LIGHT
	_cashier_light.light_energy = 0.6
	booth.add_child(_cashier_light)
	# The sign over it, turned to the audience: CASHIER in gold, a big "$", a frame of bulbs.
	var sign := Node3D.new()
	sign.name = "Sign"
	sign.position = Vector3(-0.3, 2.95, 0.4)
	sign.rotation.y = -0.45
	booth.add_child(sign)
	_box(sign, Vector3(3.0, 1.15, 0.12), Vector3.ZERO, Palette.VIP_BURGUNDY.darkened(0.2))
	_box(sign, Vector3(3.14, 1.29, 0.08), Vector3(0, 0, -0.04), Palette.WARM_GOLD, 0.7)
	var title := Label3D.new()
	title.text = "CASHIER"
	title.font = FONT
	title.font_size = 150
	title.pixel_size = 0.005
	title.modulate = Palette.VIP_GOLD
	title.outline_size = 0
	title.position = Vector3(0.25, 0, 0.07)
	sign.add_child(title)
	var dollar := Label3D.new()
	dollar.text = "$"
	dollar.font = FONT
	dollar.font_size = 170
	dollar.pixel_size = 0.005
	dollar.modulate = Palette.CREAM
	dollar.outline_size = 0
	dollar.position = Vector3(-1.15, 0, 0.07)
	sign.add_child(dollar)
	_sign_bulbs = _mat(BULB, 0.0, 1.0)
	for i: int in 12:
		var t: float = float(i) / 11.0
		_bulb(sign, Vector3(lerpf(-1.45, 1.45, t), 0.62, 0.08), _sign_bulbs)
		_bulb(sign, Vector3(lerpf(-1.45, 1.45, t), -0.62, 0.08), _sign_bulbs)
	# Coins that pour out of the window when someone gets there.
	_coins = CPUParticles3D.new()
	_coins.name = "Coins"
	_coins.position = Vector3(-0.5, 1.9, 0)
	_coins.emitting = false
	_coins.one_shot = true
	_coins.amount = 70
	_coins.lifetime = 1.6
	_coins.explosiveness = 0.55
	_coins.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_coins.emission_box_extents = Vector3(0.1, 0.2, (w - 0.8) * 0.5)
	_coins.direction = Vector3(-1, 0.6, 0)
	_coins.spread = 35.0
	_coins.initial_velocity_min = 2.0
	_coins.initial_velocity_max = 4.0
	_coins.gravity = Vector3(0, -9.0, 0)
	_coins.angular_velocity_min = -400.0
	_coins.angular_velocity_max = 400.0
	var coin := CylinderMesh.new()
	coin.top_radius = 0.07
	coin.bottom_radius = 0.07
	coin.height = 0.02
	coin.radial_segments = 10
	coin.material = _mat(Palette.VIP_GOLD, 0.8, 0.4)
	_coins.mesh = coin
	booth.add_child(_coins)


func _build_bench_couch() -> void:
	_bench_root.position = Vector3(X0 - 3.6, 0, 2.8)
	_bench_root.rotation.y = 0.35
	var couch := Node3D.new()
	couch.name = "Couch"
	_bench_root.add_child(couch)
	_box(couch, Vector3(3.4, 0.45, 0.8), Vector3(0, 0.22, 0), Palette.VIP_BURGUNDY)
	_box(couch, Vector3(3.4, 0.7, 0.22), Vector3(0, 0.6, -0.42), Palette.VIP_BURGUNDY.darkened(0.15))
	for s: float in [-1.0, 1.0]:
		_box(couch, Vector3(0.22, 0.6, 0.85), Vector3(s * 1.8, 0.35, 0), Palette.VIP_BURGUNDY.darkened(0.1))
	_box(couch, Vector3(3.6, 0.05, 0.9), Vector3(0, 0.02, 0), Palette.WARM_GOLD, 0.7)
	_floor_text(couch, "OUT OF THE RACE", Vector3(0, 0.05, 0.75), 60, Color(Palette.CREAM, 0.7))
	_bench_root.visible = false


func _build_lights() -> void:
	var key := SpotLight3D.new()
	key.name = "Key"
	key.position = Vector3(-1.0, 10.0, 8.0)
	key.spot_range = 24.0
	key.spot_angle = 42.0
	key.light_energy = 2.4
	key.light_color = WARM_LIGHT
	key.shadow_enabled = true
	add_child(key)
	key.look_at_from_position(key.position, Vector3(0.5, 0, 0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-4.0, 4.0, 5.0)
	fill.omni_range = 14.0
	fill.light_energy = 0.9
	fill.light_color = Palette.VIP_GOLD
	add_child(fill)
	var wash := SpotLight3D.new()
	wash.position = Vector3(0, 1.0, 6.0)
	wash.spot_range = 18.0
	wash.spot_angle = 50.0
	wash.light_energy = 1.0
	wash.light_color = Palette.VIP_GOLD
	add_child(wash)
	wash.look_at_from_position(wash.position, Vector3(0, 4.5, -6.0), Vector3.UP)
	var cash := SpotLight3D.new()
	cash.position = Vector3(3.0, 8.0, 5.0)
	cash.spot_range = 16.0
	cash.spot_angle = 22.0
	cash.light_energy = 2.0
	cash.light_color = WARM_LIGHT
	add_child(cash)
	cash.look_at_from_position(cash.position, Vector3(step_x(track_length) + 1.0, 1.5, 0), Vector3.UP)


func _burst(at: Vector3, big: bool) -> void:
	var fx := CPUParticles3D.new()
	fx.position = at
	fx.one_shot = true
	fx.amount = 40 if big else 18
	fx.lifetime = 0.7
	fx.explosiveness = 0.95
	fx.direction = Vector3.UP
	fx.spread = 70.0
	fx.initial_velocity_min = 1.5
	fx.initial_velocity_max = 3.2
	fx.gravity = Vector3(0, -5.0, 0)
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.2
	var m := BoxMesh.new()
	m.size = Vector3(0.06, 0.06, 0.06)
	m.material = _mat(Palette.VIP_GOLD, 0.5, 2.0)
	fx.mesh = m
	add_child(fx)
	fx.emitting = true
	get_tree().create_timer(1.2).timeout.connect(fx.queue_free)


# --- Mesh helpers ------------------------------------------------------------------------------

func _mat(c: Color, metallic: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s/%s/%s" % [c.to_html(), metallic, glow]
	if _mats.has(key) and glow == 0.0:
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.4 if metallic > 0.0 else 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	if glow == 0.0:
		_mats[key] = m
	return m


func _box(parent: Node, sz: Vector3, pos: Vector3, c: Color, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c, metallic)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node, radius: float, height: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(c, 0.75)
	parent.add_child(mi)
	return mi


func _bulb(parent: Node, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _stanchion(parent: Node, pos: Vector3) -> void:
	_cyl(parent, 0.04, 0.7, pos + Vector3(0, 0.35, 0), Palette.WARM_GOLD)
	_cyl(parent, 0.13, 0.04, pos + Vector3(0, 0.02, 0), Palette.WARM_GOLD)
	var top := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	top.mesh = sm
	top.position = pos + Vector3(0, 0.72, 0)
	top.material_override = _mat(Palette.VIP_GOLD, 0.8)
	parent.add_child(top)


## A velvet rope from `a` to `b`, sagging a little in the middle.
func _rope(parent: Node, a: Vector3, b: Vector3) -> void:
	var sag := Vector3(0, -0.14, 0)
	var segs: int = 6
	var mat: StandardMaterial3D = _mat(Palette.VIP_BURGUNDY.lightened(0.05))
	for i: int in segs:
		var t0: float = float(i) / float(segs)
		var t1: float = float(i + 1) / float(segs)
		var p0: Vector3 = a.lerp(b, t0) + sag * sin(t0 * PI)
		var p1: Vector3 = a.lerp(b, t1) + sag * sin(t1 * PI)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = p0.distance_to(p1) + 0.02
		cm.radial_segments = 6
		mi.mesh = cm
		mi.material_override = mat
		mi.position = (p0 + p1) * 0.5
		mi.basis = _basis_up(p1 - p0)
		parent.add_child(mi)


## Lettering lying on the floor, tipped up a little towards the audience.
func _floor_text(parent: Node, text: String, pos: Vector3, size_px: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = size_px
	l.pixel_size = 0.005
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.rotation.x = -PI * 0.5 + 0.35
	parent.add_child(l)
	return l
