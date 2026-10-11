class_name VoiceCapture
extends Node
## Microphone → voice frames (§2.22). Samples come straight from the audio driver's input buffer
## (`VoiceMicSource`), are mixed to mono, resampled to 8 kHz, cut into 40 ms frames, gated
## (push-to-talk / open mic with a level threshold / off) and encoded.
##
## Without a microphone (headless, input disabled, no device) nothing is captured, but `feed_*`
## pushes any audio (a generated tone, a WAV via `--voice-test`) through the very same path.

## A frame ready to send (a `VoicePacket` up packet).
signal frame_captured(packet: PackedByteArray)

enum Mode { PUSH_TO_TALK, OPEN_MIC, OFF }

## Open mic: frames louder than this open the gate…
const OPEN_MIC_THRESHOLD_DB: float = -40.0
## …and it stays open this long after the voice drops (no clipped word endings).
const HANGOVER: float = 0.4
## Seconds a started microphone may deliver nothing before we log that it is silent.
const SILENT_WARN_SECONDS: float = 3.0

var mode: Mode = Mode.PUSH_TO_TALK
## Push-to-talk key state (the channel reads the input map).
var ptt_pressed: bool = false
var codec: VoiceCodec = MulawCodec.new()
## Level of the last frame (RMS, linear).
var level: float = 0.0
## True while the last frame was sent.
var transmitting: bool = false
var frames_sent: int = 0
var bytes_sent: int = 0
## True once a real microphone is being read.
var mic_active: bool = false
## Why the microphone could not start ("" when it did, or was never asked to).
var mic_error: String = ""
## Where microphone samples come from (tests swap in a fake).
var source: VoiceMicSource = VoiceMicSource.new()
## Microphone frames read since `start_microphone` (stereo frames at the device rate).
var mic_frames: int = 0
## Loudest frame (RMS) since `start_microphone`: 0 means the device only ever sent digital silence.
var mic_peak: float = 0.0
## Seconds since the last frame went through `_frame` (the level meter fades when it grows).
var frame_age: float = 0.0
## Mouth flap for our own avatar (fed while transmitting).
var mouth: VoiceMouth = VoiceMouth.new()

var _resampler: VoiceResampler = null
var _pending: PackedFloat32Array = PackedFloat32Array()
var _seq: int = 0
var _hang: float = 0.0
var _mic_for: float = 0.0
var _warned_silent: bool = false


## Starts reading the microphone. False when there is none to read (headless, input disabled in
## the project, the device would not open: see `mic_error`); the capture then only processes
## what `feed_*` gives it.
func start_microphone() -> bool:
	if mic_active:
		return true
	if source.start() != OK:
		if mic_error != source.error:
			mic_error = source.error
			if DisplayServer.get_name() != "headless":
				Log.warn(&"voice", "microphone: %s" % mic_error)
		return false
	mic_error = ""
	mic_active = true
	mic_frames = 0
	mic_peak = 0.0
	_mic_for = 0.0
	_warned_silent = false
	_pending.clear()
	Log.info(&"voice", "microphone capture started: device \"%s\" at %d Hz" % [source.device(), roundi(source.rate())])
	return true


## Stops reading the microphone.
func stop_microphone() -> void:
	if not mic_active:
		return
	source.stop()
	mic_active = false
	Log.info(&"voice", "microphone capture stopped (%d frames read, peak level %.3f)" % [mic_frames, mic_peak])


func _exit_tree() -> void:
	stop_microphone()


func _process(delta: float) -> void:
	# Frames drive the mouth; if they stop coming (mic off), let it close on its own.
	frame_age += delta
	if frame_age > VoiceCodec.FRAME_SECONDS * 2.0:
		mouth.update(delta)
	if not mic_active:
		return
	var buf: PackedVector2Array = source.read_all()
	if not buf.is_empty():
		mic_frames += buf.size()
		feed_stereo(buf, source.rate())
		mic_peak = maxf(mic_peak, level)
	_mic_for += delta
	if not _warned_silent and _mic_for >= SILENT_WARN_SECONDS and mic_peak <= 0.0:
		_warned_silent = true
		var what: String = "no audio" if mic_frames == 0 else "only silence"
		Log.warn(&"voice", "microphone \"%s\" delivered %s in %.0f s (%d frames at %d Hz): muted, blocked in the Windows privacy settings, or the wrong device (Settings > Audio)" % [source.device(), what, _mic_for, mic_frames, roundi(source.rate())])


## Level for a meter: the last frame's RMS (linear), fading to 0 when frames stop coming.
func meter_level() -> float:
	return level if frame_age < 0.25 else 0.0


## Feeds stereo audio at `rate` Hz (the capture effect's format).
func feed_stereo(buffer: PackedVector2Array, rate: float) -> void:
	var mono := PackedFloat32Array()
	mono.resize(buffer.size())
	for i: int in buffer.size():
		mono[i] = (buffer[i].x + buffer[i].y) * 0.5
	feed_mono(mono, rate)


## Feeds mono audio at `rate` Hz.
func feed_mono(samples: PackedFloat32Array, rate: float) -> void:
	if _resampler == null or not is_equal_approx(_resampler.from_rate, rate):
		_resampler = VoiceResampler.new(rate, VoiceCodec.SAMPLE_RATE)
	_pending.append_array(_resampler.process(samples))
	var n: int = VoiceCodec.FRAME_SAMPLES
	var used: int = 0
	while _pending.size() - used >= n:
		_frame(_pending.slice(used, used + n))
		used += n
	if used > 0:
		_pending = _pending.slice(used)


func _frame(frame: PackedFloat32Array) -> void:
	level = VoiceCodec.rms(frame)
	frame_age = 0.0
	var want: bool = false
	match mode:
		Mode.PUSH_TO_TALK:
			want = ptt_pressed
		Mode.OPEN_MIC:
			if VoiceCodec.rms_db(frame) >= OPEN_MIC_THRESHOLD_DB:
				_hang = HANGOVER
			want = _hang > 0.0
			_hang -= VoiceCodec.FRAME_SECONDS
	if want:
		mouth.feed(frame)
	mouth.update(VoiceCodec.FRAME_SECONDS)
	if not want and not transmitting:
		return
	# The first silent frame after a spurt still goes out, flagged as the end.
	var packet: PackedByteArray = VoicePacket.make_up(_seq, 0 if want else VoicePacket.FLAG_END, codec.encode(frame))
	_seq = (_seq + 1) & 0xFFFF
	transmitting = want
	frames_sent += 1
	bytes_sent += packet.size()
	frame_captured.emit(packet)
