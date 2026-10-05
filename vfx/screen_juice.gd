class_name ScreenJuice
extends Node
## Client-only impact feel: screen shake (camera offsets, trauma model) and hit-stop (a brief dip
## of `Engine.time_scale`). Both run on real time so the hit-stop does not stretch them. A server
## never has one of these; a practice host keeps its in-process server on real time with
## `ScreenJuice.unscaled(delta)`.

## Largest camera offset at full trauma (metres).
const MAX_OFFSET: float = 0.22
## Trauma lost per real second.
const DECAY: float = 1.5

var trauma: float = 0.0
var _stop_until_ms: int = 0
var _stop_scale: float = 1.0
var _restore_ms: int = 0
var _last_ms: int = 0
var _cam: Camera3D
var _seed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_ms = Time.get_ticks_msec()
	_seed = randf() * 100.0


func _exit_tree() -> void:
	if hit_stopping() or Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_reset_cam()


## Adds screen shake (0..1; 0.3 = a nudge, 0.8 = a jackpot).
func shake(amount: float) -> void:
	if not Vfx.enabled():
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Freezes the game almost still for `seconds` of real time, then eases back to normal speed.
func hit_stop(seconds: float = 0.12, time_scale: float = 0.08) -> void:
	if not Vfx.enabled():
		return
	var now: int = Time.get_ticks_msec()
	_stop_scale = minf(time_scale, _stop_scale) if hit_stopping() else time_scale
	_stop_until_ms = maxi(_stop_until_ms, now + int(seconds * 1000.0))
	_restore_ms = 0
	Engine.time_scale = _stop_scale


func hit_stopping() -> bool:
	return _stop_until_ms > 0


## `delta` from a scaled `_process` back in real seconds (for the practice host's server tick).
static func unscaled(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.001)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var dt: float = clampf((now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	_update_hit_stop(now)
	_update_shake(dt, now)


func _update_hit_stop(now: int) -> void:
	if _stop_until_ms <= 0:
		return
	if now < _stop_until_ms:
		Engine.time_scale = _stop_scale
		return
	if _restore_ms == 0:
		_restore_ms = now
	var f: float = clampf((now - _restore_ms) / 90.0, 0.0, 1.0)  # ease back over 90 ms
	Engine.time_scale = lerpf(_stop_scale, 1.0, f * f)
	if f >= 1.0:
		Engine.time_scale = 1.0
		_stop_until_ms = 0
		_restore_ms = 0


func _update_shake(dt: float, now: int) -> void:
	if trauma <= 0.0:
		if _cam != null:
			_reset_cam()
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != _cam:
		_reset_cam()
		_cam = cam
	trauma = maxf(trauma - DECAY * dt, 0.0)
	if _cam == null:
		return
	var k: float = trauma * trauma * MAX_OFFSET
	var t: float = now / 1000.0 * 32.0 + _seed
	_cam.h_offset = k * (sin(t * 1.3) + sin(t * 2.9) * 0.5) / 1.5
	_cam.v_offset = k * (sin(t * 1.7 + 1.0) + sin(t * 3.7) * 0.5) / 1.5


func _reset_cam() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
	_cam = null
