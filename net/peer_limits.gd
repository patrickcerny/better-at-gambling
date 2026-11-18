class_name PeerLimits
extends RefCounted
## SERVER: per-peer caps on the client messages that are not intents (intents have their own
## limit in `IntentValidator`). A modified client could otherwise flood the room server with
## SNAPSHOT_REQ (each one builds and sends a full snapshot), PING or MOVE packets and slow the
## match down for everyone (OWASP A04/A05, denial of service). The caps sit far above what the
## real client sends: MOVE every `PlayerAvatar.MOVE_SEND_INTERVAL`, PING once a second, a
## snapshot only after a gap or a new floor.

## Message type → allowed per second (also the burst size). Types not listed are not limited.
const PER_SECOND: Dictionary = {
	Protocol.Msg.SNAPSHOT_REQ: 2.0,
	Protocol.Msg.PING: 5.0,
	Protocol.Msg.MOVE: 60.0,
}

var _buckets: Dictionary = {}


## True if `peer` may send a message of `type` at time `now` (seconds); consumes a token.
func allow(peer: int, type: int, now: float) -> bool:
	if not PER_SECOND.has(type):
		return true
	var key: int = peer * 64 + type
	var limiter: RateLimiter = _buckets.get(key)
	if limiter == null:
		limiter = RateLimiter.new(float(PER_SECOND[type]))
		_buckets[key] = limiter
	return limiter.allow(peer, now)


## Drops everything known about `peer` (it left; peer ids get reused).
func forget(peer: int) -> void:
	for type: int in PER_SECOND:
		_buckets.erase(peer * 64 + type)
