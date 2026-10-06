class_name HitPop
extends RefCounted
## Contact feedback for shoves and throws: a quick white flash disc and a spray of cream/gold
## sparks where the hands land, plus a comic word on the hits that matter (knockdown, knockout).
## Every node frees itself; nothing is built when `Vfx.enabled()` is false.

const WORDS: Array[String] = ["BONK!", "POW!", "WHAM!", "OOF!"]
const LIFETIME: float = 0.45


## Pops at `pos` (world). `strength` 1 = a normal shove, 2 = knockdown/knockout (bigger, with a word).
static func at(parent: Node, pos: Vector3, strength: float = 1.0) -> Node3D:
	if not Vfx.enabled() or parent == null or not parent.is_inside_tree():
		return null
	var root := Node3D.new()
	root.name = "HitPop"
	parent.add_child(root)
	root.global_position = pos
	# Flash: an unshaded disc facing the camera that snaps open and fades.
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.5
	flash.mesh = quad
	var m: StandardMaterial3D = Vfx.glow_material(Color(1.0, 0.97, 0.85, 0.95), true)
	m.vertex_color_use_as_albedo = false
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = Vfx.soft_dot()
	flash.material_override = m
	flash.scale = Vector3.ONE * 0.3
	root.add_child(flash)
	var t: Tween = flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector3.ONE * (1.4 + 0.5 * strength), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, 0.2).set_delay(0.06)
	# Sparks.
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	var dot := QuadMesh.new()
	dot.size = Vector2.ONE * 0.09
	p.mesh = dot
	p.material_override = Vfx.glow_material(Color.WHITE, true, true)
	p.amount = int(10 * strength)
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5 + strength
	p.gravity = Vector3(0, -6.0, 0)
	p.damping_min = 4.0
	p.damping_max = 6.0
	var g := Gradient.new()
	g.set_color(0, Palette.CREAM)
	g.set_color(g.get_point_count() - 1, Color(Palette.VIP_GOLD, 0.0))
	p.color_ramp = g
	p.local_coords = false
	root.add_child(p)
	p.emitting = true
	if strength >= 1.5:
		Vfx.floating_text(parent, pos + Vector3(0.0, 0.35, 0.0), WORDS[randi() % WORDS.size()], Palette.VIP_GOLD, 80, 0.5, 0.7)
	Vfx.free_after(root, LIFETIME + 0.1)
	return root
