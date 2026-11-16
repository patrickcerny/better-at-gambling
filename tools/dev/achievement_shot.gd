extends Node3D
## Dev: close look-dev sheets of the achievement rewards (`AchievementMeshes`), one bean per piece
## in a grid, each labelled with its name and the achievement that unlocks it. Run with
## scripts/screenshot.sh res://tools/dev/achievement_shot.tscn <name> 40 --ids a,b,c [--cols 4]
## [--yaw 25] [--back] [--walk]. Colours and skins work too (the bean wears them).

## Achievements still on other branches.
const PENDING: Dictionary = {&"ACH_BJ_SUITED_TRIPS": "Suited Trips", &"ACH_HOLDEM_ROYAL_FLUSH": "Royal Flush"}

var _beans: Array[AvatarVisuals] = []
var _walk: bool = false
var _t: float = 0.0


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_walk = c.has_flag("walk")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.WARM_CHARCOAL
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.shadow_enabled = true
	add_child(sun)
	var ids: PackedStringArray = c.get_string("ids", "").split(",", false)
	var back_ids: PackedStringArray = c.get_string("back-ids", "").split(",", false)
	var cols: int = mini(c.get_int("cols", 4), ids.size())
	var rows: int = ceili(ids.size() / float(cols))
	var yaw: float = deg_to_rad(c.get_float("yaw", 25.0))
	const DX: float = 1.7
	const DY: float = 2.75
	for i: int in ids.size():
		var d: CosmeticDef = CosmeticShop.default().find(StringName(ids[i]))
		if d == null:
			push_error("unknown id %s" % ids[i])
			continue
		var cell := Vector3((i % cols - (cols - 1) * 0.5) * DX, -(i / cols) * DY, 0)
		var floor_mi := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.65
		disc.bottom_radius = 0.65
		disc.height = 0.04
		floor_mi.mesh = disc
		floor_mi.material_override = GreyboxKit.material(Palette.FELT_GREEN)
		floor_mi.position = cell + Vector3(0, -0.02, 0)
		add_child(floor_mi)
		var v := AvatarVisuals.new()
		v.position = cell
		v.rotation.y = PI + (PI if c.has_flag("back") or ids[i] in back_ids else 0.0) + yaw
		add_child(v)
		if d.kind == CosmeticDef.KIND_COLOR:
			v.set_color(Palette.player_color(d.color_index))
		else:
			v.set_color(Palette.player_color([0, 4, 8, 11, 17, 19, 16, 5][i % 8]))
			v.set_outfit({d.kind: d.id})
		_beans.append(v)
		var tag := Label3D.new()
		tag.text = "%s\n%s" % [d.display_name, Achievements.DEFS.get(d.achievement, [PENDING.get(d.achievement, String(d.achievement))])[0]]
		tag.font_size = 34
		tag.outline_size = 10
		tag.pixel_size = 0.0045
		tag.position = cell + Vector3(0, -0.3, 0.75)
		tag.modulate = Palette.CREAM
		add_child(tag)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var w: float = cols * DX
	var h: float = rows * DY
	cam.size = maxf(h + 0.2, w * 1080.0 / 1920.0 + 0.2)
	var mid: float = 0.75 - (rows - 1) * DY * 0.5
	cam.position = Vector3(0, mid + 2.2, 8.0)
	cam.look_at(Vector3(0, mid, 0))


func _process(delta: float) -> void:
	_t += delta
	if not _walk:
		return
	for v: AvatarVisuals in _beans:
		var vel: Vector3 = -v.global_basis.z * 3.0 * maxf(cos(_t * 2.2), 0.0)
		v.update_motion(vel, true, minf(delta, 1.0 / 30.0))
