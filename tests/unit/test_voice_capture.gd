extends GutTest
## Voice capture path without a microphone (§2.22, M6 tests): a WAV file / generated tone is fed
## into `VoiceCapture` exactly where the mic samples would go. Checks gating (push-to-talk, open
## mic, off), the decoded signal, and the per-speaker bandwidth cap.

const WAV_PATH: String = "user://voice_test_tone.wav"
## Per-speaker cap: 72 kbit/s.
const CAP_BYTES_PER_SECOND: float = 9000.0

var cap: VoiceCapture
var packets: Array[PackedByteArray] = []


func before_each() -> void:
	cap = VoiceCapture.new()
	add_child_autofree(cap)
	cap.gain = 1.0  # whatever the saved Mic volume is
	packets.clear()
	cap.frame_captured.connect(func(p: PackedByteArray) -> void: packets.append(p))


func after_all() -> void:
	if FileAccess.file_exists(WAV_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV_PATH))


## Feeds `samples` at `rate` in 10 ms chunks, like a capture effect polled every frame.
func _feed(samples: PackedFloat32Array, rate: int) -> void:
	var chunk: int = int(rate * 0.01)
	for i: int in range(0, samples.size(), chunk):
		cap.feed_mono(samples.slice(i, mini(i + chunk, samples.size())), rate)


func test_headless_has_no_microphone_and_that_is_fine() -> void:
	assert_false(cap.start_microphone(), "no mic headless")
	assert_false(cap.mic_active)
	cap.stop_microphone()


func test_wav_through_capture_stays_under_the_bandwidth_cap() -> void:
	# A 3 s, 48 kHz "recording": speech-level tone, written and read back as a WAV file.
	assert_eq(VoiceWav.write(WAV_PATH, VoiceWav.tone(330.0, 3.0, 48000, 0.4), 48000), OK)
	var wav: Dictionary = VoiceWav.read(WAV_PATH)
	assert_eq(int(wav["rate"]), 48000)
	cap.mode = VoiceCapture.Mode.OPEN_MIC
	_feed(wav["samples"], int(wav["rate"]))
	var bytes: int = 0
	for p: PackedByteArray in packets:
		bytes += p.size()
	var rate: float = bytes / 3.0
	assert_between(packets.size(), 74, 75, "25 frames per second")
	assert_lt(rate, CAP_BYTES_PER_SECOND, "%.0f B/s = %.1f kbit/s per speaker" % [rate, rate * 8.0 / 1000.0])
	assert_lt(rate * 8.0 / 1000.0, 72.0)
	# The server's cap lets a steady speaker through untouched (relay adds 2 header bytes).
	var relay := VoiceRelay.new()
	var dropped: int = 0
	for i: int in packets.size():
		if not relay.allow(1, packets[i].size() + 2, i * VoiceCodec.FRAME_SECONDS):
			dropped += 1
	assert_eq(dropped, 0)


func test_captured_frames_decode_back_to_the_tone() -> void:
	cap.mode = VoiceCapture.Mode.OPEN_MIC
	_feed(VoiceWav.tone(300.0, 1.0, 44100, 0.5), 44100)
	assert_gt(packets.size(), 20)
	var codec := MulawCodec.new()
	var p: Dictionary = VoicePacket.parse_up(packets[10])
	var decoded: PackedFloat32Array = codec.decode(p["payload"])
	assert_eq(decoded.size(), VoiceCodec.FRAME_SAMPLES)
	assert_almost_eq(VoiceCodec.rms(decoded), 0.5 / sqrt(2.0), 0.03)
	# Sequence numbers count up by one per frame.
	for i: int in range(1, packets.size()):
		assert_eq(VoicePacket.parse_up(packets[i])["seq"], i)


func test_stereo_input_at_48k() -> void:
	cap.mode = VoiceCapture.Mode.OPEN_MIC
	var mono: PackedFloat32Array = VoiceWav.tone(300.0, 1.0, 48000, 0.5)
	var stereo := PackedVector2Array()
	stereo.resize(mono.size())
	for i: int in mono.size():
		stereo[i] = Vector2(mono[i], mono[i])
	cap.feed_stereo(stereo, 48000.0)
	assert_eq(packets.size(), 25)


func test_push_to_talk_only_sends_while_held_and_marks_the_end() -> void:
	cap.mode = VoiceCapture.Mode.PUSH_TO_TALK
	var tone: PackedFloat32Array = VoiceWav.tone(300.0, 0.4, 48000, 0.4)
	_feed(tone, 48000)
	assert_eq(packets.size(), 0, "not held: nothing sent")
	cap.ptt_pressed = true
	_feed(tone, 48000)
	assert_eq(packets.size(), 10)
	assert_true(cap.transmitting)
	assert_gt(cap.mouth.openness, 0.0, "our own mouth moves while we talk")
	cap.ptt_pressed = false
	_feed(tone, 48000)
	assert_eq(packets.size(), 11, "one closing frame after release")
	assert_eq(VoicePacket.parse_up(packets[10])["flags"] & VoicePacket.FLAG_END, VoicePacket.FLAG_END)
	assert_false(cap.transmitting)


func test_open_mic_gate_ignores_silence_and_hangs_over() -> void:
	cap.mode = VoiceCapture.Mode.OPEN_MIC
	var silence := PackedFloat32Array()
	silence.resize(48000)
	_feed(silence, 48000)
	assert_eq(packets.size(), 0, "silence is not sent")
	_feed(VoiceWav.tone(300.0, 0.2, 48000, 0.3), 48000)
	assert_eq(packets.size(), 5)
	_feed(silence, 48000)
	# 0.4 s hangover (10 frames) plus the closing frame, then quiet.
	assert_between(packets.size(), 15, 16)
	assert_false(cap.transmitting)


func test_off_sends_nothing() -> void:
	cap.mode = VoiceCapture.Mode.OFF
	cap.ptt_pressed = true
	_feed(VoiceWav.tone(300.0, 1.0, 48000, 0.5), 48000)
	assert_eq(packets.size(), 0)


## Patrick: "change your voice loudness (so like an amplifier if the mic is too loud and stuff)".
func test_mic_gain_scales_samples_and_clamps_at_full_scale() -> void:
	var f := PackedFloat32Array([0.0, 0.1, -0.2, 0.4, -0.7, 0.9])
	var up: PackedFloat32Array = VoiceCapture.apply_gain(f, 2.0)
	assert_almost_eq(up[1], 0.2, 0.0001)
	assert_almost_eq(up[2], -0.4, 0.0001)
	assert_almost_eq(up[3], 0.8, 0.0001)
	assert_eq(up[4], -1.0, "clamped, not wrapped")
	assert_eq(up[5], 1.0, "clamped, not wrapped")
	var down: PackedFloat32Array = VoiceCapture.apply_gain(f, 0.5)
	assert_almost_eq(down[3], 0.2, 0.0001)
	assert_almost_eq(down[4], -0.35, 0.0001)
	assert_eq(VoiceCodec.rms(VoiceCapture.apply_gain(f, 0.0)), 0.0, "0 % mutes")
	assert_eq(VoiceCapture.apply_gain(f, 1.0), f, "100 % leaves the samples alone")
	assert_almost_eq(VoiceCapture.apply_gain(f, 10.0)[1], 0.2, 0.0001, "gain itself is capped at 200 %")


func test_mic_gain_applies_before_the_gate_and_the_encoder() -> void:
	cap.mode = VoiceCapture.Mode.OPEN_MIC
	# -50 dBFS RMS: under the open-mic gate at 100 %...
	var quiet: PackedFloat32Array = VoiceWav.tone(300.0, 0.4, 48000, 0.0045)
	_feed(quiet, 48000)
	assert_eq(packets.size(), 0, "too quiet to open the gate")
	# ...but 200 % lifts it by 6 dB, over the -45 dB gate.
	cap.gain = 2.0
	_feed(quiet, 48000)
	assert_gt(packets.size(), 5, "amplified speech opens the gate")
	var decoded: PackedFloat32Array = MulawCodec.new().decode(VoicePacket.parse_up(packets[3])["payload"])
	assert_almost_eq(VoiceCodec.rms(decoded), 0.009 / sqrt(2.0), 0.002, "the encoded frame is the amplified one")
	assert_almost_eq(cap.level, 0.009 / sqrt(2.0), 0.001, "the meter shows the amplified level")


func test_mic_gain_follows_the_setting() -> void:
	var old: float = float(Settings.get_value("voice", "mic_gain"))
	Settings.change("voice", "mic_gain", 1.75)
	assert_almost_eq(cap.gain, 1.75, 0.0001)
	Settings.change("voice", "mic_gain", 5.0)
	assert_almost_eq(cap.gain, Settings.MAX_MIC_GAIN, 0.0001, "kept within 200 %")
	Settings.change("voice", "mic_gain", old)
	assert_almost_eq(cap.gain, Settings.mic_gain(), 0.0001)
