extends GutTest
## The listening end of voice (§2.22): how loud a speaker is at a distance (full volume within
## 4 m, fading out by 20 m, measured from the camera), table/global voice at full volume, every
## played frame announced (`--voice-dump`, the microphone test), and the non-positional playback
## the settings panel's microphone test uses.

var cam: Camera3D
var head: Node3D
var codec := MulawCodec.new()


func before_each() -> void:
	cam = Camera3D.new()
	add_child_autofree(cam)
	cam.current = true
	head = Node3D.new()
	add_child_autofree(head)


func _playback(positional: bool = true) -> VoicePlayback:
	var pb := VoicePlayback.new()
	pb.speaker = 2
	pb.positional = positional
	head.add_child(pb)
	return pb


func _packet(seq: int, flags: int = 0, amp: float = 0.3) -> Dictionary:
	return {"seq": seq, "flags": flags, "payload": codec.encode(VoiceWav.tone(440.0, VoiceCodec.FRAME_SECONDS, VoiceCodec.SAMPLE_RATE, amp))}


func test_gain_is_full_within_4m_and_fades_out_by_20m() -> void:
	assert_eq(VoiceProximity.gain_at(0.0), 1.0)
	assert_eq(VoiceProximity.gain_at(4.0), 1.0)
	assert_almost_eq(VoiceProximity.gain_at(12.0), 0.5, 0.001, "half volume half way")
	assert_almost_eq(VoiceProximity.gain_at(16.0), 0.25, 0.001)
	assert_eq(VoiceProximity.gain_at(20.0), 0.0)
	assert_eq(VoiceProximity.gain_at(35.0), 0.0)


func test_distance_to_the_camera_sets_the_volume_and_table_voice_ignores_it() -> void:
	var pb: VoicePlayback = _playback()
	head.position = Vector3(0, -VoicePlayback.HEAD_Y, -12.0)  # the head 12 m in front of the camera
	pb.push_packet(_packet(0))
	pb.advance(0.016)
	assert_almost_eq(pb.gain, 0.5, 0.01, "12 m: half volume (Godot's own curve gave -19 dB)")
	head.position = Vector3(0, -VoicePlayback.HEAD_Y, -3.0)
	pb.advance(0.016)
	assert_eq(pb.gain, 1.0, "3 m: full volume")
	head.position = Vector3(0, -VoicePlayback.HEAD_Y, -40.0)
	pb.push_packet(_packet(1, VoicePacket.FLAG_TABLE))
	pb.advance(0.016)
	assert_eq(pb.gain, 1.0, "same table: full volume at any distance")
	pb.push_packet(_packet(2))
	pb.advance(0.016)
	assert_eq(pb.gain, 0.0, "positional again: out of earshot")


func test_every_played_frame_is_announced_in_order() -> void:
	var pb: VoicePlayback = _playback()
	var got: Array[PackedFloat32Array] = []
	pb.frame_played.connect(func(f: PackedFloat32Array) -> void: got.append(f))
	for seq: int in 6:
		pb.push_packet(_packet(seq, VoicePacket.FLAG_END if seq == 5 else 0))
	for i: int in 20:
		pb.advance(VoiceCodec.FRAME_SECONDS)
	assert_eq(got.size(), 6)
	assert_eq(pb.frames_played, 6)
	assert_almost_eq(VoiceCodec.rms(got[3]), 0.3 / sqrt(2.0), 0.02, "the decoded tone")


func test_the_microphone_test_playback_is_not_positional() -> void:
	var pb: VoicePlayback = _playback(false)
	assert_null(pb.icon, "no speaker icon over anyone's head")
	assert_null(pb.player)
	head.position = Vector3(0, 0, -40.0)
	pb.push_packet(_packet(0, VoicePacket.FLAG_END))
	pb.advance(VoiceCodec.FRAME_SECONDS)
	assert_eq(pb.gain, 1.0, "full volume wherever the camera is")
	assert_eq(pb.frames_played, 1)
