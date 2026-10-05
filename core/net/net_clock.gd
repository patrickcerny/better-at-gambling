class_name NetClock
extends RefCounted
## Client estimate of the server clock (§4.1 "Timing"): ping/pong samples give the round-trip
## time and the offset between local and server time; both are smoothed. Pure: callers pass
## their own local time in seconds.

## Smoothed round-trip time in seconds (-1 until the first sample).
var rtt: float = -1.0
## server_time ≈ local_time + offset.
var offset: float = 0.0
var samples: int = 0

var _min_rtt: float = INF


## Feeds one pong: `sent_at` (local time the ping left), `server_time` (server clock in the
## pong), `now` (local time the pong arrived).
func add_sample(sent_at: float, server_time: float, now: float) -> void:
	var sample_rtt: float = maxf(now - sent_at, 0.0)
	var sample_offset: float = server_time + sample_rtt * 0.5 - now
	_min_rtt = minf(_min_rtt, sample_rtt)
	if samples == 0:
		rtt = sample_rtt
		offset = sample_offset
	else:
		rtt = lerpf(rtt, sample_rtt, 0.15)
		# Samples delayed by queueing (much slower than the best seen) skew the offset: trust them less.
		var weight: float = 0.2 if sample_rtt <= _min_rtt * 1.5 + 0.01 else 0.04
		offset = lerpf(offset, sample_offset, weight)
	samples += 1


## Server time now, given the local time.
func server_now(local_now: float) -> float:
	return local_now + offset


## Round-trip time in milliseconds (0 before the first sample).
func ping_ms() -> int:
	return int(round(maxf(rtt, 0.0) * 1000.0))
