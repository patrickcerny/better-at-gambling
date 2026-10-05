class_name VoicePlayback
extends Node3D
## One remote speaker's voice (§2.22): jitter buffer → decoder → `AudioStreamGenerator` in an
## `AudioStreamPlayer3D` at their head on the `Voice` bus, plus their mouth flap and the speaker
## icon over their head. Lives under the speaker's avatar, so it follows them around.
##
## Proximity voice is full volume within 4 m and fades out by 20 m; table and global voice
## (flagged by the server) play at full volume wherever the speaker is.
## Headless there is no audio device: frames are still pulled on a 40 ms clock so the mouth and
## talking state behave exactly as they would with sound.

const BUS: StringName = &"Voice"
## Head height above the avatar's origin.
const HEAD_Y: float = 1.3
## Decoded audio kept queued in the generator (on top of the jitter buffer).
const GENERATOR_LEAD: int = VoiceCodec.FRAME_SAMPLES * 2

var speaker: int = -1
var codec: VoiceCodec = MulawCodec.new()
var buffer: VoiceJitterBuffer = VoiceJitterBuffer.new()
var mouth: VoiceMouth = VoiceMouth.new()
## True while the last packet was table/global voice (no distance falloff).
var full_volume: bool = false
## Plays sound (false headless, or when forced off for tests).
var audio_enabled: bool = true
var player: AudioStreamPlayer3D = null
var icon: Sprite3D = null

var _gen: AudioStreamGeneratorPlayback = null
var _capacity: int = 0
var _clock: float = 0.0


func _ready() -> void:
	position.y = HEAD_Y
	if DisplayServer.get_name() == "headless":
		audio_enabled = false
	if audio_enabled:
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = VoiceCodec.SAMPLE_RATE
		stream.buffer_length = 0.3
		player = AudioStreamPlayer3D.new()
		player.name = "Voice"
		player.stream = stream
		player.bus = BUS
		player.panning_strength = 0.6
		add_child(player)
		_set_full_volume(false)
		player.play()
		_gen = player.get_stream_playback() as AudioStreamGeneratorPlayback
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
	_gen = null


## Queues one parsed down packet (see `VoicePacket.parse_down`).
func push_packet(p: Dictionary) -> void:
	var flags: int = int(p["flags"])
	_set_full_volume((flags & (VoicePacket.FLAG_GLOBAL | VoicePacket.FLAG_TABLE)) != 0)
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
				mouth.feed(f)
		if not buffer.is_active():
			_clock = 0.0
	mouth.update(delta)
	if icon != null:
		icon.visible = mouth.is_talking()


func _play(f: PackedFloat32Array) -> void:
	mouth.feed(f)
	var stereo := PackedVector2Array()
	stereo.resize(f.size())
	for i: int in f.size():
		stereo[i] = Vector2(f[i], f[i])
	_gen.push_buffer(stereo)


func _set_full_volume(on: bool) -> void:
	full_volume = on
	if player == null:
		return
	if on:
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = 0.0
	else:
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = VoiceProximity.FULL_VOLUME_RADIUS
		player.max_distance = VoiceProximity.HEARING_RADIUS
