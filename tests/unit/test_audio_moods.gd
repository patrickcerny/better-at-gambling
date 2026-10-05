extends GutTest
## Music moods (M7): which loop plays when, every mood has its loop, and every SFX name the game
## asks `Audio` for has a clip (a typo would only log a warning at runtime).


func test_mood_for_phases() -> void:
	assert_eq(MusicMood.mood_for(Phase.Id.LOBBY, false), &"casino")
	assert_eq(MusicMood.mood_for(Phase.Id.INTRO, false), &"casino")
	assert_eq(MusicMood.mood_for(Phase.Id.CASINO, false), &"casino")
	assert_eq(MusicMood.mood_for(Phase.Id.CASINO, true), &"last_call")
	assert_eq(MusicMood.mood_for(Phase.Id.PRE_MINIGAME, true), &"last_call")
	assert_eq(MusicMood.mood_for(Phase.Id.MINIGAME, false), &"quiz")
	assert_eq(MusicMood.mood_for(Phase.Id.REWARDS, true), &"quiz")
	assert_eq(MusicMood.mood_for(Phase.Id.RESULTS, true), &"results")


func test_every_mood_has_a_looping_track() -> void:
	for mood: StringName in Audio.MOODS:
		var path: String = "res://audio/music/%s.ogg" % Audio.MOODS[mood]
		assert_true(ResourceLoader.exists(path), "%s → %s" % [mood, path])
		var stream: AudioStreamOggVorbis = load(path)
		assert_not_null(stream)
		assert_true(stream.loop, "%s loops (import setting)" % path)
		assert_between(stream.get_length(), 30.0, 60.0, "%s is a 30–60 s loop" % path)


func test_set_mood_tracks_the_current_mood() -> void:
	var before: StringName = Audio.current_mood()
	Audio.set_mood(&"last_call")
	assert_eq(Audio.current_mood(), &"last_call")
	Audio.set_mood(&"quiz")
	assert_eq(Audio.current_mood(), &"quiz")
	Audio.set_mood(before)


func test_tracker_follows_the_client_state() -> void:
	var st := ClientMatchState.new()
	var m := MusicMood.new()
	add_child_autofree(m)
	st.phase = Phase.Id.CASINO
	m.setup(st)
	assert_eq(Audio.current_mood(), &"casino")
	st.last_call = true
	m._process(0.1)
	assert_eq(Audio.current_mood(), &"last_call")
	st.phase = Phase.Id.RESULTS
	m._process(0.1)
	assert_eq(Audio.current_mood(), &"results")


func test_every_sfx_name_in_the_code_has_a_clip() -> void:
	var re := RegEx.new()
	re.compile("Audio\\.play(?:_at)?\\(&\"([a-z0-9_]+)\"")
	var names: Dictionary[String, String] = {}
	for path: String in _scripts("res://"):
		var text: String = FileAccess.get_file_as_string(path)
		for m: RegExMatch in re.search_all(text):
			names[m.get_string(1)] = path
	assert_gt(names.size(), 20, "found the game's SFX calls")
	for n: String in names:
		var found: bool = false
		for p: String in ["res://audio/sfx/%s.wav" % n, "res://audio/sfx/%s.ogg" % n, "res://audio/sfx/%s-v1.ogg" % n]:
			found = found or ResourceLoader.exists(p)
		assert_true(found, "clip for &\"%s\" (used in %s)" % [n, names[n]])


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub: String in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub in ["addons", "tests", "build", "tools"]:
			continue
		out.append_array(_scripts(dir.path_join(sub)))
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
