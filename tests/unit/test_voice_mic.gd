extends GutTest
## The microphone end of voice (Patrick on 0.9.0: "fix the proximity chat. It doesnt work."):
## `VoiceCapture` reads the driver's input buffer through `VoiceMicSource` at the device's own
## rate, push-to-talk on T (remappable), a microphone that will not open is reported instead of
## silently sending nothing, and the saved input device falls back to Default when it is gone.


## A microphone that plays a tone at `rate` Hz, `per_read` frames at a time.
class FakeMic:
	extends VoiceMicSource
	var mic_rate: float = 48000.0
	var fail: bool = false
	var queued: PackedVector2Array = PackedVector2Array()
	var phase: int = 0
	var starts: int = 0
	var stops: int = 0

	func start() -> Error:
		starts += 1
		if fail:
			error = "could not open the microphone \"Default\" (error 1)"
			return FAILED
		error = ""
		return OK

	func stop() -> void:
		stops += 1

	func available() -> int:
		return queued.size()

	func read(frames: int) -> PackedVector2Array:
		if frames > queued.size():
			return PackedVector2Array()
		var out: PackedVector2Array = queued.slice(0, frames)
		queued = queued.slice(frames)
		return out

	func rate() -> float:
		return mic_rate

	func device() -> String:
		return "Default"

	## Queues `seconds` of a 300 Hz tone at `amp` (stereo, as drivers deliver it).
	func speak(seconds: float, amp: float = 0.4) -> void:
		for i: int in int(seconds * mic_rate):
			var x: float = amp * sin(TAU * 300.0 * phase / mic_rate)
			phase += 1
			queued.append(Vector2(x, x))


var cap: VoiceCapture
var mic: FakeMic
var packets: Array[PackedByteArray] = []


func before_each() -> void:
	cap = VoiceCapture.new()
	mic = FakeMic.new()
	cap.source = mic
	add_child_autofree(cap)
	packets.clear()
	cap.frame_captured.connect(func(p: PackedByteArray) -> void: packets.append(p))


func after_each() -> void:
	Settings.reset_keybinds()


## One second of microphone audio, read the way `_process` reads it each frame.
func _talk(seconds: float, rate: float = 48000.0) -> void:
	mic.mic_rate = rate
	var steps: int = int(seconds / 0.016)
	for i: int in steps:
		mic.speak(0.016)
		cap._process(0.016)


func test_microphone_frames_at_the_device_rate_become_8k_voice_frames() -> void:
	assert_true(cap.start_microphone())
	assert_true(cap.mic_active)
	assert_eq(cap.mic_error, "")
	cap.mode = VoiceCapture.Mode.PUSH_TO_TALK
	cap.ptt_pressed = true
	_talk(1.0)
	assert_gt(cap.mic_frames, 47000, "the driver's samples are read")
	assert_between(packets.size(), 23, 25, "25 frames of 40 ms per second at 48 kHz in")
	var p: Dictionary = VoicePacket.parse_up(packets[10])
	var decoded: PackedFloat32Array = MulawCodec.new().decode(p["payload"])
	assert_eq(decoded.size(), VoiceCodec.FRAME_SAMPLES)
	assert_almost_eq(VoiceCodec.rms(decoded), 0.4 / sqrt(2.0), 0.03, "the voice survives resampling and μ-law")
	assert_gt(cap.meter_level(), 0.2, "the settings meter sees the level")


func test_44k_device_works_too() -> void:
	cap.start_microphone()
	cap.mode = VoiceCapture.Mode.OPEN_MIC
	_talk(1.0, 44100.0)
	assert_between(packets.size(), 23, 25)


func test_push_to_talk_gates_the_microphone() -> void:
	cap.start_microphone()
	cap.mode = VoiceCapture.Mode.PUSH_TO_TALK
	cap.ptt_pressed = false
	_talk(0.5)
	assert_eq(packets.size(), 0, "nothing sent while T is up")
	assert_gt(cap.meter_level(), 0.0, "but the level meter still moves")
	cap.ptt_pressed = true
	_talk(0.5)
	assert_gt(packets.size(), 8)
	assert_true(cap.transmitting)


func test_stale_audio_after_a_stall_is_skipped() -> void:
	cap.start_microphone()
	mic.speak(2.0)  # a 2 s hitch (loading) left this much waiting
	var got: PackedVector2Array = mic.read_all()
	assert_eq(got.size(), int(mic.mic_rate * VoiceMicSource.KEEP_SECONDS), "only the newest 100 ms is kept")
	assert_eq(mic.available(), 0)
	mic.speak(0.02)
	assert_eq(mic.read_all().size(), int(mic.mic_rate * 0.02), "normal reads keep everything")


func test_a_microphone_that_will_not_open_is_reported_and_retried() -> void:
	mic.fail = true
	assert_false(cap.start_microphone())
	assert_false(cap.mic_active)
	assert_ne(cap.mic_error, "", "the reason is kept for the HUD and the settings panel")
	assert_eq(SettingsPanel.mic_status_text(cap).begins_with("No microphone"), true)
	mic.fail = false
	assert_true(cap.start_microphone(), "plugged in later: the next try opens it")
	assert_eq(cap.mic_error, "")
	assert_eq(mic.starts, 2)
	cap.stop_microphone()
	assert_eq(mic.stops, 1)
	assert_false(cap.mic_active)


func test_real_source_headless_reports_why() -> void:
	var src := VoiceMicSource.new()
	assert_ne(src.start(), OK)
	assert_ne(src.error, "")
	assert_eq(src.read_all().size(), 0)
	src.stop()


func test_push_to_talk_is_t_and_remappable() -> void:
	assert_true(InputMap.has_action(&"push_to_talk"))
	assert_eq(Settings.binding_label(&"push_to_talk"), "T")
	assert_true(Settings.KEYBINDS.has(&"push_to_talk"), "listed in the Controls tab")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_V
	Settings.bind_key(&"push_to_talk", k)
	assert_eq(Settings.binding_label(&"push_to_talk"), "V")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_V
	press.pressed = true
	assert_true(press.is_action(&"push_to_talk"), "V now talks")
	Settings.reset_keybinds()
	assert_eq(Settings.binding_label(&"push_to_talk"), "T")


func test_saved_input_device_falls_back_to_default_when_unplugged() -> void:
	var devices := PackedStringArray(["Default", "USB Headset", "Webcam Mic"])
	assert_eq(Settings.pick_input_device("USB Headset", devices), "USB Headset")
	assert_eq(Settings.pick_input_device("Old Mic", devices), "Default")
	assert_eq(Settings.pick_input_device("", devices), "Default")
	assert_eq(str(Settings.DEFAULTS["voice"]["input_device"]), "Default")


func test_apply_points_the_driver_at_the_saved_device() -> void:
	var old: String = str(Settings.get_value("voice", "input_device"))
	Settings.change("voice", "input_device", "Microphone that is not here")
	assert_eq(AudioServer.input_device, "Default", "missing device: the system default")
	assert_eq(str(Settings.get_value("voice", "input_device")), "Microphone that is not here", "the choice stays saved")
	Settings.change("voice", "input_device", old)
	assert_eq(AudioServer.input_device, "Default")
