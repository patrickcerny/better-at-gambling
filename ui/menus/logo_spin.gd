class_name LogoSpin
extends RefCounted
## The main menu logo's spin (Patrick 2026-11-16: "Be able to drag and spin the logo on the
## startscreen"): pure maths, no nodes, so it is tested headless. `Logo3DView` feeds it mouse
## drags and the right stick and turns `yaw` into the sign's rotation.
##
## Dragging turns the sign with the pointer; letting go keeps the drag's speed (momentum), which
## friction slows down; once it stops the sign eases back to face the front. A full turn is
## counted each time the sign gets a whole 360° further, in either direction, from where the last
## turn was counted, so wobbling back and forth never counts (the hidden achievement for 1000 turns,
## `Achievements.LOGO_SPINS`).

## Degrees the sign turns per canvas unit dragged.
const DRAG_DEG_PER_UNIT: float = 0.6
## Fastest spin (deg/s): 3 turns a second, so the letters still read as a spinning sign.
const MAX_SPEED: float = 1080.0
## Momentum loss: speed *= exp(-FRICTION * seconds).
const FRICTION: float = 0.9
## Below this (deg/s) the spin stops and the sign eases back to the front.
const STOP_SPEED: float = 20.0
## How fast (deg/s) the stopped sign eases back to face the front.
const SETTLE_SPEED: float = 240.0
## Right stick fully tilted: this speed (deg/s), reached at STICK_ACCEL.
const STICK_SPEED: float = 720.0
const STICK_ACCEL: float = 1800.0
## How quickly the drag speed follows the pointer (per second), for the speed at release.
const DRAG_SMOOTH: float = 18.0

## Total rotation in degrees, unbounded (+ = to the right).
var yaw: float = 0.0
## Current spin speed (deg/s).
var velocity: float = 0.0
var dragging: bool = false
## Full turns counted since this spin was made.
var turns: int = 0

## Where the last turn was counted (always a multiple of 360).
var _anchor: float = 0.0
## Degrees dragged since the last `step`.
var _dragged: float = 0.0


## The pointer grabs the sign: it stops spinning and follows the drag.
func press() -> void:
	dragging = true
	velocity = 0.0
	_dragged = 0.0


## The pointer moved `dx` canvas units sideways while holding the sign. Returns full turns completed.
func drag(dx: float) -> int:
	if not dragging:
		return 0
	var d: float = dx * DRAG_DEG_PER_UNIT
	yaw += d
	_dragged += d
	return _count()


## Let go: the sign keeps the drag's speed (capped).
func release() -> void:
	if not dragging:
		return
	dragging = false
	velocity = clampf(velocity, -MAX_SPEED, MAX_SPEED)
	_dragged = 0.0


## Advances `dt` seconds; `stick` is the right stick's sideways tilt (-1..1, 0 = none). Returns the
## full turns completed.
func step(dt: float, stick: float = 0.0) -> int:
	if dt <= 0.0:
		return 0
	if dragging:
		# Follow the pointer's speed so letting go keeps it (no extra turning: the drag moved it).
		var w: float = 1.0 - exp(-DRAG_SMOOTH * dt)
		velocity = lerpf(velocity, _dragged / dt, w)
		_dragged = 0.0
		return 0
	if absf(stick) > 0.0:
		velocity = move_toward(velocity, clampf(stick, -1.0, 1.0) * STICK_SPEED, STICK_ACCEL * dt)
	else:
		velocity *= exp(-FRICTION * dt)
		if absf(velocity) < STOP_SPEED:
			velocity = 0.0
	velocity = clampf(velocity, -MAX_SPEED, MAX_SPEED)
	if velocity != 0.0:
		yaw += velocity * dt
	else:
		yaw = move_toward(yaw, front(), SETTLE_SPEED * dt)
	return _count()


## The nearest yaw at which the sign faces the front.
func front() -> float:
	return roundf(yaw / 360.0) * 360.0


## Whether the sign is moving (spinning, held or easing back).
func is_busy() -> bool:
	return dragging or velocity != 0.0 or not is_equal_approx(yaw, front())


func _count() -> int:
	var n: int = 0
	while yaw - _anchor >= 360.0:
		_anchor += 360.0
		n += 1
	while _anchor - yaw >= 360.0:
		_anchor -= 360.0
		n += 1
	turns += n
	return n
