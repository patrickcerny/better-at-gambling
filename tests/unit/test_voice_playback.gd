extends GutTest
## The listening end of voice (§2.22): how loud a speaker is at a distance (full volume within
## 4 m, fading out by 20 m, measured from the camera), table/global voice at full volume, every
## played frame announced (`--voice-dump`, the microphone test), and the non-positional playback
## the settings panel's microphone test uses.

var cam: Camera3D
var head: Node3D
var codec := MulawCodec.new()


func before_each() -> void:
	cam = Camera3D.new()
	add_child_autofree(cam)
	cam.current = true
	head = Node3D.new()
	add_child_autofree(head)


func _playback(positional: bool = true) -> VoicePlayback:
	var pb := VoicePlayback.new()
	pb.speaker = 2
	pb.positional = positional
	head.add_child(pb)
	return pb


func _packet(seq: int, flags: int = 0, amp: float = 0.3) -> Dictionary:
	return {"seq": seq, "flags": flags, "payload": codec.encode(VoiceWav.tone(440.0, VoiceCodec.FRAME_SECONDS, VoiceCodec.SAMPLE_RATE, amp))}


func test_gain_is_full_within_4m_and_fades_out_by_20m() -> void:
	assert_eq(VoiceProximity.gain_at(0.0), 1.0)
	assert_eq(VoiceProximity.gain_at(4.0), 1.0)
	assert_almost_eq(VoiceProximity.gain_at(12.0), 0.5, 0.001, "half volume half way")
	assert_almost_eq(VoiceProximity.gain_at(16.0), 0.25, 0.001)
	assert_eq(VoiceProximity.gain_at(20.0), 0.0)
	assert_eq(VoiceProximity.gain_at(35.0), 0.0)


func test_distance_to_the_camera_sets_the_volume_and_table_voice_ignores_it() -> void:
	var pb: VoicePlayback = _playback()
	head.position = Vector3(0, -VoicePlayback.HEAD_Y, -12.0)  # the head 12 m in front of the camera
	pb.push_packet(_packet(0))
	pb.advance(0.016)
	assert_almost_eq(pb.gain, 0.5, 0.01, "12 m: half volume (Godot's own curve gave -19 dB)")
	head.position = Vector3(0, -VoicePlayback.HEAD_Y, -3.0)
	pb.advance(0.016)
	assert_eq(pb.gain, 1.0, "3 m: full volume")
	head.position = Vector3(0, -VoicePlayback.HEAD_Y, -40.0)
	pb.push_packet(_packet(1, VoicePacket.FLAG_TABLE))
	pb.advance(0.016)
	assert_eq(pb.gain, 1.0, "same table: full volume at any distance")
	pb.push_packet(_packet(2))
	pb.advance(0.016)
	assert_eq(pb.gain, 0.0, "positional again: out of earshot")


func test_every_played_frame_is_announced_in_order() -> void:
	var pb: VoicePlayback = _playback()
	var got: Array[PackedFloat32Array] = []
	pb.frame_played.connect(func(f: PackedFloat32Array) -> void: got.append(f))
	for seq: int in 6:
		pb.push_packet(_packet(seq, VoicePacket.FLAG_END if seq == 5 else 0))
	for i: int in 20:
		pb.advance(VoiceCodec.FRAME_SECONDS)
	assert_eq(got.size(), 6)
	assert_eq(pb.frames_played, 6)
	assert_almost_eq(VoiceCodec.rms(got[3]), 0.3 / sqrt(2.0), 0.02, "the decoded tone")


func test_the_microphone_test_playback_is_not_positional() -> void:
	var pb: VoicePlayback = _playback(false)
	assert_null(pb.icon, "no speaker icon over anyone's head")
	assert_null(pb.player)
	head.position = Vector3(0, 0, -40.0)
	pb.push_packet(_packet(0, VoicePacket.FLAG_END))
	pb.advance(VoiceCodec.FRAME_SECONDS)
	assert_eq(pb.gain, 1.0, "full volume wherever the camera is")
	assert_eq(pb.frames_played, 1)


## Patrick (0.9.8, Windows): the microphone test recorded fine but played nothing back. Playback
## now runs the generator at the output mix rate and upsamples the 8 kHz voice itself; `sink`
## captures exactly what would be pushed to the generator.
func _sink_playback(rate: float, out: Array[PackedVector2Array], positional: bool = false) -> VoicePlayback:
	var pb := VoicePlayback.new()
	pb.speaker = 2
	pb.positional = positional
	pb.output_rate = rate
	pb.sink = func(block: PackedVector2Array) -> void: out.append(block)
	head.add_child(pb)
	return pb


static func _left(blocks: Array[PackedVector2Array]) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	for b: PackedVector2Array in blocks:
		for v: Vector2 in b:
			x.append(v.x)
	return x


## A continuous 440 Hz tone cut into `n` packets (the phase runs on across packets).
func _tone_packets(n: int, amp: float = 0.4) -> Array[Dictionary]:
	var all: PackedFloat32Array = VoiceWav.tone(440.0, n * VoiceCodec.FRAME_SECONDS, VoiceCodec.SAMPLE_RATE, amp)
	var out: Array[Dictionary] = []
	for i: int in n:
		var f: PackedFloat32Array = all.slice(i * VoiceCodec.FRAME_SAMPLES, (i + 1) * VoiceCodec.FRAME_SAMPLES)
		out.append({"seq": i, "flags": VoicePacket.FLAG_END if i == n - 1 else 0, "payload": codec.encode(f)})
	return out


static func _goertzel(x: PackedFloat32Array, hz: float, rate: float) -> float:
	var c: float = 2.0 * cos(TAU * hz / rate)
	var s1: float = 0.0
	var s2: float = 0.0
	for v: float in x:
		var s0: float = v + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(maxf(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) * 2.0 / x.size()


## Largest deviation from the 440 Hz sine recurrence x[n] = 2cos(w)x[n-1] - x[n-2]: a missing,
## repeated or swapped frame (or a gap of silence) breaks it.
static func _worst_break(x: PackedFloat32Array, rate: float) -> float:
	var c: float = 2.0 * cos(TAU * 440.0 / rate)
	var worst: float = 0.0
	for n: int in range(2, x.size()):
		worst = maxf(worst, absf(x[n] - (c * x[n - 1] - x[n - 2])))
	return worst


## Feeds `packets` one every 40 ms (up to 15 ms late, as the network delivers them) while the game
## runs at an uneven 30–200 fps. Returns how often the jitter buffer stopped playing before the
## last packet was in.
func _feed_live(pb: VoicePlayback, packets: Array[Dictionary], extra_seconds: float = 0.5) -> int:
	var t: float = 0.0
	var next: int = 0
	var steps: Array[float] = [0.016, 0.005, 0.033, 0.012, 0.021, 0.008, 0.016]
	var tick: int = 0
	var rebuffered: int = 0
	var was_playing: bool = false
	while next < packets.size() or t < packets.size() * VoiceCodec.FRAME_SECONDS + extra_seconds:
		# The playback runs first, then the frame's packets arrive (as they do from the network).
		var dt: float = steps[tick % steps.size()]
		tick += 1
		pb.advance(dt)
		t += dt
		while next < packets.size() and t >= next * VoiceCodec.FRAME_SECONDS + (next * 7 % 16) * 0.001:
			pb.push_packet(packets[next])
			next += 1
		var playing: bool = pb.buffer.state == VoiceJitterBuffer.State.PLAYING
		if was_playing and not playing and next < packets.size():
			rebuffered += 1
		was_playing = playing
	return rebuffered


func test_playback_pushes_at_the_output_rate_and_a_440hz_tone_stays_440hz() -> void:
	for rate: float in [48000.0, 44100.0]:
		var out: Array[PackedVector2Array] = []
		var pb: VoicePlayback = _sink_playback(rate, out)
		assert_true(pb.audio_enabled, "a sink plays even headless")
		var prime: int = int(VoicePlayback.PRIME_SECONDS * rate)
		assert_eq(pb.pushed_frames, prime, "%d Hz: primed with %d ms of silence" % [rate, roundi(VoicePlayback.PRIME_SECONDS * 1000.0)])
		_feed_live(pb, _tone_packets(25))
		assert_eq(pb.frames_played, 25, "%d Hz: frames_played counts 40 ms voice frames" % rate)
		var x: PackedFloat32Array = _left(out)
		var per_frame: float = VoiceCodec.FRAME_SAMPLES * rate / VoiceCodec.SAMPLE_RATE
		assert_almost_eq(float(x.size() - prime), 25.0 * per_frame, 2.0, "%d Hz: %d output frames per 40 ms voice frame" % [rate, roundi(per_frame)])
		assert_eq(_goertzel(x.slice(0, prime), 440.0, rate), 0.0, "the priming is silence")
		var talk: PackedFloat32Array = x.slice(prime + roundi(per_frame), x.size() - roundi(per_frame))
		var a440: float = _goertzel(talk, 440.0, rate)
		assert_almost_eq(a440, 0.4, 0.03, "%d Hz: the 440 Hz tone at its level" % rate)
		for hz: float in [300.0, 700.0, 1000.0, 2500.0, 7560.0, 8440.0]:
			assert_lt(_goertzel(talk, hz, rate), a440 * 0.05, "%d Hz: nothing at %d Hz (no pitch shift, no 8 kHz images)" % [rate, roundi(hz)])
		assert_lt(_worst_break(talk, rate), 0.03, "%d Hz: one continuous tone, frame after frame" % rate)
		pb.free()


func test_the_generator_lead_is_kept_in_output_frames() -> void:
	var out: Array[PackedVector2Array] = []
	var pb: VoicePlayback = _sink_playback(48000.0, out)
	var prime: int = pb.pushed_frames
	for p: Dictionary in _tone_packets(10):
		pb.push_packet(p)
	pb.advance(0.0)
	assert_eq(pb.frames_played, 2, "80 ms queued ahead: 2 voice frames of 1920 output frames at 48 kHz")
	assert_eq(pb.pushed_frames, prime + 2 * 1920)
	pb.advance(VoiceCodec.FRAME_SECONDS)
	assert_eq(pb.frames_played, 3, "40 ms later the next one")


func test_a_spurt_is_not_cut_between_two_packets() -> void:
	# The jitter buffer is empty for a moment between packets; popping it then ended the spurt and
	# rebuffered 120 ms while the generator ran dry (heard on Linux: two gaps in 3 s).
	var out: Array[PackedVector2Array] = []
	var pb: VoicePlayback = _sink_playback(48000.0, out, true)
	assert_eq(_feed_live(pb, _tone_packets(50)), 0, "the spurt plays through")
	assert_eq(pb.frames_played, 50)
	assert_eq(pb.buffer.lost + pb.buffer.late, 0)


func test_the_microphone_test_says_when_playback_failed() -> void:
	assert_eq(VoiceMicTest.result_after_playback("", 75, 0.25), "Microphone works")
	assert_eq(VoiceMicTest.result_after_playback("the voice player is not playing", 75, 0.25), "Playback failed", "one short line; the reason is in the log")


func test_upsampler_is_continuous_across_any_cut() -> void:
	var tone: PackedFloat32Array = VoiceWav.tone(440.0, 0.2, VoiceCodec.SAMPLE_RATE, 0.5)
	var whole: PackedFloat32Array = VoiceResampler.new(VoiceCodec.SAMPLE_RATE, 48000.0).process(tone)
	var r := VoiceResampler.new(VoiceCodec.SAMPLE_RATE, 48000.0)
	var cut := PackedFloat32Array()
	var pos: int = 0
	for n: int in [1, 7, 320, 33, 320, 919]:
		cut.append_array(r.process(tone.slice(pos, mini(pos + n, tone.size()))))
		pos += n
	cut.append_array(r.process(tone.slice(pos)))
	assert_eq(whole.size(), tone.size() * 6, "8 → 48 kHz: exactly 6 per sample")
	assert_eq(cut, whole, "the same in pieces as in one go")
	var r44 := VoiceResampler.new(VoiceCodec.SAMPLE_RATE, 44100.0)
	var total: int = 0
	for i: int in 200:
		total += r44.process(tone.slice(0, VoiceCodec.FRAME_SAMPLES)).size()
	assert_eq(total, 200 * 1764, "8 → 44.1 kHz: 1764 per 40 ms frame, no drift")
