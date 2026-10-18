extends GutTest
## Voice from one player's microphone to another player's speaker, in one process (Patrick on
## 0.9.0: "fix the proximity chat. It doesnt work."): holding the `push_to_talk` action with a
## (fake) microphone talking → `VoiceChannel` A → server relay with the real proximity rules →
## `VoiceChannel` B → B's `VoicePlayback` under A's avatar plays the frames and flaps the mouth.
## The multi-process version over real ENet sockets is `tests/net/test_net_match.py -k voice`.

const FakeMicTest = preload("res://tests/unit/test_voice_mic.gd")

var fx: ServerFixture
var relay: VoiceRelay
var alice: int
var bob: int
var ch_a: VoiceChannel
var ch_b: VoiceChannel
var mic: VoiceMicSource
## Avatars as each client sees them (player id → node).
var avatars_a: Dictionary[int, Node3D] = {}
var avatars_b: Dictionary[int, Node3D] = {}
var _old_mode: String
## Seconds of simulated time (the relay's bandwidth clock).
var _t: float = 0.0


func before_each() -> void:
	_old_mode = str(Settings.get_value("voice", "mode"))
	Settings.change("voice", "mode", "push_to_talk")
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 100.0, "seed": 3})
	fx.server.start_match()
	fx.run(3.1)  # casino: proximity voice
	relay = VoiceRelay.new()
	alice = fx.player_ids[0]
	bob = fx.player_ids[1]
	fx.server.world.set_transform(alice, Vector3.ZERO, 0.0)
	fx.server.world.set_transform(bob, Vector3(3, 0, 0), 0.0)
	for pid: int in fx.player_ids:
		avatars_a[pid] = _avatar("A%d" % pid)
		avatars_b[pid] = _avatar("B%d" % pid)
	ch_a = _channel(alice, avatars_a)
	ch_b = _channel(bob, avatars_b)
	ch_b.audio_enabled = false
	mic = FakeMicTest.FakeMic.new()
	ch_a.capture.source = mic
	assert_true(ch_a.capture.start_microphone(), "the (fake) microphone opens")
	# What the server would do with A's packets: route them, B's client receives its copy.
	ch_a.capture.frame_captured.disconnect(ch_a._on_frame)
	ch_a.capture.frame_captured.connect(_relay_from_a)


func after_each() -> void:
	Input.action_release(&"push_to_talk")
	Settings.change("voice", "mode", _old_mode)
	fx.server.free()


func _avatar(n: String) -> Node3D:
	var a := Node3D.new()
	a.name = n
	add_child_autofree(a)
	return a


func _channel(pid: int, avatars: Dictionary[int, Node3D]) -> VoiceChannel:
	var ch := VoiceChannel.new()
	ch.setup(null, pid, func(p: int) -> Node3D: return avatars.get(p, null), null, true)
	add_child_autofree(ch)
	return ch


func _relay_from_a(packet: PackedByteArray) -> void:
	assert_true(ch_a.is_active(), "A only sends while voice is on")
	var out: Dictionary[int, PackedByteArray] = relay.route(fx.server, alice, packet, _t, fx.player_ids)
	if out.has(bob):
		ch_b._on_voice(out[bob])


## `seconds` of game frames: A's mic delivers audio, both channels and B's playbacks tick.
func _run(seconds: float, talking: bool = true) -> void:
	var dt: float = 0.016
	for i: int in int(seconds / dt):
		_t += dt
		if talking:
			(mic as FakeMicTest.FakeMic).speak(dt)
		ch_a._process(dt)
		ch_a.capture._process(dt)
		ch_b._process(dt)
		var pb: VoicePlayback = ch_b.playbacks.get(alice, null)
		if pb != null:
			pb.advance(dt)


func test_holding_push_to_talk_is_heard_by_a_player_nearby() -> void:
	_run(0.5)
	assert_eq(ch_a.capture.frames_sent, 0, "not holding T: nothing goes out")
	assert_eq(ch_b.received_packets, 0)
	Input.action_press(&"push_to_talk")
	_run(1.0)
	assert_true(ch_a.capture.transmitting, "holding T: transmitting")
	assert_true(ch_a.is_talking(alice), "own talking state for the HUD")
	assert_gt(ch_a.capture.frames_sent, 20)
	assert_gt(ch_b.received_packets, 20, "B receives A's frames through the relay")
	var pb: VoicePlayback = ch_b.playbacks.get(alice, null)
	assert_not_null(pb, "B plays A's voice under A's avatar")
	if pb == null:
		return
	assert_eq(pb.get_parent(), avatars_b[alice])
	assert_gt(pb.frames_played, 15, "and actually plays the frames")
	assert_true(pb.is_talking(), "A's mouth moves on B's screen")
	assert_true(ch_b.is_talking(alice))
	Input.action_release(&"push_to_talk")
	_run(1.0)
	assert_false(ch_a.capture.transmitting)
	assert_false(pb.is_talking(), "the mouth closes when A lets go")


func test_out_of_reach_is_not_heard_and_voice_off_sends_nothing() -> void:
	fx.server.world.set_transform(bob, Vector3(0, 0, 40), 0.0)
	Input.action_press(&"push_to_talk")
	_run(0.5)
	assert_gt(ch_a.capture.frames_sent, 5)
	assert_eq(ch_b.received_packets, 0, "40 m away: out of earshot")
	fx.server.world.set_transform(bob, Vector3(3, 0, 0), 0.0)
	Settings.change("voice", "mode", "off")
	assert_false(ch_a.capture.mic_active, "voice off closes the microphone")
	var sent: int = ch_a.capture.frames_sent
	_run(0.5)
	assert_eq(ch_a.capture.frames_sent, sent)


func test_open_mic_needs_no_key() -> void:
	Settings.change("voice", "mode", "open_mic")
	assert_true(ch_a.capture.mic_active)
	_run(1.0)
	assert_gt(ch_b.received_packets, 20)


## 0.9.12: push-to-talk was the default and almost nobody held T (15 frames of voice in a whole
## casino round on the VPS). With nothing saved, voice is open mic and talking is enough.
func test_a_fresh_install_talks_on_open_mic_without_a_key() -> void:
	assert_eq(Settings.DEFAULTS["voice"]["mode"], "open_mic")
	if Settings._cfg.has_section_key("voice", "mode"):
		Settings._cfg.erase_section_key("voice", "mode")
	Settings.changed.emit()
	assert_eq(ch_a.mode_key(), "open_mic", "the default mode")
	assert_eq(ch_a.capture.mode, VoiceCapture.Mode.OPEN_MIC)
	assert_true(ch_a.capture.mic_active, "the microphone is open")
	_run(1.0)
	assert_gt(ch_a.capture.frames_sent, 20, "speech goes out with no key held")
	assert_gt(ch_b.received_packets, 20, "and is heard nearby")


func _key_t(pressed: bool) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_T
	k.pressed = pressed
	Input.parse_input_event(k)
	Input.flush_buffered_events()


## The key itself (not `Input.action_press`): T held while a text field has the focus (a menu, the
## lobby panel) still talks, and the HUD names the key.
func test_holding_the_t_key_talks_even_with_a_focused_text_field() -> void:
	var field := LineEdit.new()
	add_child_autofree(field)
	field.grab_focus()
	_key_t(true)
	_run(0.6)
	assert_true(ch_a.capture.transmitting, "T held: transmitting")
	assert_gt(ch_b.received_packets, 8)
	_key_t(false)
	_run(0.3)
	assert_false(ch_a.capture.transmitting, "T up: quiet")
	var hud := VoiceHud.new()
	hud.channel = ch_a
	add_child_autofree(hud)
	hud._process(1.0)
	assert_eq(hud._self_label.text, "Hold T to talk")
