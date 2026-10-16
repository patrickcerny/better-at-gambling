class_name VoiceChannel
extends Node
## Client side of proximity voice (§2.22), owned by the match scene. Sends our captured frames to
## the server (`Net.send_voice`), feeds every relayed frame to that speaker's `VoicePlayback`
## (created under their avatar on first use), drives everyone's mouth from their voice and keeps
## the per-player mute list (client-side, for this match).
##
## Settings: `audio/voice` (Voice bus volume), `voice/mode` (`MODE_KEYS`), `voice/input_device`
## (the microphone, applied by `Settings`). Push-to-talk is the `push_to_talk` action (T / Caps
## Lock / gamepad; remappable in the Controls tab). `--voice-test <wav>` loops a WAV into the
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
## Packets received per speaker (also those that were ignored, see `diagnostics`).
var received_from: Dictionary[int, int] = {}
## Frames played per speaker.
var played_from: Dictionary[int, int] = {}
## The last thing that went wrong ("" when nothing did), for the settings panel.
var last_error: String = ""
## Plays sound (VoicePlayback); tests turn it off.
var audio_enabled: bool = true
## Tests: called with every new `VoicePlayback` before it enters the tree (to give it a `sink`).
var playback_setup: Callable = Callable()
## `--voice-dump`: where played frames go (empty: not dumping) and what each speaker played.
var dump_path: String = ""
var dumped: Dictionary[int, PackedFloat32Array] = {}

var _mode: String = "push_to_talk"
var _test_samples: PackedFloat32Array = PackedFloat32Array()
var _test_rate: int = 0
var _test_pos: float = 0.0
var _played_at_start: int = 0
var _logged_sent: bool = false
## "<what><player>" keys of the one-off log lines already written.
var _logged: Dictionary[String, bool] = {}


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
	_played_at_start = VoicePlayback.total_frames_played
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
	dump_path = cmd.get_string("voice-dump")
	_apply_settings()
	if online:
		var how: String = MODE_LABELS[MODE_KEYS.find(_mode)]
		if not _test_samples.is_empty() and _mode != "off":
			how = "open mic from the --voice-test WAV"
		Log.info(&"voice", "voice chat: %s, player %d" % [how, local_id])
		Log.info(&"voice", audio_text())


func _exit_tree() -> void:
	if online:
		Log.info(&"voice", "sent %d frames (%d bytes), received %d frames from %d speakers, played %d frames" % [capture.frames_sent, capture.bytes_sent, received_packets, playbacks.size(), VoicePlayback.total_frames_played - _played_at_start])
		for pid: int in received_from:
			Log.info(&"voice", "voice from player %d: received %d, played %d" % [pid, received_from[pid], played_from.get(pid, 0)])
	_write_dump()
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


## The audio driver, output device and mix rates in one line (what a Windows log needs to tell
## why voice is silent).
static func audio_text() -> String:
	var voice: int = AudioServer.get_bus_index(VoicePlayback.BUS)
	var bus: String = "missing" if voice < 0 else "%.1f dB%s" % [AudioServer.get_bus_volume_db(voice), ", MUTED" if AudioServer.is_bus_mute(voice) else ""]
	return "audio: driver %s, output device \"%s\" at %d Hz (%s speakers), input device \"%s\" at %d Hz, Voice bus %s" % [
		AudioServer.get_driver_name(), AudioServer.output_device, roundi(AudioServer.get_mix_rate()),
		["stereo", "3.1", "5.1", "7.1"][clampi(AudioServer.get_speaker_mode(), 0, 3)], AudioServer.input_device, roundi(AudioServer.get_input_mix_rate()), bus]


## True when voice is on but the microphone would not start (see `capture.mic_error`); never
## while `--voice-test` feeds a WAV instead.
func mic_missing() -> bool:
	return is_active() and _test_samples.is_empty() and not capture.mic_active and capture.mic_error != ""


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
	if not is_active():
		return
	if Net.send_voice(packet):
		if not _logged_sent:
			_logged_sent = true
			Log.info(&"voice", "first voice packet sent to the server (%d bytes)" % packet.size())
	elif _once("unsent", 0):
		last_error = "not connected: voice frames are not sent"
		Log.warn(&"voice", last_error)


## A relayed frame from the server (also called directly by tests).
func _on_voice(data: PackedByteArray) -> void:
	var p: Dictionary = VoicePacket.parse_down(data)
	if p.is_empty():
		if _once("malformed", 0):
			Log.warn(&"voice", "malformed voice packet (%d bytes) ignored" % data.size())
		return
	var speaker: int = int(p["speaker"])
	received_from[speaker] = received_from.get(speaker, 0) + 1
	if _once("rx", speaker):
		Log.info(&"voice", "first voice packet received from player %d (%s)" % [speaker, _name(speaker)])
	if not is_active():
		if _once("off", speaker):
			Log.info(&"voice", "voice from player %d ignored: voice chat is off on this PC (Settings > Audio)" % speaker)
		return
	if speaker == local_id:
		return
	if muted.get(speaker, false):
		if _once("muted", speaker):
			Log.info(&"voice", "voice from player %d ignored: muted" % speaker)
		return
	var pb: VoicePlayback = playback_for(speaker)
	if pb == null:
		if _once("noavatar", speaker):
			last_error = "no avatar for player %d yet: their voice is dropped" % speaker
			Log.warn(&"voice", last_error)
		return
	received_packets += 1
	pb.push_packet(p)


## True the first time it is asked about `what` for `pid` (one-off log lines).
func _once(what: String, pid: int) -> bool:
	var key: String = "%s%d" % [what, pid]
	if _logged.has(key):
		return false
	_logged[key] = true
	return true


func _name(pid: int) -> String:
	return state.player_name(pid) if state != null else "player %d" % pid


## One-line status for the settings panel: microphone, frames sent, frames received and played per
## speaker, the last error.
func diagnostics() -> String:
	var mic: String
	if not online:
		return "no voice in Practice (nobody to talk to)"
	if not is_active():
		mic = "voice off"
	elif not _test_samples.is_empty():
		mic = "--voice-test WAV"
	elif capture.mic_active:
		mic = "mic \"%s\" %d Hz" % [capture.source.device(), roundi(capture.input_rate())]
	else:
		mic = "no mic (%s)" % capture.mic_error
	var heard: Array[String] = []
	for pid: int in received_from:
		heard.append("%s %d in/%d played" % [_name(pid), received_from[pid], played_from.get(pid, 0)])
	var err: String = last_error if last_error != "" else capture.mic_error
	return "%s · sent %d · %s · last error: %s" % [mic, capture.frames_sent, ", ".join(heard) if not heard.is_empty() else "heard nobody yet", err if err != "" else "none"]


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
	if playback_setup.is_valid():
		playback_setup.call(pb)
	a.add_child(pb)
	playbacks[pid] = pb
	pb.frame_played.connect(_on_played.bind(pid))
	return pb


func _on_played(f: PackedFloat32Array, pid: int) -> void:
	played_from[pid] = played_from.get(pid, 0) + 1
	if dump_path == "":
		return
	if not dumped.has(pid):
		dumped[pid] = PackedFloat32Array()
	dumped[pid].append_array(f)


## `--voice-dump`: one WAV per speaker heard.
func _write_dump() -> void:
	if dump_path == "":
		return
	for pid: int in dumped:
		var path: String = dump_file(dump_path, pid)
		var err: Error = VoiceWav.write(path, dumped[pid], VoiceCodec.SAMPLE_RATE)
		Log.info(&"voice", "voice dump: %d frames from player %d -> %s (%s)" % [dumped[pid].size() / VoiceCodec.FRAME_SAMPLES, pid, path, error_string(err)])


## Where `--voice-dump <base>` writes player `pid`'s voice.
static func dump_file(base: String, pid: int) -> String:
	return "%s_p%d.wav" % [base.get_basename(), pid]


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
