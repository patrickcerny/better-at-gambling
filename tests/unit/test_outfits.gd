extends GutTest
## Outfits (Patrick: "Hats, Boots, Pants, Capes, shirts. Design for each 15"; later skins, eyes,
## mouths and beards): at least 15 pieces per clothing slot in the shop, each with a model
## (`OutfitMeshes`), worn from the profile, cleaned on the way in from the network, and put on /
## taken off the bean (`AvatarVisuals.wear`).

const CLOTHES: Array[StringName] = [CosmeticDef.KIND_HAT, CosmeticDef.KIND_SHIRT, CosmeticDef.KIND_PANTS, CosmeticDef.KIND_CAPE, CosmeticDef.KIND_BOOTS]
const EMPTY_WIRE: Array[String] = ["", "", "", "", "", "", "", "", ""]


func before_each() -> void:
	ProfileManager.reload()  # fresh, in memory under GUT


func after_each() -> void:
	AvatarVisuals.outfits_headless = false
	ProfileManager.reload()


func test_fifteen_pieces_per_slot_each_with_a_model() -> void:
	var shop: CosmeticShop = CosmeticShop.default()
	var ids: Array[StringName] = []
	for kind: StringName in CLOTHES:
		var items: Array[CosmeticDef] = shop.of_kind(kind)
		assert_gte(items.size(), 15, "15 or more %s" % kind)
		var free: int = 0
		for d: CosmeticDef in items:
			assert_true(String(d.id).begins_with(String(kind) + "_"), "%s is named after its slot" % d.id)
			assert_false(d.id in ids, "%s is listed once" % d.id)
			ids.append(d.id)
			assert_true(OutfitMeshes.has_model(d.id), "%s has a model" % d.id)
			assert_between(d.swatch.size(), 1, 3, "%s has a swatch" % d.id)
			assert_ne(d.display_name, "")
			if d.is_free():
				free += 1
		assert_eq(free, 2, "two free %s to start with" % kind)
	for kind: StringName in [CosmeticDef.KIND_SKIN, CosmeticDef.KIND_EYES, CosmeticDef.KIND_MOUTH, CosmeticDef.KIND_BEARD]:
		var items: Array[CosmeticDef] = shop.of_kind(kind)
		assert_gte(items.size(), 6, "a choice of %s" % kind)
		for d: CosmeticDef in items:
			assert_true(String(d.id).begins_with(String(kind) + "_"), "%s is named after its slot" % d.id)
			assert_false(d.id in ids, "%s is listed once" % d.id)
			ids.append(d.id)
			assert_false(d.is_free(), "%s is bought or unlocked" % d.id)
			assert_true(d.coin_buyable() or d.steam_buyable() or d.level > 0, "%s can be had somehow" % d.id)
	for d: CosmeticDef in shop.of_kind(CosmeticDef.KIND_BEARD):
		assert_true(OutfitMeshes.has_model(d.id), "%s has a model" % d.id)
	for d: CosmeticDef in shop.of_kind(CosmeticDef.KIND_SKIN):
		assert_not_null(ToonMaterial.make_skin(d.id), "%s has a skin shader" % d.id)
	assert_null(OutfitMeshes.mesh(&"hat_nope"))
	assert_true(OutfitMeshes.boot_meshes(&"boots_nope").is_empty())


func test_models_stay_light() -> void:
	# Pattern edges are cut exactly along the paint (OutfitMeshKit.surface), which costs triangles on
	# busy patterns (checks, plaid); 24k per piece keeps eight dressed beans comfortably light.
	var kinds: Array[StringName] = CLOTHES.duplicate()
	kinds.append(CosmeticDef.KIND_BEARD)
	for kind: StringName in kinds:
		for d: CosmeticDef in CosmeticShop.default().of_kind(kind):
			var m: ArrayMesh = OutfitMeshes.boot_meshes(d.id)[0] if kind == CosmeticDef.KIND_BOOTS else OutfitMeshes.mesh(d.id)
			assert_eq(m.get_surface_count(), 1, "%s is one draw call" % d.id)
			assert_lt(m.surface_get_array_index_len(0) / 3, 24000, "%s stays light" % d.id)


func test_sanitize_outfit_keeps_only_real_pieces_in_their_slots() -> void:
	assert_eq(Cosmetics.sanitize_outfit(null), PackedStringArray(EMPTY_WIRE))
	assert_eq(Cosmetics.sanitize_outfit({"hat": "hat_crown"}), PackedStringArray(EMPTY_WIRE), "a dictionary is not the wire form")
	assert_eq(Cosmetics.sanitize_outfit(["hat_crown", "pants_kilt", "pants_kilt", "cape_hero", "boots_gold", "skin_lava", "eyes_star", "mouth_gold", "beard_viking", "extra"]),
		PackedStringArray(["hat_crown", "", "pants_kilt", "cape_hero", "boots_gold", "skin_lava", "eyes_star", "mouth_gold", "beard_viking"]))
	assert_eq(Cosmetics.sanitize_outfit(["", "", "", "", "", "beard_viking", "", "", "skin_lava"]), PackedStringArray(EMPTY_WIRE), "each piece only in its own slot")
	assert_eq(Cosmetics.sanitize_outfit([[], 3.0, "color_mint"]), PackedStringArray(EMPTY_WIRE))
	assert_eq(Cosmetics.outfit_dict(["", "shirt_tux"]), {&"shirt": &"shirt_tux"})


func test_the_profile_wears_owned_pieces_and_remembers_them() -> void:
	var p: PlayerProfile = ProfileManager.profile
	assert_false(p.wear(&"hat_top"), "not bought yet")
	assert_true(p.wear(&"hat_party"), "free pieces are owned")
	p.coins = 5000
	assert_eq(p.buy(&"hat_top"), &"")
	assert_true(p.wear(&"hat_top"), "one hat at a time: the top hat replaces the party hat")
	assert_true(p.wear(&"cape_towel"))
	assert_false(p.wear(&"color_mint"), "colours are not outfit pieces")
	assert_eq(p.outfit_wire(), PackedStringArray(["hat_top", "", "", "cape_towel", "", "", "", "", ""]))
	var path: String = "user://test_outfit_profile.cfg"
	assert_eq(p.save(path), OK)
	var back := PlayerProfile.new()
	assert_eq(back.load_from(path), OK)
	assert_eq(back.outfit_wire(), p.outfit_wire(), "saved and loaded")
	# A hand-edited file can't wear what it doesn't own.
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(PlayerProfile.SECTION, "owned", PackedStringArray())
	cfg.set_value("outfit", "boots", "boots_party_hat")
	cfg.save(path)
	assert_eq(back.load_from(path), OK)
	assert_eq(back.outfit_wire(), PackedStringArray(["", "", "", "cape_towel", "", "", "", "", ""]), "only owned pieces stay on")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	p.take_off(&"hat")
	assert_false(p.is_worn(&"hat_top"))
	assert_eq(SceneRouter.profile_cosmetics()["outfit"], p.outfit_wire(), "the next join sends it")


func test_the_bean_puts_pieces_on_and_takes_them_off() -> void:
	AvatarVisuals.outfits_headless = true
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	var foot_meshes: Array[Mesh] = [v._legs[0].mesh, v._legs[1].mesh]
	v.set_outfit(Cosmetics.outfit_dict(["hat_viking", "shirt_police", "pants_jeans", "cape_hero", "boots_cowboy"]))
	assert_not_null(v.body.find_child("OutfitHat", false, false), "the hat rides the body")
	assert_not_null(v.body.find_child("OutfitShirt", false, false))
	assert_not_null(v.body.find_child("OutfitPants", false, false))
	assert_not_null(v.body.find_child("Cape", false, false), "the cape hangs on its hinge")
	for foot: MeshInstance3D in v._legs:
		assert_null(foot.mesh, "the boot replaces the foot")
		assert_not_null(foot.find_child("Boot", false, false))
	assert_ne(v._segments[0].material_override, v._body_mat, "police sleeves on the arms")
	v.wear(&"shirt", &"shirt_hawaiian")
	assert_eq(v.outfit[&"shirt"], &"shirt_hawaiian", "a new shirt replaces the old one")
	v.set_outfit({&"hat": &"hat_top"})
	await wait_process_frames(1)
	assert_eq(v.outfit, {&"hat": &"hat_top"} as Dictionary[StringName, StringName])
	assert_null(v.body.find_child("OutfitShirt", false, false), "everything else came off")
	assert_null(v.body.find_child("Cape", false, false))
	for i: int in 2:
		assert_eq(v._legs[i].mesh, foot_meshes[i], "bare feet again")
		assert_null(v._legs[i].find_child("Boot", false, false))
	assert_eq(v._segments[0].material_override, v._body_mat, "bare arms again")
	v.wear(&"hat", &"cape_hero")
	assert_false(v.outfit.has(&"hat"), "a cape is not a hat")
	var torso := Node3D.new()
	add_child_autofree(torso)
	assert_eq(AvatarVisuals.dress(torso, {&"hat": &"hat_top", &"boots": &"boots_gold", &"cape": &"cape_royal"}).size(), 2, "the ragdoll wears hat and cape (no feet to put boots on)")


func test_the_shop_sells_and_puts_on_outfit_pieces() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var panel := CosmeticsPanel.new()
	layer.add_child(panel)
	panel.open()
	for tab: String in ["COLOURS", "HATS", "SHIRTS", "TROUSERS", "CAPES", "BOOTS"]:
		assert_not_null(panel.find_child(tab, true, false), "a %s tab" % tab)
	var worn: Array = []
	panel.outfit_worn.connect(func(kind: StringName, id: StringName) -> void: worn.append([kind, id]))
	var top_hat: CosmeticDef = CosmeticShop.default().find(&"hat_top")
	ProfileManager.profile.coins = top_hat.price
	panel.select(&"hat_top")
	assert_eq(panel.preview.outfit.get(&"hat"), &"hat_top", "the preview tries it on")
	assert_string_contains(panel.action_button.text, "BUY")
	panel.action_button.pressed.emit()
	assert_true(ProfileManager.profile.owns(&"hat_top"))
	assert_eq(panel.action_button.text, "WEAR")
	panel.action_button.pressed.emit()
	assert_true(ProfileManager.profile.is_worn(&"hat_top"))
	assert_eq(worn, [[&"hat", &"hat_top"]])
	assert_eq((panel.tiles[&"hat_top"].find_child("Price", true, false) as Label).text, "WEARING")
	assert_eq(panel.action_button.text, "TAKE OFF")
	panel.action_button.pressed.emit()
	assert_false(ProfileManager.profile.is_worn(&"hat_top"))
	assert_eq(worn[-1], [&"hat", &""])


func test_capes_are_cloth_that_hangs_from_the_shoulders() -> void:
	var m: ArrayMesh = OutfitMeshes.mesh(&"cape_hero")
	var uv2: PackedVector2Array = m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	assert_eq(uv2.size(), (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "every vertex knows its place on the cloth")
	var mi := MeshInstance3D.new()
	mi.mesh = m
	add_child_autofree(mi)
	var mat := ShaderMaterial.new()
	mat.shader = ToonMaterial.CLOTH_SHADER
	var cloth := CapeCloth.new(&"cape_hero", mi, mat)
	for i: int in 30:
		mi.global_position += Vector3(0, 0, -0.15)  # running forward (-Z)
		cloth.step(1.0 / 60.0, -10.0)
	var disp: PackedVector3Array = mat.get_shader_parameter(&"cloth")
	assert_eq(disp.size(), CapeCloth.NU * CapeCloth.NV)
	for i: int in CapeCloth.NU:
		assert_eq(disp[i], Vector3.ZERO, "the top row stays on the shoulders")
	var hem: Vector3 = disp[disp.size() - 1 - CapeCloth.NU / 2]
	assert_gt(hem.z, 0.05, "the hem trails behind a running bean")
	for d: Vector3 in disp:
		assert_lt(d.length(), 1.5, "the cloth stays in one piece")
