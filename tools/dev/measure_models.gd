extends SceneTree
## Dev: prints the model-space bounds, mesh names and materials of the 3D models given as
## positional args (res:// paths), so placement code can scale and recolour them.
##   tools/godot/godot --headless --path . -s tools/dev/measure_models.gd -- res://assets/models/x.glb


func _initialize() -> void:
	for p: String in Cmdline.parse(OS.get_cmdline_user_args()).positional():
		var ps: PackedScene = load(p) as PackedScene
		if ps == null:
			print("%s: not loadable" % p)
			continue
		var m: Node3D = ps.instantiate()
		var acc: Array = []
		_collect(m, Transform3D.IDENTITY, acc)
		var aabb: AABB = acc[0] if not acc.is_empty() else AABB()
		for a: AABB in acc:
			aabb = aabb.merge(a)
		print("%s: pos=%s size=%s" % [p, aabb.position, aabb.size])
		for n: Node in m.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			var mats: Array = []
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				var desc: String = "none"
				if mat is BaseMaterial3D:
					desc = "%s albedo=%s tex=%s" % [mat.resource_name, (mat as BaseMaterial3D).albedo_color, (mat as BaseMaterial3D).albedo_texture != null]
				mats.append(desc)
			print("   mesh %s (%s) verts=%d mats=%s" % [mi.name, mi.get_parent().name, mi.mesh.get_faces().size(), mats])
		m.free()
	quit(0)


func _collect(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is Node3D:
		xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		acc.append(xf * (n as MeshInstance3D).mesh.get_aabb())
	for c: Node in n.get_children():
		_collect(c, xf, acc)
