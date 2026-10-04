class_name RateLimiter
extends RefCounted
## Per-player token bucket: at most `per_second` intents per second, burst of the same size.

var per_second: float
var _tokens: Dictionary[int, float] = {}
var _last: Dictionary[int, float] = {}


func _init(p_per_second: float = 20.0) -> void:
	per_second = p_per_second


## True if the player may act now at time `now` (seconds); consumes a token.
func allow(player: int, now: float) -> bool:
	var tokens: float = _tokens.get(player, per_second)
	var last: float = _last.get(player, now)
	tokens = minf(tokens + (now - last) * per_second, per_second)
	_last[player] = now
	if tokens < 1.0:
		_tokens[player] = tokens
		return false
	_tokens[player] = tokens - 1.0
	return true
