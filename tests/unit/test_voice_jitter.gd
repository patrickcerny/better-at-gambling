extends GutTest
## Voice jitter buffer: plays frames in order after a short pre-buffer, conceals lost frames,
## drops late and duplicate ones, rebuffers after running dry and survives sequence wrap-around.


func _frame(seq: int) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(VoiceCodec.FRAME_SAMPLES)
	f.fill(float(seq % 1000) / 1000.0 + 0.001)
	return f


func _id(f: PackedFloat32Array) -> int:
	return roundi((f[0] - 0.001) * 1000.0) if not f.is_empty() else -1


func test_prebuffers_then_plays_in_order() -> void:
	var jb := VoiceJitterBuffer.new(3)
	jb.push(0, _frame(0))
	jb.push(1, _frame(1))
	assert_true(jb.pop().is_empty(), "still buffering with 2 of 3 frames")
	jb.push(2, _frame(2))
	assert_eq(_id(jb.pop()), 0)
	jb.push(3, _frame(3))
	assert_eq(_id(jb.pop()), 1)
	assert_eq(_id(jb.pop()), 2)
	assert_eq(_id(jb.pop()), 3)
	assert_eq(jb.played, 4)
	assert_eq(jb.lost, 0)


func test_reordered_frames_come_out_in_order() -> void:
	var jb := VoiceJitterBuffer.new(3)
	for s: int in [2, 0, 3, 1, 5, 4]:
		jb.push(s, _frame(s))
	var got: Array[int] = []
	for i: int in 6:
		got.append(_id(jb.pop()))
	assert_eq(got, [0, 1, 2, 3, 4, 5])
	assert_eq(jb.lost, 0)


func test_lost_frame_is_concealed_and_playback_continues() -> void:
	var jb := VoiceJitterBuffer.new(3)
	for s: int in [0, 1, 2, 4, 5]:
		jb.push(s, _frame(s))
	assert_eq(_id(jb.pop()), 0)
	assert_eq(_id(jb.pop()), 1)
	assert_eq(_id(jb.pop()), 2)
	var concealed: PackedFloat32Array = jb.pop()
	assert_eq(concealed.size(), VoiceCodec.FRAME_SAMPLES, "a full frame fills the gap")
	assert_almost_eq(concealed[0], _frame(2)[0] * 0.5, 0.0001, "the previous frame, quieter")
	assert_eq(jb.lost, 1)
	assert_eq(_id(jb.pop()), 4, "then playback carries on")
	assert_eq(_id(jb.pop()), 5)
	# The frame that went missing turns up after all: too late, dropped.
	jb.push(3, _frame(3))
	assert_eq(jb.late, 1)


func test_consecutive_losses_fade_to_silence() -> void:
	var jb := VoiceJitterBuffer.new(1)
	jb.push(0, _frame(500))
	jb.push(4, _frame(4))
	jb.pop()
	assert_almost_eq(jb.pop()[0], _frame(500)[0] * 0.5, 0.0001)
	assert_eq(jb.pop()[0], 0.0, "second lost frame in a row is silence")
	assert_eq(jb.pop()[0], 0.0)
	assert_eq(_id(jb.pop()), 4)
	assert_eq(jb.lost, 3)


func test_duplicates_are_dropped() -> void:
	var jb := VoiceJitterBuffer.new(2)
	jb.push(0, _frame(0))
	jb.push(0, _frame(0))
	jb.push(1, _frame(1))
	assert_eq(jb.duplicates, 1)
	assert_eq(_id(jb.pop()), 0)
	assert_eq(_id(jb.pop()), 1)
	assert_true(jb.pop().is_empty())


func test_running_dry_rebuffers() -> void:
	var jb := VoiceJitterBuffer.new(2)
	jb.push(0, _frame(0))
	jb.push(1, _frame(1))
	jb.pop()
	jb.pop()
	assert_true(jb.pop().is_empty(), "dry")
	assert_eq(jb.state, VoiceJitterBuffer.State.BUFFERING)
	jb.push(2, _frame(2))
	assert_true(jb.pop().is_empty(), "waits for the pre-buffer again")
	jb.push(3, _frame(3))
	assert_eq(_id(jb.pop()), 2)


func test_short_spurt_with_end_flag_plays_without_waiting() -> void:
	var jb := VoiceJitterBuffer.new(3)
	jb.push(10, _frame(10))
	jb.push(11, _frame(11), true)
	assert_eq(_id(jb.pop()), 10)
	assert_eq(_id(jb.pop()), 11)
	assert_false(jb.is_active())


func test_burst_after_a_stall_is_bounded() -> void:
	var jb := VoiceJitterBuffer.new(3, 8)
	for s: int in 20:
		jb.push(s, _frame(s))
	assert_eq(jb.depth(), 8, "latency does not grow without bound")
	assert_eq(jb.overflowed, 12)
	assert_eq(_id(jb.pop()), 12, "the newest frames are kept")


func test_sequence_wraps_around() -> void:
	var jb := VoiceJitterBuffer.new(3)
	for s: int in [65534, 65535, 0, 1]:
		jb.push(s, _frame(s))
	var got: Array[int] = []
	for i: int in 4:
		got.append(_id(jb.pop()))
	assert_eq(got, [534, 535, 0, 1])
	assert_eq(jb.lost, 0)


func test_random_jitter_and_loss_keeps_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var jb := VoiceJitterBuffer.new(3)
	# 200 frames sent every 40 ms, each delayed 0–100 ms, 5 % lost. Real frames carry 0.5 + seq/1000
	# (concealment frames are quieter than 0.5, so they're told apart).
	var arrivals: Array[Array] = []
	var sent_lost: int = 0
	for s: int in 200:
		if rng.randf() < 0.05:
			sent_lost += 1
			continue
		arrivals.append([s * 0.04 + rng.randf() * 0.1, s])
	arrivals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var t: float = 0.0
	var i: int = 0
	var played: Array[int] = []
	while t < 200 * 0.04 + 0.5:
		while i < arrivals.size() and arrivals[i][0] <= t:
			var s: int = arrivals[i][1]
			var f := PackedFloat32Array()
			f.resize(VoiceCodec.FRAME_SAMPLES)
			f.fill(0.5 + s / 1000.0)
			jb.push(s, f)
			i += 1
		var out: PackedFloat32Array = jb.pop()
		if not out.is_empty() and out[0] >= 0.5:
			played.append(roundi((out[0] - 0.5) * 1000.0))
		t += 0.04
	var out_of_order: int = 0
	for k: int in range(1, played.size()):
		if played[k] <= played[k - 1]:
			out_of_order += 1
	assert_eq(out_of_order, 0, "frames never play out of order")
	assert_gt(played.size(), 200 - sent_lost - 10, "almost every delivered frame plays (%d of %d)" % [played.size(), 200 - sent_lost])
