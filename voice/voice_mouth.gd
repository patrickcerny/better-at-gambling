class_name VoiceMouth
extends RefCounted
## Mouth flap from voice level (§2.22 "the mouths move"): decoded frames go in, a smoothed mouth
## openness comes out (0 = closed `-`, ~0.5 = `o`, 1 = `O`; see `AvatarVisuals.mouth_open`).
## Opens fast, closes a little slower, and shuts on its own when the frames stop.

## Below this level the mouth stays shut (room noise, codec hiss).
const FLOOR_DB: float = -46.0
## At or above this level the mouth is wide open.
const FULL_DB: float = -14.0
## Seconds to close most of the way / to open most of the way.
const RELEASE: float = 0.08
const ATTACK: float = 0.03
## No frame for this long counts as silence.
const HOLD: float = 0.1
## Openness above which the speaker counts as talking (indicator, HUD).
const TALKING: float = 0.08

var openness: float = 0.0
var target: float = 0.0
var _since_feed: float = INF
## Seconds since the last audible frame (talking indicator hysteresis).
var _since_voice: float = INF


## Feeds one decoded frame.
func feed(samples: PackedFloat32Array) -> void:
	target = level_to_openness(VoiceCodec.rms_db(samples))
	_since_feed = 0.0
	if target > TALKING:
		_since_voice = 0.0


## Advances the smoothing by `delta` seconds and returns the openness.
func update(delta: float) -> float:
	_since_feed += delta
	_since_voice += delta
	if _since_feed > HOLD:
		target = 0.0
	var tau: float = ATTACK if target > openness else RELEASE
	openness = lerpf(openness, target, 1.0 - exp(-delta / tau))
	if openness < 0.001:
		openness = 0.0
	return openness


## True while this voice was audible in the last quarter second.
func is_talking() -> bool:
	return _since_voice < 0.25


## Maps a frame level in dBFS to mouth openness.
static func level_to_openness(db: float) -> float:
	return clampf((db - FLOOR_DB) / (FULL_DB - FLOOR_DB), 0.0, 1.0)
