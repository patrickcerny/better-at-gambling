class_name SwordTapperStation
extends StationBase
## Sword Tapper pedestal: a round marble plinth with a brass rim, a burgundy velvet disc on top with
## 17 brass-set gem lamps round a grey stone, and a gold-hilted sword stuck in the stone. Each lamp
## has its prize printed on the velvet beside it (for the stake of the pull); warm white when idle,
## gold when the sword lights it, the big ruby at the top of the ring red. A soft warm spotlight
## shaft falls on it from above with a few slow dust motes. The player stands in front of it (+z).
##
## Presentation only (client-side; a headless server builds the solid plinth and nothing else). On
## `sword_pull` (`play_pull`) the sword heaves; it either wobbles and stays (grind, thud, a dust
## puff) or rips free with a ring of light, the lit gems pop one by one with a rising chime, a
## multiplier may slam down over the hilt, and the reveal ends as the server pays
## (`sword_reveal_time`). A big pull raises a golden light column the whole floor sees.

## The plinth: radius, height of its top, and the velvet disc on it.
const PLINTH_R: float = 0.7
const TOP_Y: float = 0.82
const DISC_R: float = 0.66
## The gem ring: lamp radius on the disc and the prize labels' radius just outside it.
const GEM_R: float = 0.47
const LABEL_R: float = 0.585
## The stone in the middle and where the sword's pivot sits (on top of the stone).
const STONE_TOP: float = TOP_Y + 0.2
## Blade length (from the pivot down into the stone is `BLADE_IN`), and the lift when it comes free.
const BLADE_LEN: float = 0.82
const BLADE_IN: float = 0.24
const FREE_LIFT: float = 0.42
## Where the player stands (the seat; no stool: `stand` meta) and their view (0.9.14, Patrick:
## "Even closer on ... sword tapper ... almost the whole screen should be the game"): right over
## the pedestal's top, looking down at the ring so the gems and the stone fill most of the left two
## thirds of the screen (the overlay is a column down the right third); the sword runs off the top.
const STAND_Z: float = 1.15
## Where the multiplier slams down: past the far rim, so the seat view sees it over the ring, not on it.
const MULT_SPOT: Vector3 = Vector3(-0.3, TOP_Y + 0.18, -0.95)
const SEAT_EYE: Vector3 = Vector3(0.4, 1.66, 0.6)
const SEAT_AIM: Vector3 = Vector3(0.4, 0.84, 0.1)
## The reveal, in seconds from the tap: the heave, the sword coming free, the first and last gem
## lighting, and the multiplier slam (all inside `sword_reveal_time`, when the pull pays).
const HEAVE: float = 0.5
const RIP: float = 0.25
const GEMS_FROM: float = 0.85
const GEMS_TO: float = 1.95
const SLAM_AT: float = 2.05
## A stuck sword wobbles until this and lands with a thud.
const STUCK_END: float = 1.1
## Seconds after the reveal that a freed sword sinks back into the stone.
const RETURN_AFTER: float = 2.2
const RETURN_TIME: float = 0.45
## The golden light column of a big pull: height, radius and how long it stands.
const COLUMN_H: float = 9.0
const COLUMN_R: float = 0.55
const COLUMN_TIME: float = 3.6
## Gem colours: idle (warm white), lit (gold), and the ruby's own red.
const GEM_IDLE: Color = Color("#F4E7C8")
const GEM_LIT: Color = Color("#FFC94A")
const RUBY: Color = Color("#D2203A")
const MARBLE: Color = Color("#D8CDBA")
const VELVET: Color = Color("#5E1626")
const STONE: Color = Color("#625D56")

## Client-side presentation (null / empty on a headless server).
var sword: Node3D
var gems: Array[MeshInstance3D] = []
var gem_mats: Array[StandardMaterial3D] = []
var prize_labels: Array[Label3D] = []
var mult_label: Label3D
var column: MeshInstance3D
var column_light: OmniLight3D
var dust: CPUParticles3D
## The stake the ring's prizes are printed for.
var shown_stake: int = 0
## The pull on show ({free, gems, mult}, empty = none), its serial and the seconds since its tap.
var shown_pull: Dictionary = {}
var shown_serial: int = -1
var t: float = 0.0
## Gems lit right now (ring indices).
var lit: Array[int] = []
var _reveal: float = 2.5
var _own: bool = false
var _column_left: float = 0.0
var _column_mat: StandardMaterial3D


func _build_visuals() -> void:
	game_id = &"sword_tapper"
	seat_count = 1
	interact_radius = 1.8
	hot_center = Vector3(0, 0, 0.3)
	GreyboxKit.cylinder(self, PLINTH_R, TOP_Y, Vector3(0, TOP_Y * 0.5, 0), MARBLE, "Plinth")
	var spot: Node3D = _add_seat(Vector3(0, 0, STAND_Z), 0.0)  # faces the sword (−z)
	spot.set_meta(&"stand", true)  # stands at the pedestal, no stool
	_add_seat_camera(SEAT_EYE, SEAT_AIM)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = SEAT_EYE
	camera_anchor.rotation = look_rotation(SEAT_EYE, SEAT_AIM)
	add_child(camera_anchor)
	_reveal = Registry.balance.sword_reveal_time
	if not Vfx.enabled():
		return
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	_round_rug(2.4)
	_build_plinth(brass)
	_build_stone()
	_build_sword(brass)
	_build_ring(brass)
	_build_light()
	_build_column()
	mult_label = _label("", 150, 0.0024, Palette.VIP_GOLD)
	mult_label.name = "Multiplier"
	mult_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mult_label.outline_size = 26
	mult_label.outline_modulate = Palette.CASINO_BLACK
	mult_label.no_depth_test = true
	mult_label.position = MULT_SPOT
	mult_label.visible = false
	add_child(mult_label)
	set_stake(Registry.balance.sword_min_bet)
	var ticker := _Ticker.new()
	ticker.name = "SwordTicker"
	ticker.station = self
	add_child(ticker)
	_apply()


## Prompt at the pedestal.
func prompt_text(min_bet: int) -> String:
	if out_of_order_left > 0.0:
		return "OUT OF ORDER (%ds)" % ceili(out_of_order_left)
	return "%s Pull the sword — from $%d" % [InputGlyphs.hint(&"interact"), min_bet]


## Prints the ring's prizes for a stake of `amount`.
func set_stake(amount: int) -> void:
	shown_stake = amount
	for i: int in prize_labels.size():
		prize_labels[i].text = cents_text(SwordTapperLogic.gem_prize_cents(amount, Registry.balance, i))


## "$10", or "$2.50" for a prize with cents.
static func cents_text(cents: int) -> String:
	if cents % 100 == 0:
		return "$%s" % WinFx.thousands(cents / 100)
	return "$%s.%02d" % [WinFx.thousands(cents / 100), cents % 100]


## A pull (the `sword_pull` event, or the public state for late joiners): the reveal plays from
## `at` seconds after the tap. `own` = the local player's pull (sounds at full volume).
func play_pull(ev: Dictionary, own: bool = false, at: float = 0.0) -> void:
	var s: int = int(ev.get("serial", -1))
	if s >= 0 and s == shown_serial:
		return
	shown_serial = s
	shown_pull = {"free": bool(ev.get("free", false)), "gems": (ev.get("gems", []) as Array).duplicate(), "mult": int(ev.get("mult", 1))}
	_own = own
	t = maxf(at, 0.0)
	lit.clear()
	if int(ev.get("stake", 0)) > 0:
		set_stake(int(ev["stake"]))
	if at <= 0.0:
		_sound(&"stone_grind", -4.0, randf_range(0.95, 1.05))
	_apply()


## Mirrors the server state: a pull still revealing plays from where it is; else the last pull
## stays on show (its gems lit) until the next one.
func show_state(pub: Dictionary) -> void:
	if bool(pub.get("pulling", false)):
		var p: Dictionary = (pub.get("pull", {}) as Dictionary).duplicate()
		p["serial"] = int(pub.get("serial", -1))
		p["stake"] = int(pub.get("stake", 0))
		play_pull(p, false, _reveal - float(pub.get("reveal_left", _reveal)))
		return
	var last: Dictionary = pub.get("last", {})
	if not last.is_empty() and int(last.get("serial", -1)) != shown_serial:
		var p: Dictionary = (last.get("pull", {}) as Dictionary).duplicate()
		p["serial"] = int(last.get("serial", -1))
		p["stake"] = int(last.get("stake", 0))
		play_pull(p, false, _reveal + RETURN_AFTER + RETURN_TIME)


## The golden light column over the pedestal (a big pull), seen across the floor.
func big_win_column() -> void:
	if column == null:
		return
	_column_left = COLUMN_TIME
	column.visible = true
	column_light.visible = true


## True while the reveal is still playing.
func revealing() -> bool:
	return not shown_pull.is_empty() and t < _reveal


## Ring indices lit by the time `at` (in the order they light: clockwise from the ruby).
func lit_at(at: float) -> Array[int]:
	var out: Array[int] = []
	if not bool(shown_pull.get("free", false)):
		return out
	var g: Array = shown_pull.get("gems", [])
	for k: int in g.size():
		if at >= gem_time(k, g.size()):
			out.append(int(g[k]))
	return out


## When the `k`-th of `n` lit gems pops on.
static func gem_time(k: int, n: int) -> float:
	if n <= 1:
		return GEMS_FROM
	return GEMS_FROM + (GEMS_TO - GEMS_FROM) * k / float(n - 1)


func _tick(delta: float) -> void:
	if _column_left > 0.0:
		_column_left -= delta
		var fade: float = clampf(minf(COLUMN_TIME - _column_left, _column_left) / 0.4, 0.0, 1.0)
		_column_mat.albedo_color.a = 0.32 * fade
		column_light.light_energy = 3.0 * fade
		if _column_left <= 0.0:
			column.visible = false
			column_light.visible = false
	if shown_pull.is_empty() or t > _reveal + RETURN_AFTER + RETURN_TIME + 0.1:
		return
	var before: float = t
	t += delta
	_cues(before, t)
	_apply()


## One-off sounds and puffs for the moments the clock passed (never when snapping to a state).
func _cues(from: float, to: float) -> void:
	var free: bool = bool(shown_pull.get("free", false))
	if free:
		if from < HEAVE and to >= HEAVE:
			_sound(&"sword_ring", -2.0)
			_ring_flash()
		var g: Array = shown_pull.get("gems", [])
		for k: int in g.size():
			var at: float = gem_time(k, g.size())
			if from < at and to >= at:
				_sound(&"plink", -6.0, 0.85 + 0.06 * k)
		if int(shown_pull.get("mult", 1)) > 1 and from < SLAM_AT and to >= SLAM_AT:
			_sound(&"thud", -2.0, 0.7)
			_sound(&"coin", -8.0, 0.9)
		var back: float = _reveal + RETURN_AFTER
		if from < back and to >= back:
			_sound(&"stone_grind", -12.0, 1.2)
	elif from < STUCK_END and to >= STUCK_END:
		_sound(&"thud", -4.0, 0.85)
		_dust_puff()


## Poses the sword, the gems and the multiplier for the clock `t` (pure: snapping and playing agree).
func _apply() -> void:
	if sword == null:
		return
	var free: bool = bool(shown_pull.get("free", false))
	var lift: float = 0.0
	var tilt: float = 0.0
	if not shown_pull.is_empty():
		if t < HEAVE:
			var k: float = t / HEAVE
			lift = 0.03 * k
			tilt = sin(t * 46.0) * 0.035 * k
		elif free:
			lift = FREE_LIFT * ease(clampf((t - HEAVE) / RIP, 0.0, 1.0), 0.4)
			var back: float = clampf((t - _reveal - RETURN_AFTER) / RETURN_TIME, 0.0, 1.0)
			lift *= 1.0 - back * back
		elif t < STUCK_END:
			var w: float = (STUCK_END - t) / (STUCK_END - HEAVE)
			lift = 0.03 * w
			tilt = sin(t * 38.0) * 0.06 * w
	sword.position.y = STONE_TOP + lift
	sword.rotation.z = tilt
	lit = lit_at(t)
	for i: int in gems.size():
		_light_gem(i, i in lit)
	var m: int = int(shown_pull.get("mult", 1))
	mult_label.visible = free and m > 1 and t >= SLAM_AT
	if mult_label.visible:
		mult_label.text = "×%d" % m
		var s: float = clampf((t - SLAM_AT) / 0.18, 0.0, 1.0)
		mult_label.scale = Vector3.ONE * lerpf(2.4, 1.0, s * s)


func _light_gem(i: int, on: bool) -> void:
	var mat: StandardMaterial3D = gem_mats[i]
	var ruby: bool = _is_ruby(i)
	var base: Color = RUBY if ruby else (GEM_LIT if on else GEM_IDLE.darkened(0.62))
	mat.albedo_color = base
	mat.emission = (RUBY.lightened(0.1) if ruby else GEM_LIT) if on else (RUBY.darkened(0.5) if ruby else GEM_IDLE.darkened(0.5))
	mat.emission_energy_multiplier = 1.25 if on else 0.08
	prize_labels[i].modulate = Palette.VIP_GOLD if on else Palette.CREAM.darkened(0.08)
	prize_labels[i].outline_modulate = Color(0.35, 0.05, 0.05, 1.0) if on else VELVET.darkened(0.4)


func _is_ruby(i: int) -> bool:
	return is_ruby(i)


## True for the ring's top prize (the ruby).
static func is_ruby(i: int) -> bool:
	var top: float = 0.0
	for v: float in Registry.balance.sword_ring:
		top = maxf(top, v)
	return Registry.balance.sword_ring[i] >= top


## Radius (m) of gem `i`'s lamp: the ruby biggest, then smaller with the prize (the overlay's ring
## draws its dots to the same sizes).
static func gem_radius(i: int) -> float:
	var v: float = Registry.balance.sword_ring[i]
	return 0.06 if is_ruby(i) else (0.05 if v >= 2.0 else (0.044 if v >= 1.0 else (0.039 if v >= 0.5 else 0.034)))


## A gem lamp's place on the ring (index 0 at the top, far side as the player sees it; clockwise).
static func gem_spot(i: int, radius: float = GEM_R) -> Vector3:
	var a: float = TAU * i / SwordTapperLogic.RING_SIZE
	return Vector3(sin(a) * radius, TOP_Y + 0.03, -cos(a) * radius)


# --- Building -----------------------------------------------------------------------------------


## The marble plinth: a wider foot, the brass rim round the top, a brass band, the velvet disc.
func _build_plinth(brass: Material) -> void:
	var marble: StandardMaterial3D = GreyboxKit.material(MARBLE, 0.0, 0.35)
	_part_mesh(_disc(PLINTH_R + 0.06, 0.1), Vector3(0, 0.05, 0), marble, "Foot")
	_part_mesh(_disc(PLINTH_R + 0.075, 0.025), Vector3(0, 0.11, 0), brass, "FootBand")
	_part_mesh(_disc(PLINTH_R + 0.02, 0.05), Vector3(0, TOP_Y - 0.03, 0), marble, "Cap")
	var rim := TorusMesh.new()
	rim.inner_radius = DISC_R
	rim.outer_radius = PLINTH_R + 0.035
	rim.rings = 48
	rim.ring_segments = 10
	_part_mesh(rim, Vector3(0, TOP_Y, 0), brass, "Rim")
	_part_mesh(_disc(PLINTH_R + 0.012, 0.03), Vector3(0, TOP_Y * 0.55, 0), brass, "Band")
	_part_mesh(_disc(DISC_R, 0.02), Vector3(0, TOP_Y + 0.005, 0), GreyboxKit.material(VELVET, 0.0, 0.95), "Velvet")
	var plate := _label("SWORD TAPPER", 54, 0.0016, Palette.WARM_GOLD)
	plate.position = Vector3(0, TOP_Y * 0.32, PLINTH_R + 0.005)
	add_child(plate)


func _build_stone() -> void:
	var rock := SphereMesh.new()
	rock.radius = 0.2
	rock.height = 0.3
	rock.radial_segments = 9
	rock.rings = 5
	var mi: MeshInstance3D = _part_mesh(rock, Vector3(0, TOP_Y + 0.06, 0), GreyboxKit.material(STONE, 0.0, 0.95), "Stone")
	mi.scale = Vector3(1.05, 1.0, 0.9)
	mi.rotation.y = 0.4
	var cap := SphereMesh.new()
	cap.radius = 0.11
	cap.height = 0.16
	cap.radial_segments = 7
	cap.rings = 4
	_part_mesh(cap, Vector3(0.02, STONE_TOP - 0.04, 0.01), GreyboxKit.material(STONE.lightened(0.08), 0.0, 0.95), "StoneTop")


## The sword on its pivot (the stone top): a polished blade, a gold cross-guard, a red leather grip
## and a gold pommel.
func _build_sword(brass: Material) -> void:
	sword = Node3D.new()
	sword.name = "Sword"
	sword.position = Vector3(0, STONE_TOP, 0)
	add_child(sword)
	var steel: StandardMaterial3D = GreyboxKit.material(Color("#E6DDC6"), 0.9, 0.22)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.VIP_GOLD, 0.9, 0.25)
	var blade_mid: float = (BLADE_LEN - BLADE_IN) * 0.5 - BLADE_IN * 0.5
	_part_mesh(_box(Vector3(0.055, BLADE_LEN, 0.012)), Vector3(0, blade_mid, 0), steel, "Blade", sword)
	_part_mesh(_box(Vector3(0.012, BLADE_LEN * 0.8, 0.014)), Vector3(0, blade_mid + 0.04, 0), brass, "Fuller", sword)
	var top: float = BLADE_LEN - BLADE_IN
	_part_mesh(_box(Vector3(0.3, 0.035, 0.05)), Vector3(0, top, 0), gold, "Guard", sword)
	for side: int in [-1, 1]:
		var end := SphereMesh.new()
		end.radius = 0.026
		end.height = 0.052
		_part_mesh(end, Vector3(side * 0.15, top, 0), gold, "GuardEnd", sword)
	_part_mesh(_rod(0.019, 0.17), Vector3(0, top + 0.1, 0), GreyboxKit.material(VELVET.darkened(0.2), 0.0, 0.7), "Grip", sword)
	var pommel := SphereMesh.new()
	pommel.radius = 0.038
	pommel.height = 0.076
	_part_mesh(pommel, Vector3(0, top + 0.21, 0), gold, "Pommel", sword)
	var jewel := SphereMesh.new()
	jewel.radius = 0.018
	jewel.height = 0.036
	var red := StandardMaterial3D.new()
	red.albedo_color = RUBY
	red.emission_enabled = true
	red.emission = RUBY
	red.emission_energy_multiplier = 0.8
	_part_mesh(jewel, Vector3(0, top, 0.028), red, "GuardJewel", sword)


## The 17 gem lamps in brass settings, each with its prize printed beside it on the velvet.
func _build_ring(brass: Material) -> void:
	var cfg: BalanceConfig = Registry.balance
	for i: int in cfg.sword_ring.size():
		var r: float = gem_radius(i)
		var p: Vector3 = gem_spot(i)
		_part_mesh(_disc(r + 0.016, 0.022), Vector3(p.x, TOP_Y + 0.016, p.z), brass, "Setting%d" % i)
		var gem := SphereMesh.new()
		gem.radius = r
		gem.height = r * 1.3
		gem.radial_segments = 8
		gem.rings = 3
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.metallic = 0.3
		mat.roughness = 0.15
		gem_mats.append(mat)
		gems.append(_part_mesh(gem, Vector3(p.x, TOP_Y + 0.03 + r * 0.4, p.z), mat, "Gem%d" % i))
		var label := _label("", 64, 0.00068, Palette.CREAM)
		label.name = "Prize%d" % i
		label.outline_size = 10
		label.rotation.x = -PI * 0.5  # flat on the velvet, read from the player's side
		var lp: Vector3 = gem_spot(i, LABEL_R + (0.012 if _is_ruby(i) else 0.0))
		label.position = Vector3(lp.x, TOP_Y + 0.018, lp.z)
		add_child(label)
		prize_labels.append(label)
		_light_gem(i, false)


## The soft warm spotlight from above (a faint shaft of light and a few slow dust motes in it).
func _build_light() -> void:
	var spot := SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = Color(1.0, 0.84, 0.58)
	spot.light_energy = 0.7
	spot.spot_range = 5.0
	spot.spot_angle = 17.0
	spot.spot_attenuation = 0.8
	spot.position = Vector3(0, 3.6, 0.15)
	spot.rotation.x = -PI * 0.5
	add_child(spot)
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.78
	cm.height = 2.7
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	shaft.mesh = cm
	shaft.material_override = _glow(Color(1.0, 0.86, 0.6, 0.022))
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(0, TOP_Y + 1.38, 0.0)
	add_child(shaft)
	dust = CPUParticles3D.new()
	dust.name = "Dust"
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	q.material = Vfx.glow_material(Color.WHITE, true, true)
	dust.mesh = q
	dust.amount = 14
	dust.lifetime = 7.0
	dust.preprocess = 7.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.45, 1.0, 0.45)
	dust.position = Vector3(0, TOP_Y + 1.3, 0)
	dust.direction = Vector3(0.2, -1, 0.1)
	dust.spread = 60.0
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.06
	dust.gravity = Vector3.ZERO
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.7, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.9, 0.7, 0.55))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.9, 0.7, 0.0))
	dust.color_ramp = ramp
	add_child(dust)


## The big-pull column (hidden until `big_win_column`).
func _build_column() -> void:
	column = MeshInstance3D.new()
	column.name = "LightColumn"
	var cm := CylinderMesh.new()
	cm.top_radius = COLUMN_R * 1.3
	cm.bottom_radius = COLUMN_R
	cm.height = COLUMN_H
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	column.mesh = cm
	_column_mat = _glow(Color(1.0, 0.78, 0.3, 0.0))
	column.material_override = _column_mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position = Vector3(0, TOP_Y + COLUMN_H * 0.5, 0)
	column.visible = false
	add_child(column)
	column_light = OmniLight3D.new()
	column_light.name = "ColumnLight"
	column_light.light_color = Color(1.0, 0.78, 0.35)
	column_light.light_energy = 0.0
	column_light.omni_range = 7.0
	column_light.position = Vector3(0, 2.2, 0)
	column_light.visible = false
	add_child(column_light)


## A ring of gold light that sweeps out over the velvet as the sword comes free.
func _ring_flash() -> void:
	if not is_inside_tree() or sword == null:
		return
	var ring := MeshInstance3D.new()
	ring.name = "RingFlash"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.22
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	var mat: StandardMaterial3D = _glow(Color(1.0, 0.85, 0.4, 0.9))
	ring.material_override = mat
	ring.position = Vector3(0, TOP_Y + 0.05, 0)
	add_child(ring)
	var tw: Tween = ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(3.4, 1.0, 3.4), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	Vfx.free_after(ring, 0.6)


## A grey puff of stone dust round the base of the stone (the sword stayed).
func _dust_puff() -> void:
	if not is_inside_tree() or sword == null:
		return
	var p := CPUParticles3D.new()
	p.name = "DustPuff"
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	q.material = Vfx.glow_material(Color.WHITE, false, true)
	p.mesh = q
	p.amount = 16
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.18
	p.emission_ring_inner_radius = 0.1
	p.emission_ring_height = 0.02
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, -0.6, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.72, 0.66, 0.7))
	ramp.set_color(1, Color(0.6, 0.58, 0.55, 0.0))
	p.color_ramp = ramp
	p.position = Vector3(0, TOP_Y + 0.08, 0)
	add_child(p)
	p.emitting = true
	Vfx.free_after(p, 1.2)


func _sound(clip: StringName, db: float, pitch: float = 1.0) -> void:
	if sword == null or not is_inside_tree():
		return
	if _own:
		Audio.play(clip, &"SFX", db, pitch)
	else:
		Audio.play_at(clip, self, db - 2.0, pitch)


static func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = color
	return m


func _part_mesh(mesh: Mesh, pos: Vector3, mat: Material, node_name: String, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _rod(radius: float, length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 12
	return c


static func _disc(radius: float, depth: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = depth
	c.radial_segments = 40
	return c


func _label(text: String, size: int, pixel: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	return l


## Runs the reveal every frame (StationBase turns its own processing on and off with the Hot marker).
class _Ticker:
	extends Node
	var station: SwordTapperStation

	func _process(delta: float) -> void:
		if station != null:
			station._tick(delta)
