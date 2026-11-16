extends GutTest
## Basic tests for Coin visual system (0.8.5+)


func test_coin_renders() -> void:
	var coin := Coin.new()
	add_child_autofree(coin)
	assert_eq(coin.get_child_count(), 1, "coin has mesh instance")
	var mesh_inst: MeshInstance3D = coin.get_child(0) as MeshInstance3D
	assert_not_null(mesh_inst, "first child is mesh instance")
	assert_not_null(mesh_inst.mesh, "mesh instance has mesh")
	assert_is(mesh_inst.mesh, CylinderMesh, "mesh is cylinder")


func test_coin_physics() -> void:
	var coin := Coin.new()
	coin.position = Vector3(0, 2, 0)
	add_child_autofree(coin)
	var initial_y: float = coin.position.y
	coin.burst(Vector3.ZERO, Vector3.ZERO)
	await wait_frames(5)
	assert_lt(coin.position.y, initial_y, "coin falls with gravity")


func test_coin_bounce() -> void:
	var coin := Coin.new()
	coin.position = Vector3(0, 0.5, 0)
	add_child_autofree(coin)
	coin.burst(Vector3.ZERO, Vector3.ZERO)
	await wait_frames(10)
	assert_gte(coin.position.y, 0.0, "coin stays above ground (bouncing)")


func test_coin_pile_creation() -> void:
	var pile := CoinPile.new()
	pile.amount = 100
	add_child_autofree(pile)
	assert_eq(pile.amount, 100)
	assert_eq(pile._chips.size(), 0, "chips made by spawn_chips, not _ready")


func test_coin_pile_spawns_big_hovering_chips() -> void:
	var pile := CoinPile.new()
	pile.amount = 100
	add_child_autofree(pile)
	pile.spawn_chips(pile.global_position)
	await wait_frames(2)
	assert_eq(pile._chips.size(), CoinPile.chip_count(100), "one chip per $50")
	assert_gt(pile._carousel.position.y, 0.3, "the chips hover above the carpet")
	var mi: MeshInstance3D = pile._chips[0].get_node("Mesh") as MeshInstance3D
	assert_gt(mi.scale.x, 0.1, "big enough to spot across the room")
	assert_not_null(mi.material_overlay, "with a warm rim glow")


func test_chip_count_is_capped() -> void:
	assert_eq(CoinPile.chip_count(10), 1, "always at least one chip")
	assert_eq(CoinPile.chip_count(100000), CoinPile.MAX_CHIPS)


func test_hovering_chips_turn_and_bob() -> void:
	var pile := CoinPile.new()
	pile.amount = 200
	add_child_autofree(pile)
	pile.spawn_chips(pile.global_position)
	var yaw: float = pile._chips[0].rotation.y
	var spin: float = pile._carousel.rotation.y
	await wait_frames(10)
	assert_ne(pile._chips[0].rotation.y, yaw, "each chip turns")
	assert_ne(pile._carousel.rotation.y, spin, "the chips circle the pile")


func test_shaken_chips_arc_out_then_hover() -> void:
	Vfx.force_enabled = true
	var pile := CoinPile.new()
	pile.amount = 150
	add_child_autofree(pile)
	pile.spawn_chips(pile.global_position + Vector3(1.0, 1.0, 0.0))
	assert_false(pile._hovering, "still flying out of the victim")
	await wait_seconds(CoinPile.SETTLE_SECONDS + 0.1)
	Vfx.force_enabled = false
	assert_true(pile._hovering, "landed: hovering over the carpet")
	assert_almost_eq(pile._carousel.position.y, CoinPile.HOVER_HEIGHT, CoinPile.BOB_HEIGHT + 0.01)


func test_restore_brings_a_predicted_pile_back() -> void:
	var pile := CoinPile.new()
	pile.amount = 60
	add_child_autofree(pile)
	pile.spawn_chips(pile.global_position)
	pile.fly_to(null, true)
	assert_true(pile.is_leaving())
	pile.restore()
	assert_false(pile.is_leaving())
	assert_true(pile.visible)


func test_coin_pile_has_label() -> void:
	var pile := CoinPile.new()
	pile.amount = 250
	add_child_autofree(pile)
	var label: Label3D = pile._label as Label3D
	assert_not_null(label, "pile has label")
	assert_eq(label.text, "$250", "label shows correct amount")
