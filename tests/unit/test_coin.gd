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
	assert_eq(pile._coins.size(), 0, "coins created by create_coins, not _ready")


func test_coin_pile_creates_coins() -> void:
	var pile := CoinPile.new()
	pile.amount = 100
	pile.position = Vector3(0, 0, 0)
	add_child_autofree(pile)
	pile.create_coins(Vector3(0, 1, 0))
	await wait_frames(2)
	var coin_count: int = clampi(100 / 25, 1, 6)
	assert_eq(pile._coins.size(), coin_count, "correct number of coins created")


func test_coin_pile_has_label() -> void:
	var pile := CoinPile.new()
	pile.amount = 250
	add_child_autofree(pile)
	var label: Label3D = pile._label as Label3D
	assert_not_null(label, "pile has label")
	assert_eq(label.text, "$250", "label shows correct amount")
