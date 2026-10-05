class_name WinFx
extends RefCounted
## Win / lose / jackpot feedback in the world: floating "+$120" / "-$50" deltas, a coin burst on
## wins, a big gold burst with a flash on big wins and jackpots, a small sad puff on losses.
## Every node frees itself when done; nothing is built when `Vfx.enabled()` is false.

const COIN_LIFETIME: float = 1.3
const PUFF_LIFETIME: float = 1.1


## Floating money delta in Money Green / Loss Red (`big` = larger and higher).
static func money_delta(parent: Node, pos: Vector3, amount: int, big: bool = false) -> Label3D:
	if amount == 0:
		return null
	var text: String = ("+$%s" if amount > 0 else "-$%s") % thousands(absi(amount))
	return Vfx.floating_text(parent, pos, text, Palette.delta_color(amount), 140 if big else 96, 1.4 if big else 0.9, 1.8 if big else 1.4)


## A fountain of gold coins (`count` coins, `speed` m/s upwards).
static func coin_burst(parent: Node, pos: Vector3, count: int = 18, speed: float = 3.2) -> CPUParticles3D:
	if not Vfx.enabled() or parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.name = "CoinBurst"
	var coin := CylinderMesh.new()
	coin.top_radius = 0.035
	coin.bottom_radius = 0.035
	coin.height = 0.01
	coin.radial_segments = 12
	coin.rings = 1
	coin.material = GreyboxKit.material(Palette.VIP_GOLD, 0.85, 0.3)
	p.mesh = coin
	p.amount = count
	p.lifetime = COIN_LIFETIME
	p.one_shot = true
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = speed * 0.55
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.2
	p.local_coords = false
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	Vfx.free_after(p, COIN_LIFETIME + 0.3)
	return p


## Gold sparkles (additive billboards) for big moments.
static func sparkles(parent: Node, pos: Vector3, count: int = 40, speed: float = 4.0) -> CPUParticles3D:
	if not Vfx.enabled() or parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.name = "Sparkles"
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	q.material = Vfx.glow_material(Color.WHITE, true, true)
	p.mesh = q
	p.amount = count
	p.lifetime = 1.0
	p.one_shot = true
	p.explosiveness = 0.85
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.86, 0.45, 1.0))
	ramp.set_color(1, Color(Palette.WARM_GOLD, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	Vfx.free_after(p, 1.3)
	return p


## Big win / jackpot: a heavy coin fountain, sparkles and a warm flash of light.
static func gold_burst(parent: Node, pos: Vector3, scale: float = 1.0) -> Node3D:
	if not Vfx.enabled() or parent == null or not parent.is_inside_tree():
		return null
	var root := Node3D.new()
	root.name = "GoldBurst"
	parent.add_child(root)
	root.global_position = pos
	coin_burst(root, pos, int(48 * scale), 4.5 * sqrt(scale))
	sparkles(root, pos + Vector3(0, 0.3, 0), int(50 * scale), 4.0 * sqrt(scale))
	var flash := OmniLight3D.new()
	flash.light_color = Palette.VIP_GOLD
	flash.light_energy = 5.0 * scale
	flash.omni_range = 5.0
	root.add_child(flash)
	var t: Tween = flash.create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.6).set_ease(Tween.EASE_OUT)
	Vfx.free_after(root, COIN_LIFETIME + 0.5)
	return root


## Loss: a small grey puff that drifts up and fades.
static func sad_puff(parent: Node, pos: Vector3) -> CPUParticles3D:
	if not Vfx.enabled() or parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.name = "SadPuff"
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	s.radial_segments = 8
	s.rings = 4
	s.material = Vfx.glow_material()
	p.mesh = s
	p.amount = 7
	p.lifetime = PUFF_LIFETIME
	p.one_shot = true
	p.explosiveness = 0.8
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.55
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 0.4
	p.damping_max = 0.8
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.6, 0.58, 0.55))
	ramp.set_color(1, Color(0.4, 0.38, 0.38, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	Vfx.free_after(p, PUFF_LIFETIME + 0.3)
	return p


## True when a win is "big" (gold burst, shake, hit-stop): five times the stake or $1,000+.
static func is_big_win(net: int, stake: int) -> bool:
	return net > 0 and (net >= stake * 5 or net >= 1000)


static func thousands(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
