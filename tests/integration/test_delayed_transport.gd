extends GutTest
## DelayedTransport (test-only latency/loss): packets arrive half an RTT later, unreliable ones
## can vanish, reliable ones are late but never lost or reordered on their channel.


class LoopTransport:
	extends NetTransport
	var queue: Array[Dictionary] = []

	func send(to: int, channel: int, _reliable: bool, data: PackedByteArray) -> void:
		queue.append({"peer": to, "channel": channel, "data": data})

	func poll() -> Array[Dictionary]:
		var out: Array[Dictionary] = queue.duplicate()
		queue.clear()
		return out


func _drain(t: DelayedTransport, seconds: float) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		got.append_array(t.poll())
		OS.delay_msec(5)
	return got


func test_latency_and_reliable_ordering() -> void:
	var t := DelayedTransport.new(LoopTransport.new(), 200.0, 0.3, 7)
	for i: int in 40:
		t.send(1, Protocol.CHANNEL_EVENTS, true, PackedByteArray([i]))
	assert_eq(t.poll().size(), 0, "nothing arrives instantly")
	var got: Array[Dictionary] = _drain(t, 0.9)
	assert_eq(got.size(), 40, "reliable packets are never lost")
	for i: int in got.size():
		assert_eq(got[i]["data"][0], i, "and stay in order")
	t.close()


func test_unreliable_loss_rate() -> void:
	var t := DelayedTransport.new(LoopTransport.new(), 20.0, 0.25, 3)
	for i: int in 400:
		t.send(1, Protocol.CHANNEL_PHYSICS, false, PackedByteArray([i % 256]))
	var got: int = _drain(t, 0.3).size()
	# Through the loopback the loss applies on the way out and on the way back in: 0.75² ≈ 56%.
	assert_between(got, 190, 260, "loss applied per direction (got %d of 400)" % got)
	t.close()
