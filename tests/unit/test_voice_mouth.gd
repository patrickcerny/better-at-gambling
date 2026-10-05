extends GutTest
## "The mouths move" (§2.22): mouth openness follows the decoded voice level, opens on a fed sine
## tone and closes again in silence, both on its own and through the full playback path.


func _frames(seconds: float, amp: float) -> Array[PackedFloat32Array]:
	var tone: PackedFloat32Array = VoiceWav.tone(220.0, seconds, VoiceCodec.SAMPLE_RATE, amp)
	var out: Array[PackedFloat32Array] = []
	for i: int in range(0, tone.size() - VoiceCodec.FRAME_SAMPLES + 1, VoiceCodec.FRAME_SAMPLES):
		out.append(tone.slice(i, i + VoiceCodec.FRAME_SAMPLES))
	return out


func test_mouth_opens_on_a_tone_and_closes_in_silence() -> void:
	var m := VoiceMouth.new()
	assert_eq(m.openness, 0.0)
	var peak: float = 0.0
	for f: PackedFloat32Array in _frames(0.4, 0.4):
		m.feed(f)
		peak = maxf(peak, m.update(VoiceCodec.FRAME_SECONDS))
	assert_gt(peak, 0.6, "a loud tone opens the mouth wide (peak %.2f)" % peak)
	assert_true(m.is_talking())
	for f: PackedFloat32Array in _frames(0.5, 0.0):
		m.feed(f)
		m.update(VoiceCodec.FRAME_SECONDS)
	assert_lt(m.openness, 0.02, "silence closes it (%.3f)" % m.openness)
	assert_false(m.is_talking())


func test_mouth_closes_when_frames_stop_arriving() -> void:
	var m := VoiceMouth.new()
	for f: PackedFloat32Array in _frames(0.3, 0.4):
		m.feed(f)
		m.update(VoiceCodec.FRAME_SECONDS)
	assert_gt(m.openness, 0.5)
	for i: int in 30:
		m.update(1.0 / 60.0)
	assert_lt(m.openness, 0.02, "no more frames: closed after half a second")


func test_quiet_voice_opens_less_than_loud_voice() -> void:
	assert_eq(VoiceMouth.level_to_openness(-80.0), 0.0, "room noise keeps it shut")
	assert_eq(VoiceMouth.level_to_openness(0.0), 1.0)
	assert_lt(VoiceMouth.level_to_openness(-35.0), VoiceMouth.level_to_openness(-20.0))


func test_playback_path_drives_the_mouth_from_decoded_frames() -> void:
	var pb := VoicePlayback.new()
	pb.audio_enabled = false
	add_child_autofree(pb)
	var codec := MulawCodec.new()
	var seq: int = 0
	var peak: float = 0.0
	# 0.6 s of tone arriving in real time: one 40 ms frame per tick.
	for f: PackedFloat32Array in _frames(0.6, 0.4):
		pb.push_packet(VoicePacket.parse_down(VoicePacket.make_down(2, seq, 0, codec.encode(f))))
		seq += 1
		pb.advance(VoiceCodec.FRAME_SECONDS)
		peak = maxf(peak, pb.mouth.openness)
	assert_gt(peak, 0.6, "mouth opened from the decoded RMS (peak %.2f)" % peak)
	assert_true(pb.is_talking())
	assert_true(pb.icon.visible, "talking indicator over the head")
	assert_eq(pb.buffer.lost, 0)
	# Then a silent end frame and nothing more.
	var silent := PackedFloat32Array()
	silent.resize(VoiceCodec.FRAME_SAMPLES)
	pb.push_packet(VoicePacket.parse_down(VoicePacket.make_down(2, seq, VoicePacket.FLAG_END, codec.encode(silent))))
	for i: int in 30:
		pb.advance(1.0 / 60.0)
	assert_lt(pb.mouth.openness, 0.02, "closed again in silence")
	assert_false(pb.is_talking())
	assert_false(pb.icon.visible)


func test_table_and_global_voice_flag_full_volume() -> void:
	var pb := VoicePlayback.new()
	pb.audio_enabled = false
	add_child_autofree(pb)
	var codec := MulawCodec.new()
	var f: PackedFloat32Array = _frames(0.04, 0.2)[0]
	pb.push_packet(VoicePacket.parse_down(VoicePacket.make_down(2, 0, VoicePacket.FLAG_GLOBAL, codec.encode(f))))
	assert_true(pb.full_volume)
	pb.push_packet(VoicePacket.parse_down(VoicePacket.make_down(2, 1, 0, codec.encode(f))))
	assert_false(pb.full_volume)
	pb.push_packet(VoicePacket.parse_down(VoicePacket.make_down(2, 2, VoicePacket.FLAG_TABLE, codec.encode(f))))
	assert_true(pb.full_volume)
