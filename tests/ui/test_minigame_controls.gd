extends GutTest
## Every minigame's rules card shows its controls (keyboard + gamepad) and a looping preview clip
## (MinigameControls, MinigamePreview, tools/minigame_clips.sh).


func test_every_minigame_has_controls_and_a_clip() -> void:
	for id: StringName in Registry.minigames:
		var rows: Array[Dictionary] = MinigameControls.rows(id)
		assert_false(rows.is_empty(), "%s has controls" % id)
		for r: Dictionary in rows:
			assert_false("{" in str(r["key"]) or "{" in str(r["pad"]), "%s: every {action} is a real action" % id)
			assert_ne(str(r["what"]), "", "%s: every row says what it does" % id)
		assert_true(ResourceLoader.exists(MinigamePreview.CLIP_PATH % id), "%s has a preview clip" % id)


func test_bindings_follow_the_input_map() -> void:
	var rows: Array[Dictionary] = MinigameControls.rows(&"bust_or_bank")
	assert_eq(rows[0]["key"], InputGlyphs.labels(&"bj_hit", false)[0])
	assert_eq(rows[0]["pad"], InputGlyphs.labels(&"bj_hit", true)[0])
	var walk: Array[Dictionary] = MinigameControls.rows(&"pass_the_bomb")
	assert_eq(walk[0]["key"], "WASD")
	assert_eq(walk[0]["pad"], "Left stick")


func test_preview_cycles_the_sheet() -> void:
	var p := MinigamePreview.new()
	add_child_autofree(p)
	assert_true(p.set_game(&"quiz"))
	assert_eq(p.frames, 50, "10 x 5 frames")
	p._process(0.25)
	assert_eq(p.frame, 2, "10 fps")
	p._process(5.0)
	assert_eq(p.frame, 2, "loops after 5 s")
	assert_false(p.set_game(&"no_such_game"))


func test_rules_card_shows_clip_and_controls() -> void:
	var st := ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Bo", "color": 1}}
	var card := MinigameBriefing.new()
	add_child_autofree(card)
	card.open({"minigame": &"find_the_lady", "players": [1, 2], "briefing": 30.0}, st, 1)
	assert_eq(card.preview.frames, 50)
	assert_eq(card.key_chips.size(), MinigameControls.rows(&"find_the_lady").size())
	InputGlyphs.set_gamepad(true)
	card._process(0.1)
	assert_eq(card.pad_chips[0].modulate.a, 1.0, "the pad column is lit after a pad press")
	assert_lt(card.key_chips[0].modulate.a, 1.0)
	assert_string_contains(card.ready_button.text, "A")
	InputGlyphs.set_gamepad(false)
	card._process(0.1)
	assert_eq(card.key_chips[0].modulate.a, 1.0)
