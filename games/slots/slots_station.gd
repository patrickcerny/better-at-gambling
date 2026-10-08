class_name SlotsStation
extends StationBase
## Slot machine: a classic upright cabinet (pedestal, cream-and-gold belly with the coin tray,
## button deck, gold-framed reel window, rounded red marquee with bulbs) with the pull lever
## mounted on its right side on a bracket and axle, and one stool in front.

## Cabinet body (the collision footprint the map and the stool layout were tuned around).
const BODY_SIZE: Vector3 = Vector3(0.9, 1.87, 0.7)
## Front face of the body (local +z faces the player).
const FRONT_Z: float = 0.35
## Centre of the reels on the cabinet (the reel window is built around it).
const REELS_POS: Vector3 = Vector3(0, 1.35, 0.4)
## Lever axle: where the arm pivots on its bracket, on the cabinet's right side near the front so
## the seated player sees it past the cabinet edge.
const LEVER_PIVOT: Vector3 = Vector3(0.6, 1.2, 0.18)
## Arm length from the axle to the ball knob.
const LEVER_LENGTH: float = 0.55
## Marquee arch: radius across the cabinet, flattened to this height above the body.
const ARCH_RADIUS: float = 0.45
const ARCH_SQUASH: float = 0.55


func _build_visuals() -> void:
	game_id = &"slots"
	seat_count = 1
	interact_radius = 1.8
	var body_col: Color = Palette.WARM_CHARCOAL if is_vip else Palette.VIP_BURGUNDY.darkened(0.25)
	var trim: StandardMaterial3D = GreyboxKit.material(Palette.VIP_GOLD if is_vip else Palette.WARM_GOLD, 0.8, 0.35)
	GreyboxKit.box(self, BODY_SIZE, Vector3(0, BODY_SIZE.y * 0.5, 0), body_col, "Cabinet")
	_build_pedestal(body_col, trim)
	_build_belly(trim)
	_build_deck(trim)
	_build_window(trim)
	_build_marquee(trim)
	_build_lever(trim)
	if Vfx.enabled():
		reels_fx = SlotReelsFx.new()
		reels_fx.position = REELS_POS
		add_child(reels_fx)
	_stool(Vector3(0, 0, 0.9))
	_add_seat(Vector3(0, 0.5, 0.9), 0.0)  # faces the cabinet (−z)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	# Far enough back to frame the reels and the marquee (the old view sat inside the screen).
	camera_anchor.position = CAMERA_POS
	camera_anchor.rotation.x = deg_to_rad(CAMERA_PITCH)
	add_child(camera_anchor)


## Wider plinth under the body with a gold kick strip.
func _build_pedestal(body_col: Color, trim: Material) -> void:
	_part(Vector3(1.02, 0.12, 0.82), Vector3(0, 0.06, 0.02), GreyboxKit.material(body_col.darkened(0.45)), "Pedestal")
	_part(Vector3(1.04, 0.025, 0.84), Vector3(0, 0.125, 0.02), trim, "PedestalTrim")
	for side: int in [-1, 1]:  # gold corner strips up the front edges
		_part(Vector3(0.03, BODY_SIZE.y - 0.14, 0.03), Vector3(side * 0.445, 0.14 + (BODY_SIZE.y - 0.14) * 0.5, FRONT_Z), trim, "CornerTrim")


## Cream belly panel in a gold frame (a red seven on it) and the coin tray at the bottom front.
func _build_belly(trim: Material) -> void:
	_part(Vector3(0.74, 0.5, 0.02), Vector3(0, 0.6, FRONT_Z + 0.005), trim, "BellyFrame")
	_part(Vector3(0.68, 0.44, 0.02), Vector3(0, 0.6, FRONT_Z + 0.015), GreyboxKit.material(Palette.CREAM), "BellyPanel")
	var seven := _label("7 7 7", 150, 0.0016, Palette.CASINO_RED)
	seven.position = Vector3(0, 0.62, FRONT_Z + 0.027)
	add_child(seven)
	var deco := _label("— LUCKY LOUNGE —", 48, 0.0016, Palette.WARM_GOLD.darkened(0.2))
	deco.position = Vector3(0, 0.45, FRONT_Z + 0.027)
	add_child(deco)
	_part(Vector3(0.56, 0.035, 0.18), Vector3(0, 0.2, FRONT_Z + 0.09), trim, "CoinTray")
	_part(Vector3(0.5, 0.03, 0.14), Vector3(0, 0.225, FRONT_Z + 0.09), GreyboxKit.material(Palette.CASINO_BLACK), "CoinTrayWell")
	_part(Vector3(0.56, 0.08, 0.02), Vector3(0, 0.24, FRONT_Z + 0.17), trim, "CoinTrayLip")
	_part(Vector3(0.18, 0.1, 0.02), Vector3(0, 0.3, FRONT_Z + 0.01), GreyboxKit.material(Palette.CASINO_BLACK), "CoinChute")


## Button deck below the reel window: a slanted ledge with the bet / spin buttons.
func _build_deck(trim: Material) -> void:
	var deck: MeshInstance3D = _part(Vector3(0.9, 0.05, 0.2), Vector3(0, 0.98, FRONT_Z + 0.09), GreyboxKit.material(Palette.CASINO_BLACK), "ButtonDeck")
	deck.rotation.x = deg_to_rad(12.0)  # tilts towards the player
	_part(Vector3(0.92, 0.03, 0.03), Vector3(0, 0.955, FRONT_Z + 0.19), trim, "DeckTrim")
	var cols: Array[Color] = [Palette.CREAM, Palette.WARM_GOLD, Palette.CASINO_RED]
	var xs: Array[float] = [-0.26, -0.12, 0.2]
	for i: int in 3:
		var b := CylinderMesh.new()
		b.top_radius = 0.045 if i == 2 else 0.03
		b.bottom_radius = b.top_radius
		b.height = 0.03
		b.radial_segments = 12
		var mat := GreyboxKit.material(cols[i])
		var btn: MeshInstance3D = _part_mesh(b, Vector3(xs[i], 1.0, FRONT_Z + 0.09), mat, "Button%d" % i)
		btn.rotation.x = deg_to_rad(12.0)


## Dark screen behind the reels, framed in gold, with a black jackpot strip above it.
func _build_window(trim: Material) -> void:
	_part(Vector3(0.78, 0.42, 0.04), Vector3(0, REELS_POS.y, FRONT_Z + 0.0), GreyboxKit.material(Palette.CASINO_BLACK), "Screen")
	for side: int in [-1, 1]:
		_part(Vector3(0.045, 0.46, 0.05), Vector3(side * 0.385, REELS_POS.y, FRONT_Z + 0.03), trim, "WindowFrame")
		_part(Vector3(0.815, 0.045, 0.05), Vector3(0, REELS_POS.y + side * 0.2075, FRONT_Z + 0.03), trim, "WindowFrame")
	_part(Vector3(0.7, 0.16, 0.02), Vector3(0, 1.69, FRONT_Z + 0.01), GreyboxKit.material(Palette.CASINO_BLACK), "JackpotStrip")
	var jp := _label("JACKPOT", 72, 0.0016, Palette.VIP_GOLD)
	jp.position = Vector3(0, 1.69, FRONT_Z + 0.022)
	add_child(jp)


## Rounded red marquee on top: a flattened half-round with a gold rim, "SLOTS" and a row of bulbs.
func _build_marquee(trim: Material) -> void:
	var top: float = BODY_SIZE.y
	_part(Vector3(0.96, 0.05, 0.76), Vector3(0, top + 0.025, 0), trim, "Crown")
	var rim: MeshInstance3D = _part_mesh(_disc(ARCH_RADIUS + 0.03, 0.62), Vector3(0, top + 0.05, -0.02), trim, "MarqueeRim")
	rim.rotation.x = PI * 0.5
	rim.scale = Vector3(1, 1, ARCH_SQUASH)  # local z is world up once the axis lies along z
	var arch: MeshInstance3D = _part_mesh(_disc(ARCH_RADIUS, 0.68), Vector3(0, top + 0.05, -0.02), GreyboxKit.material(Palette.CASINO_RED), "Marquee")
	arch.rotation.x = PI * 0.5
	arch.scale = Vector3(1, 1, ARCH_SQUASH)
	var sign := _label("SLOTS", 160, 0.0016, Palette.VIP_GOLD if is_vip else Palette.WARM_GOLD)
	sign.position = Vector3(0, top + 0.13, 0.32 + 0.005)
	sign.outline_size = 16
	sign.outline_modulate = Palette.VIP_BURGUNDY.darkened(0.4)
	add_child(sign)
	if not Vfx.enabled():
		return
	var bulb := SphereMesh.new()
	bulb.radius = 0.022
	bulb.height = 0.044
	bulb.radial_segments = 8
	bulb.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.CREAM
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.45)
	mat.emission_energy_multiplier = 1.4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	var n: int = 11
	mm.instance_count = n
	for i: int in n:
		var a: float = lerpf(0.12, PI - 0.12, i / float(n - 1))
		var p := Vector3(cos(a) * (ARCH_RADIUS - 0.035), top + 0.05 + sin(a) * (ARCH_RADIUS - 0.035) * ARCH_SQUASH, 0.33)
		mm.set_instance_transform(i, Transform3D(Basis(), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MarqueeBulbs"
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## The pull lever on the cabinet's right side: a gold bracket plate with an axle through a hub;
## `lever` pivots on the axle (rotation.x pulls the knob forward and down).
func _build_lever(trim: Material) -> void:
	var chrome: StandardMaterial3D = GreyboxKit.material(Color("#B9B4AA"), 0.9, 0.25)
	var x0: float = BODY_SIZE.x * 0.5
	_part(Vector3(0.03, 0.32, 0.22), Vector3(x0 + 0.015, LEVER_PIVOT.y, LEVER_PIVOT.z), trim, "LeverBracket")
	_part(Vector3(0.09, 0.09, 0.12), Vector3(x0 + 0.045, LEVER_PIVOT.y, LEVER_PIVOT.z), trim, "LeverBoss")
	var axle: MeshInstance3D = _part_mesh(_rod(0.028, LEVER_PIVOT.x - x0 + 0.03), Vector3((x0 + LEVER_PIVOT.x + 0.03) * 0.5, LEVER_PIVOT.y, LEVER_PIVOT.z), chrome, "LeverAxle")
	axle.rotation.z = PI * 0.5
	lever = Node3D.new()
	lever.name = "Lever"
	lever.position = LEVER_PIVOT
	add_child(lever)
	var hub: MeshInstance3D = _part_mesh(_rod(0.055, 0.05), Vector3.ZERO, trim, "Hub", lever)
	hub.rotation.z = PI * 0.5
	_part_mesh(_rod(0.018, LEVER_LENGTH), Vector3(0, LEVER_LENGTH * 0.5, 0), chrome, "Arm", lever)
	var knob := GreyboxKit.sphere(lever, 0.065, Vector3(0, LEVER_LENGTH + 0.03, 0), Palette.CASINO_RED, "Knob")
	knob.material_override = GreyboxKit.material(Palette.CASINO_RED, 0.2, 0.3)


## Visual-only box (the body box carries the collision).
func _part(size: Vector3, pos: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _part_mesh(b, pos, mat, node_name)


func _part_mesh(mesh: Mesh, pos: Vector3, mat: Material, node_name: String, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Vertical cylinder of `radius` and `length`.
func _rod(radius: float, length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 12
	return c


## Cylinder lying along z (`depth` deep): the marquee's half-round, its lower half hidden in the crown.
func _disc(radius: float, depth: float) -> CylinderMesh:
	var c := _rod(radius, depth)
	c.radial_segments = 20
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


## Seated view: behind the stool at eye height, reels and marquee above the bet strip.
const CAMERA_POS: Vector3 = Vector3(0, 1.5, 1.35)
const CAMERA_PITCH: float = -1.0

## The lever's pivot (rotates about its axle on the bracket).
var lever: Node3D
## Reels on the cabinet screen (client only; null on a headless server).
var reels_fx: SlotReelsFx


## Seconds of the lever's down-stroke; the reels start spinning when it bottoms out.
const LEVER_DOWN: float = 0.24


## A bet pulls the lever (with Patrick's lever sound: full volume for your own pull, from the
## machine for others') and the reels start spinning on the down-stroke.
func start_spin(own: bool = false) -> void:
	if reels_fx == null:
		return
	if own:
		Audio.play(&"slots_lever", &"SFX", 0.0)
	else:
		Audio.play_at(&"slots_lever", self, -2.0)
	var t: Tween = lever.create_tween()
	t.tween_property(lever, "rotation:x", 0.9, LEVER_DOWN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(reels_fx.spin)
	t.tween_property(lever, "rotation:x", 0.0, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## The spin was refunded for a minigame: the reels stop where they are, no result.
func reset_table() -> void:
	if reels_fx != null:
		reels_fx.cancel()


## The reels stop on `line` one by one; returns the seconds until the last one has stopped.
## `own` = the local player's spin (plays the riser / no-match sounds).
func stop_on(line: Array, own: bool = false) -> float:
	return reels_fx.stop_on(line, own) if reels_fx != null else 0.0
