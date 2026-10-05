class_name LastCallLighting
extends Node
## Last Call mood: the room dims and turns warmer, spotlights pick out every table, and the audio
## director gets a mood cue. Follows `ClientMatchState.last_call`, so a rejoin mid-Last Call and a
## new match in the same room both come out right. Client only.

const FADE: float = 1.5
## Room lamps and ambient light keep this much of their energy.
const DIM: float = 0.55
const WARM: Color = Color(1.0, 0.68, 0.4)
const SPOT_ENERGY: float = 5.0

var state: ClientMatchState
## Map root (its WorldEnvironment and room lamps) and stations to light.
var map: Node3D
var stations: Dictionary = {}

var active: bool = false
var level: float = 0.0
var spots: Array[SpotLight3D] = []
var _env: Environment
var _lamps: Array[OmniLight3D] = []
var _base_lamp: Array[Array] = []
var _base_ambient: Color
var _base_ambient_energy: float = 1.0
var _base_bg: Color
var _tween: Tween


func setup(p_state: ClientMatchState, p_map: Node3D, p_stations: Dictionary) -> void:
	state = p_state
	map = p_map
	stations = p_stations


func _process(_delta: float) -> void:
	if state != null and state.last_call != active:
		set_active(state.last_call)


## Fades the Last Call look in or out.
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if not Vfx.enabled():
		return
	if on and _env == null and _lamps.is_empty():
		_capture()
	if on and spots.is_empty():
		_build_spots()
	Audio.set_mood(&"last_call" if on else &"")
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply, level, 1.0 if on else 0.0, FADE).set_trans(Tween.TRANS_SINE)


func _capture() -> void:
	if map == null:
		return
	for c: Node in map.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			_env = (c as WorldEnvironment).environment
			_base_ambient = _env.ambient_light_color
			_base_ambient_energy = _env.ambient_light_energy
			_base_bg = _env.background_color
		elif c is OmniLight3D:
			var l: OmniLight3D = c
			_lamps.append(l)
			_base_lamp.append([l.light_energy, l.light_color])


func _build_spots() -> void:
	for node: Variant in stations.values():
		var st: Node3D = node as Node3D
		if st == null or not st.is_inside_tree():
			continue
		var s := SpotLight3D.new()
		s.name = "LastCallSpot"
		s.light_color = Color(1.0, 0.78, 0.5)
		s.light_energy = 0.0
		s.spot_range = 9.0
		s.spot_angle = 26.0
		s.spot_attenuation = 0.8
		s.position = Vector3(0, 6.5, 0)
		s.rotation.x = -PI * 0.5
		st.add_child(s)
		spots.append(s)


func _apply(f: float) -> void:
	level = f
	if _env != null:
		_env.ambient_light_color = _base_ambient.lerp(_base_ambient * WARM, f)
		_env.ambient_light_energy = lerpf(_base_ambient_energy, _base_ambient_energy * DIM, f)
		_env.background_color = _base_bg.lerp(_base_bg.darkened(0.3), f)
	for i: int in _lamps.size():
		if not is_instance_valid(_lamps[i]):
			continue
		var base_e: float = _base_lamp[i][0]
		var base_c: Color = _base_lamp[i][1]
		_lamps[i].light_energy = lerpf(base_e, base_e * DIM, f)
		_lamps[i].light_color = base_c.lerp(base_c * WARM, f)
	for s: SpotLight3D in spots:
		if is_instance_valid(s):
			s.light_energy = SPOT_ENERGY * f
			s.visible = f > 0.001


func _exit_tree() -> void:
	if level > 0.0:
		_apply(0.0)  # leave the shared Environment as we found it
