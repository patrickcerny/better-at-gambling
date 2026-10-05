class_name VoiceChannel
extends Node
## Client side of proximity voice (§2.22), owned by the match scene. Sends our captured frames to
## the server (`Net.send_voice`), feeds every relayed frame to that speaker's `VoicePlayback`
## (created under their avatar on first use), drives everyone's mouth from their voice and keeps
## the per-player mute list (client-side, for this match).
##
## Settings: `audio/voice` (Voice bus volume), `voice/mode` (`MODE_KEYS`). Push-to-talk is the
## `push_to_talk` action (T / Caps Lock / gamepad). `--voice-test <wav>` loops a WAV into the
## capture path in open-mic mode instead of the microphone.

const MODE_KEYS: Array[String] = ["push_to_talk", "open_mic", "off"]
const MODE_LABELS: Array[String] = ["Push to talk (T)", "Open mic", "Off"]

## The live channel (the settings panel's mute list reads it); null outside a match.
static var current: VoiceChannel = null

## Voice runs only against a real server (online); Practice has nobody to talk to.
var online: bool = false
var local_id: int = -1
var state: ClientMatchState = null
## Callable(player: int) -> Node3D, normally the `PlayerAvatar` (null when there is none).
var avatar_of: Callable
var capture: VoiceCapture
var hud: VoiceHud = null
var playbacks: Dictionary[int, VoicePlayback] = {}
var muted: Dictionary[int, bool] = {}
var received_packets: int = 0
## Plays sound (VoicePlayback); tests turn it off.
var audio_enabled: bool = true

var _mode: String = "push_to_talk"
var _test_samples: PackedFloat32Array = PackedFloat32Array()
var _test_rate: int = 0
var _test_pos: float = 0.0


## Wires the channel up before it enters the tree. `ui_parent` gets the voice HUD (may be null).
func setup(p_state: ClientMatchState, p_local_id: int, p_avatar_of: Callable, ui_parent: Node, p_online: bool) -> void:
	state = p_state
	local_id = p_local_id
	avatar_of = p_avatar_of
	online = p_online
	if ui_parent != null and online:
		hud = VoiceHud.new()
		hud.name = "VoiceHud"
		hud.channel = self
		ui_parent.add_child(hud)


func _ready() -> void:
	current = self
	capture = VoiceCapture.new()
	capture.name = "Capture"
	add_child(capture)
	capture.frame_captured.connect(_on_frame)
	if not Net.voice_received.is_connected(_on_voice):
		Net.voice_received.connect(_on_voice)
	Settings.changed.connect(_apply_settings)
	var cmd: Cmdline = SceneRouter.cmdline if SceneRouter.cmdline != null else Cmdline.from_os()
	var wav: String = cmd.get_string("voice-test")
	if wav != "":
		var w: Dictionary = VoiceWav.read(wav)
		if w.is_empty():
			Log.warn(&"voice", "--voice-test: could not read %s (PCM WAV expected)" % wav)
		else:
			_test_samples = w["samples"]
			_test_rate = int(w["rate"])
			Log.info(&"voice", "--voice-test: looping %s (%.1f s) into the capture path" % [wav, _test_samples.size() / float(_test_rate)])
	_apply_settings()


func _exit_tree() -> void:
	if online:
		Log.info(&"voice", "sent %d frames (%d bytes), played %d frames from %d speakers" % [capture.frames_sent, capture.bytes_sent, received_packets, playbacks.size()])
	if current == self:
		current = null
	if Net.voice_received.is_connected(_on_voice):
		Net.voice_received.disconnect(_on_voice)
	if Settings.changed.is_connected(_apply_settings):
		Settings.changed.disconnect(_apply_settings)


func _apply_settings() -> void:
	_mode = str(Settings.get_value("voice", "mode", "push_to_talk"))
	if not (_mode in MODE_KEYS):
		_mode = "push_to_talk"
	var active: bool = online and _mode != "off"
	if not _test_samples.is_empty():
		capture.mode = VoiceCapture.Mode.OPEN_MIC if active else VoiceCapture.Mode.OFF
	else:
		capture.mode = VoiceCapture.Mode.OFF if not active else (VoiceCapture.Mode.OPEN_MIC if _mode == "open_mic" else VoiceCapture.Mode.PUSH_TO_TALK)
		if active:
			capture.start_microphone()
		else:
			capture.stop_microphone()
	if not active:
		for pid: int in playbacks:
			var pb: VoicePlayback = _live_playback(pid)
			if pb != null:
				pb.clear()


## The current mode key (see `MODE_KEYS`).
func mode_key() -> String:
	return _mode


## True while voice is on (online and not switched off).
func is_active() -> bool:
	return online and _mode != "off"


func _process(delta: float) -> void:
	capture.ptt_pressed = InputMap.has_action(&"push_to_talk") and Input.is_action_pressed(&"push_to_talk")
	if not _test_samples.is_empty() and _test_rate > 0:
		_feed_test(delta)
	for pid: int in playbacks.keys():
		var pb: VoicePlayback = _live_playback(pid)
		if pb == null:
			playbacks.erase(pid)  # the avatar went away with it
			continue
		_set_mouth(pid, pb.mouth.openness)
	_set_mouth(local_id, capture.mouth.openness)


func _feed_test(delta: float) -> void:
	var start: int = int(_test_pos)
	_test_pos += delta * _test_rate
	var chunk := PackedFloat32Array()
	for i: int in range(start, int(_test_pos)):
		chunk.append(_test_samples[i % _test_samples.size()])
	if _test_pos >= _test_samples.size():
		_test_pos -= _test_samples.size()
	capture.feed_mono(chunk, _test_rate)


func _set_mouth(pid: int, openness: float) -> void:
	if not avatar_of.is_valid():
		return
	var a: Node3D = avatar_of.call(pid)
	if a is PlayerAvatar and (a as PlayerAvatar).visuals != null:
		(a as PlayerAvatar).visuals.mouth_open = openness


func _on_frame(packet: PackedByteArray) -> void:
	if is_active():
		Net.send_voice(packet)


## A relayed frame from the server (also called directly by tests).
func _on_voice(data: PackedByteArray) -> void:
	if not is_active():
		return
	var p: Dictionary = VoicePacket.parse_down(data)
	if p.is_empty():
		return
	var speaker: int = int(p["speaker"])
	if speaker == local_id or muted.get(speaker, false):
		return
	var pb: VoicePlayback = playback_for(speaker)
	if pb != null:
		received_packets += 1
		pb.push_packet(p)


## The speaker's playback node, created under their avatar on first use (null without an avatar).
func playback_for(pid: int) -> VoicePlayback:
	var pb: VoicePlayback = _live_playback(pid)
	if pb != null:
		return pb
	if not avatar_of.is_valid():
		return null
	var a: Node3D = avatar_of.call(pid)
	if a == null or not a.is_inside_tree():
		return null
	pb = VoicePlayback.new()
	pb.name = "VoicePlayback"
	pb.speaker = pid
	pb.audio_enabled = audio_enabled
	a.add_child(pb)
	playbacks[pid] = pb
	return pb


## The speaker's playback node, or null (never a freed one: avatars take theirs with them).
func _live_playback(pid: int) -> VoicePlayback:
	var v: Variant = playbacks.get(pid, null)
	if v == null or not is_instance_valid(v):
		return null
	var pb: VoicePlayback = v
	return null if pb.is_queued_for_deletion() else pb


func set_muted(pid: int, on: bool) -> void:
	if on:
		muted[pid] = true
		var pb: VoicePlayback = _live_playback(pid)
		if pb != null:
			pb.clear()
	else:
		muted.erase(pid)


func is_muted(pid: int) -> bool:
	return muted.get(pid, false)


## True while `pid` is audibly talking (we are talking: our own transmit state).
func is_talking(pid: int) -> bool:
	if pid == local_id:
		return capture.transmitting
	var pb: VoicePlayback = _live_playback(pid)
	return pb != null and pb.is_talking()


## Other players, for mute lists: [{id, name, muted}].
func roster() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	for pid: int in state.players:
		if pid == local_id:
			continue
		out.append({"id": pid, "name": state.player_name(pid), "muted": is_muted(pid)})
	return out
