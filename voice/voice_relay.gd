class_name VoiceRelay
extends RefCounted
## Server side of proximity voice (§4.1 channel 3): takes a speaker's frame, drops it if the
## speaker is over the bandwidth cap, and readdresses it to every listener in reach (see
## `VoiceProximity`). The server never decodes voice.

## Per-speaker cap: 72 kbit/s. One μ-law speaker needs 8.1 KB/s (25 × 324 bytes).
const MAX_BYTES_PER_SECOND: float = 9000.0
## Burst allowance in seconds of the cap (a short stall flushing queued frames still gets through).
const BURST_SECONDS: float = 0.5

var relayed_packets: int = 0
var dropped_packets: int = 0

var _tokens: Dictionary[int, float] = {}
var _last_at: Dictionary[int, float] = {}


## True (and the bytes are charged) if `speaker` may send `bytes` more at time `now` (seconds).
func allow(speaker: int, bytes: int, now: float) -> bool:
	var cap: float = MAX_BYTES_PER_SECOND * BURST_SECONDS
	var t: float = _tokens.get(speaker, cap)
	t = minf(cap, t + (now - _last_at.get(speaker, now)) * MAX_BYTES_PER_SECOND)
	_last_at[speaker] = now
	if t < bytes:
		_tokens[speaker] = t
		return false
	_tokens[speaker] = t - bytes
	return true


## Routes one up packet from `speaker` to the `listeners` (player ids) in reach.
## Returns listener → down packet; empty when malformed, over the cap or nobody is in reach.
func route(server: MatchServer, speaker: int, data: PackedByteArray, now: float, listeners: Array[int]) -> Dictionary[int, PackedByteArray]:
	var out: Dictionary[int, PackedByteArray] = {}
	var up: Dictionary = VoicePacket.parse_up(data)
	if up.is_empty() or server == null or not server.state.players.has(speaker):
		return out
	if not allow(speaker, data.size(), now):
		dropped_packets += 1
		return out
	var phase: Phase.Id = server.phases.phase if server.phases != null else Phase.Id.LOBBY
	var spos: Vector3 = server.world.get_position(speaker)
	var sstation: StringName = server.stations.station_of(speaker)
	var by_flags: Dictionary[int, PackedByteArray] = {}
	for l: int in listeners:
		if l == speaker:
			continue
		var r: VoiceProximity.Reach = VoiceProximity.reach(phase, spos, server.world.get_position(l), sstation, server.stations.station_of(l))
		if r == VoiceProximity.Reach.NONE:
			continue
		var flags: int = (int(up["flags"]) & VoicePacket.FLAG_END) | VoiceProximity.flags_for(r)
		if not by_flags.has(flags):
			by_flags[flags] = VoicePacket.make_down(speaker, int(up["seq"]), flags, up["payload"])
		out[l] = by_flags[flags]
	if not out.is_empty():
		relayed_packets += 1
	return out


## Forgets a speaker's bandwidth state (left the room).
func forget(speaker: int) -> void:
	_tokens.erase(speaker)
	_last_at.erase(speaker)
