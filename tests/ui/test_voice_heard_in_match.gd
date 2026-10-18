extends GutTest
## Voice reaches the speakers in a real match scene, through the real mixer (0.9.12: "friends
## can't hear each other" while every headless test was green, because headless playback never
## made a sound: it only clocked frames through the mouth). Here `VoicePlayback.force_audio` keeps
## the real `AudioStreamPlayer3D` + `AudioStreamGenerator` on, the Dummy audio driver mixes them,
## and an `AudioEffectCapture` on the Voice bus records what the listener's speakers would get.
## A relayed packet is looked up by player id, played under that player's avatar inside the pixel
## view's viewport, heard from the local camera, and must come out as the tone it carries.

const TONE_HZ: float = 440.0
const AMP: float = 0.4

var scene: MatchScene
var cap: AudioEffectCapture = null
var _bus: int = -1
var _old_mode: String
var _codec := MulawCodec.new()
var _phase: float = 0.0
var _seq: int = 0


func before_each() -> void:
	Net.stop()
	_old_mode = str(Settings.get_value("voice", "mode"))
	Settings.change("voice", "mode", "open_mic")
	VoicePlayback.force_audio = true
	MatchScene.test_dummies = 2
	MatchScene.test_briefing = 0.0
	MatchScene.test_curtain_fast = true
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_process_frames(3)
	_bus = AudioServer.get_bus_index(VoicePlayback.BUS)
	cap = AudioEffectCapture.new()
	cap.buffer_length = 4.0
	AudioServer.add_bus_effect(_bus, cap)
	_phase = 0.0
	_seq = 0


func after_each() -> void:
	VoicePlayback.force_audio = false
	MatchScene.test_dummies = 0
	MatchScene.test_briefing = -1.0
	MatchScene.test_curtain_fast = false
	if _bus >= 0:
		for i: int in range(AudioServer.get_bus_effect_count(_bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(_bus, i) == cap:
				AudioServer.remove_bus_effect(_bus, i)
	Settings.change("voice", "mode", _old_mode)


func _other() -> int:
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			return pid
	return -1


## One relayed 40 ms frame of the tone from `speaker`, as the server sends it down.
func _down(speaker: int, flags: int) -> PackedByteArray:
	var f := PackedFloat32Array()
	for i: int in VoiceCodec.FRAME_SAMPLES:
		f.append(AMP * sin(_phase))
		_phase += TAU * TONE_HZ / VoiceCodec.SAMPLE_RATE
	var p: PackedByteArray = VoicePacket.make_down(speaker, _seq, flags, _codec.encode(f))
	_seq += 1
	return p


## Delivers `seconds` of `speaker`'s voice in real time (25 packets a second) to the match's voice
## channel, the way `Net.voice_received` does.
func _talk(speaker: int, seconds: float, flags: int) -> void:
	var start: int = Time.get_ticks_msec()
	var sent: int = 0
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		var due: int = int((Time.get_ticks_msec() - start) / (VoiceCodec.FRAME_SECONDS * 1000.0)) + 1
		while sent < due:
			scene.voice._on_voice(_down(speaker, flags))
			sent += 1
		await wait_process_frames(1)


## Everything the Voice bus played since the last call (left channel).
func _recorded() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n: int = cap.get_frames_available()
	if n > 0:
		for v: Vector2 in cap.get_buffer(n):
			out.append(v.x)
	return out


static func _rms(x: PackedFloat32Array) -> float:
	var e: float = 0.0
	for v: float in x:
		e += v * v
	return sqrt(e / maxf(x.size(), 1.0))


static func _tone(x: PackedFloat32Array, hz: float, rate: float) -> float:
	var c: float = 2.0 * cos(TAU * hz / rate)
	var s1: float = 0.0
	var s2: float = 0.0
	for v: float in x:
		var s0: float = v + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(maxf(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) * 2.0 / maxf(x.size(), 1.0)


func _go_online() -> void:
	# A Practice scene stands in for the online client: same scene, avatars, camera, pixel view.
	scene.voice.online = true
	scene.voice._apply_settings()
	assert_true(scene.voice.is_active(), "voice is on")


func test_the_voice_bus_exists_unmuted_at_the_default_volume() -> void:
	var layout: AudioBusLayout = load(ProjectSettings.get_setting("audio/buses/default_bus_layout")) as AudioBusLayout
	assert_not_null(layout, "the project's bus layout loads")
	assert_gt(_bus, 0, "a Voice bus at runtime (no bus means voice plays nowhere)")
	assert_eq(AudioServer.get_bus_send(_bus), &"Master", "it feeds the speakers")
	var v: float = float(Settings.get_value("audio", "voice"))
	assert_gt(float(Settings.DEFAULTS["audio"]["voice"]), 0.5, "voice is loud by default")
	assert_eq(AudioServer.is_bus_mute(_bus), v <= 0.001, "muted only when the slider is at 0")
	assert_almost_eq(AudioServer.get_bus_volume_db(_bus), Settings.slider_db(v), 0.01, "at the Voice volume setting")
	assert_false(AudioServer.is_bus_mute(0), "Master is not muted")


func test_a_relayed_packet_is_heard_from_the_speakers_avatar() -> void:
	_go_online()
	var pid: int = _other()
	assert_gt(pid, 0, "someone else is in the match")
	await wait_process_frames(2)
	_recorded()
	assert_almost_eq(_rms(_recorded()), 0.0, 0.0001, "nothing on the Voice bus before anyone talks")
	await _talk(pid, 1.6, 0)  # positional voice, as on the casino floor
	var pb: VoicePlayback = scene.voice.playbacks.get(pid, null)
	assert_not_null(pb, "a playback for that player id")
	if pb == null:
		return
	assert_eq(pb.get_parent(), scene.avatars[pid], "under the speaker's own avatar")
	assert_not_null(pb.player, "a real 3D player (not the headless clock)")
	assert_true(pb.is_playing(), "playing")
	assert_eq(pb.player.bus, VoicePlayback.BUS)
	var vp: Viewport = pb.get_viewport()
	assert_true(vp.audio_listener_enable_3d, "its viewport hears 3D sound")
	assert_not_null(vp.get_camera_3d(), "through the local camera")
	assert_gt(pb.gain, 0.3, "the dummy stands close enough to be heard (gain %.2f)" % pb.gain)
	assert_gt(pb.frames_played, 30, "frames were played")
	assert_eq(pb.buffer.overflowed, 0, "none thrown away")
	var x: PackedFloat32Array = _recorded()
	var rate: float = AudioServer.get_mix_rate()
	assert_gt(x.size(), int(rate), "over a second of mixed audio")
	var rms: float = _rms(x)
	assert_gt(rms, 0.05 * pb.gain, "the listener's speakers get the voice (RMS %.4f)" % rms)
	var at_tone: float = _tone(x, TONE_HZ, rate)
	for other: float in [300.0, 700.0, 1000.0]:
		assert_lt(_tone(x, other, rate), at_tone * 0.3, "it is the %d Hz tone, not noise at %d Hz" % [roundi(TONE_HZ), roundi(other)])


func test_table_and_global_voice_play_at_full_volume() -> void:
	_go_online()
	var pid: int = _other()
	await wait_process_frames(2)
	_recorded()
	await _talk(pid, 1.2, VoicePacket.FLAG_GLOBAL)
	var pb: VoicePlayback = scene.voice.playbacks.get(pid, null)
	assert_not_null(pb)
	if pb == null:
		return
	assert_true(pb.full_volume)
	assert_eq(pb.gain, 1.0)
	assert_gt(_rms(_recorded()), 0.05, "heard")


func test_a_muted_player_is_silent() -> void:
	_go_online()
	var pid: int = _other()
	scene.voice.set_muted(pid, true)
	await wait_process_frames(2)
	_recorded()
	await _talk(pid, 1.0, VoicePacket.FLAG_GLOBAL)
	assert_almost_eq(_rms(_recorded()), 0.0, 0.0001, "the capture only hears voice that plays")
