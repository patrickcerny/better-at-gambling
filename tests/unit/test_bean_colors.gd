extends GutTest
## Bean colours (Patrick: "If you choose that, your bean is in that color. Remove all other
## skins."): 16 colours, the first 8 free and handed out as slot colours, 8 more sold for Coins in
## the shop data; the bean wears the preferred colour unless another bean does, else the slot
## colour, else the first colour nobody wears.


func test_palette_and_shop_cover_every_colour() -> void:
	assert_eq(Palette.PLAYER_COLORS.size(), Cosmetics.COLOR_COUNT)
	assert_eq(Palette.PLAYER_COLOR_NAMES.size(), Cosmetics.COLOR_COUNT)
	assert_eq(Cosmetics.SLOT_COLORS, Protocol.MAX_PLAYERS, "a slot colour per seat")
	var shop: CosmeticShop = CosmeticShop.default()
	assert_eq(shop.resource_path, CosmeticShop.PATH)
	var seen: Dictionary = {}
	for c: int in Cosmetics.COLOR_COUNT:
		var d: CosmeticDef = shop.color_item(c)
		assert_not_null(d, "colour %d is in the shop" % c)
		if d == null:
			continue
		assert_eq(d.kind, CosmeticDef.KIND_COLOR)
		assert_false(seen.has(d.id), "ids are unique")
		seen[d.id] = true
		assert_eq(d.display_name, Palette.PLAYER_COLOR_NAMES[c])
		if c < Cosmetics.SLOT_COLORS:
			assert_true(d.is_free(), "%s is free" % d.display_name)
		else:
			assert_between(d.price, 100, 1000, "%s costs Coins" % d.display_name)
	var colours: Array[Color] = []
	for c: Color in Palette.PLAYER_COLORS:
		assert_false(c in colours, "no two colours the same")
		colours.append(c)


func test_the_preferred_colour_wins_while_free() -> void:
	assert_eq(Cosmetics.bean_color_for(12, 0, []), 12)
	assert_eq(Cosmetics.bean_color_for(12, 0, [3, 4]), 12)
	assert_eq(Cosmetics.bean_color_for(-1, 2, []), 2, "no wish: the slot colour")


func test_a_collision_falls_back_to_the_slot_colour() -> void:
	assert_eq(Cosmetics.bean_color_for(12, 1, [12]), 1, "two players picked the same: the later one gets their slot colour")
	assert_eq(Cosmetics.bean_color_for(99, 3, []), 3, "an unknown colour is no wish")
	assert_eq(Cosmetics.bean_color_for(12, 1, [12, 1]), 0, "slot colour worn too: the first free colour")
	var all: Array[int] = []
	for c: int in Cosmetics.COLOR_COUNT - 1:
		all.append(c)
	assert_eq(Cosmetics.bean_color_for(0, 0, all), Cosmetics.COLOR_COUNT - 1)


func test_slot_colours_stay_in_the_free_eight() -> void:
	assert_eq(Cosmetics.free_slot([]), 0)
	assert_eq(Cosmetics.free_slot([0, 1, 3]), 2)
	var lobby := LobbyController.new()
	assert_eq(lobby.free_color([0, 1], 12), 2, "a bought colour is never a slot colour")
	assert_true(Cosmetics.is_slot_color(7))
	assert_false(Cosmetics.is_slot_color(8))
	assert_true(Cosmetics.is_valid_color(15))
	assert_false(Cosmetics.is_valid_color(16))


func test_palette_bean_color_reads_the_wire() -> void:
	assert_eq(Palette.bean_color({"color": 2, "bean_color": 11}), Palette.player_color(11))
	assert_eq(Palette.bean_color({"color": 2}), Palette.player_color(2), "older rows: the slot colour")
