extends GutTest
## Old fix batch: "3D roulette table mirrored compared with the panel" and "chips sliding onto the
## neighbouring number". Seen from a seat on the betting side, the felt must be the panel turned a
## quarter (a rotation, never a mirror image), and a bet's chips stay on its printed spot however
## many bets land there.

var view: SubViewport
var rs: RouletteStation


func before_each() -> void:
	view = SubViewport.new()
	view.size = Vector2i(1920, 1080)
	add_child_autofree(view)
	rs = RouletteStation.new()
	view.add_child(rs)
	await wait_process_frames(1)


func after_each() -> void:
	Vfx.force_enabled = false


## Screen position of a bet spot from seat 0's camera (the betting side).
func _screen(type: StringName, value: int) -> Vector2:
	var cam := Camera3D.new()
	view.add_child(cam)
	cam.global_transform = rs.camera_for_seat(0).global_transform
	var p: Vector2 = cam.unproject_position(rs.to_global(RouletteStation.bet_spot(type, value)))
	cam.free()
	return p


## Centre of the panel's button for a spot.
func _panel(ui: RouletteUi, type: StringName, value: int) -> Vector2:
	var columns: int = 0
	for b: Button in ui._buttons:
		var t: StringName = b.get_meta(&"type")
		if t != type:
			continue
		var hit: bool = false
		match type:
			&"straight":
				hit = int(b.text) == value
			&"dozen":
				hit = b.text.begins_with(["1st", "2nd", "3rd"][value - 1])
			&"column":
				columns += 1
				hit = columns == value
			_:
				hit = true
		if hit:
			return b.get_global_rect().get_center()
	assert_true(false, "no panel button for %s %d" % [type, value])
	return Vector2.ZERO


## +1 / -1: which way the triangle a → b → c turns (a mirror image turns the other way).
func _turn(a: Vector2, b: Vector2, c: Vector2) -> float:
	return signf((b - a).cross(c - a))


func test_the_felt_is_the_panel_turned_not_mirrored() -> void:
	var ui := RouletteUi.new()
	add_child_autofree(ui)
	await wait_process_frames(2)
	assert_lt(rs.camera_for_seat(0).global_position.z, 99.0)
	assert_gt(rs.camera_for_seat(0).global_position.z, rs.global_position.z, "seat 0 is on the betting side (+z)")
	var triples: Array = [
		[[&"straight", 1], [&"straight", 3], [&"straight", 34]],
		[[&"straight", 0], [&"straight", 2], [&"column", 1]],
		[[&"straight", 5], [&"dozen", 1], [&"column", 3]],
		[[&"red", 0], [&"straight", 36], [&"straight", 0]],
		[[&"low", 0], [&"high", 0], [&"straight", 20]],
		[[&"dozen", 1], [&"dozen", 3], [&"straight", 0]],
	]
	for t: Array in triples:
		var sp: Array[Vector2] = []
		var pp: Array[Vector2] = []
		for spot: Array in t:
			sp.append(_screen(spot[0], spot[1]))
			pp.append(_panel(ui, spot[0], spot[1]))
		assert_eq(_turn(sp[0], sp[1], sp[2]), _turn(pp[0], pp[1], pp[2]), "%s turns the same way on the felt and on the panel" % str(t))
	# The outside bets lie on the player's side of the numbers, like beside them on the panel.
	assert_gt(RouletteStation.bet_spot(&"dozen", 2).z, RouletteStation.bet_spot(&"straight", 1).z)
	assert_gt(RouletteStation.bet_spot(&"red", 0).z, RouletteStation.bet_spot(&"dozen", 2).z, "even money outermost, as on the panel")
	assert_eq(RouletteStation.bet_spot(&"column", 1).z, RouletteStation.bet_spot(&"straight", 34).z, "a column's 2:1 ends its own row")


func test_every_spot_stays_on_the_felt() -> void:
	var spots: Array = [[&"straight", 0], [&"dozen", 1], [&"column", 3], [&"red", 0], [&"high", 0]]
	for n: int in range(1, 37):
		spots.append([&"straight", n])
	for s: Array in spots:
		var p: Vector3 = RouletteStation.bet_spot(s[0], s[1])
		var half: Vector2 = RouletteStation.spot_half_size(s[0])
		assert_between(p.x - half.x, -0.1, 2.5, "%s on the layout" % str(s))
		assert_between(p.x + half.x, -0.1, 2.5)
		assert_between(p.z - half.y, -0.75, 0.75, "%s inside the felt" % str(s))
		assert_between(p.z + half.y, -0.75, 0.75)


func test_chips_stay_on_their_number() -> void:
	Vfx.force_enabled = true
	var w := Node3D.new()
	view.add_child(w)
	var fx := TableFx.new()
	add_child_autofree(fx)
	fx.setup({&"r": rs}, func(_p: int) -> PlayerAvatar: return null, 1, null, w,
		func(pid: int) -> Color: return Palette.player_color(pid - 1), func(_sid: StringName) -> int: return 10)
	# Two big bets (two columns of chips each) and a small one on 17, from two players.
	for b: Array in [[1, 200], [1, 50], [2, 300], [1, 10]]:
		fx.on_event({"type": &"bet_placed", "player": b[0], "station": &"r", "amount": b[1], "details": {"game": "roulette", "type": &"straight", "value": 17}})
	fx.on_event({"type": &"bet_placed", "player": 2, "station": &"r", "amount": 300, "details": {"game": "roulette", "type": &"column", "value": 2}})
	await wait_seconds(0.8)
	var spot: Vector3 = RouletteStation.bet_spot(&"straight", 17)
	var half: Vector2 = RouletteStation.spot_half_size(&"straight")
	var col: Vector3 = RouletteStation.bet_spot(&"column", 2)
	var col_half: Vector2 = RouletteStation.spot_half_size(&"column")
	var stacks: int = 0
	for c: Node in rs.get_children():
		if not c is ChipStack:
			continue
		stacks += 1
		var on_col: bool = (c as ChipStack).position.x > 2.2
		var centre: Vector3 = col if on_col else spot
		var h: Vector2 = col_half if on_col else half
		for chip: Node in c.get_children():
			var p: Vector3 = rs.to_local((chip as Node3D).global_position)
			assert_between(p.x - centre.x, -h.x + ChipStack.CHIP_RADIUS - 0.012, h.x - ChipStack.CHIP_RADIUS + 0.012, "chip inside its spot across (%s)" % p)
			assert_between(p.z - centre.z, -h.y + ChipStack.CHIP_RADIUS - 0.012, h.y - ChipStack.CHIP_RADIUS + 0.012, "chip inside its spot along (%s)" % p)
	assert_eq(stacks, 5)
	# The stacks on 17 sit on top of one another, not side by side.
	var ys: Array[float] = []
	for c: Node in rs.get_children():
		if c is ChipStack and (c as ChipStack).position.x < 2.2:
			ys.append((c as ChipStack).position.y)
	ys.sort()
	for i: int in range(1, ys.size()):
		assert_gt(ys[i], ys[i - 1] + ChipStack.CHIP_HEIGHT * 0.5, "the next bet goes on top")
