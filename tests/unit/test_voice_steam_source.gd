extends GutTest
## `VoiceSteamSource`: microphone samples from Steam voice (0.9.24), with a fake GodotSteam.


class FakeSteamVoice:
	extends RefCounted
	var recording: int = 0
	var started: int = 0
	## Each entry: PCM16 bytes Steam would hand out for one GetVoice.
	var queue: Array[PackedByteArray] = []

	func startVoiceRecording() -> void:
		recording += 1
		started += 1

	func stopVoiceRecording() -> void:
		recording -= 1

	func getVoice() -> Dictionary:
		if queue.is_empty():
			return {"result": 2, "written": 0, "buffer": PackedByteArray()}
		# The "compressed" voice is the PCM itself here; decompressVoice passes it on.
		var b: PackedByteArray = queue.pop_front()
		return {"result": 0, "written": b.size(), "buffer": b}

	func decompressVoice(voice: PackedByteArray, _rate: int) -> Dictionary:
		return {"result": 0, "size": voice.size(), "uncompressed": voice}


func _pcm(values: Array[int]) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(values.size() * 2)
	for i: int in values.size():
		b.encode_s16(i * 2, values[i])
	return b


func test_pcm16_converts_to_unit_samples() -> void:
	var f: PackedFloat32Array = VoiceSteamSource.pcm16_to_float(_pcm([0, 16384, -32768, 32767]), 8)
	assert_eq(f.size(), 4)
	assert_almost_eq(f[0], 0.0, 0.0001)
	assert_almost_eq(f[1], 0.5, 0.0001)
	assert_almost_eq(f[2], -1.0, 0.0001)
	assert_almost_eq(f[3], 1.0, 0.001)


func test_steam_voice_is_read_as_stereo_frames() -> void:
	var fake := FakeSteamVoice.new()
	fake.queue.append(_pcm([8192, 8192, -8192]))
	var src := VoiceSteamSource.new()
	src._steam = fake
	assert_eq(src.start(), OK)
	assert_eq(fake.recording, 1, "Steam records")
	var got: PackedVector2Array = src.read_all()
	assert_eq(got.size(), 3)
	assert_almost_eq(got[0].x, 0.25, 0.0001)
	assert_almost_eq(got[0].y, 0.25, 0.0001, "mono on both channels")
	assert_eq(src.steam_samples, 3)
	assert_eq(src.rate(), float(VoiceSteamSource.RATE))
	assert_false(src.continuous, "no rate check on Steam's speech-only stream")
	src.stop()
	assert_eq(fake.recording, 0, "Steam stops recording")


func test_two_sources_share_one_recording() -> void:
	var fake := FakeSteamVoice.new()
	var a := VoiceSteamSource.new()
	var b := VoiceSteamSource.new()
	a._steam = fake
	b._steam = fake
	a.start()
	b.start()
	assert_eq(fake.started, 1, "started once")
	a.stop()
	assert_eq(fake.recording, 1, "still recording for the other")
	b.stop()
	assert_eq(fake.recording, 0)


func test_silence_fills_the_gaps_steam_leaves() -> void:
	var fake := FakeSteamVoice.new()
	var src := VoiceSteamSource.new()
	var now: Array[int] = [1000000]
	src.clock = func() -> int: return now[0]
	src._steam = fake
	src.start()
	src.read_all()
	now[0] += 50000  # 50 ms: within LAG_SECONDS, Steam may still deliver
	assert_eq(src.read_all().size(), 0)
	now[0] += 350000  # 0.4 s in all
	var got: PackedVector2Array = src.read_all()
	assert_eq(got.size(), int(VoiceSteamSource.RATE * (0.4 - VoiceSteamSource.LAG_SECONDS)), "silence up to the clock, minus the lag")
	assert_eq(got[0], Vector2.ZERO)
	# Voice that arrives late plays on; the clock does not run ahead of it.
	fake.queue.append(_pcm([4096, 4096]))
	assert_eq(src.read_all().size(), 2)
	src.stop()


func test_stock_sources_are_replaced_fakes_are_kept() -> void:
	assert_true(VoiceMicSource.is_stock(VoiceMicSource.new()))
	assert_true(VoiceMicSource.is_stock(VoiceSteamSource.new()))
	assert_false(VoiceMicSource.is_stock(null))
	# Without Steam (the tests) the driver is read.
	assert_false(VoiceMicSource.make() is VoiceSteamSource)
