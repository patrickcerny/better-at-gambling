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
## Every 40 ms mono frame at 8 kHz, gated or not (the settings panel's "Test microphone" records
## these).
signal frame_processed(frame: PackedFloat32Array)

enum Mode { PUSH_TO_TALK, OPEN_MIC, OFF }

## Open mic: frames louder than this open the gate… (-45 dBFS: a quiet webcam or laptop mic at
## Windows' default level speaks at -35..-45 dBFS RMS; room hiss sits around -60.)
const OPEN_MIC_THRESHOLD_DB: float = -45.0
## …and it stays open this long after the voice drops (no clipped word endings).
const HANGOVER: float = 0.4
## Seconds a started microphone may deliver nothing before we log that it is silent.
const SILENT_WARN_SECONDS: float = 3.0
## A channel this much quieter than the other (energy ratio, -12 dB) counts as dead: a mic that
## only fills one side of a stereo stream would otherwise come out 6 dB quieter.
const DEAD_CHANNEL_RATIO: float = 1.0 / 16.0
## Seconds of steady microphone audio after which the delivered frame rate is compared with the
## rate the driver reports.
const RATE_CHECK_SECONDS: float = 3.0
## Sample rates a device may really run at (the measured rate snaps to one of these).
const COMMON_RATES: Array[int] = [8000, 11025, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000]

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
## Frames delivered per second as measured over `RATE_CHECK_SECONDS` (0 until measured).
var measured_rate: float = 0.0
## Rate the samples are resampled from when the device does not run at the rate it reports
## (0: trust `source.rate()`).
var rate_override: float = 0.0
## Microsecond clock for the rate check (tests replace it).
var clock: Callable = Time.get_ticks_usec

var _resampler: VoiceResampler = null
var _pending: PackedFloat32Array = PackedFloat32Array()
var _seq: int = 0
var _hang: float = 0.0
var _mic_for: float = 0.0
var _warned_silent: bool = false
var _first_audio_logged: bool = false
var _first_frame_logged: bool = false
var _rate_t0: int = -1
var _rate_frames: int = 0
var _rate_skipped_at: int = 0


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
	_first_audio_logged = false
	_rate_t0 = -1
	_rate_frames = 0
	measured_rate = 0.0
	rate_override = 0.0
	_pending.clear()
	Log.info(&"voice", "microphone opened: device \"%s\" at %d Hz (driver %s)" % [source.device(), roundi(source.rate()), AudioServer.get_driver_name()])
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
		_check_rate(buf.size())
		feed_stereo(buf, input_rate())
		mic_peak = maxf(mic_peak, level)
		if not _first_audio_logged:
			_first_audio_logged = true
			Log.info(&"voice", "microphone: first audio after %.1f s (%d frames, level %s)" % [_mic_for, buf.size(), db_text(level)])
	_mic_for += delta
	if not _warned_silent and _mic_for >= SILENT_WARN_SECONDS and mic_peak <= 0.0:
		_warned_silent = true
		var what: String = "no audio" if mic_frames == 0 else "only silence"
		Log.warn(&"voice", "microphone \"%s\" delivered %s in %.0f s (%d frames at %d Hz): muted, blocked in the Windows privacy settings, or the wrong device (Settings > Audio)" % [source.device(), what, _mic_for, mic_frames, roundi(source.rate())])


## The rate the microphone's samples are resampled from: the driver's, unless the device was
## measured running at another one (see `_check_rate`).
func input_rate() -> float:
	return rate_override if rate_override > 0.0 else source.rate()


## Compares the frames the driver delivers with the rate it reports, once per start: a device that
## runs at another rate (Windows can hand out a 16 kHz headset or a 44.1 kHz mic as "48000")
## would come out too fast or too slow and overflow the listeners' jitter buffers.
func _check_rate(frames: int) -> void:
	if measured_rate > 0.0:
		return
	var now: int = int(clock.call())
	if _rate_t0 < 0:
		_rate_t0 = now  # what waited before the first read came in before t0
		_rate_frames = 0
		_rate_skipped_at = source.skipped
		return
	_rate_frames += frames + source.skipped - _rate_skipped_at
	_rate_skipped_at = source.skipped
	var secs: float = (now - _rate_t0) / 1000000.0
	if secs < RATE_CHECK_SECONDS:
		return
	measured_rate = _rate_frames / secs
	var reported: float = source.rate()
	var snapped: int = nearest_common_rate(measured_rate)
	if snapped > 0 and absf(snapped - reported) > reported * 0.04:
		rate_override = snapped
		Log.warn(&"voice", "microphone \"%s\" delivers %d frames/s but reports %d Hz: resampling from %d Hz" % [source.device(), roundi(measured_rate), roundi(reported), snapped])
	else:
		Log.info(&"voice", "microphone delivers %d frames/s (reported %d Hz)" % [roundi(measured_rate), roundi(reported)])


## The common sample rate within 2 % of `rate`, or 0 (a hitch or a stall makes odd numbers).
static func nearest_common_rate(rate: float) -> int:
	for r: int in COMMON_RATES:
		if absf(rate - r) <= r * 0.02:
			return r
	return 0


## "-23 dB" for a linear level ("silence" for digital zero).
static func db_text(linear: float) -> String:
	return "%.0f dB" % linear_to_db(linear) if linear > 0.00001 else "silence"


## Level for a meter: the last frame's RMS (linear), fading to 0 when frames stop coming.
func meter_level() -> float:
	return level if frame_age < 0.25 else 0.0


## Feeds stereo audio at `rate` Hz (the driver's format).
func feed_stereo(buffer: PackedVector2Array, rate: float) -> void:
	feed_mono(to_mono(buffer), rate)


## Stereo → mono. Both channels are averaged, unless one is dead (`DEAD_CHANNEL_RATIO`): then the
## live one is taken alone, so a mic that only fills the left channel is not halved.
static func to_mono(buffer: PackedVector2Array) -> PackedFloat32Array:
	var el: float = 0.0
	var er: float = 0.0
	for f: Vector2 in buffer:
		el += f.x * f.x
		er += f.y * f.y
	var mono := PackedFloat32Array()
	mono.resize(buffer.size())
	if er < el * DEAD_CHANNEL_RATIO:
		for i: int in buffer.size():
			mono[i] = buffer[i].x
	elif el < er * DEAD_CHANNEL_RATIO:
		for i: int in buffer.size():
			mono[i] = buffer[i].y
	else:
		for i: int in buffer.size():
			mono[i] = (buffer[i].x + buffer[i].y) * 0.5
	return mono


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
	frame_processed.emit(frame)
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
	if not _first_frame_logged:
		_first_frame_logged = true
		Log.info(&"voice", "first voice frame captured (%s, level %s)" % [Mode.keys()[mode].to_lower(), db_text(level)])
	frame_captured.emit(packet)
