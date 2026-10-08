extends GutTest
## 3D title logo (Patrick, 0.8.15): it replaces the text logo in the main menu, goes through the
## pixel look there, hangs once above the casino entrance in place of the "LUCKY LOUNGE" signs,
## and the revolving door is gone.

var _old_force: bool


func before_each() -> void:
	_old_force = Vfx.force_enabled


func after_each() -> void:
	Vfx.force_enabled = _old_force


func test_model_has_the_four_logo_materials() -> void:
	var model: Node3D = Logo3D.build_model()
	add_child_autofree(model)
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1, "one mesh")
	if meshes.size() != 1:
		return
	var mi: MeshInstance3D = meshes[0]
	assert_eq(mi.mesh.get_surface_count(), 4, "letters, outline, banner, trim")
	for i in mi.mesh.get_surface_count():
		var m: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
		assert_not_null(m, "surface %d has the logo material" % i)
		if m != null:
			assert_true(m.vertex_color_use_as_albedo, "colours come from the mesh")
	var aabb: AABB = mi.get_aabb()
	assert_almost_eq(aabb.size.x, 13.6, 0.3, "about 13.6 m wide at full size")


func test_main_menu_uses_the_3d_logo() -> void:
	var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(2)
	var logo: Node = menu.get_node("Left/Column/Logo")
	assert_true(logo is Logo3DView, "the menu logo is the 3D view")
	assert_null(menu.find_child("Gambling", true, false), "the old text logo is gone")


func test_entrance_has_one_logo_and_no_revolving_door() -> void:
	Vfx.force_enabled = true
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	add_child_autofree(map)
	await wait_process_frames(2)
	assert_null(map.find_child("RevolvingDoor", true, false), "no revolving door")
	assert_false("revolving_door" in map, "no revolving door property left")
	var signs: Array[Node] = map.find_children("LogoSign", "", true, false)
	assert_eq(signs.size(), 1, "the logo hangs once")
	if signs.size() == 1:
		var p: Vector3 = (signs[0] as Node3D).global_position
		assert_almost_eq(p.x, 0.0, 0.01, "centred over the entrance")
		assert_gt(p.y, 3.2, "above the door opening")
		assert_gt(p.z, LuckyLounge.ENTRANCE_POS.z - 1.0, "on the entrance wall")
	for l: Node in map.find_children("*", "Label3D", true, false):
		assert_ne((l as Label3D).text, "LUCKY LOUNGE", "old name sign removed")
