class_name VoiceCapture
extends Node
## Microphone → voice frames (§2.22). The microphone plays into the muted `Mic` bus, whose
## `AudioEffectCapture` hands us the samples; they are mixed to mono, resampled to 8 kHz, cut into
## 40 ms frames, gated (push-to-talk / open mic with a level threshold / off) and encoded.
##
## Without a microphone (headless, input disabled, no device) nothing is captured, but `feed_*`
## pushes any audio (a generated tone, a WAV via `--voice-test`) through the very same path.

## A frame ready to send (a `VoicePacket` up packet).
signal frame_captured(packet: PackedByteArray)

enum Mode { PUSH_TO_TALK, OPEN_MIC, OFF }

const MIC_BUS: StringName = &"Mic"
## Open mic: frames louder than this open the gate…
const OPEN_MIC_THRESHOLD_DB: float = -40.0
## …and it stays open this long after the voice drops (no clipped word endings).
const HANGOVER: float = 0.4

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
## Mouth flap for our own avatar (fed while transmitting).
var mouth: VoiceMouth = VoiceMouth.new()

var _resampler: VoiceResampler = null
var _pending: PackedFloat32Array = PackedFloat32Array()
var _seq: int = 0
var _hang: float = 0.0
var _frame_age: float = 0.0
var _mic_player: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null


## Starts reading the microphone. False when there is none to read (headless, input disabled in
## the project, no `Mic` bus); the capture then only processes what `feed_*` gives it.
func start_microphone() -> bool:
	if mic_active:
		return true
	if DisplayServer.get_name() == "headless" or not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		return false
	var bus: int = AudioServer.get_bus_index(MIC_BUS)
	if bus < 0:
		Log.warn(&"voice", "no %s bus: voice capture disabled" % MIC_BUS)
		return false
	for i: int in AudioServer.get_bus_effect_count(bus):
		var fx: AudioEffect = AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectCapture:
			_capture = fx as AudioEffectCapture
	if _capture == null:
		Log.warn(&"voice", "the %s bus has no AudioEffectCapture: voice capture disabled" % MIC_BUS)
		return false
	_capture.clear_buffer()
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "Microphone"
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = MIC_BUS
	add_child(_mic_player)
	_mic_player.play()
	mic_active = true
	Log.info(&"voice", "microphone capture started (%d Hz)" % roundi(AudioServer.get_mix_rate()))
	return true


## Stops reading the microphone.
func stop_microphone() -> void:
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.stream = null
		_mic_player.queue_free()
		_mic_player = null
	_capture = null
	mic_active = false


func _exit_tree() -> void:
	stop_microphone()


func _process(delta: float) -> void:
	# Frames drive the mouth; if they stop coming (mic off), let it close on its own.
	_frame_age += delta
	if _frame_age > VoiceCodec.FRAME_SECONDS * 2.0:
		mouth.update(delta)
	if _capture == null:
		return
	var n: int = _capture.get_frames_available()
	if n > 0:
		feed_stereo(_capture.get_buffer(n), AudioServer.get_mix_rate())


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
	_frame_age = 0.0
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
