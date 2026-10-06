class_name PlinkoChip
extends Node3D
## Visual chip that plays a `PlinkoFlight` on a `PlinkoStation` board: falls out of the funnel,
## clacks off one peg per row with real gravity arcs and spin, drops into the server's slot,
## hops, settles, then shrinks away. Time is scaled so it touches down exactly `seconds` after
## `play` (when the server settles the drop). Client only.

signal landed(slot: int)

## Seconds the chip rests in its slot before it fades.
const LINGER: float = 1.4

var color: Color = Palette.CASINO_RED
var board: PlinkoStation
var flight: PlinkoFlight
## Natural seconds of flight per real second.
var rate: float = 1.0
var slot: int = 0
## Multiplier this chip wins (shown over the slot when it lands); < 0 = none.
var mult: float = -1.0

var _t: float = 0.0
var _arc: int = -1
var _landed: bool = false
var _fading: bool = false
var _rest_for: float = 0.0
var _disc: Node3D


func _ready() -> void:
	_disc = Node3D.new()
	add_child(_disc)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PlinkoStation.CHIP_R
	cm.bottom_radius = PlinkoStation.CHIP_R
	cm.height = 0.035
	cm.radial_segments = 20
	cm.rings = 1
	body.mesh = cm
	body.material_override = GreyboxKit.material(color, 0.1, 0.5)
	body.rotation.x = PI * 0.5
	_disc.add_child(body)
	# Cream edge spots (like a casino chip) and a cream centre so the spin reads.
	var spot := BoxMesh.new()
	spot.size = Vector3(0.026, 0.022, 0.038)
	var cream: StandardMaterial3D = GreyboxKit.material(Palette.CREAM)
	for i: int in 6:
		var a: float = TAU * i / 6.0
		var s := MeshInstance3D.new()
		s.mesh = spot
		s.material_override = cream
		s.position = Vector3(cos(a), sin(a), 0.0) * (PlinkoStation.CHIP_R - 0.011)
		s.rotation.z = a
		_disc.add_child(s)
	var inner := MeshInstance3D.new()
	var im := CylinderMesh.new()
	im.top_radius = PlinkoStation.CHIP_R * 0.45
	im.bottom_radius = PlinkoStation.CHIP_R * 0.45
	im.height = 0.038
	im.radial_segments = 14
	im.rings = 1
	inner.mesh = im
	inner.material_override = cream
	inner.rotation.x = PI * 0.5
	_disc.add_child(inner)
	if flight != null:
		_apply(0.0)


## Plays `p_flight`, touching down in its slot `seconds` from now.
func play(p_flight: PlinkoFlight, seconds: float) -> void:
	flight = p_flight
	slot = flight.slot
	rate = clampf(flight.land_time / maxf(seconds, 0.05), 0.5, 8.0)
	_t = 0.0
	_arc = -1
	_landed = false
	if _disc != null:
		_apply(0.0)


func _process(delta: float) -> void:
	if flight == null or _fading:
		return
	_t += delta * rate
	var idx: int = flight.arc_index(_t)
	while _arc < idx:  # strike every peg we passed this frame
		if _arc >= 0:
			_bounce(flight.arcs[_arc])
		_arc += 1
	if not _landed and _t >= flight.land_time:
		_landed = true
		landed.emit(slot)
		Audio.play_at(&"chip_clack", self, -10.0, randf_range(1.05, 1.2))
		if board != null:
			board.flash_slot(slot, mult)
	_apply(_t)
	if _t >= flight.rest_time:
		_rest_for += delta
		if _rest_for >= LINGER:
			_fading = true
			var tw: Tween = create_tween()
			tw.tween_property(self, "scale", Vector3.ONE * 0.05, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tw.tween_callback(queue_free)


func _bounce(a: PlinkoFlight.Arc) -> void:
	if a.peg.x < 0:
		return
	Audio.play_at(&"plink", self, -14.0, randf_range(0.9, 1.35))
	if board != null:
		board.flash_peg(a.peg.x, a.peg.y)


func _apply(t: float) -> void:
	var p: Vector2 = flight.position_at(t)
	position = Vector3(p.x, p.y, 0.0)
	_disc.rotation.z = flight.spin_at(t)
	# A little wobble out of the board plane while it is moving.
	_disc.rotation.y = sin(t * 9.0) * 0.18 * (0.0 if t >= flight.rest_time else 1.0)
