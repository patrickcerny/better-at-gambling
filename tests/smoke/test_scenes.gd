extends GutTest
## Instantiates every project scene (outside addons/ and the dev screenshot rigs in tools/dev/)
## and runs a few frames, so broken references and script errors in `_ready` fail the suite
## (scripts/test.sh also fails the run on any engine error printed while they run).

const SKIP_DIRS: Array[String] = ["res://addons", "res://.godot", "res://tools/dev", "res://tools/godot", "res://tools/.cache", "res://build"]
const FRAMES: int = 10
## Scenes that must be found, so a broken walk can't pass by finding nothing.
const MUST_FIND: Array[String] = [
	"res://ui/menus/main_menu.tscn", "res://match/match_scene.tscn", "res://maps/lucky_lounge/lucky_lounge.tscn",
	"res://ui/hud/hud.tscn", "res://ui/stations/blackjack_ui.tscn", "res://player/player_avatar.tscn",
]


func after_each() -> void:
	Vfx.force_enabled = false


func test_every_scene_instantiates() -> void:
	var scenes: Array[String] = all_scenes()
	for must: String in MUST_FIND:
		assert_has(scenes, must, "scene walk found %s" % must)
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		assert_not_null(packed, "load %s" % path)
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		assert_not_null(node, "instantiate %s" % path)
		if node == null:
			continue
		add_child_autofree(node)
		await wait_physics_frames(FRAMES)
		assert_true(is_instance_valid(node) and node.is_inside_tree(), "%s still alive after %d frames" % [path, FRAMES])
		node.queue_free()
		await wait_process_frames(1)
	gut.p("instantiated %d scenes" % scenes.size())


## The client-only art pass builds when effects are on (a real display) and never on a headless
## server, and the map works either way.
func test_lounge_decor_is_client_only() -> void:
	var server_map := LuckyLounge.new()
	server_map.bake_navmesh = false
	add_child_autofree(server_map)
	await wait_process_frames(2)
	assert_null(server_map.get_node_or_null("Decor"), "no decor on the headless server")
	Vfx.force_enabled = true
	var client_map := LuckyLounge.new()
	client_map.bake_navmesh = false
	add_child_autofree(client_map)
	await wait_process_frames(2)
	var decor: Node = client_map.get_node_or_null("Decor")
	assert_not_null(decor, "decor on a client")
	if decor == null:
		return
	var instances: int = 0
	for c: Node in decor.get_children():
		if c is MultiMeshInstance3D:
			instances += (c as MultiMeshInstance3D).multimesh.instance_count
		assert_false(c is CollisionObject3D, "decor never collides (%s)" % c.name)
	assert_gt(instances, 200, "chandeliers, panels and bulbs are batched")
	assert_lt(decor.get_child_count(), 40, "a handful of draw calls, not one per piece")
	assert_true((client_map.get_node("Carpet") as MeshInstance3D).material_override is ShaderMaterial, "patterned carpet")


## Beans get the toon material on clients and a plain material on the server.
func test_toon_material_client_only() -> void:
	assert_true(ToonMaterial.make(Palette.CASINO_RED) is StandardMaterial3D, "plain material headless")
	Vfx.force_enabled = true
	var m: Material = ToonMaterial.make(Palette.CASINO_RED)
	assert_true(m is ShaderMaterial, "toon material on a client")
	ToonMaterial.set_color(m, Palette.FELT_GREEN)
	assert_eq((m as ShaderMaterial).get_shader_parameter(&"albedo"), Palette.FELT_GREEN)


static func all_scenes() -> Array[String]:
	var out: Array[String] = []
	_collect("res://", out)
	out.sort()
	return out


static func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path.trim_suffix("/") in SKIP_DIRS:
		return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))
