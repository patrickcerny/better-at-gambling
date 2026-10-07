extends GutTest
## Chips on the felt: one chip per table minimum, capped, a second column past the column height,
## and the owner's colour with a rim that reads on it.


func test_count_grows_linearly_with_the_bet() -> void:
	for k: int in range(1, ChipStack.MAX_CHIPS + 1):
		assert_eq(ChipStack.chip_count(10 * k, 10), k, "%d minimums = %d chips" % [k, k])
	assert_eq(ChipStack.chip_count(25, 25), 1)
	assert_eq(ChipStack.chip_count(100, 25), 4, "limits multiplier: the unit grows with the table minimum")
	assert_eq(ChipStack.chip_count(15, 10), 2, "a part minimum still shows a chip")


func test_count_caps_and_is_never_zero() -> void:
	assert_eq(ChipStack.chip_count(100000, 10), ChipStack.MAX_CHIPS)
	assert_eq(ChipStack.chip_count(0, 10), 1)
	assert_eq(ChipStack.chip_count(3, 10), 1)
	assert_eq(ChipStack.chip_count(-5, 10), 1)
	assert_gt(ChipStack.chip_count(50), 0, "no unit: the old size scale")
	assert_gt(ChipStack.chip_count(0), 0)


func test_past_a_column_a_second_column_not_a_taller_tower() -> void:
	assert_eq(ChipStack.columns(1), 1)
	assert_eq(ChipStack.columns(ChipStack.COLUMN_CHIPS), 1)
	assert_eq(ChipStack.columns(ChipStack.COLUMN_CHIPS + 1), 2)
	assert_eq(ChipStack.columns(ChipStack.MAX_CHIPS), 2)
	var s: ChipStack = ChipStack.make(1000, Palette.player_color(2), 10)
	add_child_autofree(s)
	assert_eq(s.get_child_count(), ChipStack.MAX_CHIPS)
	var top: float = 0.0
	for c: Node in s.get_children():
		top = maxf(top, (c as Node3D).position.y)
	assert_lt(top, ChipStack.CHIP_HEIGHT * ChipStack.COLUMN_CHIPS, "no taller than one column")


func test_player_colour_and_rim() -> void:
	var red: Color = Palette.CASINO_RED
	var s: ChipStack = ChipStack.make(30, red, 10)
	add_child_autofree(s)
	assert_eq(s.color, red)
	var mats: Array = ChipStack.materials_for(red)
	assert_eq((s.get_child(0) as MeshInstance3D).material_override, mats[0], "base colour = player colour")
	assert_eq((mats[2] as StandardMaterial3D).albedo_color, Palette.CREAM, "cream rim kept")
	assert_same(ChipStack.materials_for(red)[0], mats[0], "one material per colour")
	var light: Array = ChipStack.materials_for(Color("#F4F0E0"))
	assert_ne((light[2] as StandardMaterial3D).albedo_color, Palette.CREAM, "a light colour gets a dark rim")
	assert_lt((light[1] as StandardMaterial3D).albedo_color.get_luminance(), 0.6, "and a darker edge band")
	var house: ChipStack = ChipStack.make(30)
	add_child_autofree(house)
	assert_eq(house.color, ChipStack.tier_color(30), "house chips keep the size colours")
