extends GutTest
## The spinnable main menu logo (Patrick 2026-11-16: "Be able to drag and spin the logo on the
## startscreen. Add a hidden achievement (spin the startlogo 1000 times). That needs to be tested
## so make it work"): `LogoSpin`'s drag, momentum and turn counting, the count kept in profile.cfg,
## and `Logo3DView` turning drags into saved turns and the achievement at 1000.

const TMP_PATH: String = "user://test_logo_spin_profile.cfg"

var _saved_profile: PlayerProfile
var _saved_path: String
var _saved_persist: bool


func before_each() -> void:
	_saved_profile = ProfileManager.profile
	_saved_path = ProfileManager.path
	_saved_persist = ProfileManager.persist
	ProfileManager.profile = PlayerProfile.new()


func after_each() -> void:
	ProfileManager.profile = _saved_profile
	ProfileManager.path = _saved_path
	ProfileManager.persist = _saved_persist
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))


## Drags `degrees` in steps of `per_step` degrees, one 60 fps frame each.
func _drag(s: LogoSpin, degrees: float, per_step: float = 30.0) -> int:
	var n: int = 0
	var left: float = absf(degrees)
	var dir: float = signf(degrees)
	while left > 0.0:
		var d: float = minf(per_step, left)
		n += s.drag(dir * d / LogoSpin.DRAG_DEG_PER_UNIT)
		n += s.step(1.0 / 60.0)
		left -= d
	return n


## Steps `seconds` at 60 fps.
func _run(s: LogoSpin, seconds: float, stick: float = 0.0) -> int:
	var n: int = 0
	for i in int(round(seconds * 60.0)):
		n += s.step(1.0 / 60.0, stick)
	return n


# --- LogoSpin ------------------------------------------------------------------------------------

func test_dragging_turns_the_sign_with_the_pointer() -> void:
	var s := LogoSpin.new()
	s.drag(100.0)
	assert_eq(s.yaw, 0.0, "no drag without a press")
	s.press()
	s.drag(100.0)
	assert_almost_eq(s.yaw, 100.0 * LogoSpin.DRAG_DEG_PER_UNIT, 0.001)
	s.drag(-50.0)
	assert_almost_eq(s.yaw, 50.0 * LogoSpin.DRAG_DEG_PER_UNIT, 0.001)


func test_one_full_drag_counts_one_turn_in_either_direction() -> void:
	var s := LogoSpin.new()
	s.press()
	assert_eq(_drag(s, 359.0), 0, "not quite round")
	assert_eq(_drag(s, 1.0), 1, "360 degrees: one turn")
	assert_eq(s.turns, 1)
	var back := LogoSpin.new()
	back.press()
	assert_eq(_drag(back, -720.0), 2, "two turns to the left")


func test_wobbling_back_and_forth_never_counts() -> void:
	var s := LogoSpin.new()
	s.press()
	var n: int = 0
	for i in 50:
		n += _drag(s, 300.0)
		n += _drag(s, -300.0)
	assert_eq(n, 0, "300 degrees there and back, 50 times")
	assert_eq(s.turns, 0)


func test_turning_back_after_a_turn_needs_a_whole_turn_the_other_way() -> void:
	var s := LogoSpin.new()
	s.press()
	assert_eq(_drag(s, 360.0), 1)
	assert_eq(_drag(s, -359.0), 0, "almost back: no turn")
	assert_eq(_drag(s, -1.0), 1, "a whole turn to the left since the last one counted")
	assert_eq(_drag(s, 359.0), 0)
	assert_eq(_drag(s, 1.0), 1)


func test_letting_go_keeps_spinning_then_slows_down() -> void:
	var s := LogoSpin.new()
	s.press()
	_drag(s, 360.0, 12.0)  # 12 deg per frame = 720 deg/s
	s.release()
	assert_false(s.dragging)
	assert_gt(s.velocity, 500.0, "the fling keeps the drag's speed")
	var yaw_at_release: float = s.yaw
	var turns: int = _run(s, 1.0)
	assert_gt(s.yaw, yaw_at_release + 300.0, "momentum carries it on")
	assert_gte(turns, 0)
	_run(s, 10.0)
	assert_eq(s.velocity, 0.0, "friction stops it")
	assert_almost_eq(s.yaw, s.front(), 0.001, "and it eases back to face the front")
	assert_false(s.is_busy())


func test_holding_still_before_letting_go_drops_the_momentum() -> void:
	var s := LogoSpin.new()
	s.press()
	_drag(s, 360.0, 12.0)
	_run(s, 0.5)  # still held, pointer not moving
	s.release()
	assert_lt(absf(s.velocity), LogoSpin.STOP_SPEED, "a held sign doesn't fly off")


func test_grabbing_stops_the_spin() -> void:
	var s := LogoSpin.new()
	s.velocity = 800.0
	s.press()
	assert_eq(s.velocity, 0.0)
	var yaw: float = s.yaw
	_run(s, 0.5)
	assert_eq(s.yaw, yaw, "held still: the sign stays put")


func test_spin_speed_is_capped() -> void:
	var s := LogoSpin.new()
	s.press()
	s.drag(100000.0)
	s.step(1.0 / 60.0)
	s.release()
	assert_lte(absf(s.velocity), LogoSpin.MAX_SPEED)
	var yaw: float = s.yaw
	s.step(1.0)
	assert_lte(s.yaw - yaw, LogoSpin.MAX_SPEED + 0.001)


func test_momentum_turns_are_counted() -> void:
	var s := LogoSpin.new()
	s.velocity = LogoSpin.MAX_SPEED
	var n: int = _run(s, 10.0)
	assert_eq(n, s.turns)
	assert_eq(n, int(floor(s.yaw / 360.0)), "every whole turn it made, once")
	assert_gte(n, 2, "a fast fling goes round a few times")


func test_right_stick_spins_it() -> void:
	var s := LogoSpin.new()
	var n: int = _run(s, 5.0, 1.0)
	assert_gt(n, 5, "held right: about 2 turns a second")
	assert_gt(s.yaw, 0.0)
	var left := LogoSpin.new()
	assert_gt(_run(left, 5.0, -1.0), 5)
	assert_lt(left.yaw, 0.0, "held left: the other way")


func test_reaching_1000_turns_by_spinning() -> void:
	var s := LogoSpin.new()
	var n: int = 0
	var guard: int = 0
	while n < Achievements.LOGO_SPINS and guard < 100000:
		n += _run(s, 1.0, 1.0)
		guard += 1
	assert_eq(n, s.turns)
	assert_gte(n, Achievements.LOGO_SPINS, "the stick gets there in a few minutes")
	assert_eq(n, int(floor(s.yaw / 360.0)), "no turn counted twice or missed")


# --- Profile and achievement --------------------------------------------------------------------

func test_the_achievement_needs_1000_turns() -> void:
	assert_true(Achievements.DEFS.has(Achievements.LOGO_SPINNER))
	assert_eq(Achievements.LOGO_SPINS, 1000)
	assert_true(Achievements.from_logo_spins(0).is_empty())
	assert_true(Achievements.from_logo_spins(999).is_empty())
	assert_eq(Achievements.from_logo_spins(1000), [Achievements.LOGO_SPINNER] as Array[StringName])
	assert_eq(Achievements.from_logo_spins(5000), [Achievements.LOGO_SPINNER] as Array[StringName])
	var p := PlayerProfile.new()
	p.logo_spins = 999
	assert_false(Achievements.LOGO_SPINNER in Achievements.from_profile(p))
	p.logo_spins = 1000
	assert_true(Achievements.LOGO_SPINNER in Achievements.from_profile(p), "rechecked on every Steam start")


func test_spins_are_saved_and_loaded() -> void:
	var p := PlayerProfile.new()
	p.logo_spins = 734
	assert_eq(p.save(TMP_PATH), OK)
	var q := PlayerProfile.new()
	assert_eq(q.load_from(TMP_PATH), OK)
	assert_eq(q.logo_spins, 734)


func test_a_damaged_spin_count_is_cleaned() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "logo_spins", -50)
	var p := PlayerProfile.new()
	p.from_config(cfg)
	assert_eq(p.logo_spins, 0)
	cfg.set_value("stats", "logo_spins", "lots")
	p.from_config(cfg)
	assert_eq(p.logo_spins, 0)
	var old := ConfigFile.new()  # a profile from before 0.10.24
	p.from_config(old)
	assert_eq(p.logo_spins, 0)


func test_profile_manager_adds_and_saves_spins() -> void:
	ProfileManager.path = TMP_PATH
	ProfileManager.persist = true
	assert_eq(ProfileManager.add_logo_spins(3), 3)
	assert_eq(ProfileManager.add_logo_spins(0), 3, "nothing to add")
	assert_eq(ProfileManager.add_logo_spins(-5), 3, "never subtracts")
	var fresh := PlayerProfile.new()
	assert_eq(fresh.load_from(TMP_PATH), OK)
	assert_eq(fresh.logo_spins, 3, "on disk at once")
	ProfileManager.reload()
	assert_eq(ProfileManager.profile.logo_spins, 3, "kept across a restart")


# --- The view on the main menu ------------------------------------------------------------------

func _view(spinnable: bool = true) -> Array:
	var got: Array = []
	var v := Logo3DView.new()
	v.spinnable = spinnable
	v.unlock = func(ids: Array[StringName]) -> void: got.append_array(ids)
	add_child_autofree(v)
	v.set_process(false)  # the test drives the frames
	return [v, got]


func _press(v: Logo3DView, on: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = on
	v._gui_input(e)


## Drags the view `turns` whole turns, `per_event` canvas units per motion event.
func _drag_view(v: Logo3DView, turns: int, per_event: float = 50.0) -> void:
	var units: float = turns * 360.0 / LogoSpin.DRAG_DEG_PER_UNIT
	while units > 0.0:
		var e := InputEventMouseMotion.new()
		var d: float = minf(per_event, units)
		e.relative = Vector2(d, 0)
		v._gui_input(e)
		v._process(1.0 / 60.0)
		units -= d


func test_main_menu_logo_is_spinnable_and_loading_logo_is_not() -> void:
	var scene: PackedScene = load("res://ui/menus/main_menu.tscn")
	var state: SceneState = scene.get_state()
	var found: bool = false
	for i in state.get_node_count():
		if state.get_node_name(i) == &"Logo":
			for k in state.get_node_property_count(i):
				if state.get_node_property_name(i, k) == &"spinnable":
					found = bool(state.get_node_property_value(i, k))
	assert_true(found, "main_menu.tscn's Logo has spinnable = true")
	var loading: Logo3DView = Logo3DView.make()
	assert_false(loading.spinnable, "the loading screens' logo just sits there")
	loading.free()


func test_view_takes_the_mouse_only_when_spinnable() -> void:
	var on: Logo3DView = _view(true)[0]
	assert_eq(on.mouse_filter, Control.MOUSE_FILTER_STOP)
	var off: Logo3DView = _view(false)[0]
	assert_eq(off.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	_press(off, true)
	_drag_view(off, 2)
	assert_eq(off.spin.turns, 0)
	assert_eq(ProfileManager.profile.logo_spins, 0)


func test_dragging_the_view_counts_turns_into_the_profile() -> void:
	var r: Array = _view()
	var v: Logo3DView = r[0]
	_press(v, true)
	_drag_view(v, 3)
	_press(v, false)
	assert_eq(v.spin.turns, 3)
	assert_eq(ProfileManager.profile.logo_spins, 3)
	assert_true((r[1] as Array).is_empty(), "no achievement yet")


func test_motion_without_a_press_does_nothing() -> void:
	var v: Logo3DView = _view()[0]
	_drag_view(v, 2)
	assert_eq(ProfileManager.profile.logo_spins, 0)


func test_the_1000th_turn_unlocks_the_achievement() -> void:
	ProfileManager.profile.logo_spins = 998
	var r: Array = _view()
	var v: Logo3DView = r[0]
	var got: Array = r[1]
	_press(v, true)
	_drag_view(v, 1)
	assert_eq(ProfileManager.profile.logo_spins, 999)
	assert_true(got.is_empty(), "999: not yet")
	_drag_view(v, 1)
	assert_eq(ProfileManager.profile.logo_spins, 1000)
	assert_eq(got, [Achievements.LOGO_SPINNER], "unlocked on the 1000th turn")


func test_turns_add_up_across_sessions_to_1000() -> void:
	ProfileManager.path = TMP_PATH
	ProfileManager.persist = true
	# Session 1: 600 turns, then the game closes.
	var a: Array = _view()
	_press(a[0], true)
	_drag_view(a[0], 600, 400.0)
	_press(a[0], false)
	assert_true((a[1] as Array).is_empty())
	ProfileManager.reload()  # next start reads profile.cfg
	assert_eq(ProfileManager.profile.logo_spins, 600)
	# Session 2: 400 more.
	var b: Array = _view()
	_press(b[0], true)
	_drag_view(b[0], 399, 400.0)
	assert_true((b[1] as Array).is_empty(), "999 in total")
	_drag_view(b[0], 1, 400.0)
	assert_eq(ProfileManager.profile.logo_spins, 1000)
	assert_eq(b[1], [Achievements.LOGO_SPINNER])


func test_a_fling_counts_its_momentum_turns() -> void:
	var v: Logo3DView = _view()[0]
	_press(v, true)
	_drag_view(v, 1, 20.0)  # 12 degrees a frame
	_press(v, false)
	for i in 600:
		v._process(1.0 / 60.0)
	assert_gt(v.spin.turns, 1, "it kept turning after letting go")
	assert_eq(ProfileManager.profile.logo_spins, v.spin.turns)
