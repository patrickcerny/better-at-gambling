extends GutTest
## Slot machine reels (the machine is the display): riser / no-match sounds for the local
## player's spin as the reels land, the payline lighting up on a win, the winning reels.

const CH: int = SlotsLogic.Sym.CHERRY
const LEM: int = SlotsLogic.Sym.LEMON
const BELL: int = SlotsLogic.Sym.BELL
const SEVEN: int = SlotsLogic.Sym.SEVEN
const CLOVER: int = SlotsLogic.Sym.CLOVER
const DIA: int = SlotsLogic.Sym.DIAMOND


func after_each() -> void:
	Vfx.force_enabled = false


func _reels() -> SlotReelsFx:
	var fx := SlotReelsFx.new()
	add_child_autofree(fx)
	return fx


func test_stop_sounds_for_aaa_aab_abx() -> void:
	var r1: StringName = SlotReelsFx.RISERS[0]
	var r2: StringName = SlotReelsFx.RISERS[1]
	var r3: StringName = SlotReelsFx.RISERS[2]
	var nm: StringName = SlotReelsFx.NO_MATCH
	assert_eq(SlotReelsFx.stop_sounds_for([SEVEN, SEVEN, SEVEN] as Array[int]), [r1, r2, r3] as Array[StringName], "AAA: all three risers")
	assert_eq(SlotReelsFx.stop_sounds_for([SEVEN, SEVEN, BELL] as Array[int]), [r1, r2, nm] as Array[StringName], "AAB: riser 1, 2, then no-match")
	assert_eq(SlotReelsFx.stop_sounds_for([SEVEN, BELL, SEVEN] as Array[int]), [r1, nm, &""] as Array[StringName], "ABA: riser 1, no-match, plain stop")
	assert_eq(SlotReelsFx.stop_sounds_for([SEVEN, BELL, LEM] as Array[int]), [r1, nm, &""] as Array[StringName], "ABC: riser 1, no-match, plain stop")
	assert_eq(SlotReelsFx.stop_sounds_for([CLOVER, SEVEN, SEVEN] as Array[int])[1], nm, "exact emblems: a wild does not continue the riser")


func test_sound_files_exist() -> void:
	for n: StringName in SlotReelsFx.RISERS + [SlotReelsFx.NO_MATCH]:
		assert_true(ResourceLoader.exists("res://audio/sfx/%s-v1.ogg" % n), "%s is imported" % n)


func test_stagger_chains_the_riser_segments() -> void:
	assert_almost_eq(SlotReelsFx.STAGGER, 0.71, 0.02, "reels stop as far apart as the riser segments")
	assert_almost_eq(SlotReelsFx.land_seconds(), SlotReelsFx.FIRST_STOP + SlotReelsFx.STAGGER * 2.0 + SlotReelsFx.SETTLE, 0.001)


func _land(fx: SlotReelsFx, line: Array, own: bool) -> void:
	fx.spin()
	fx.stop_on(line, own)
	var t: float = 0.0
	while t < SlotReelsFx.land_seconds() + 0.1:
		fx._process(0.05)
		t += 0.05


func test_own_spin_plays_the_sounds_in_order() -> void:
	var fx: SlotReelsFx = _reels()
	_land(fx, [SEVEN, SEVEN, SEVEN], true)
	assert_eq(fx.played_sounds, SlotReelsFx.RISERS, "AAA plays riser 1, 2, 3 as the reels land")
	_land(fx, [SEVEN, SEVEN, BELL], true)
	assert_eq(fx.played_sounds, [SlotReelsFx.RISERS[0], SlotReelsFx.RISERS[1], SlotReelsFx.NO_MATCH] as Array[StringName])
	_land(fx, [SEVEN, BELL, SEVEN], true)
	assert_eq(fx.played_sounds, [SlotReelsFx.RISERS[0], SlotReelsFx.NO_MATCH] as Array[StringName])


func test_someone_elses_spin_is_silent() -> void:
	var fx: SlotReelsFx = _reels()
	_land(fx, [SEVEN, SEVEN, SEVEN], false)
	assert_false(fx.is_spinning())
	assert_eq(fx.played_sounds.size(), 0, "no risers for other players' machines")


func test_last_reel_teases_when_the_first_two_match() -> void:
	var fx: SlotReelsFx = _reels()
	fx.spin()
	fx.stop_on([SEVEN, SEVEN, BELL], true)
	assert_true(fx._tease)
	fx.stop_on([SEVEN, BELL, BELL], true)
	assert_false(fx._tease)


func test_win_lights_the_payline_and_marks_the_reels() -> void:
	var fx: SlotReelsFx = _reels()
	_land(fx, [BELL, CLOVER, BELL], false)
	assert_true(fx.is_showing_win(), "three of a kind with a wild lights the payline")
	assert_eq(fx.winners, [0, 1, 2] as Array[int])
	_land(fx, [SEVEN, BELL, LEM], false)
	assert_false(fx.is_showing_win(), "a loss leaves the payline dark")
	fx.spin()
	assert_false(fx.is_showing_win(), "a new spin clears the payline")


func test_lever_pull_starts_the_reels_on_the_down_stroke() -> void:
	Vfx.force_enabled = true
	var ss := SlotsStation.new()
	add_child_autofree(ss)
	await wait_process_frames(1)
	ss.start_spin(true)
	await wait_process_frames(1)
	assert_false(ss.reels_fx.is_spinning(), "the reels wait for the lever")
	await wait_seconds(SlotsStation.LEVER_DOWN + 0.1)
	assert_true(ss.reels_fx.is_spinning(), "spinning once the lever bottoms out")
	assert_true(ResourceLoader.exists("res://audio/sfx/slots_lever-v1.ogg"))


func test_winning_reels_match_the_payout() -> void:
	var cfg: BalanceConfig = Registry.balance
	assert_eq(SlotReelsFx.winning_reels([DIA, DIA, DIA] as Array[int], cfg), [0, 1, 2] as Array[int])
	assert_eq(SlotReelsFx.winning_reels([CH, LEM, CH] as Array[int], cfg), [0, 2] as Array[int], "two cherries")
	assert_eq(SlotReelsFx.winning_reels([CH, LEM, BELL] as Array[int], cfg), [0] as Array[int], "left cherry")
	assert_eq(SlotReelsFx.winning_reels([LEM, CH, BELL] as Array[int], cfg), [] as Array[int], "a loss")
