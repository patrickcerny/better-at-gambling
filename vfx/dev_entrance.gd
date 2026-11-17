class_name DevEntrance
extends Node
## The dev's entrance show (Patrick 2026-11-17: "es soll auch alles dunkel werden also alle lichter
## dimmed, dann ein spotlight mittem am eingang vorm casino ... kamera zu mir gedreht der spieler
## smooth (danach schon bewegen). Spotlight und ich schweb von oben rein. Währenddessen läuft der
## song langsam und es kommt eine drummroll vorm song. Ein text "Be prepared for a special
## guest...." in cooler schrift"). Client only, played by every client on `dev_entrance`:
##
## 0 s: the room's lamps and ambient light dim, a drumroll, the line in big gold letters typed
##   out, everyone's controls held (`InputRouter.cutscene`) and their camera turning smoothly to
##   the entrance stage (and following the dev down).
## `DROP_AT`: the drumroll's crash, the spotlight snaps on over the stage with a visible beam, the
##   dev's song fades in slowly (casino music ducked) and the dev floats down from `DROP_HEIGHT`
##   into the light, turning, for `DROP_SECONDS`.
## `seconds`: controls back; the lights come up again, the spotlight fades, the song plays on.
## The song is the `dev_join` clip (a placeholder until Patrick's audio/sfx/dev_join-v1.ogg).

const LINE: String = "Be prepared for a special guest...."
const DIM: float = 0.08
const DIM_FADE: float = 1.2
const DROP_AT: float = 3.0
const DROP_SECONDS: float = 4.2
const DROP_HEIGHT: float = 9.0
const SPOT_ENERGY: float = 16.0
const LIGHTS_BACK: float = 2.5
## The casino music sits this much lower while the song plays.
const MUSIC_DUCK_DB: float = -18.0
const SONG_DB: float = -3.0

var dev: PlayerAvatar
var local: PlayerAvatar
var router: InputRouter
var stage_pos: Vector3
var seconds: float = 9.0
var t: float = 0.0
var spot: SpotLight3D
var beam: MeshInstance3D
var song: AudioStreamPlayer
var line_label: Label
var _layer: CanvasLayer
var _lights: Array[Light3D] = []
var _light_base: Array[float] = []
var _env: Environment
var _ambient_base: float = 1.0
var _dim: float = 0.0
var _dropped: bool = false
var _released: bool = false
var _music_bus: int = -1
var _music_base_db: float = 0.0
var _visual_base: Vector3 = Vector3.ZERO
var _done: bool = false


## Starts the show on `map` with `dev` landing at `pos`; `p_local` is this client's avatar (null
## when spectating), `p_router` its input.
func play(map: Node3D, p_dev: PlayerAvatar, p_local: PlayerAvatar, p_router: InputRouter, _hud: Node, pos: Vector3, p_seconds: float) -> void:
	dev = p_dev
	local = p_local
	router = p_router
	stage_pos = pos
	seconds = maxf(p_seconds, DROP_AT + DROP_SECONDS)
	if router != null:
		router.cutscene = true
	_capture_lights(map)
	_build_spot(map)
	_build_line()
	if dev != null and is_instance_valid(dev.visuals):
		_visual_base = dev.visuals.position
		dev.visuals.position = _visual_base + Vector3(0, DROP_HEIGHT, 0)
		dev.visuals.visible = false  # appears in the light
		dev.nametag.visible = false  # comes with him once he has landed
	Audio.play(&"drumroll", &"SFX", -2.0)


func _process(delta: float) -> void:
	if _done:
		return
	t += delta
	# Lights down, later up again.
	var want: float = 1.0 if t < seconds else 0.0
	_dim = move_toward(_dim, want, delta / (DIM_FADE if want > 0.5 else LIGHTS_BACK))
	_apply_dim(_dim)
	# The line: typed out, then gone once the dev has landed.
	if line_label != null:
		line_label.visible_ratio = clampf(t / 2.2, 0.0, 1.0)
		var a: float = clampf(t / 0.4, 0.0, 1.0) * clampf((DROP_AT + DROP_SECONDS + 0.8 - t) / 0.6, 0.0, 1.0)
		line_label.modulate.a = a
		line_label.scale = Vector2.ONE * (1.0 + 0.03 * sin(t * 3.0))
	# The drop.
	if not _dropped and t >= DROP_AT:
		_drop()
	if _dropped and dev != null and is_instance_valid(dev):
		var f: float = clampf((t - DROP_AT) / DROP_SECONDS, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - f, 3.0)
		dev.visuals.position = _visual_base + Vector3(0, DROP_HEIGHT * (1.0 - eased), 0)
		dev.visuals.rotation.y = (1.0 - eased) * TAU * 2.0
		if f >= 1.0:
			dev.visuals.rotation.y = 0.0
			dev.nametag.visible = not dev.is_local
	# Song fades in.
	if song != null and song.playing:
		song.volume_db = lerpf(-32.0, SONG_DB, clampf((t - DROP_AT) / 3.5, 0.0, 1.0))
	# Spotlight: on at the drop, fades after the lights are back.
	if spot != null:
		var s: float = 0.0
		if _dropped:
			s = clampf((seconds + LIGHTS_BACK + 1.5 - t) / 1.5, 0.0, 1.0)
		spot.light_energy = SPOT_ENERGY * s
		spot.visible = s > 0.001
		if beam != null:
			beam.visible = spot.visible
			(beam.material_override as StandardMaterial3D).albedo_color.a = 0.16 * s
	# Everyone looks at the dev until the controls come back.
	if not _released:
		_turn_camera(delta)
	if not _released and t >= seconds:
		_release()
	if _released and t >= seconds + LIGHTS_BACK + 1.6:
		_cleanup_visuals()
		if song == null or not song.playing:
			_finish()


## Ends the show at once (another one starts, the scene leaves).
func finish_now() -> void:
	_apply_dim(0.0)
	_release()
	if dev != null and is_instance_valid(dev):
		dev.visuals.position = _visual_base
		dev.visuals.rotation.y = 0.0
		dev.visuals.visible = not dev.hidden
		dev.nametag.visible = not dev.hidden and not dev.is_local
	_finish()


func _drop() -> void:
	_dropped = true
	if dev != null and is_instance_valid(dev):
		dev.visuals.visible = true
	Audio.play(&"whoosh", &"SFX", -6.0)
	var clip: AudioStream = Audio.clip(&"dev_join")
	if clip != null:
		song = AudioStreamPlayer.new()
		song.name = "DevSong"
		song.stream = clip
		song.bus = &"SFX"
		song.volume_db = -32.0
		add_child(song)
		song.play()
		song.finished.connect(_restore_music)
		_music_bus = AudioServer.get_bus_index(&"Music")
		if _music_bus >= 0:
			_music_base_db = AudioServer.get_bus_volume_db(_music_bus)
			AudioServer.set_bus_volume_db(_music_bus, _music_base_db + MUSIC_DUCK_DB)


func _release() -> void:
	if _released:
		return
	_released = true
	if router != null and is_instance_valid(router):
		router.cutscene = false


func _turn_camera(delta: float) -> void:
	if local == null or not is_instance_valid(local) or local == dev or local.cam == null or local.cam.camera == null:
		return
	var head: Vector3 = stage_pos + Vector3(0, 1.4, 0)
	if dev != null and is_instance_valid(dev) and _dropped:
		head = dev.visuals.global_position + Vector3(0, 1.0, 0)
	var dir: Vector3 = head - local.cam.camera.global_position
	if dir.length() < 0.5:
		return
	var want_yaw: float = atan2(-dir.x, -dir.z)
	var want_pitch: float = clampf(atan2(dir.y, Vector2(dir.x, dir.z).length()), deg_to_rad(-60.0), deg_to_rad(70.0))
	var k: float = 1.0 - exp(-2.6 * delta)
	local.cam.yaw = lerp_angle(local.cam.yaw, want_yaw, k)
	local.cam.pitch = lerpf(local.cam.pitch, want_pitch, k)


func _capture_lights(map: Node3D) -> void:
	if map == null:
		return
	for n: Node in map.find_children("*", "Light3D", true, false):
		var l: Light3D = n
		if l is DirectionalLight3D or l.light_energy <= 0.0:
			continue
		_lights.append(l)
		_light_base.append(l.light_energy)
	for c: Node in map.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			_env = (c as WorldEnvironment).environment
			_ambient_base = _env.ambient_light_energy


func _apply_dim(f: float) -> void:
	for i: int in _lights.size():
		if is_instance_valid(_lights[i]):
			_lights[i].light_energy = lerpf(_light_base[i], _light_base[i] * DIM, f)
	if _env != null:
		_env.ambient_light_energy = lerpf(_ambient_base, _ambient_base * 0.12, f)


func _build_spot(map: Node3D) -> void:
	var parent: Node3D = map if map != null else (dev.get_parent() as Node3D if dev != null else null)
	if parent == null:
		return
	spot = SpotLight3D.new()
	spot.name = "DevSpotlight"
	spot.light_color = Color(1.0, 0.93, 0.78)
	spot.light_energy = 0.0
	spot.spot_range = 14.0
	spot.spot_angle = 16.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = true
	spot.visible = false
	parent.add_child(spot)
	spot.global_position = stage_pos + Vector3(0, 6.6, 0)
	spot.global_rotation = Vector3(-PI * 0.5, 0, 0)
	# The beam you see in the dark: a soft open cone from the lamp to the floor.
	beam = MeshInstance3D.new()
	beam.name = "DevSpotBeam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 6.6 * tan(deg_to_rad(16.0))
	cone.height = 6.6
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 32
	beam.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.9, 0.7, 0.0)
	mat.no_depth_test = false
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	parent.add_child(beam)
	beam.global_position = stage_pos + Vector3(0, 3.3, 0)


func _build_line() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_layer = CanvasLayer.new()
	_layer.name = "DevEntranceText"
	_layer.layer = 60
	add_child(_layer)
	line_label = Label.new()
	line_label.name = "Line"
	line_label.text = LINE
	line_label.theme_type_variation = &"LogoLabel"
	line_label.add_theme_font_size_override(&"font_size", 64)
	line_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	line_label.add_theme_color_override(&"font_outline_color", Color(0.08, 0.04, 0.02))
	line_label.add_theme_constant_override(&"outline_size", 14)
	line_label.add_theme_color_override(&"font_shadow_color", Color(Palette.WARM_GOLD, 0.45))
	line_label.add_theme_constant_override(&"shadow_offset_x", 0)
	line_label.add_theme_constant_override(&"shadow_offset_y", 0)
	line_label.add_theme_constant_override(&"shadow_outline_size", 28)
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	line_label.offset_left = -900
	line_label.offset_right = 900
	line_label.offset_top = 150
	line_label.offset_bottom = 260
	line_label.pivot_offset = Vector2(900, 55)
	line_label.visible_ratio = 0.0
	line_label.modulate.a = 0.0
	_layer.add_child(line_label)


func _cleanup_visuals() -> void:
	if spot != null:
		spot.queue_free()
		spot = null
	if beam != null:
		beam.queue_free()
		beam = null
	if _layer != null:
		_layer.queue_free()
		_layer = null
		line_label = null


func _restore_music() -> void:
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, _music_base_db)
		_music_bus = -1


func _finish() -> void:
	if _done:
		return
	_done = true
	_restore_music()
	_cleanup_visuals()
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_apply_dim(0.0)
		_release()
		_restore_music()
