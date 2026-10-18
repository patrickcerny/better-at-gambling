class_name VoicePlayback
extends Node3D
## One remote speaker's voice (§2.22): jitter buffer → decoder → our own 8 kHz → output-rate
## upsampler → `AudioStreamGenerator` in an `AudioStreamPlayer3D` at their head on the `Voice`
## bus, plus their mouth flap and the speaker icon over their head. Lives under the speaker's
## avatar, so it follows them around.
##
## The generator runs at the output mix rate (`MIX_RATE_OUTPUT`, 48 kHz on most Windows PCs) and is
## fed already upsampled audio (`VoiceResampler`, linear), so Godot's own stream resampler only
## ever sees a 1:1 ratio (Patrick, 0.9.8: the microphone test recorded fine but played nothing
## back on Windows; it played on Linux at 44.1 and 48 kHz). The player is started only inside the
## tree, primed with a little silence, and restarted if it ever stops.
##
## Proximity voice is full volume within 4 m and fades out by 20 m (`VoiceProximity.gain_at`,
## applied here from the distance to the camera; Godot's own attenuation would multiply an
## inverse-distance curve with a linear fade and leave a voice 13 m away at -19 dB); table and
## global voice (flagged by the server) play at full volume wherever the speaker is.
## `positional = false` plays through a plain `AudioStreamPlayer` instead (the settings panel's
## microphone test). Headless there is no audio device: frames are still pulled on a 40 ms clock
## so the mouth and talking state behave exactly as they would with sound (`force_audio` keeps the
## real players headless, for tests that listen to the Voice bus).

## Every frame this playback plays (decoded samples at 8 kHz; `--voice-dump`, tests).
signal frame_played(samples: PackedFloat32Array)

const BUS: StringName = &"Voice"
## Head height above the avatar's origin.
const HEAD_Y: float = 1.3
## Decoded audio kept queued in the generator (on top of the jitter buffer).
const LEAD_SECONDS: float = VoiceCodec.FRAME_SECONDS * 2.0
## Silence pushed when the player starts, so its first mix never runs dry.
const PRIME_SECONDS: float = 0.02
## Generator buffer (at the output rate): room for `LEAD_SECONDS` plus a slow frame's lead.
const BUFFER_SECONDS: float = 0.5
## The lead never asks for more than this share of the generator buffer.
const MAX_LEAD_SHARE: float = 0.8
## A stopped player is restarted at most this often.
const RESTART_SECONDS: float = 1.0

## Frames every playback has pulled out of its jitter buffer and played (or, headless, clocked
## through the mouth), for the end-of-match voice log line and the tests.
static var total_frames_played: int = 0
## Tests: real players (the `AudioServer` mixer, Dummy driver) even headless, where playback is
## otherwise clocked silently. Lets a test hear what reaches the Voice bus.
static var force_audio: bool = false

var speaker: int = -1
## 40 ms voice frames this speaker's playback has played.
var frames_played: int = 0
var codec: VoiceCodec = MulawCodec.new()
var buffer: VoiceJitterBuffer = VoiceJitterBuffer.new()
var mouth: VoiceMouth = VoiceMouth.new()
## True while the last packet was table/global voice (no distance falloff).
var full_volume: bool = false
## Plays sound (false headless unless a `sink` is set, or when forced off for tests).
var audio_enabled: bool = true
## Positioned at the speaker's head (false: straight to the Voice bus, see the class comment).
var positional: bool = true
## Current loudness from the distance to the listener (1 at full volume).
var gain: float = 1.0
## Rate of what is pushed to the generator (0 until it starts: then `AudioServer.get_mix_rate()`;
## tests set it beforehand).
var output_rate: float = 0.0
## Tests: called with every block of stereo frames (at `output_rate`) that would be pushed to the
## generator, in place of a real player. `advance` drains it at `output_rate` like the mixer would.
var sink: Callable = Callable()
## Stereo frames pushed (priming silence and voice), at `output_rate`.
var pushed_frames: int = 0
## Why this playback cannot make sound ("" while it can), for the microphone test's verdict.
var failure: String = ""
## Times the player had stopped and was started again.
var restarts: int = 0
var player: AudioStreamPlayer3D = null
var flat_player: AudioStreamPlayer = null
var icon: Sprite3D = null

var _gen: AudioStreamGeneratorPlayback = null
var _upsampler: VoiceResampler = null
var _capacity: int = 0
var _sink_queued: float = 0.0
var _clock: float = 0.0
var _restart_wait: float = 0.0
var _rate_injected: bool = false
var _logged_first: bool = false
var _warned: Dictionary[String, bool] = {}


func _ready() -> void:
	position.y = HEAD_Y
	if DisplayServer.get_name() == "headless" and not sink.is_valid() and not force_audio:
		audio_enabled = false
	if audio_enabled:
		_rate_injected = output_rate > 0.0
		if not _rate_injected:
			output_rate = AudioServer.get_mix_rate()
		_upsampler = VoiceResampler.new(VoiceCodec.SAMPLE_RATE, output_rate)
		if not sink.is_valid():
			_make_player()
		_start()
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


func _make_player() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate_mode = AudioStreamGenerator.MIX_RATE_OUTPUT
	stream.buffer_length = BUFFER_SECONDS
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
	else:
		flat_player = AudioStreamPlayer.new()
		flat_player.name = "Voice"
		flat_player.stream = stream
		flat_player.bus = BUS
		add_child(flat_player)


## (Re)starts the player and primes it with silence. Only inside the tree (Godot refuses to play
## a node outside it); `advance` tries again later.
func _start() -> void:
	_restart_wait = RESTART_SECONDS
	if sink.is_valid():
		_sink_queued = 0.0
		_prime()
		return
	var node: Node = player if player != null else flat_player
	if node == null or not node.is_inside_tree():
		return
	if player != null:
		player.play()
		_gen = player.get_stream_playback() as AudioStreamGeneratorPlayback
	else:
		flat_player.play()
		_gen = flat_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _gen == null:
		failure = "no generator playback (Godot returned none)"
		_warn_once("nogen", "%s: no generator playback, voice is silent" % _who())
		return
	_capacity = _gen.get_frames_available()
	_prime()


func _prime() -> void:
	var silence := PackedVector2Array()
	silence.resize(int(PRIME_SECONDS * output_rate))
	_push(silence)


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


## Drops everything queued (muted). What is already in the generator (at most `LEAD_SECONDS`)
## plays out: Godot refuses to clear the buffer of a playing generator.
func clear() -> void:
	buffer = VoiceJitterBuffer.new()


func is_talking() -> bool:
	return mouth.is_talking()


## True while the player is playing (or a test sink takes the audio).
func is_playing() -> bool:
	if sink.is_valid():
		return true
	if player != null:
		return player.playing
	return flat_player != null and flat_player.playing


## Output rate, playing state and underruns in a few words, for the log.
func describe() -> String:
	if not audio_enabled:
		return "headless, no sound"
	if _gen == null and not sink.is_valid():
		return "no generator playback"
	var skips: String = " (test sink)" if sink.is_valid() else ", %d underruns" % _gen.get_skips()
	return "%d Hz, playing %s, %d restarts%s" % [roundi(output_rate), is_playing(), restarts, skips]


func _process(delta: float) -> void:
	advance(delta)


## Pulls due frames out of the jitter buffer and updates the mouth and icon.
func advance(delta: float) -> void:
	_update_gain()
	if audio_enabled:
		_keep_alive(delta)
	if audio_enabled and (_gen != null or sink.is_valid()):
		var queued: int = _queued(delta)
		var lead: int = ceili(lead_seconds(delta) * output_rate)
		while queued < lead:
			# Between two packets of a spurt the jitter buffer is briefly empty: popping it then
			# would end the spurt and rebuffer 120 ms while the generator runs dry (a gap every
			# second or so). Wait for the next packet while the generator still has audio.
			if queued > 0 and buffer.state == VoiceJitterBuffer.State.PLAYING and buffer.depth() == 0:
				break
			var f: PackedFloat32Array = buffer.pop()
			if f.is_empty():
				break
			queued += _play(f)
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


## Audio to keep queued in the generator after a frame of `delta` seconds: `LEAD_SECONDS`, or
## enough to last until the next frame and one voice frame more when frames are slow. With a
## fixed 80 ms lead a game running under 12 fps let the generator run dry every frame, played
## voice slower than it arrived and the jitter buffer threw half of it away (overflowed; found
## with a real audio device at 8 fps, 0.9.12).
static func lead_seconds(delta: float) -> float:
	return clampf(delta * 1.5 + VoiceCodec.FRAME_SECONDS, LEAD_SECONDS, BUFFER_SECONDS * MAX_LEAD_SHARE)


## Output frames still waiting in the generator (or the test sink).
func _queued(delta: float) -> int:
	if sink.is_valid():
		_sink_queued = maxf(_sink_queued - delta * output_rate, 0.0)
		return ceili(_sink_queued)
	var free: int = _gen.get_frames_available()
	_capacity = maxi(_capacity, free)
	return _capacity - free


## Starts the player again if it has stopped (or never got going), and follows a change of the
## output mix rate (Windows reopens the device at its own rate when it changes).
func _keep_alive(delta: float) -> void:
	if sink.is_valid():
		return
	if not _rate_injected and AudioServer.get_mix_rate() != output_rate:
		Log.info(&"voice", "%s: output mix rate %d -> %d Hz" % [_who(), roundi(output_rate), roundi(AudioServer.get_mix_rate())])
		output_rate = AudioServer.get_mix_rate()
		_upsampler = VoiceResampler.new(VoiceCodec.SAMPLE_RATE, output_rate)
	if _gen != null and is_playing():
		return
	_restart_wait -= delta
	if _restart_wait > 0.0:
		return
	if _gen != null:
		restarts += 1
		_warn_once("restart", "%s: the voice player had stopped, restarting it" % _who())
	_start()


func _count_played(f: PackedFloat32Array) -> void:
	frames_played += 1
	total_frames_played += 1
	if not _logged_first:
		_logged_first = true
		_log_first(f)
	frame_played.emit(f)


func _log_first(f: PackedFloat32Array) -> void:
	var level: String = VoiceCapture.db_text(VoiceCodec.rms(f))
	if not audio_enabled:
		Log.info(&"voice", "first frame played for %s (headless, no sound, level %s)" % [_who(), level])
		return
	var vol: String = "%.0f%% volume" % (gain * 100.0) if positional else "full volume"
	var bus: int = AudioServer.get_bus_index(BUS)
	var bus_state: String = "missing"
	if bus >= 0:
		bus_state = "%.1f dB%s" % [AudioServer.get_bus_volume_db(bus), ", MUTED" if AudioServer.is_bus_mute(bus) else ""]
	var master: String = "%.1f dB%s" % [AudioServer.get_bus_volume_db(0), ", MUTED" if AudioServer.is_bus_mute(0) else ""]
	Log.info(&"voice", "first frame played for %s (level %s, %s): output mix rate %d Hz, generator %d Hz (8 kHz upsampled by us), playing %s, %s bus %s, Master %s" % [
		_who(), level, vol, roundi(AudioServer.get_mix_rate()), roundi(output_rate), is_playing(), BUS, bus_state, master])
	if _gen == null and not sink.is_valid():
		return
	if not is_playing():
		failure = "the voice player is not playing"
		_warn_once("notplaying", "%s: the voice player is not playing after the first frame: no sound" % _who())


func _play(f: PackedFloat32Array) -> int:
	_count_played(f)
	mouth.feed(f)
	var up: PackedFloat32Array = _upsampler.process(f)
	var stereo := PackedVector2Array()
	stereo.resize(up.size())
	for i: int in up.size():
		stereo[i] = Vector2(up[i], up[i])
	_push(stereo)
	return stereo.size()


func _push(stereo: PackedVector2Array) -> void:
	if stereo.is_empty():
		return
	pushed_frames += stereo.size()
	if sink.is_valid():
		_sink_queued += stereo.size()
		sink.call(stereo)
		return
	if _gen != null and not _gen.push_buffer(stereo):
		_warn_once("full", "%s: voice generator buffer full, %d frames dropped" % [_who(), stereo.size()])


func _who() -> String:
	return "player %d" % speaker if positional else "the microphone test"


func _warn_once(what: String, msg: String) -> void:
	if _warned.has(what):
		return
	_warned[what] = true
	Log.warn(&"voice", msg)


## Loudness from the distance between the speaker's head and the camera that hears it.
func _update_gain() -> void:
	gain = 1.0
	if positional and not full_volume and is_inside_tree():
		var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null:
			gain = VoiceProximity.gain_at(global_position.distance_to(cam.global_position))
	if player != null:
		player.volume_db = linear_to_db(gain) if gain > 0.001 else -80.0
