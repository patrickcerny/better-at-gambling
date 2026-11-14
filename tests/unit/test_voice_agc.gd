extends GutTest
## `VoiceAgc`: the automatic mic level (0.9.17, "people hear me INSANELY quietly").


func _frame(amp: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(VoiceCodec.FRAME_SAMPLES)
	for i: int in f.size():
		f[i] = amp * sin(TAU * 300.0 * i / VoiceCodec.SAMPLE_RATE)
	return f


func test_quiet_speech_rises_to_the_target_within_a_second() -> void:
	var agc := VoiceAgc.new()
	var out := PackedFloat32Array()
	for i: int in 25:  # 1 s
		out = agc.process(_frame(0.03), true)  # -33.5 dBFS RMS
	assert_almost_eq(VoiceCodec.rms_db(out), VoiceAgc.TARGET_DB, 0.6)
	assert_almost_eq(agc.gain_db, 21.5, 0.6, "-33.5 dBFS lifted to -12")


func test_boost_is_capped() -> void:
	var agc := VoiceAgc.new()
	for i: int in 60:
		agc.process(_frame(0.002), true)  # -57 dBFS: ignored as not speech
	assert_eq(agc.gain_db, 0.0, "under SPEECH_DB the gain never moves")
	for i: int in 60:
		agc.process(_frame(0.005), true)  # -49 dBFS
	assert_almost_eq(agc.gain_db, VoiceAgc.MAX_BOOST_DB, 0.001)


func test_silence_between_words_keeps_the_gain() -> void:
	var agc := VoiceAgc.new()
	for i: int in 40:
		agc.process(_frame(0.05), true)
	var g: float = agc.gain_db
	for i: int in 40:
		agc.process(_frame(0.001), false)
	assert_eq(agc.gain_db, g)


func test_a_louder_voice_turns_it_down_at_once() -> void:
	var agc := VoiceAgc.new()
	for i: int in 40:
		agc.process(_frame(0.02), true)
	var out: PackedFloat32Array = agc.process(_frame(0.2), true)
	assert_lt(agc.gain_db, 6.0, "shouting right after a whisper")
	assert_lt(VoiceCodec.rms_db(VoiceAgc.limit(out)), -3.0, "no blast on the first loud frame")


func test_limit_rounds_off_instead_of_clipping() -> void:
	var f := PackedFloat32Array([0.0, 0.3, -0.6, 0.9, -1.5, 4.0])
	var out: PackedFloat32Array = VoiceAgc.limit(f)
	assert_almost_eq(out[1], 0.3, 0.000001, "under the knee: untouched")
	assert_almost_eq(out[2], -0.6, 0.000001)
	assert_between(out[3], 0.75, 0.9)
	assert_between(out[4], -1.0, -0.9)
	assert_lt(out[5], 1.0, "never full scale")
	assert_gt(out[5], out[3], "still louder")
	assert_almost_eq(f[3], 0.9, 0.000001, "the input is not changed")
