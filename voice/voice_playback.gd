class_name VoicePlayback
extends Node3D
## One remote speaker's voice (§2.22): jitter buffer → decoder → `AudioStreamGenerator` in an
## `AudioStreamPlayer3D` at their head on the `Voice` bus, plus their mouth flap and the speaker
## icon over their head. Lives under the speaker's avatar, so it follows them around.
##
## Proximity voice is full volume within 4 m and fades out by 20 m (`VoiceProximity.gain_at`,
## applied here from the distance to the camera; Godot's own attenuation would multiply an
## inverse-distance curve with a linear fade and leave a voice 13 m away at -19 dB); table and
## global voice (flagged by the server) play at full volume wherever the speaker is.
## `positional = false` plays through a plain `AudioStreamPlayer` instead (the settings panel's
## microphone test). Headless there is no audio device: frames are still pulled on a 40 ms clock
## so the mouth and talking state behave exactly as they would with sound.

## Every frame this playback plays (decoded samples at 8 kHz; `--voice-dump`, tests).
signal frame_played(samples: PackedFloat32Array)

const BUS: StringName = &"Voice"
## Head height above the avatar's origin.
const HEAD_Y: float = 1.3
## Decoded audio kept queued in the generator (on top of the jitter buffer).
const GENERATOR_LEAD: int = VoiceCodec.FRAME_SAMPLES * 2

## Frames every playback has pulled out of its jitter buffer and played (or, headless, clocked
## through the mouth), for the end-of-match voice log line and the tests.
static var total_frames_played: int = 0

var speaker: int = -1
## Frames this speaker's playback has played.
var frames_played: int = 0
var codec: VoiceCodec = MulawCodec.new()
var buffer: VoiceJitterBuffer = VoiceJitterBuffer.new()
var mouth: VoiceMouth = VoiceMouth.new()
## True while the last packet was table/global voice (no distance falloff).
var full_volume: bool = false
## Plays sound (false headless, or when forced off for tests).
var audio_enabled: bool = true
## Positioned at the speaker's head (false: straight to the Voice bus, see the class comment).
var positional: bool = true
## Current loudness from the distance to the listener (1 at full volume).
var gain: float = 1.0
var player: AudioStreamPlayer3D = null
var flat_player: AudioStreamPlayer = null
var icon: Sprite3D = null

var _gen: AudioStreamGeneratorPlayback = null
var _capacity: int = 0
var _clock: float = 0.0
var _logged_first: bool = false


func _ready() -> void:
	position.y = HEAD_Y
	if DisplayServer.get_name() == "headless":
		audio_enabled = false
	if audio_enabled:
		var stream := AudioStreamGenerator.new()
		stream.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
		stream.mix_rate = VoiceCodec.SAMPLE_RATE
		stream.buffer_length = 0.3
		if positional:
			player = AudioStreamPlayer3D.new()
			player.name = "Voice"
			player.stream = stream
			player.bus = BUS
			player.panning_strength = 0.6
			# Loudness over distance is ours (`_update_gain`); Godot only pans.
			player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			player.max_distance = 0.0
			add_child(player)
			player.play()
			_gen = player.get_stream_playback() as AudioStreamGeneratorPlayback
		else:
			flat_player = AudioStreamPlayer.new()
			flat_player.name = "Voice"
			flat_player.stream = stream
			flat_player.bus = BUS
			add_child(flat_player)
			flat_player.play()
			_gen = flat_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _gen == null:
			Log.warn(&"voice", "player %d: no generator playback, voice is silent" % speaker)
	if not positional:
		return
	icon = Sprite3D.new()
	icon.name = "TalkingIcon"
	icon.texture = VoiceIcons.speaker(Palette.CREAM)
	icon.pixel_size = 0.005
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = false
	icon.position.y = 1.15
	icon.visible = false
	add_child(icon)


func _exit_tree() -> void:
	if player != null:
		player.stop()
		player.stream = null
	if flat_player != null:
		flat_player.stop()
		flat_player.stream = null
	_gen = null


## Queues one parsed down packet (see `VoicePacket.parse_down`).
func push_packet(p: Dictionary) -> void:
	var flags: int = int(p["flags"])
	full_volume = (flags & (VoicePacket.FLAG_GLOBAL | VoicePacket.FLAG_TABLE)) != 0
	buffer.push(int(p["seq"]), codec.decode(p["payload"]), (flags & VoicePacket.FLAG_END) != 0)


## Drops everything queued (muted).
func clear() -> void:
	buffer = VoiceJitterBuffer.new()
	if _gen != null:
		_gen.clear_buffer()


func is_talking() -> bool:
	return mouth.is_talking()


func _process(delta: float) -> void:
	advance(delta)


## Pulls due frames out of the jitter buffer and updates the mouth and icon.
func advance(delta: float) -> void:
	_update_gain()
	if _gen != null:
		var free: int = _gen.get_frames_available()
		_capacity = maxi(_capacity, free)
		var queued: int = _capacity - free
		while queued < GENERATOR_LEAD:
			var f: PackedFloat32Array = buffer.pop()
			if f.is_empty():
				break
			_play(f)
			queued += f.size()
	else:
		_clock += delta
		while _clock >= VoiceCodec.FRAME_SECONDS:
			_clock -= VoiceCodec.FRAME_SECONDS
			var f: PackedFloat32Array = buffer.pop()
			if not f.is_empty():
				_count_played(f)
				mouth.feed(f)
		if not buffer.is_active():
			_clock = 0.0
	mouth.update(delta)
	if icon != null:
		icon.visible = mouth.is_talking()


func _count_played(f: PackedFloat32Array) -> void:
	frames_played += 1
	total_frames_played += 1
	if not _logged_first:
		_logged_first = true
		var how: String = "headless, no sound"
		if _gen != null:
			how = "on bus %s at %s" % [BUS, "%.0f%% volume" % (gain * 100.0) if positional else "full volume"]
		Log.info(&"voice", "first frame played for player %d (%s, level %s)" % [speaker, how, VoiceCapture.db_text(VoiceCodec.rms(f))])
	frame_played.emit(f)


func _play(f: PackedFloat32Array) -> void:
	_count_played(f)
	mouth.feed(f)
	var stereo := PackedVector2Array()
	stereo.resize(f.size())
	for i: int in f.size():
		stereo[i] = Vector2(f[i], f[i])
	_gen.push_buffer(stereo)


## Loudness from the distance between the speaker's head and the camera that hears it.
func _update_gain() -> void:
	gain = 1.0
	if positional and not full_volume and is_inside_tree():
		var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null:
			gain = VoiceProximity.gain_at(global_position.distance_to(cam.global_position))
	if player != null:
		player.volume_db = linear_to_db(gain) if gain > 0.001 else -80.0
