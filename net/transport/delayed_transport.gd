class_name DelayedTransport
extends NetTransport
## Test-only wrapper (§4.1 `DelayedPeer`): delays every packet by half the configured round trip
## in each direction and drops `loss` of unreliable packets. Reliable packets are never dropped;
## a "lost" reliable packet arrives one extra round trip late (ENet retransmits) and holds back the
## packets behind it on the same channel, as real ordered delivery would.

var inner: NetTransport
var rtt_ms: float = 150.0
var loss: float = 0.02
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Pending [{at, peer, channel, reliable, data}] per direction.
var _out: Array[Dictionary] = []
var _in: Array[Dictionary] = []
var _last_release: Dictionary = {}
var _clock: float = 0.0
var _start_ticks: int = Time.get_ticks_msec()


func _init(p_inner: NetTransport, p_rtt_ms: float = 150.0, p_loss: float = 0.02, seed_value: int = 1) -> void:
	inner = p_inner
	rtt_ms = p_rtt_ms
	loss = p_loss
	rng.seed = seed_value
	inner.peer_connected.connect(func(id: int) -> void: peer_connected.emit(id))
	inner.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))
	inner.connection_failed.connect(func() -> void: connection_failed.emit())


func poll() -> Array[Dictionary]:
	_clock = (Time.get_ticks_msec() - _start_ticks) / 1000.0
	for p: Dictionary in inner.poll():
		_queue(_in, p["peer"], p["channel"], Protocol.is_reliable_channel(p["channel"]), p["data"], "in")
	_flush_out()
	var ready: Array[Dictionary] = []
	while not _in.is_empty() and _in[0]["at"] <= _clock:
		var p: Dictionary = _in.pop_front()
		bytes_in += (p["data"] as PackedByteArray).size()
		ready.append({"peer": p["peer"], "channel": p["channel"], "data": p["data"]})
	return ready


func send(to: int, channel: int, reliable: bool, data: PackedByteArray) -> void:
	_count_out(to, data.size())
	_queue(_out, to, channel, reliable, data, "out")
	_flush_out()


func kick(id: int) -> void:
	inner.kick(id)


func close() -> void:
	inner.close()
	for sig: StringName in [&"peer_connected", &"peer_disconnected", &"connection_failed"]:
		for c: Dictionary in inner.get_signal_connection_list(sig):
			inner.disconnect(sig, c["callable"])


func is_active() -> bool:
	return inner.is_active()


func local_id() -> int:
	return inner.local_id()


func _queue(q: Array[Dictionary], peer: int, channel: int, reliable: bool, data: PackedByteArray, dir: String) -> void:
	var delay: float = rtt_ms / 2000.0
	if rng.randf() < loss:
		if not reliable:
			return  # dropped
		delay += rtt_ms / 1000.0  # retransmitted one round trip later
	var at: float = _clock + delay
	if reliable:
		var key: String = "%s:%d:%d" % [dir, peer, channel]
		at = maxf(at, _last_release.get(key, 0.0))
		_last_release[key] = at
	var item: Dictionary = {"at": at, "peer": peer, "channel": channel, "reliable": reliable, "data": data}
	# Keep the queue sorted by release time (stable for equal times).
	var i: int = q.size()
	while i > 0 and q[i - 1]["at"] > at:
		i -= 1
	q.insert(i, item)


func _flush_out() -> void:
	while not _out.is_empty() and _out[0]["at"] <= _clock:
		var p: Dictionary = _out.pop_front()
		inner.send(p["peer"], p["channel"], p["reliable"], p["data"])
