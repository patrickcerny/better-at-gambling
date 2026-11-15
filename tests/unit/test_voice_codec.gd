extends GutTest
## Voice codec (§2.22): μ-law and ADPCM round trips, packet framing, resampling to the voice rate.

var codec: MulawCodec


func before_each() -> void:
	codec = MulawCodec.new()


func test_mulaw_round_trip_within_error_bound() -> void:
	var xs := PackedFloat32Array()
	for i: int in range(-1000, 1001):
		xs.append(i / 1000.0)
	var enc: PackedByteArray = codec.encode(xs)
	assert_eq(enc.size(), xs.size(), "one byte per sample")
	var dec: PackedFloat32Array = codec.decode(enc)
	var worst: float = 0.0
	for i: int in xs.size():
		var err: float = absf(dec[i] - xs[i])
		# Half a quantisation step: ≤ 1/32 of the value in every segment, plus the tiny floor step.
		var bound: float = absf(xs[i]) / 32.0 + 0.0005
		if err > bound:
			fail_test("x=%.3f decoded %.5f (error %.5f > %.5f)" % [xs[i], dec[i], err, bound])
			return
		worst = maxf(worst, err)
	assert_lt(worst, 0.035, "worst absolute error %.4f" % worst)


func test_mulaw_sine_signal_to_noise_above_30_db() -> void:
	var tone: PackedFloat32Array = VoiceWav.tone(440.0, 0.5, VoiceCodec.SAMPLE_RATE, 0.5)
	var dec: PackedFloat32Array = codec.decode(codec.encode(tone))
	var sig: float = 0.0
	var noise: float = 0.0
	for i: int in tone.size():
		sig += tone[i] * tone[i]
		noise += (dec[i] - tone[i]) * (dec[i] - tone[i])
	var snr: float = 10.0 * log(sig / noise) / log(10.0)
	assert_gt(snr, 30.0, "SNR %.1f dB" % snr)


func test_mulaw_silence_and_clipping() -> void:
	var dec: PackedFloat32Array = codec.decode(codec.encode(PackedFloat32Array([0.0, 0.0, 2.0, -2.0])))
	assert_almost_eq(dec[0], 0.0, 0.0005)
	assert_almost_eq(dec[2], 1.0, 0.04, "over-range clips to full scale")
	assert_almost_eq(dec[3], -1.0, 0.04)
	# Every byte decodes and re-encodes to itself (except the two zero codes).
	for b: int in 256:
		var s: int = MulawCodec.decode_sample(b)
		if s != 0:
			assert_eq(MulawCodec.encode_sample(s), b, "byte %d" % b)


func test_packets_round_trip_and_reject_junk() -> void:
	var payload := PackedByteArray([1, 2, 3, 250])
	var up: PackedByteArray = VoicePacket.make_up(65535, VoicePacket.FLAG_END, payload)
	assert_eq(up.size(), VoicePacket.UP_HEADER + 4)
	var u: Dictionary = VoicePacket.parse_up(up)
	assert_eq(u["seq"], 65535)
	assert_eq(u["flags"], VoicePacket.FLAG_END)
	assert_eq(u["payload"], payload)
	var down: PackedByteArray = VoicePacket.make_down(300, 7, VoicePacket.FLAG_GLOBAL, payload)
	var d: Dictionary = VoicePacket.parse_down(down)
	assert_eq(d["speaker"], 300)
	assert_eq(d["seq"], 7)
	assert_eq(d["flags"], VoicePacket.FLAG_GLOBAL)
	assert_eq(d["payload"], payload)
	assert_true(VoicePacket.parse_up(PackedByteArray([1, 2, 3, 4, 5])).is_empty(), "wrong magic")
	assert_true(VoicePacket.parse_up(PackedByteArray([VoicePacket.MAGIC, 0])).is_empty(), "too short")
	var huge := PackedByteArray()
	huge.resize(VoicePacket.MAX_PAYLOAD + 1)
	assert_true(VoicePacket.parse_up(VoicePacket.make_up(0, 0, huge)).is_empty(), "too long")
	# A voice packet that ends up in the game-message path is ignored there, quietly.
	assert_eq(Wire.decode(down), [])


func test_sequence_numbers_wrap() -> void:
	assert_eq(VoicePacket.seq_diff(0, 65535), 1)
	assert_eq(VoicePacket.seq_diff(65535, 0), -1)
	assert_eq(VoicePacket.seq_diff(10, 3), 7)


func test_resampler_48k_and_44k_to_the_voice_rate() -> void:
	for rate: int in [48000, 44100]:
		var r := VoiceResampler.new(rate, VoiceCodec.SAMPLE_RATE)
		var tone: PackedFloat32Array = VoiceWav.tone(300.0, 1.0, rate, 0.5)
		var out := PackedFloat32Array()
		# Streamed in uneven chunks, as the capture effect delivers them.
		var pos: int = 0
		var chunk: int = 441
		while pos < tone.size():
			out.append_array(r.process(tone.slice(pos, mini(pos + chunk, tone.size()))))
			pos += chunk
			chunk = 1024 if chunk == 441 else 441
		assert_between(out.size(), VoiceCodec.SAMPLE_RATE - 1, VoiceCodec.SAMPLE_RATE + 1, "%d Hz: one second in, one second out" % rate)
		assert_almost_eq(VoiceCodec.rms(out), 0.5 / sqrt(2.0), 0.02, "%d Hz: a low tone keeps its level" % rate)


## 0.9.32: IMA ADPCM at 16 kHz carries voice on the wire, same bandwidth as 8 kHz μ-law.
func test_adpcm_frame_size_and_bandwidth() -> void:
	var adpcm := AdpcmCodec.new()
	var enc: PackedByteArray = adpcm.encode(VoiceWav.tone(440.0, VoiceCodec.FRAME_SECONDS, VoiceCodec.SAMPLE_RATE, 0.3))
	assert_eq(enc.size(), AdpcmCodec.HEADER + VoiceCodec.FRAME_SAMPLES / 2, "4 bits per sample")
	assert_eq(adpcm.decode(enc).size(), VoiceCodec.FRAME_SAMPLES)
	var per_second: float = (enc.size() + VoicePacket.UP_HEADER) / VoiceCodec.FRAME_SECONDS
	assert_lt(per_second, VoiceRelay.MAX_BYTES_PER_SECOND, "%.0f B/s fits the relay's cap" % per_second)


func test_adpcm_signal_to_noise_for_speech_band_tones() -> void:
	var adpcm := AdpcmCodec.new()
	# Up to 4 kHz (where speech lives) clearly; 6 kHz, near the 8 kHz edge, still usable.
	for hz: float in [200.0, 1000.0, 3000.0, 4000.0, 6000.0]:
		for amp: float in [0.02, 0.3, 0.9]:
			var sig: float = 0.0
			var noise: float = 0.0
			var tone: PackedFloat32Array = VoiceWav.tone(hz, 0.4, VoiceCodec.SAMPLE_RATE, amp)
			for f: int in range(0, tone.size(), VoiceCodec.FRAME_SAMPLES):
				var frame: PackedFloat32Array = tone.slice(f, f + VoiceCodec.FRAME_SAMPLES)
				var dec: PackedFloat32Array = adpcm.decode(adpcm.encode(frame))
				for i: int in frame.size():
					sig += frame[i] * frame[i]
					noise += (dec[i] - frame[i]) * (dec[i] - frame[i])
			var snr: float = 10.0 * log(sig / maxf(noise, 1e-12)) / log(10.0)
			assert_gt(snr, 16.0 if hz <= 4000.0 else 12.0, "%d Hz at %.2f: SNR %.1f dB" % [roundi(hz), amp, snr])


func test_adpcm_frames_stand_alone_and_survive_junk() -> void:
	var adpcm := AdpcmCodec.new()
	var silence := PackedFloat32Array()
	silence.resize(VoiceCodec.FRAME_SAMPLES)
	var dec: PackedFloat32Array = adpcm.decode(adpcm.encode(silence))
	assert_lt(VoiceCodec.rms(dec), 0.001, "silence stays silent")
	assert_eq(adpcm.decode(PackedByteArray([1, 2])).size(), 0, "a cut-off header decodes to nothing")
	var junk := PackedByteArray()
	junk.resize(AdpcmCodec.encoded_size(VoiceCodec.FRAME_SAMPLES))
	for i: int in junk.size():
		junk[i] = (i * 37 + 11) & 0xFF
	for x: float in adpcm.decode(junk):
		assert_between(x, -1.0, 1.0)
		if x < -1.0 or x > 1.0:
			break
