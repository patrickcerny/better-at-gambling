extends Node3D
## Dev: look-dev shots of the outfit pieces (`OutfitMeshes`). Run with
## scripts/screenshot.sh res://tools/dev/outfit_shot.tscn <name> 60 --kind <kind> [--back] [--walk]
## `--kind hat|shirt|pants|cape|boots`: all 15 of one kind, a bean each (3 rows of 5);
## `--kind sets`: the shop's packs (whole outfits), `--only a,b` just those; `--back` turns the beans round (capes), `--walk` makes them
## run in place (cape sway, boots), `--low` a low camera close to the feet.

var _beans: Array[AvatarVisuals] = []
var _walk: bool = false
var _t: float = 0.0


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var kind: String = c.get_string("kind", "sets")
	_walk = c.has_flag("walk")
	var back: bool = c.has_flag("back")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.WARM_CHARCOAL
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 20, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.shadow_enabled = true
	add_child(sun)
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	fm.mesh = plane
	fm.material_override = GreyboxKit.material(Palette.FELT_GREEN)
	add_child(fm)
	var looks: Array[Dictionary] = []
	if kind == "sets":
		var only: PackedStringArray = c.get_string("only", "").split(",", false)
		for pack: CosmeticPack in CosmeticShop.default().packs:
			if only.is_empty() or String(pack.id).trim_prefix("pack_") in only:
				var o: Dictionary = CosmeticsPanel.pack_outfit(pack)
				o[&"_name"] = pack.display_name
				looks.append(o)
	else:
		for d: CosmeticDef in CosmeticShop.default().of_kind(StringName(kind)):
			looks.append({StringName(kind): d.id, &"_name": d.display_name})
	var cols: int = mini(c.get_int("cols", 5), looks.size())
	for i: int in looks.size():
		var v := AvatarVisuals.new()
		var row: int = i / cols
		var col: int = i % cols
		v.position = Vector3((col - (cols - 1) * 0.5) * 1.5, 0, -row * 2.2)
		v.rotation.y = (0.0 if back else PI) + (PI * 0.5 if c.has_flag("side") else 0.0)
		add_child(v)
		v.set_color(Palette.player_color((i * 3) % Cosmetics.COLOR_COUNT))
		v.set_outfit(looks[i])
		_beans.append(v)
		var tag := Label3D.new()
		tag.text = str(looks[i].get(&"_name", ""))
		tag.font_size = 28
		tag.pixel_size = 0.005
		tag.position = v.position + Vector3(0, 0.02, 0.85)
		tag.rotation = Vector3(-PI * 0.5, 0.0, 0)
		tag.modulate = Palette.CREAM
		add_child(tag)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40
	var rows: int = ceili(looks.size() / float(cols))
	var z: float = (6.2 + rows * 0.9) * c.get_float("zoom", 1.0)
	if c.has_flag("low"):
		cam.position = Vector3(0, 0.9, z * 0.6)
		cam.look_at(Vector3(0, 0.35, -(rows - 1) * 1.1))
	else:
		cam.position = Vector3(0, 3.4 * c.get_float("zoom", 1.0), z)
		cam.look_at(Vector3(0, 0.6, -(rows - 1) * 1.1))


func _process(delta: float) -> void:
	_t += delta
	if not _walk:
		return
	for v: AvatarVisuals in _beans:
		# Run back and forth along the facing (the capes trail and swing).
		var vel: Vector3 = -v.global_basis.z * 4.5 * maxf(cos(_t * 2.2), 0.0)
		v.global_position += vel * minf(delta, 1.0 / 30.0)  # the bean animates at most 1/30 s a frame
		v.update_motion(vel, true, delta)
