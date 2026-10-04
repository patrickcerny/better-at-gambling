class_name PlinkoChip
extends Node3D
## Visual chip that plays back a PlinkoSteering path on a PlinkoStation board: hops from peg to
## peg with little arcs, plinks on each bounce, lands in the server-chosen slot, then fades.

signal landed(slot: int)

var color: Color = Palette.CASINO_RED
var points: Array[Vector3] = []
var duration: float = 3.0
var slot: int = 0

var _t: float = 0.0
var _seg_time: float = 0.0
var _last_seg: int = -1
var _done: bool = false


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 0.05
	mi.mesh = cm
	mi.material_override = GreyboxKit.material(color)
	mi.rotation.x = PI * 0.5
	add_child(mi)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.13
	rim.mesh = tm
	rim.material_override = GreyboxKit.material(Palette.CREAM)
	rim.rotation.x = PI * 0.5
	add_child(rim)
	if points.size() >= 2:
		position = points[0]
		_seg_time = duration / float(points.size() - 1)


## Starts playback along `pts` taking `seconds` in total.
func play(pts: Array[Vector3], seconds: float, p_slot: int) -> void:
	points = pts
	duration = seconds
	slot = p_slot
	_t = 0.0
	_done = false
	if pts.size() >= 2:
		position = pts[0]
		_seg_time = seconds / float(pts.size() - 1)


func _process(delta: float) -> void:
	if _done or points.size() < 2:
		return
	_t += delta
	var seg_f: float = _t / _seg_time
	var seg: int = int(floor(seg_f))
	if seg >= points.size() - 1:
		position = points[points.size() - 1]
		_done = true
		landed.emit(slot)
		var tw: Tween = create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(queue_free)
		return
	if seg != _last_seg:
		_last_seg = seg
		if seg > 0:
			Audio.play_at(&"plink", self, -14.0, randf_range(0.9, 1.3))
	var f: float = seg_f - seg
	var a: Vector3 = points[seg]
	var b: Vector3 = points[seg + 1]
	var p: Vector3 = a.lerp(b, f)
	p.y += sin(f * PI) * 0.08  # small hop over each peg
	position = p
	rotation.z += delta * 6.0 * signf(b.x - a.x + 0.001)
