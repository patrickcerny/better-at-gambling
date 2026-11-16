extends GutTest
## The Sword Tapper spotlight only on a win (0.10.19, Patrick: "entferne den glow. der kommt nur
## wenn du gewinnst (slow glow fade in)"): idle and stuck pedestals stand dark; a freed sword fades
## the light, shaft and dust in slowly, holds them through the reveal and fades them out again.

var st: SwordTapperStation


func before_each() -> void:
	Vfx.force_enabled = true  # a client's pedestal, lamps and all
	st = SwordTapperStation.new()
	st.station_id = &"sword_1"
	add_child_autofree(st)
	Vfx.force_enabled = false
	await wait_process_frames(1)


func _assert_dark(why: String) -> void:
	assert_eq(st.glow, 0.0, why)
	assert_false(st.spot_light.visible, "%s: no spotlight" % why)
	assert_false(st.shaft.visible, "%s: no shaft" % why)
	assert_false(st.dust.emitting, "%s: no dust" % why)


func test_idle_pedestal_has_no_glow() -> void:
	_assert_dark("idle")


func test_stuck_pull_stays_dark() -> void:
	st.play_pull({"free": false, "gems": [], "mult": 1, "serial": 1, "stake": 25}, true, 1.5)
	_assert_dark("stuck sword")


func test_win_fades_in_slowly_then_out() -> void:
	var pull := {"free": true, "gems": [0, 5, 9], "mult": 1, "serial": 2, "stake": 25}
	st.play_pull(pull, true, SwordTapperStation.HEAVE)
	assert_eq(st.glow, 0.0, "nothing yet as the sword starts to come free")
	st.play_pull(pull.merged({"serial": 3}, true), true, SwordTapperStation.HEAVE + SwordTapperStation.GLOW_IN * 0.3)
	assert_between(st.glow, 0.05, 0.5, "still fading in (slow)")
	assert_true(st.spot_light.visible and st.shaft.visible and st.dust.emitting, "light, shaft and dust on")
	assert_almost_eq(st.spot_light.light_energy, SwordTapperStation.SPOT_ENERGY * st.glow, 0.0001)
	st.play_pull(pull.merged({"serial": 4}, true), true, SwordTapperStation.HEAVE + SwordTapperStation.GLOW_IN + 0.05)
	assert_almost_eq(st.glow, 1.0, 0.0001, "full during the reveal")
	var reveal: float = Registry.balance.sword_reveal_time
	st.play_pull(pull.merged({"serial": 5}, true), true, reveal + SwordTapperStation.RETURN_AFTER + SwordTapperStation.GLOW_OUT * 0.5)
	assert_between(st.glow, 0.1, 0.9, "fading out after the sword sinks back")
	st.play_pull(pull.merged({"serial": 6}, true), true, reveal + SwordTapperStation.RETURN_AFTER + SwordTapperStation.GLOW_OUT + 0.05)
	_assert_dark("after the win")


func test_late_joiner_sees_settled_last_pull_dark() -> void:
	st.show_state({"pulling": false, "last": {"serial": 9, "stake": 25, "pull": {"free": true, "gems": [1, 2, 3], "mult": 2}}})
	_assert_dark("last pull on show")
	assert_eq(st.lit, [1, 2, 3] as Array[int], "its gems still lit")


func test_glow_ticks_in_over_time() -> void:
	st.play_pull({"free": true, "gems": [0, 5, 9], "mult": 1, "serial": 8, "stake": 25}, true, SwordTapperStation.HEAVE + 0.05)
	var first: float = st.glow
	await wait_seconds(0.4)
	assert_gt(st.glow, first, "brighter as the clock runs")
