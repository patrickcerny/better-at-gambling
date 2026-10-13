extends GutTest
## Voice reception proved by content (Patrick: "think of a way to test it if the other user
## received it"): Alice's and Carol's (fake) microphones play known tones, the server relays with
## the real proximity rules, and Bob's `VoicePlayback`s decode them. What Bob plays must be the
## same tone (dominant frequency by Goertzel), as loud as the source within μ-law tolerance, every
## frame in order with no gap (a pure tone continues across every frame boundary), and two
## speakers talking at once must stay separate.

const FakeMicTest = preload("res://tests/unit/test_voice_mic.gd")
## Frequencies a wrong or smeared signal would show up at.
const PROBES: Array[float] = [300.0, 440.0, 700.0, 1000.0, 1500.0, 2500.0]
const AMP: float = 0.4

var fx: ServerFixture
var relay: VoiceRelay
var bob: int
var ch_bob: VoiceChannel
var senders: Dictionary[int, VoiceChannel] = {}
var mics: Dictionary[int, FakeMicTest.FakeMic] = {}
var avatars_bob: Dictionary[int, Node3D] = {}
## What Bob's playback played, per speaker (8 kHz samples, in play order).
var heard: Dictionary[int, PackedFloat32Array] = {}
var _old_mode: String
var _t: float = 0.0


func before_each() -> void:
	_old_mode = str(Settings.get_value("voice", "mode"))
	Settings.change("voice", "mode", "push_to_talk")
	fx = ServerFixture.new(3, {"minigames": 2, "gamble_seconds": 100.0, "seed": 5})
	fx.server.start_match()
	fx.run(3.1)  # casino: proximity voice
	relay = VoiceRelay.new()
	bob = fx.player_ids[1]
	fx.server.world.set_transform(fx.player_ids[0], Vector3.ZERO, 0.0)
	fx.server.world.set_transform(bob, Vector3(3, 0, 0), 0.0)
	fx.server.world.set_transform(fx.player_ids[2], Vector3(0, 0, 3), 0.0)
	senders.clear()
	mics.clear()
	heard.clear()
	for pid: int in fx.player_ids:
		var a := Node3D.new()
		add_child_autofree(a)
		avatars_bob[pid] = a
	ch_bob = _channel(bob, func(p: int) -> Node3D: return avatars_bob.get(p, null))
	ch_bob.audio_enabled = false


func after_each() -> void:
	Settings.change("voice", "mode", _old_mode)
	fx.server.free()


func _channel(pid: int, avatar_of: Callable) -> VoiceChannel:
	var ch := VoiceChannel.new()
	ch.setup(null, pid, avatar_of, null, true)
	add_child_autofree(ch)
	return ch


## A speaker whose microphone plays `hz` (holding push-to-talk).
func _speaker(pid: int, hz: float) -> void:
	var ch: VoiceChannel = _channel(pid, func(_p: int) -> Node3D: return null)
	var mic: FakeMicTest.FakeMic = FakeMicTest.FakeMic.new()
	mic.tone_hz = hz
	ch.capture.source = mic
	assert_true(ch.capture.start_microphone())
	ch.capture.frame_captured.disconnect(ch._on_frame)
	ch.capture.frame_captured.connect(func(packet: PackedByteArray) -> void:
		var out: Dictionary[int, PackedByteArray] = relay.route(fx.server, pid, packet, _t, fx.player_ids)
		if out.has(bob):
			ch_bob._on_voice(out[bob]))
	senders[pid] = ch
	mics[pid] = mic


## `seconds` of game frames: the microphones deliver audio, everyone's channel ticks, Bob's
## playbacks play (and we keep what they played).
func _run(seconds: float, talking: bool) -> void:
	var dt: float = 0.016
	for i: int in int(seconds / dt):
		_t += dt
		for pid: int in senders:
			if talking:
				mics[pid].speak(dt, AMP)
			senders[pid].capture.ptt_pressed = talking
			senders[pid].capture._process(dt)
		for pid: int in ch_bob.playbacks:
			var pb: VoicePlayback = ch_bob.playbacks[pid]
			if not pb.frame_played.is_connected(_on_played):
				pb.frame_played.connect(_on_played.bind(pid))
			pb.advance(dt)


func _on_played(f: PackedFloat32Array, pid: int) -> void:
	if not heard.has(pid):
		heard[pid] = PackedFloat32Array()
	heard[pid].append_array(f)


## Amplitude of the `hz` component of `x` (Goertzel; a sine of amplitude A reads ≈ A).
static func tone_amplitude(x: PackedFloat32Array, hz: float, rate: float = VoiceCodec.SAMPLE_RATE) -> float:
	var c: float = 2.0 * cos(TAU * hz / rate)
	var s1: float = 0.0
	var s2: float = 0.0
	for v: float in x:
		var s0: float = v + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(maxf(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) * 2.0 / x.size()


## The probe frequency with the most energy in `x`.
static func dominant(x: PackedFloat32Array) -> float:
	var best: float = 0.0
	var best_amp: float = -1.0
	for hz: float in PROBES:
		var a: float = tone_amplitude(x, hz)
		if a > best_amp:
			best_amp = a
			best = hz
	return best


## Largest jump at a frame boundary away from what the tone itself predicts (sine recurrence
## x[n] = 2cos(w)·x[n-1] - x[n-2]); a lost, repeated or swapped frame breaks it.
static func worst_boundary_error(x: PackedFloat32Array, hz: float) -> float:
	var c: float = 2.0 * cos(TAU * hz / VoiceCodec.SAMPLE_RATE)
	var worst: float = 0.0
	for n: int in range(VoiceCodec.FRAME_SAMPLES, x.size(), VoiceCodec.FRAME_SAMPLES):
		worst = maxf(worst, absf(x[n] - (c * x[n - 1] - x[n - 2])))
	return worst


func _check_tone(hz: float) -> void:
	var alice: int = fx.player_ids[0]
	_speaker(alice, hz)
	_run(2.0, true)
	_run(0.6, false)  # let go: the end frame goes out, Bob's buffer drains
	var pb: VoicePlayback = ch_bob.playbacks.get(alice, null)
	assert_not_null(pb, "Bob plays Alice under her avatar")
	if pb == null:
		return
	var sent: int = senders[alice].capture.frames_sent
	assert_gt(sent, 45, "2 s of 40 ms frames went out")
	assert_eq(ch_bob.received_from[alice], sent, "every frame reached Bob")
	assert_eq(pb.frames_played, sent, "and every frame was played")
	assert_eq([pb.buffer.lost, pb.buffer.late, pb.buffer.duplicates, pb.buffer.overflowed], [0, 0, 0, 0], "in order, no gaps")
	var x: PackedFloat32Array = heard[alice]
	assert_eq(x.size(), sent * VoiceCodec.FRAME_SAMPLES)
	var talk: PackedFloat32Array = x.slice(VoiceCodec.FRAME_SAMPLES * 2, (sent - 1) * VoiceCodec.FRAME_SAMPLES)  # the tone, without the closing frame
	assert_eq(dominant(talk), hz, "Bob hears %d Hz" % roundi(hz))
	for other: float in PROBES:
		if other != hz:
			assert_lt(tone_amplitude(talk, other), tone_amplitude(talk, hz) * 0.05, "%d Hz is not in it" % roundi(other))
	assert_almost_eq(VoiceCodec.rms(talk), AMP / sqrt(2.0), AMP / sqrt(2.0) * 0.05, "as loud as Alice's mic (μ-law: within 5 %)")
	assert_lt(worst_boundary_error(talk, hz), AMP * 0.08, "the tone runs on across every frame boundary")


func test_a_440hz_tone_arrives_intact() -> void:
	_check_tone(440.0)


func test_a_1khz_tone_arrives_intact() -> void:
	_check_tone(1000.0)


func test_two_speakers_at_once_stay_separate() -> void:
	var alice: int = fx.player_ids[0]
	var carol: int = fx.player_ids[2]
	_speaker(alice, 440.0)
	_speaker(carol, 1000.0)
	_run(2.0, true)
	_run(0.6, false)
	assert_true(heard.has(alice) and heard.has(carol), "Bob hears both")
	assert_ne(ch_bob.playbacks[alice], ch_bob.playbacks[carol], "one playback each")
	for pair: Array in [[alice, 440.0, 1000.0], [carol, 1000.0, 440.0]]:
		var x: PackedFloat32Array = heard[int(pair[0])]
		var talk: PackedFloat32Array = x.slice(VoiceCodec.FRAME_SAMPLES * 2, x.size() - VoiceCodec.FRAME_SAMPLES)
		assert_eq(dominant(talk), float(pair[1]), "player %d's own tone" % int(pair[0]))
		assert_lt(tone_amplitude(talk, float(pair[2])), 0.01, "nothing of the other speaker in it")
		assert_eq(ch_bob.playbacks[int(pair[0])].buffer.lost, 0)
