class_name VoiceMicTest
extends Node
## Settings → Audio → TEST MICROPHONE (Patrick: "Why is the voicechat still not working? Test it
## somehow"): records `RECORD_SECONDS` from the selected microphone through the real capture path
## (`VoiceCapture`: driver buffer, mono, resampler, 40 ms frames), sends every frame through the
## voice packet framing and the μ-law codec, and plays it back through the real playback path
## (`VoicePlayback`: jitter buffer, decoder, `AudioStreamGenerator`, `Voice` bus, not positional)
## at the pace the network would deliver it. You hear yourself, and `verdict` says in plain words
## what the microphone did ("Microphone works, peak -12 dB", "No audio from the microphone…").
##
## In a match it listens to the voice channel's own capture (two readers would steal each other's
## samples from the driver); elsewhere to the settings meter's capture or a capture of its own.

signal finished(verdict: String)

enum State { IDLE, RECORDING, PLAYING, DONE }

const RECORD_SECONDS: float = 3.0
## Below this peak the microphone only sent silence (dBFS).
const SILENT_DB: float = -60.0
## Below this peak it works but is too quiet to be heard well over the game.
const QUIET_DB: float = -30.0

var state: State = State.IDLE
## What the test found, in plain words ("" until it has a result).
var verdict: String = ""
## Loudest sample recorded (linear).
var peak: float = 0.0
## The recorded 40 ms frames (8 kHz mono).
var frames: Array[PackedFloat32Array] = []
var playback: VoicePlayback = null
## Tests: the microphone a capture of our own reads (null: the real driver).
var source_override: VoiceMicSource = null

var _capture: VoiceCapture = null
var _own_capture: bool = false
var _t: float = 0.0
var _pushed: int = 0
var _codec: MulawCodec = MulawCodec.new()
var _device: String = ""
var _rate: float = 0.0


## Starts recording from `live` (a capture already reading the microphone), or opens one.
func start(live: VoiceCapture = null) -> void:
	_reset()
	if live != null and live.mic_active:
		_capture = live
	else:
		_capture = VoiceCapture.new()
		_capture.name = "MicTestCapture"
		_capture.mode = VoiceCapture.Mode.OFF  # level and frames only, nothing is sent
		if source_override != null:
			_capture.source = source_override
		add_child(_capture)
		_own_capture = true
		if not _capture.start_microphone():
			_finish(verdict_for(_capture.mic_error, 0, 0.0))
			return
	_device = _capture.source.device()
	_capture.frame_processed.connect(_on_frame)
	state = State.RECORDING
	verdict = "Recording %d s: say something…" % roundi(RECORD_SECONDS)
	Log.info(&"voice", "microphone test: recording %.0f s from \"%s\"" % [RECORD_SECONDS, _device])


## Stops whatever the test is doing (closing the panel).
func stop() -> void:
	_release_capture()
	if playback != null:
		playback.queue_free()
		playback = null
	if state == State.RECORDING or state == State.PLAYING:
		state = State.IDLE
		verdict = ""


func is_running() -> bool:
	return state == State.RECORDING or state == State.PLAYING


func _reset() -> void:
	stop()
	frames.clear()
	peak = 0.0
	verdict = ""
	_t = 0.0
	_pushed = 0
	_rate = 0.0


func _on_frame(f: PackedFloat32Array) -> void:
	if state != State.RECORDING:
		return
	frames.append(f)
	for x: float in f:
		peak = maxf(peak, absf(x))


func _process(delta: float) -> void:
	match state:
		State.RECORDING:
			_t += delta
			if _t >= RECORD_SECONDS:
				_end_recording()
		State.PLAYING:
			_t += delta
			while _pushed < frames.size() and _t >= _pushed * VoiceCodec.FRAME_SECONDS:
				_push(_pushed)
				_pushed += 1
			var all_in: bool = _pushed >= frames.size()
			if all_in and (playback.frames_played >= frames.size() or _t > frames.size() * VoiceCodec.FRAME_SECONDS + 1.0):
				var played: int = playback.frames_played
				_finish("%s Played it back: %d of %d frames. You should have heard yourself; if not, check Voice volume and your speakers." % [verdict_for("", frames.size(), peak), played, frames.size()])


func _end_recording() -> void:
	_rate = _capture.input_rate() if _capture != null and is_instance_valid(_capture) else 0.0
	_release_capture()
	var found: String = verdict_for("", frames.size(), peak)
	Log.info(&"voice", "microphone test: %d frames from \"%s\" at %d Hz, peak %s" % [frames.size(), _device, roundi(_rate), VoiceCapture.db_text(peak)])
	if frames.is_empty() or _peak_db(peak) < SILENT_DB:
		_finish(found)
		return
	playback = VoicePlayback.new()
	playback.name = "MicTestPlayback"
	playback.positional = false
	playback.speaker = 0
	add_child(playback)
	state = State.PLAYING
	verdict = found + " Playing it back…"
	_t = 0.0
	_pushed = 0


## One recorded frame, the way it would travel: up packet → relay framing → down packet.
func _push(i: int) -> void:
	var flags: int = VoicePacket.FLAG_END if i == frames.size() - 1 else 0
	var up: Dictionary = VoicePacket.parse_up(VoicePacket.make_up(i, flags, _codec.encode(frames[i])))
	var down: PackedByteArray = VoicePacket.make_down(0, int(up["seq"]), int(up["flags"]), up["payload"])
	playback.push_packet(VoicePacket.parse_down(down))


func _release_capture() -> void:
	if _capture == null or not is_instance_valid(_capture):
		_capture = null
		return
	if _capture.frame_processed.is_connected(_on_frame):
		_capture.frame_processed.disconnect(_on_frame)
	if _own_capture:
		_capture.stop_microphone()
		_capture.queue_free()
	_capture = null
	_own_capture = false


func _finish(text: String) -> void:
	_release_capture()
	state = State.DONE
	verdict = text
	Log.info(&"voice", "microphone test: %s" % text)
	finished.emit(text)


static func _peak_db(p: float) -> float:
	return linear_to_db(p) if p > 0.00001 else -100.0


## The plain-words result for a microphone that would not open (`error`), or that delivered
## `frame_count` frames with a loudest sample of `peak_linear`.
static func verdict_for(error: String, frame_count: int, peak_linear: float) -> String:
	if error != "":
		if error.begins_with("no audio device"):
			return "N%s: no sound card or sound is off for this game." % error.substr(1)
		if AudioServer.get_driver_name() == "Dummy":
			return "No audio device (%s): no sound card or sound is off for this game." % error
		return "No microphone: %s. Check that it is plugged in and allowed in the Windows privacy settings (Microphone: let desktop apps use it)." % error
	if frame_count == 0:
		return "No audio from the microphone: check the Windows privacy settings (Microphone: let desktop apps use it), that it is plugged in, or pick it in the list above."
	var db: float = _peak_db(peak_linear)
	if db < SILENT_DB:
		return "Only silence from the microphone: it is muted, blocked in the Windows privacy settings, or the wrong device (pick it in the list above)."
	if db < QUIET_DB:
		return "Microphone works but is quiet (peak %d dB): raise its level in the Windows sound settings." % roundi(db)
	return "Microphone works, peak %d dB." % roundi(db)
