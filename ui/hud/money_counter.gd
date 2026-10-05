class_name MoneyCounter
extends RefCounted
## The HUD money readout's animation: counts up or down to the new balance (ease-out, longer for
## bigger changes) and flashes Money Green / Loss Red with a little punch while it moves.

const MIN_TIME: float = 0.35
const MAX_TIME: float = 1.2
const FLASH_TIME: float = 0.7

var displayed: float = 0.0
var target: int = 0
## 1 right after a change, fading to 0.
var flash: float = 0.0
## +1 counting up, -1 counting down, 0 settled.
var direction: int = 0

var _from: float = 0.0
var _elapsed: float = 0.0
var _duration: float = MIN_TIME


## Jumps straight to `value` (new match, first bind).
func snap(value: int) -> void:
	target = value
	displayed = float(value)
	_from = displayed
	_elapsed = _duration
	flash = 0.0
	direction = 0


## Starts counting towards `value` (no-op when it is already the target).
func set_target(value: int) -> void:
	if value == target:
		return
	_from = displayed
	direction = 1 if value > target else -1
	target = value
	_elapsed = 0.0
	_duration = clampf(MIN_TIME + log(absf(value - _from) + 1.0) / log(10.0) * 0.18, MIN_TIME, MAX_TIME)
	flash = 1.0


## Advances by `delta` seconds; returns the whole-dollar value to show.
func step(delta: float) -> int:
	_elapsed = minf(_elapsed + delta, _duration)
	var f: float = _elapsed / _duration if _duration > 0.0 else 1.0
	displayed = lerpf(_from, float(target), 1.0 - pow(1.0 - f, 3.0))
	if f >= 1.0:
		displayed = float(target)
	flash = maxf(flash - delta / FLASH_TIME, 0.0)
	if flash <= 0.0 and f >= 1.0:
		direction = 0
	return int(round(displayed))


func is_counting() -> bool:
	return _elapsed < _duration


## `base` tinted towards green (up) or red (down) while flashing.
func tint(base: Color) -> Color:
	if direction == 0 or flash <= 0.0:
		return base
	return base.lerp(Palette.MONEY_GREEN if direction > 0 else Palette.LOSS_RED, clampf(flash * 1.2, 0.0, 1.0))


## Scale punch for the label (bigger on the way up).
func punch() -> float:
	return 1.0 + flash * flash * (0.14 if direction > 0 else 0.06)
