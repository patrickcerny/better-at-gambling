class_name LeaderCrown
extends Node3D
## A gold crown floating over whoever has the most money (everyone sees it). The leader comes from
## the balances the client already mirrors; on a tie nobody wears it. It glides from head to head
## when the lead changes, bobs and turns slowly, and follows a ragdoll's head while its wearer
## flies. Headless the leader and position are still tracked (tests), but no mesh is built.

## Height of the crown above the bean's feet, and above a ragdoll's head.
const HEIGHT: float = 2.35
const RAGDOLL_HEAD_OFFSET: float = 0.75
const GLIDE: float = 9.0

## Player id wearing the crown (-1 = nobody).
var leader_id: int = -1

var _model: Node3D
var _t: float = 0.0
var _pop: float = 1.0
var _headless: bool = false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	visible = false
	if not _headless:
		_model = build_model()
		add_child(_model)


## Richest player by balance, or -1 when nobody is strictly ahead (tie, or no balances).
static func leader_of(balances: Dictionary) -> int:
	var best: int = -1
	var best_money: int = -1
	var tied: bool = false
	for pid: Variant in balances:
		var m: int = int(balances[pid])
		if m > best_money:
			best = int(pid)
			best_money = m
			tied = false
		elif m == best_money:
			tied = true
	return -1 if tied else best


## Call every frame with the mirrored balances and the scene's avatars.
func track(balances: Dictionary, avatars: Dictionary) -> void:
	var lead: int = leader_of(balances)
	var a: PlayerAvatar = avatars.get(lead, null) as PlayerAvatar
	var shown: bool = a != null and is_instance_valid(a) and a.is_visible_in_tree() and a.state != PlayerAvatar.State.AWAY
	if not shown:
		leader_id = -1 if a == null else lead
		visible = false
		return
	var target: Vector3 = anchor_for(a)
	if lead != leader_id or not visible:
		# New leader (or back in view): appear there with a little pop instead of flying across.
		if not visible or leader_id == -1:
			global_position = target
		_pop = 0.0
		leader_id = lead
	visible = true
	var dt: float = get_process_delta_time()
	global_position = global_position.lerp(target, minf(1.0, GLIDE * dt))
	if _model != null:
		_t += dt
		_pop = minf(1.0, _pop + dt * 3.0)
		var s: float = 1.0 + sin(_pop * PI) * 0.35
		_model.scale = Vector3.ONE * s
		_model.position.y = sin(_t * 2.4) * 0.06
		_model.rotation.y = _t * 1.1
		_model.rotation.z = sin(_t * 1.7) * 0.08


## Where the crown floats for `a`: over its head, or over its ragdoll's head while it flies.
static func anchor_for(a: PlayerAvatar) -> Vector3:
	if a.ragdoll != null and is_instance_valid(a.ragdoll) and a.ragdoll.head != null:
		return a.ragdoll.head.global_position + Vector3(0.0, RAGDOLL_HEAD_OFFSET, 0.0)
	return a.global_position + Vector3(0.0, HEIGHT, 0.0)


## Low-poly crown: a gold band with five points, ruby and emerald studs, tiny pearls on the tips.
static func build_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Crown"
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Palette.VIP_GOLD
	gold.metallic = 0.85
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Palette.WARM_GOLD
	gold.emission_energy_multiplier = 0.35
	var band := MeshInstance3D.new()
	band.name = "Band"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.23
	bm.bottom_radius = 0.2
	bm.height = 0.12
	bm.radial_segments = 10
	bm.rings = 1
	band.mesh = bm
	band.material_override = gold
	root.add_child(band)
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.07
	spike.height = 0.2
	spike.radial_segments = 4
	spike.rings = 1
	var pearl := SphereMesh.new()
	pearl.radius = 0.03
	pearl.height = 0.06
	pearl.radial_segments = 8
	pearl.rings = 4
	var gem := SphereMesh.new()
	gem.radius = 0.035
	gem.height = 0.07
	gem.radial_segments = 6
	gem.rings = 3
	var ruby: StandardMaterial3D = GreyboxKit.material(Palette.CASINO_RED, 0.2, 0.25)
	var emerald: StandardMaterial3D = GreyboxKit.material(Palette.MONEY_GREEN, 0.2, 0.25)
	var cream: StandardMaterial3D = GreyboxKit.material(Palette.CREAM, 0.0, 0.4)
	for i: int in 5:
		var a: float = i * TAU / 5.0
		var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var s := MeshInstance3D.new()
		s.mesh = spike
		s.material_override = gold
		s.position = dir * 0.19 + Vector3(0, 0.15, 0)
		s.rotation.y = -a
		root.add_child(s)
		var p := MeshInstance3D.new()
		p.mesh = pearl
		p.material_override = cream
		p.position = dir * 0.19 + Vector3(0, 0.26, 0)
		root.add_child(p)
		var g := MeshInstance3D.new()
		g.mesh = gem
		g.material_override = ruby if i % 2 == 0 else emerald
		var ga: float = a + TAU / 10.0
		g.position = Vector3(cos(ga), 0.0, sin(ga)) * 0.225
		root.add_child(g)
	for c: Node in root.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root
