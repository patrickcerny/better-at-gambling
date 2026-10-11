class_name ForeheadPokerStage
extends MinigameStage
## Client presentation for Forehead Poker: Lucky's card room in the dark (`CardTableSet` with
## `dark = true`: one hanging lamp over the felt, the rest in shadow), seen from your own chair.
## Move the mouse (or the right stick) to turn your head and read the cards on the other beans'
## foreheads; the yaw is clamped to the table. Each round Lucky flicks a card onto every forehead
## (DEAL), the table talks it over (TALK, timer bar), then 1 = STAY / 2 = FOLD (DECIDE: a gold tick
## pops over everyone who decided, never what). At the SHOWDOWN every card lifts off its forehead,
## tips over and lands face up in a row on the felt, the winning card glows, and +N / -1 / 0 pop
## over the beans.
##
## Your own card never reaches this client before the showdown: the others' cards come in through
## our private state (`on_private`), ours is a plain card back (both sides) until the showdown
## event names it. The 2D overlay shows it as a "?" card with a "Don't peek" line.

const CARD_SIZE: Vector2 = Vector2(0.34, 0.48)
## Where the card sits on a bean (bean-local, the bean is scaled by `CardTableSet.BEAN_SCALE`):
## its lower edge just over the eyebrows, standing up in front of the forehead (a bean faces -Z).
const FOREHEAD: Vector3 = Vector3(0.0, 1.8, -0.42)
const FOREHEAD_TILT: float = -0.22
const TURN_MAX: float = 1.0
## The camera: our eyes (seat-local, metres) and how far we may look around.
const EYE: Vector3 = Vector3(0.0, 1.48, -0.18)
## Sitting back at the showdown: metres back and up.
const SIT_BACK: Vector2 = Vector2(0.55, 0.15)
const PITCH_UP: float = 0.42
const PITCH_DOWN: float = -0.6
const YAW_MARGIN: float = 0.3
const YAW_MAX: float = 1.75
const STICK_SPEED: float = 2.4
## Cursor near the left / right edge keeps turning (the cursor is confined on a stage).
const EDGE_ZONE: float = 0.035
const EDGE_SPEED: float = 1.6
## Dealing: when Lucky flicks the first card, the gap between cards, one card's flight.
const DEAL_FIRST: float = 0.2
const DEAL_FLIGHT: float = 0.55
const SHOW_FLIGHT: float = 0.7
const SHOW_GAP: float = 0.12
## How far the showdown cards stand up off the felt (radians from lying flat).
const SHOW_LEAN: float = 1.05
const ACTION_CONFIRM_TIMEOUT: float = 1.5
## Seat-local height of the name tags (above the forehead cards).
const TAG_Y: float = 2.0

const BLACK_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Black.ttf")
const BOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")


## A gold check mark (fonts here have no ✓ glyph).
class TickMark:
	extends Control
	var color: Color = Palette.VIP_GOLD

	func _init(px: float = 22.0) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s: Vector2 = size
		var pts := PackedVector2Array([Vector2(0.14, 0.52) * s, Vector2(0.4, 0.78) * s, Vector2(0.88, 0.22) * s])
		draw_polyline(pts, Color(0, 0, 0, 0.6), maxf(s.x * 0.26, 3.0), true)
		draw_polyline(pts, color, maxf(s.x * 0.16, 2.0), true)


var table: CardTableSet
var host: QuizHost
var players_list: Array[int] = []
## player → their forehead card node (ours is a plain back until the showdown).
var cards: Dictionary[int, TableCard3D] = {}
## Cards we are allowed to know: the others' (private state), everyone's at the showdown.
var known: Dictionary[int, int] = {}
var round_num: int = 0
var rounds: int = ForeheadPokerLogic.ROUNDS
## "intro", "deal", "talk", "decide", "showdown", "over".
var phase: String = "intro"
var held: bool = false
var over: bool = false
var time_left: float = 0.0
var time_span: float = 1.0
## Our answer this round ("stay" / "fold" / "").
var my_choice: String = ""
var decided: Dictionary[int, bool] = {}
var totals: Dictionary[int, int] = {}
var gains: Dictionary[int, int] = {}
var showdown: Dictionary = {}
var ranking: Array = []
## Head turn relative to looking at the table centre (radians).
var yaw: float = 0.0
var pitch: float = 0.0
var yaw_limit: float = 1.2
var first_person: bool = false
## 0 = leaning in, 1 = sat back (the showdown).
var sit_back: float = 0.0
var _eye: Vector3 = Vector3.ZERO
var _base_yaw: float = 0.0
var _base_pitch: float = 0.0
var _mouse_seen: bool = false
## Deal animation: seconds since the deal began (< 0: cards sit on the foreheads), the order.
var deal_t: float = -1.0
var deal_order: Array[int] = []
## Showdown animation: seconds since it began (< 0: not running), and each card's flight.
var show_t: float = -1.0
var _flights: Dictionary[int, Dictionary] = {}

# UI
var root: Control
var round_label: Label
var phase_label: Label
var timer_box: HBoxContainer
var timer_bar: ProgressBar
var timer_label: Label
var prompt_label: Label
var sub_label: Label
var action_box: HBoxContainer
var stay_button: Button
var fold_button: Button
var board: VBoxContainer
var board_rows: Dictionary[int, Dictionary] = {}
var overlay: Control
var own_panel: PanelContainer
var own_card: TextureRect
var own_mark: Label
var own_caption: Label
var head_ticks: Dictionary[int, TickMark] = {}
var result_chips: Dictionary[int, PanelContainer] = {}
var pops: Array[Dictionary] = []
var bubble: PanelContainer
var bubble_label: Label
var look_hint: Label

var _clock: float = 0.0
var _last_beep: int = -1
var _action_sent_at: float = -1.0
var _flipped: Dictionary[int, bool] = {}
var _last_mouse_at: float = -10.0
## How intents leave (tests swap it).
var send_intent: Callable = func(i: Dictionary) -> Dictionary: return Net.send_intent(i)


func _build(start: Dictionary) -> void:
	_set_players(start.get("players", []))
	var hold: Variant = start.get("briefing", 0.0)
	held = (hold is Dictionary) or float(hold) > 0.0
	table = CardTableSet.new()
	table.name = "CardTable"
	add_child(table)
	table.build(state, local_id, seating(players_list, local_id), true)
	for p: int in table.seats:
		(table.seats[p]["tag"] as Node3D).position.y = TAG_Y  # name tags clear of the forehead cards
	host = table.host
	camera = table.camera
	camera.near = 0.05
	_light_faces()
	for p: int in players_list:
		totals[p] = 0
	_build_ui()
	_setup_view()
	_ensure_cards()
	if state != null and String(state.minigame.get("minigame", "")) == "forehead_poker":
		apply_state(state.minigame)  # a snapshot already reached us: use it
	else:
		_host_say("Welcome to the back room. Mind your manners... and your forehead.", QuizHost.Pose.HAPPY)
	_refresh()


func _set_players(list: Array) -> void:
	var fresh: Array[int] = []
	for p: Variant in list:
		fresh.append(int(p))
	players_list = fresh


## The seating order for this client: we take the chair nearest the front, facing Lucky across
## the table, so nobody (least of all the dealer) blocks our view. Purely visual.
static func seating(list: Array[int], me: int) -> Array[int]:
	var out: Array[int] = list.duplicate()
	var at: int = out.find(me)
	if at < 0:
		return out
	var best: int = 0
	for i: int in out.size():
		if CardTableSet.seat_position(i, out.size()).z > CardTableSet.seat_position(best, out.size()).z:
			best = i
	out[at] = out[best]
	out[best] = me
	return out


## The lamp's glow spilling sideways onto the faces round the table (the spot only hits the felt).
func _light_faces() -> void:
	var spill := OmniLight3D.new()
	spill.name = "LampSpill"
	spill.position = Vector3(0, CardTableSet.LAMP_HEIGHT - 0.55, 0)
	spill.omni_range = 4.6
	spill.omni_attenuation = 1.3
	spill.light_energy = 1.1
	spill.light_color = CardTableSet.WARM_LIGHT
	table.add_child(spill)
	# The room around it: dark panelled walls and ceiling, only grazed by the lamp.
	var shell := MeshInstance3D.new()
	shell.name = "DarkRoom"
	var cm := CylinderMesh.new()
	cm.top_radius = 6.5
	cm.bottom_radius = 6.5
	cm.height = 5.2
	cm.radial_segments = 20
	cm.rings = 1
	cm.flip_faces = true
	shell.mesh = cm
	shell.position = Vector3(0, 2.5, -0.5)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("#2A1712")
	wm.roughness = 0.9
	shell.material_override = wm
	table.add_child(shell)


# --- Camera ------------------------------------------------------------------------------------

## First person from our chair, looking at the table centre (spectators get the overview).
func _setup_view() -> void:
	first_person = local_id in players_list and table.seats.has(local_id)
	if not first_person:
		return
	var seat: Node3D = table.seats[local_id]["root"]
	(table.seats[local_id]["bean"] as Node3D).visible = false  # we are inside it
	(table.seats[local_id]["tag"] as Node3D).visible = false
	_eye = seat.position + seat.basis * EYE
	var target := Vector3(0, CardTableSet.TABLE_TOP + 0.35, -0.05)
	var d: Vector3 = target - _eye
	_base_yaw = atan2(-d.x, -d.z)
	_base_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	# The yaw reaches every other bean (plus a margin), never round to the wall behind us.
	var widest: float = 0.6
	for p: int in table.seats:
		if p == local_id:
			continue
		var h: Vector3 = (table.seats[p]["root"] as Node3D).position - _eye
		widest = maxf(widest, absf(wrapf(atan2(-h.x, -h.z) - _base_yaw, -PI, PI)))
	yaw_limit = minf(widest + YAW_MARGIN, YAW_MAX)
	_apply_view()


func _apply_view() -> void:
	if not first_person or camera == null:
		return
	yaw = clampf(yaw, -yaw_limit, yaw_limit)
	pitch = clampf(pitch, PITCH_DOWN, PITCH_UP)
	# At the showdown we sit back in the chair to take in the whole row of cards.
	var away: Vector3 = Vector3(_eye.x, 0.0, _eye.z).normalized()
	var eye: Vector3 = _eye + (away * SIT_BACK.x + Vector3(0, SIT_BACK.y, 0)) * sit_back
	camera.transform = Transform3D(Basis.from_euler(Vector3(_base_pitch + pitch, _base_yaw + yaw, 0.0)), eye)


## Turns the head by a look delta (radians, like `PlayerCamera.look`: +x turns right, +y down).
func look(delta_yaw: float, delta_pitch: float) -> void:
	yaw -= delta_yaw
	pitch -= delta_pitch
	_apply_view()


## The head turn that faces player `pid`'s forehead.
func yaw_towards(pid: int) -> float:
	if not cards.has(pid):
		return 0.0
	var h: Vector3 = _forehead_xform(pid).origin - _eye
	return wrapf(atan2(-h.x, -h.z) - _base_yaw, -PI, PI)


# --- Cards -------------------------------------------------------------------------------------

func _ensure_cards() -> void:
	for p: int in players_list:
		if cards.has(p) or not table.seats.has(p):
			continue
		var c := TableCard3D.make(TableCard3D.FACE_DOWN, CARD_SIZE, true)
		c.name = "Card%d" % p
		c.visible = false
		table.add_child(c)
		cards[p] = c
	for p: int in cards.keys():
		if not p in players_list:
			(cards[p] as Node).queue_free()
			cards.erase(p)


## The card's pose on `pid`'s forehead (set space): standing, face out towards the table. From
## our chair the others' cards turn a little our way (at most `TURN_MAX`), so a neighbour's card
## is not edge-on; it stays on their forehead.
func _forehead_xform(pid: int) -> Transform3D:
	var bean: Node3D = table.seats[pid]["bean"]
	var seat: Node3D = table.seats[pid]["root"]
	var head_local: Vector3 = Vector3(0.0, FOREHEAD.y, 0.0)
	var head: Vector3 = seat.position + seat.basis * (bean.transform * head_local)
	var pos: Vector3 = seat.position + seat.basis * (bean.transform * FOREHEAD)
	if bean.is_inside_tree():
		head = table.to_local(bean.to_global(head_local))
		pos = table.to_local(bean.to_global(FOREHEAD))
	var facing: float = seat.rotation.y
	var turn: float = 0.0
	if first_person and pid != local_id:
		var to_me: Vector3 = _eye - head
		turn = clampf(wrapf(atan2(to_me.x, to_me.z) - facing, -PI, PI), -TURN_MAX, TURN_MAX)
	pos = head + (pos - head).rotated(Vector3.UP, turn)
	return Transform3D(Basis(Vector3.UP, facing + turn) * Basis(Vector3.RIGHT, PI * 0.5 + FOREHEAD_TILT), pos)


## Lucky's dealing hand (set space).
func _dealer_point() -> Vector3:
	return Vector3(0.0, CardTableSet.TABLE_TOP + 0.35, CardTableSet.DEALER_Z + 0.45)


## Where `pid`'s card lands at the showdown: propped up in a row in the middle of the felt,
## leaning back and turned to face us (a little smaller with many players, so the row fits).
func _felt_xform(pid: int, order: Array[int]) -> Transform3D:
	var i: int = maxi(order.find(pid), 0)
	var n: int = maxi(order.size(), 1)
	var sc: float = show_scale(n)
	var gap: float = (CARD_SIZE.x + 0.07) * sc
	var me: Vector3 = _eye if first_person else Vector3(0, 0, 4.0)
	var flat := Basis(Vector3.UP, atan2(me.x, me.z))
	var b: Basis = (flat * Basis(Vector3.RIGHT, SHOW_LEAN)).scaled_local(Vector3.ONE * sc)
	var lift: float = CARD_SIZE.y * sc * 0.5 * sin(SHOW_LEAN) + 0.01
	var pos: Vector3 = table.felt_point(Vector2.ZERO, lift) + flat * Vector3((float(i) - float(n - 1) * 0.5) * gap, 0.0, 0.1)
	return Transform3D(b, pos)


static func show_scale(n: int) -> float:
	return clampf(6.0 / float(maxi(n, 1)), 0.75, 1.0)


## Puts the faces we know on the cards (ours stays a back until the showdown names it).
func _apply_faces() -> void:
	for p: int in cards:
		var c: TableCard3D = cards[p]
		var face: int = int(known.get(p, TableCard3D.FACE_DOWN))
		if c.card != face:
			c.set_card(face)
			if face != TableCard3D.FACE_DOWN and phase in ["deal", "talk", "decide"] and is_inside_tree() and not _flipped.has(p):
				_flipped[p] = true
				_pop_card(p)


func _pop_card(pid: int) -> void:
	var c: TableCard3D = cards.get(pid, null)
	if c == null or not c.is_inside_tree():
		return
	c.scale = Vector3.ONE * 0.6
	var t: Tween = c.create_tween()
	t.tween_property(c, ^"scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Every card on its forehead (no animation).
func _seat_cards() -> void:
	for p: int in cards:
		var c: TableCard3D = cards[p]
		c.visible = true
		c.scale = Vector3.ONE
		c.face_up_t = 1.0
		c.set_glow(0.0)
		c.transform = _forehead_xform(p)
	_hide_own()


## Our own card sits right in front of our eyes: it stays out of our first-person view (until
## the showdown flies it to the felt). It is a plain back anyway.
func _hide_own() -> void:
	if first_person and cards.has(local_id):
		(cards[local_id] as Node3D).visible = false


func _hide_cards() -> void:
	for p: int in cards:
		(cards[p] as Node3D).visible = false


## Poses the deal `t` seconds in: card k leaves Lucky's hand at DEAL_FIRST + k * gap, spins
## through the air and sticks to its forehead.
func deal_pose(t: float) -> void:
	var gap: float = _deal_gap()
	for k: int in deal_order.size():
		var p: int = deal_order[k]
		if not cards.has(p):
			continue
		var c: TableCard3D = cards[p]
		var u: float = (t - DEAL_FIRST - gap * float(k)) / DEAL_FLIGHT
		# Ours flies at us and vanishes just before it hits our forehead (right in front of our eyes).
		c.visible = u > 0.0 and not (first_person and p == local_id and u > 0.7)
		if u <= 0.0:
			continue
		var to: Transform3D = _forehead_xform(p)
		if u >= 1.0:
			c.transform = to
			c.face_up_t = 1.0
			continue
		var e: float = smoothstep(0.0, 1.0, u)
		var from := Transform3D(Basis(Vector3.UP, atan2(to.origin.x, to.origin.z)), _dealer_point())
		var pos: Vector3 = from.origin.lerp(to.origin, e) + Vector3(0, sin(u * PI) * 0.45, 0)
		var q: Quaternion = Quaternion(from.basis.orthonormalized()).slerp(Quaternion(to.basis.orthonormalized()), e)
		c.transform = Transform3D(Basis(q).rotated(Vector3.UP, (1.0 - e) * TAU), pos)
		c.face_up_t = e


func _deal_gap() -> float:
	return minf(0.26, 1.6 / float(maxi(deal_order.size(), 1)))


func deal_length() -> float:
	return DEAL_FIRST + _deal_gap() * float(maxi(deal_order.size() - 1, 0)) + DEAL_FLIGHT


## Poses the showdown `t` seconds in: each card lifts, tips over and lands face up on the felt.
func showdown_pose(t: float) -> void:
	for p: int in _flights:
		if not cards.has(p):
			continue
		var f: Dictionary = _flights[p]
		var c: TableCard3D = cards[p]
		c.visible = true
		var u: float = clampf((t - float(f["start"])) / SHOW_FLIGHT, 0.0, 1.0)
		var from: Transform3D = f["from"]
		var to: Transform3D = f["to"]
		var e: float = smoothstep(0.0, 1.0, u)
		var pos: Vector3 = from.origin.lerp(to.origin, e) + Vector3(0, sin(u * PI) * 0.5, 0)
		var q: Quaternion = Quaternion(from.basis.orthonormalized()).slerp(Quaternion(to.basis.orthonormalized()), e)
		c.transform = Transform3D(Basis(q).scaled_local(Vector3.ONE * lerpf(from.basis.get_scale().x, to.basis.get_scale().x, e)), pos)
		c.face_up_t = 1.0


func showdown_length() -> float:
	return SHOW_GAP * float(maxi(_flights.size() - 1, 0)) + SHOW_FLIGHT


# --- UI ----------------------------------------------------------------------------------------

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	# Title plate, top left.
	var plate := PanelContainer.new()
	plate.position = Vector2(28, 22)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override(&"panel", _panel_style(Color(Palette.CASINO_BLACK, 0.82), Palette.WARM_GOLD, 14))
	root.add_child(plate)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override(&"separation", -4)
	plate.add_child(pcol)
	pcol.add_child(_label("FOREHEAD POKER", BLACK_FONT, 46, Palette.VIP_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	round_label = _label("ROUND 1 / 5", BOLD_FONT, 28, Palette.CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	pcol.add_child(round_label)
	phase_label = _label("", BOLD_FONT, 24, Color(Palette.CREAM, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	pcol.add_child(phase_label)

	# Scoreboard, top right (a tick by everyone who decided).
	var board_panel := PanelContainer.new()
	board_panel.anchor_left = 1.0
	board_panel.anchor_right = 1.0
	board_panel.offset_left = -320.0
	board_panel.offset_right = -28.0
	board_panel.offset_top = 22.0
	board_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	board_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_theme_stylebox_override(&"panel", _panel_style(Color(Palette.CASINO_BLACK, 0.82), Palette.WARM_GOLD, 14))
	root.add_child(board_panel)
	board = VBoxContainer.new()
	board.add_theme_constant_override(&"separation", 2)
	board_panel.add_child(board)
	board.add_child(_label("POINTS", BOLD_FONT, 24, Palette.WARM_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	for p: int in players_list:
		_add_board_row(p)

	# Your own card, top centre: a back with a "?" and a warning.
	own_panel = PanelContainer.new()
	own_panel.name = "YourCard"
	own_panel.anchor_left = 0.5
	own_panel.anchor_right = 0.5
	own_panel.offset_top = 18.0
	own_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	own_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var osb: StyleBoxFlat = _panel_style(Color(Palette.CASINO_BLACK, 0.82), Palette.WARM_GOLD, 14)
	osb.content_margin_top = 6
	osb.content_margin_bottom = 8
	own_panel.add_theme_stylebox_override(&"panel", osb)
	root.add_child(own_panel)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override(&"separation", 14)
	orow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	own_panel.add_child(orow)
	own_card = TextureRect.new()
	own_card.texture = TableCard3D.texture(TableCard3D.FACE_DOWN)
	own_card.modulate = TableCard3D.BACK_TINT.lightened(0.15)
	own_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	own_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	own_card.custom_minimum_size = Vector2(62, 88)
	own_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orow.add_child(own_card)
	own_mark = _label("?", BLACK_FONT, 64, Palette.VIP_GOLD)
	_shadow(own_mark, 3)
	own_mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	own_card.add_child(own_mark)
	var ocol := VBoxContainer.new()
	ocol.alignment = BoxContainer.ALIGNMENT_CENTER
	ocol.add_theme_constant_override(&"separation", -6)
	ocol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orow.add_child(ocol)
	ocol.add_child(_label("YOUR CARD", BLACK_FONT, 34, Palette.VIP_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	own_caption = _label("Don't peek!", BOLD_FONT, 26, Palette.CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	ocol.add_child(own_caption)

	# Bottom centre: the prompt, a line under it, the timer, the two choices.
	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -250.0
	bottom.offset_bottom = -24.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override(&"separation", 4)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	prompt_label = _label("", BLACK_FONT, 60, Palette.VIP_GOLD)
	_shadow(prompt_label, 4)
	bottom.add_child(prompt_label)
	sub_label = _label("", BOLD_FONT, 30, Palette.CREAM)
	_shadow(sub_label, 3)
	bottom.add_child(sub_label)
	timer_box = HBoxContainer.new()
	timer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_box.add_theme_constant_override(&"separation", 16)
	timer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(timer_box)
	timer_bar = ProgressBar.new()
	timer_bar.custom_minimum_size = Vector2(520, 20)
	timer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer_bar.show_percentage = false
	timer_bar.max_value = 1.0
	timer_bar.step = 0.0
	timer_bar.value = 1.0
	timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_back: StyleBoxFlat = _panel_style(Color(Palette.CASINO_BLACK, 0.8), Color(Palette.WARM_GOLD, 0.6), 10)
	bar_back.set_content_margin_all(0)
	timer_bar.add_theme_stylebox_override(&"background", bar_back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.WARM_GOLD
	fill.set_corner_radius_all(10)
	timer_bar.add_theme_stylebox_override(&"fill", fill)
	timer_box.add_child(timer_bar)
	timer_label = _label("", BLACK_FONT, 40, Palette.CREAM)
	timer_label.custom_minimum_size = Vector2(50, 0)
	_shadow(timer_label, 3)
	timer_box.add_child(timer_label)
	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override(&"separation", 28)
	action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(action_box)
	stay_button = _action_button("1", "STAY", Palette.MONEY_GREEN.darkened(0.35))
	stay_button.pressed.connect(func() -> void: act(ForeheadPokerLogic.STAY))
	action_box.add_child(stay_button)
	fold_button = _action_button("2", "FOLD", Palette.CASINO_RED.darkened(0.25))
	fold_button.pressed.connect(func() -> void: act(ForeheadPokerLogic.FOLD))
	action_box.add_child(fold_button)

	look_hint = _label("MOUSE  look around", BOLD_FONT, 24, Color(Palette.CREAM, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	_shadow(look_hint, 2)
	look_hint.anchor_top = 1.0
	look_hint.anchor_bottom = 1.0
	look_hint.offset_left = 28.0
	look_hint.offset_top = -52.0
	look_hint.offset_bottom = -22.0
	root.add_child(look_hint)

	# Lucky's lines: a speech card under the top centre (he is often behind us, so it stays put).
	bubble = PanelContainer.new()
	bubble.anchor_left = 0.5
	bubble.anchor_right = 0.5
	bubble.offset_top = 118.0
	bubble.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var bsb: StyleBoxFlat = _panel_style(Palette.CREAM, Palette.WARM_GOLD, 18)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.shadow_color = Color(0, 0, 0, 0.4)
	bsb.shadow_size = 8
	bubble.add_theme_stylebox_override(&"panel", bsb)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.visible = false
	root.add_child(bubble)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override(&"separation", 10)
	brow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(brow)
	brow.add_child(_label("LUCKY:", BLACK_FONT, 26, Palette.VIP_BURGUNDY))
	bubble_label = _label("", BOLD_FONT, 26, Palette.CASINO_BLACK, HORIZONTAL_ALIGNMENT_LEFT)
	brow.add_child(bubble_label)

	for p: int in players_list:
		_add_head_tick(p)


func _action_button(key: String, text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = "%s   %s" % [key, text]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(210, 64)
	b.add_theme_font_override(&"font", BLACK_FONT)
	b.add_theme_font_size_override(&"font_size", 40)
	for st: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_disabled_color"]:
		b.add_theme_color_override(st, Palette.CREAM)
	var normal: StyleBoxFlat = _panel_style(color, Palette.VIP_GOLD, 16)
	normal.set_border_width_all(3)
	b.add_theme_stylebox_override(&"normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = color.lightened(0.15)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	var off: StyleBoxFlat = normal.duplicate()
	off.bg_color = Color(color.darkened(0.5), 0.8)
	off.border_color = Color(Palette.WARM_GOLD, 0.35)
	b.add_theme_stylebox_override(&"disabled", off)
	return b


func _add_board_row(p: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(row)
	var dot := ColorRect.new()
	dot.color = _color(p)
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var nm := _label(("YOU" if p == local_id else _name(p)).left(12), BOLD_FONT, 26, Palette.VIP_GOLD if p == local_id else Palette.CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size = Vector2(110, 0)
	row.add_child(nm)
	var tick := TickMark.new(22.0)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.visible = false
	row.add_child(tick)
	var mark := _label("", BOLD_FONT, 24, Palette.MONEY_GREEN, HORIZONTAL_ALIGNMENT_RIGHT)
	mark.custom_minimum_size = Vector2(54, 0)
	row.add_child(mark)
	var pts := _label("0", BLACK_FONT, 28, Palette.CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
	pts.custom_minimum_size = Vector2(50, 0)
	row.add_child(pts)
	board_rows[p] = {"row": row, "name": nm, "tick": tick, "mark": mark, "points": pts}


func _add_head_tick(p: int) -> void:
	if head_ticks.has(p) or p == local_id:
		return
	var t := TickMark.new(34.0)
	t.name = "Decided%d" % p
	t.visible = false
	overlay.add_child(t)
	head_ticks[p] = t


func _label(text: String, font: Font, size_px: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	return l


func _shadow(l: Label, offset: int) -> void:
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override(&"shadow_offset_y", offset)
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_outline_size", 6)


func _panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb


func _name(p: int) -> String:
	return state.player_name(p) if state != null else "Player %d" % p


func _color(p: int) -> Color:
	var idx: int = p
	if state != null and state.players.has(p):
		idx = int(state.players[p].get("color", p))
	return Palette.player_color(idx)


func _refresh() -> void:
	round_label.text = "ROUND %d / %d" % [round_num + 1, rounds]
	phase_label.text = str({"intro": "Take your seats", "deal": "Lucky deals", "talk": "Talk it over", "decide": "Stay or fold",
		"showdown": "Showdown", "over": "Final scores"}.get(phase, ""))
	var counting: bool = phase in ["talk", "decide"] and not over and not held
	timer_box.modulate.a = 1.0 if counting else 0.0  # keeps its room: the prompt does not jump
	_update_clock()
	var playing: bool = local_id in players_list
	action_box.visible = playing and phase == "decide"
	stay_button.disabled = not can_act()
	fold_button.disabled = not can_act()
	stay_button.modulate.a = 0.45 if my_choice == ForeheadPokerLogic.FOLD else 1.0
	fold_button.modulate.a = 0.45 if my_choice == ForeheadPokerLogic.STAY else 1.0
	var prompt: String = ""
	var sub: String = ""
	match phase:
		"intro":
			prompt = "FOREHEAD POKER"
			sub = "Get ready - the cards come out when everyone is ready." if held else "Everyone sees your card but you."
		"deal":
			prompt = "CARDS UP!"
			sub = "Look around: whose card beats yours?"
		"talk":
			prompt = "TALK IT OVER"
			sub = "Tell them what you see... or don't. Bluffing is allowed."
		"decide":
			if not playing:
				prompt = "STAY OR FOLD?"
				sub = "%d of %d decided." % [decided.size(), players_list.size()]
			elif my_choice != "":
				prompt = "YOU %s" % ("STAY" if my_choice == ForeheadPokerLogic.STAY else "FOLD")
				sub = "Locked in. %d of %d decided." % [decided.size(), players_list.size()]
			else:
				prompt = "STAY OR FOLD?"
				sub = "Highest staying card takes the pot. No answer folds."
		"showdown":
			var g: int = int(gains.get(local_id, 0))
			var winners: Array = showdown.get("winners", [])
			if not playing:
				prompt = "SHOWDOWN"
			elif local_id in winners:
				prompt = "YOU TAKE THE POT!  +%d" % g if winners.size() == 1 else "SPLIT POT!  +%d" % g
			elif g < 0:
				prompt = "BEATEN!  -1"
			else:
				prompt = "YOU FOLDED"
			if winners.is_empty():
				sub = "Everybody folded. Nobody scores."
			else:
				sub = "%s had the high card." % _names_of(winners)
		"over":
			var top: Array[int] = _winners()
			if local_id in top:
				prompt = "YOU WIN!" if top.size() == 1 else "SHARED WIN!"
			elif not top.is_empty():
				prompt = "%s WINS!" % _names_of(top).to_upper()
			else:
				prompt = "GAME OVER"
			sub = "Most points after %d rounds." % rounds
	prompt_label.text = prompt
	prompt_label.add_theme_color_override(&"font_color", Palette.LOSS_RED if prompt.begins_with("BEATEN") else Palette.VIP_GOLD)
	sub_label.text = sub
	_refresh_own_card()
	_refresh_board()


func _refresh_own_card() -> void:
	own_panel.visible = local_id in players_list and phase != "over"
	var mine: int = int(known.get(local_id, TableCard3D.FACE_DOWN))
	if phase == "showdown" and mine != TableCard3D.FACE_DOWN:
		own_card.texture = TableCard3D.texture(mine)
		own_card.modulate = Color.WHITE
		own_mark.text = ""
		own_caption.text = "There it was."
	else:
		own_card.texture = TableCard3D.texture(TableCard3D.FACE_DOWN)
		own_card.modulate = TableCard3D.BACK_TINT.lightened(0.15)
		own_mark.text = "?"
		own_caption.text = "Don't peek!"


func _refresh_board() -> void:
	var order: Array[int] = players_list.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(totals.get(a, 0)) != int(totals.get(b, 0)):
			return int(totals.get(a, 0)) > int(totals.get(b, 0))
		return a < b)
	var place: Dictionary = {}
	for row: Variant in ranking:
		place[int((row as Dictionary).get("player", -1))] = int((row as Dictionary).get("rank", 0))
	var choices: Dictionary = showdown.get("choices", {})
	for i: int in order.size():
		var p: int = order[i]
		if not board_rows.has(p):
			_add_board_row(p)
		var r: Dictionary = board_rows[p]
		board.move_child(r["row"] as Control, i + 1)
		(r["points"] as Label).text = str(int(totals.get(p, 0)))
		(r["tick"] as Control).visible = phase == "decide" and decided.has(p)
		var mark: Label = r["mark"]
		mark.text = ""
		if over and place.has(p):
			mark.text = "#%d" % place[p]
			mark.add_theme_color_override(&"font_color", Palette.VIP_GOLD if place[p] == 1 else Palette.CREAM)
		elif phase == "showdown" and gains.has(p):
			var g: int = int(gains[p])
			if String(choices.get(p, choices.get(str(p), ForeheadPokerLogic.FOLD))) == ForeheadPokerLogic.FOLD:
				mark.text = "fold"
				mark.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.6))
			else:
				mark.text = "%+d" % g
				mark.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if g > 0 else Palette.LOSS_RED)
	for p: int in players_list:
		_add_head_tick(p)


func _update_clock() -> void:
	if timer_box.modulate.a <= 0.0:
		return
	var frac: float = clampf(time_left / maxf(time_span, 0.01), 0.0, 1.0)
	timer_bar.value = frac
	var fill: StyleBoxFlat = timer_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	fill.bg_color = Palette.CASINO_RED if phase == "decide" and time_left <= 3.0 else Palette.WARM_GOLD
	timer_label.text = "%d" % ceili(time_left)


func _names_of(list: Array) -> String:
	var out: PackedStringArray = []
	for p: Variant in list:
		out.append("You" if int(p) == local_id else _name(int(p)))
	return " & ".join(out)


func _winners() -> Array[int]:
	var out: Array[int] = []
	for row: Variant in ranking:
		if int((row as Dictionary).get("rank", 0)) == 1:
			out.append(int((row as Dictionary).get("player", -1)))
	return out


## The dealer speaks (speech bubble) and strikes a pose.
func _host_say(text: String, pose: QuizHost.Pose = QuizHost.Pose.IDLE, hold: float = 2.2) -> void:
	if host == null:
		return
	host.say(text)
	host.set_pose(pose, hold)
	bubble_label.text = text
	bubble.visible = text != ""


func _on_screen(world: Vector3) -> bool:
	return camera != null and camera.is_inside_tree() and not camera.is_position_behind(world)


## Where a point of the set lands on the (sharp) UI canvas.
func _to_ui(world: Vector3) -> Vector2:
	return PixelView.to_canvas(camera, camera.unproject_position(world), overlay)


func _place_overlays() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	# Ticks by the cards of the beans who decided (upper corner, clear of the name tags).
	for p: int in head_ticks:
		var t: TickMark = head_ticks[p]
		var show: bool = phase == "decide" and decided.has(p) and table.seats.has(p)
		if show:
			var w: Vector3 = table.to_global(_forehead_xform(p) * Vector3(CARD_SIZE.x * 0.5 + 0.1, 0.0, -CARD_SIZE.y * 0.32))
			show = _on_screen(w)
			if show:
				t.position = _to_ui(w) - t.size * 0.5
		t.visible = show
	# Result chips under the cards on the felt.
	for p: int in result_chips:
		var chip: PanelContainer = result_chips[p]
		if not cards.has(p):
			chip.visible = false
			continue
		var c: TableCard3D = cards[p]
		var below: Vector3 = c.global_transform * Vector3(0, 0, CARD_SIZE.y * 0.5 + 0.05)
		chip.visible = _on_screen(below) and phase == "showdown"
		if chip.visible:
			chip.reset_size()
			chip.position = _to_ui(below) - Vector2(chip.size.x * 0.5, 0.0)
	# +N / -1 / 0 rising over the beans.
	for i: int in range(pops.size() - 1, -1, -1):
		var e: Dictionary = pops[i]
		var lbl: Label = e["label"]
		var age: float = _clock - float(e["at"])
		if age > 2.6:
			lbl.queue_free()
			pops.remove_at(i)
			continue
		var pid: int = int(e["player"])
		var w: Vector3 = table.head_point(pid) + Vector3(0, 0.15 + age * 0.12, 0)
		lbl.visible = age >= 0.0 and _on_screen(w)
		if lbl.visible:
			lbl.reset_size()
			lbl.position = _to_ui(w) - lbl.size * 0.5
			lbl.modulate.a = clampf(2.6 - age, 0.0, 1.0)
			lbl.scale = Vector2.ONE * (1.0 + 0.25 * maxf(0.0, 0.25 - age) / 0.25)


func _clear_results() -> void:
	for p: int in result_chips:
		(result_chips[p] as Node).queue_free()
	result_chips.clear()
	for e: Dictionary in pops:
		(e["label"] as Node).queue_free()
	pops.clear()


# --- Input -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if deal_t >= 0.0:
		deal_t += delta
		deal_pose(deal_t)
		if deal_t > deal_length():
			deal_t = -1.0
			_seat_cards()
	elif show_t >= 0.0:
		show_t += delta
		showdown_pose(minf(show_t, showdown_length()))
	elif phase in ["deal", "talk", "decide"]:
		for p: int in cards:
			(cards[p] as Node3D).transform = _forehead_xform(p)  # ride along with the bean's bobbing
		_hide_own()
	if not held and time_left > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		_update_clock()
		if phase == "decide":
			var sec: int = ceili(time_left)
			if sec <= 3 and sec > 0 and sec != _last_beep:
				_last_beep = sec
				Audio.play(&"countdown_beep", &"UI", -12.0, 1.2)
	_steer(delta)
	_place_overlays()


## Right stick and the cursor parked at a screen edge keep turning the head.
func _steer(delta: float) -> void:
	if not first_person:
		return
	var turn: float = Input.get_axis(&"look_left", &"look_right") if InputMap.has_action(&"look_left") else 0.0
	if absf(turn) < 0.2:
		turn = 0.0
	if _mouse_seen and DisplayServer.get_name() != "headless" and get_window().has_focus():
		var w: float = get_viewport().get_visible_rect().size.x
		var x: float = get_viewport().get_mouse_position().x
		if w > 0.0 and x <= w * EDGE_ZONE:
			turn -= EDGE_SPEED / STICK_SPEED
		elif w > 0.0 and x >= w * (1.0 - EDGE_ZONE):
			turn += EDGE_SPEED / STICK_SPEED
	sit_back = move_toward(sit_back, 1.0 if phase in ["showdown", "over"] else 0.0, delta * 1.5)
	if show_t >= 0.0 and turn == 0.0 and not _mouse_moved_recently():
		yaw = lerpf(yaw, 0.0, clampf(delta * 3.0, 0.0, 1.0))  # the showdown pulls your eyes to the felt
		pitch = lerpf(pitch, 0.12, clampf(delta * 3.0, 0.0, 1.0))
	if turn != 0.0:
		look(turn * STICK_SPEED * delta, 0.0)
	else:
		_apply_view()



func _mouse_moved_recently() -> bool:
	return _clock - _last_mouse_at < 1.2


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_mouse_seen = true
		if first_person and motion.relative != Vector2.ZERO:
			_last_mouse_at = _clock
			var rel: Vector2 = motion.relative * _sensitivity()
			if bool(_setting("invert_y", false)):
				rel.y = -rel.y
			look(rel.x, rel.y)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not can_act():
		return
	if key.keycode == KEY_1 or key.keycode == KEY_KP_1:
		act(ForeheadPokerLogic.STAY)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_2 or key.keycode == KEY_KP_2:
		act(ForeheadPokerLogic.FOLD)
		get_viewport().set_input_as_handled()


func _sensitivity() -> float:
	var s: Node = get_node_or_null(^"/root/Settings")
	return float(s.call(&"mouse_look")) if s != null else 0.0025


func _setting(key: String, fallback: Variant) -> Variant:
	var s: Node = get_node_or_null(^"/root/Settings")
	return s.call(&"get_value", "controls", key, fallback) if s != null else fallback


## True while the local player may still answer this round.
func can_act() -> bool:
	return phase == "decide" and not held and not over and my_choice == "" and local_id in players_list and time_left > 0.0


## STAY or FOLD (sends the intent; the server decides).
func act(action: String) -> void:
	if not can_act() or not action in [ForeheadPokerLogic.STAY, ForeheadPokerLogic.FOLD]:
		return
	my_choice = action
	_action_sent_at = _clock
	var res: Dictionary = send_intent.call(Intents.make(&"forehead_poker_action", {"action": action, "round": round_num}))
	if not bool(res.get("ok", false)) and not bool(res.get("pending", false)):
		my_choice = ""  # refused (too late…)
		_action_sent_at = -1.0
	else:
		Audio.play(&"chip_clack", &"UI", -4.0)
	_refresh()


## The local private snapshot: the others' cards (never ours) and our own answer.
func on_private(priv: Dictionary) -> void:
	var mg: Dictionary = priv.get("minigame", priv)
	if int(mg.get("round", round_num)) != round_num:
		return
	var changed: bool = false
	if phase in ["deal", "talk", "decide"]:
		var seen: Dictionary = mg.get("cards", {})
		for k: Variant in seen:
			var p: int = int(k)
			if p == local_id:
				continue  # never put our own card on display, whatever arrives
			if int(known.get(p, -1)) != int(seen[k]):
				known[p] = int(seen[k])
				changed = true
		if changed:
			_apply_faces()
	var choice: String = String(mg.get("choice", ""))
	if choice != "" and choice != my_choice:
		my_choice = choice  # the server has our answer (also after a resync)
		changed = true
	elif choice == "" and my_choice != "" and bool(mg.get("can_act", false)) and _action_sent_at >= 0.0 and _clock - _action_sent_at > ACTION_CONFIRM_TIMEOUT:
		my_choice = ""  # the server never took it: answer again
		_action_sent_at = -1.0
		changed = true
	if changed:
		_refresh()


# --- Server data -------------------------------------------------------------------------------

## Late join: the round, the phase and its clock, the cards where they are by now.
func apply_state(st: Dictionary) -> void:
	if st.has("players"):
		_set_players(st["players"])
		for p: int in players_list:
			if not board_rows.has(p):
				_add_board_row(p)
		_ensure_cards()
	for k: Variant in (st.get("totals", {}) as Dictionary):
		totals[int(k)] = int(st["totals"][k])
	rounds = int(st.get("rounds", rounds))
	var r: int = int(st.get("round", 0))
	if r != round_num:
		known.clear()
	round_num = r
	phase = String(st.get("phase", "intro"))
	time_left = float(st.get("timer", 0.0))
	time_span = maxf(float(st.get("phase_time", time_left)), 0.01)
	if st.has("briefing"):
		held = true
	decided.clear()
	for p: Variant in st.get("decided", []):
		decided[int(p)] = true
	deal_t = -1.0
	show_t = -1.0
	match phase:
		"intro":
			_hide_cards()
		"deal", "talk", "decide":
			_seat_cards()
			_apply_faces()
		"showdown", "over":
			var sd: Dictionary = st.get("showdown", {})
			if not sd.is_empty():
				_show_showdown(sd, false)
			else:
				_hide_cards()
			if phase == "over":
				over = true
				ranking = st.get("ranking", [])
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"minigame_go":
			held = false
			_refresh()
		&"forehead_poker_started":
			_set_players(ev.get("players", players_list))
			rounds = int(ev.get("rounds", rounds))
			for p: int in players_list:
				if not totals.has(p):
					totals[p] = 0
			_ensure_cards()
			_refresh()
		&"forehead_poker_deal":
			held = false
			round_num = int(ev.get("round", 0))
			phase = "deal"
			my_choice = ""
			_action_sent_at = -1.0
			decided.clear()
			gains.clear()
			showdown = {}
			known.clear()
			_flipped.clear()
			_flights.clear()
			_clear_results()
			show_t = -1.0
			table.calm_all()
			_ensure_cards()
			time_left = float(ev.get("seconds", ForeheadPokerLogic.DEAL_TIME))
			time_span = time_left
			deal_order.clear()
			for p: Variant in ev.get("order", players_list):
				deal_order.append(int(p))
			for p: int in cards:
				var c: TableCard3D = cards[p]
				c.set_card(TableCard3D.FACE_DOWN)
				c.set_glow(0.0)
				c.scale = Vector3.ONE
				c.visible = false
			deal_t = 0.0
			deal_pose(0.0)
			Audio.play(&"card_deal", &"UI", -8.0)
			if round_num == 0:
				_host_say("One card each, right on the forehead. No peeking!", QuizHost.Pose.HAPPY)
			elif round_num == rounds - 1:
				_host_say("Last hand. Make it count!", QuizHost.Pose.HAPPY)
			else:
				_host_say(["Fresh deck, fresh foreheads.", "New hand. Read the room...", "Cards up, chins up."][round_num % 3], QuizHost.Pose.IDLE)
			_refresh()
		&"forehead_poker_talk":
			if deal_t >= 0.0:
				deal_t = -1.0
				_seat_cards()
			phase = "talk"
			time_left = float(ev.get("seconds", ForeheadPokerLogic.TALK_TIME))
			time_span = time_left
			_host_say("Go on, talk. Lying is part of the game.", QuizHost.Pose.DRUMROLL, 0.0)
			_refresh()
		&"forehead_poker_decide":
			phase = "decide"
			time_left = float(ev.get("seconds", ForeheadPokerLogic.DECIDE_TIME))
			time_span = time_left
			_last_beep = -1
			_host_say("Time's up. Stay or fold?", QuizHost.Pose.SURPRISED)
			Audio.play(&"chime", &"UI", -10.0, 1.1)
			_refresh()
		&"forehead_poker_decided":
			var who: int = int(ev.get("player", -1))
			decided[who] = true
			if who != local_id:
				table.hop(who, 0.12)
				Audio.play(&"chip_clack", &"UI", -16.0, 1.2)
			_refresh()
		&"forehead_poker_showdown":
			phase = "showdown"
			time_left = ForeheadPokerLogic.SHOWDOWN_TIME
			_show_showdown(ev, true)
			_refresh()
		&"forehead_poker_over":
			phase = "over"
			over = true
			ranking = ev.get("ranking", [])
			for k: Variant in (ev.get("totals", {}) as Dictionary):
				totals[int(k)] = int(ev["totals"][k])
			var top: Array[int] = _winners()
			table.calm_all()
			for p: int in top:
				table.set_mood(p, BeanPuppet.Mood.CHEER)
			if not top.is_empty():
				_host_say("Best poker face in the house: %s!" % _names_of(top), QuizHost.Pose.HAPPY, 0.0)
			if local_id in top:
				Audio.play(&"big_win", &"UI", -4.0)
			_refresh()


## The showdown: every card lifts off its forehead and lands face up in a row on the felt (ours
## too, now that the server named it), the winning card glows, the points pop over the beans.
func _show_showdown(sd: Dictionary, animate: bool) -> void:
	deal_t = -1.0
	showdown = sd.duplicate(true)
	var hand: Dictionary = {}
	for k: Variant in (sd.get("cards", {}) as Dictionary):
		hand[int(k)] = int(sd["cards"][k])
	for p: Variant in hand:
		known[int(p)] = int(hand[p])
	var choices: Dictionary = {}
	for k: Variant in (sd.get("choices", {}) as Dictionary):
		choices[int(k)] = String(sd["choices"][k])
	showdown["choices"] = choices
	gains.clear()
	for k: Variant in (sd.get("points", {}) as Dictionary):
		gains[int(k)] = int(sd["points"][k])
	for k: Variant in (sd.get("totals", {}) as Dictionary):
		totals[int(k)] = int(sd["totals"][k])
	var winners: Array[int] = []
	for p: Variant in sd.get("winners", []):
		winners.append(int(p))
	showdown["winners"] = winners
	_ensure_cards()
	var order: Array[int] = []
	for p: int in players_list:
		if hand.has(p) and cards.has(p):
			order.append(p)
	_flights.clear()
	_clear_results()
	for i: int in order.size():
		var p: int = order[i]
		var c: TableCard3D = cards[p]
		c.set_card(int(hand[p]))
		c.set_glow(0.0)
		c.scale = Vector3.ONE
		_flights[p] = {"from": _forehead_xform(p), "to": _felt_xform(p, order), "start": SHOW_GAP * float(i)}
		var chip: PanelContainer = _make_result_chip(p, String(choices.get(p, ForeheadPokerLogic.FOLD)), int(gains.get(p, 0)), p in winners)
		overlay.add_child(chip)
		result_chips[p] = chip
	show_t = 0.0 if animate and is_inside_tree() else showdown_length()
	showdown_pose(show_t)
	var land: float = showdown_length()
	for p: int in winners:
		if cards.has(p):
			if animate and is_inside_tree():
				var t: Tween = create_tween()
				t.tween_interval(land + 0.2)
				t.tween_callback((cards[p] as TableCard3D).set_glow.bind(1.0))
			else:
				(cards[p] as TableCard3D).set_glow(1.0)
	for p: int in players_list:
		if not gains.has(p):
			continue
		var g: int = int(gains[p])
		var mood: BeanPuppet.Mood = BeanPuppet.Mood.CHEER if g > 0 else (BeanPuppet.Mood.SAD if g < 0 else BeanPuppet.Mood.IDLE)
		table.set_mood(p, mood)
		if animate and g > 0:
			table.hop(p, 0.25)
		table.set_chips(p, 25 + maxi(int(totals.get(p, 0)), 0) * 10)
		if animate:
			_add_pop(p, g, String(choices.get(p, ForeheadPokerLogic.FOLD)), land + 0.35)
	if not animate:
		return
	Audio.play(&"whoosh", &"UI", -12.0)
	var flip_sound: Tween = create_tween()
	flip_sound.tween_interval(land)
	flip_sound.tween_callback(func() -> void: Audio.play(&"card_flip", &"UI", -6.0))
	if winners.is_empty():
		_host_say("Everybody folded? The house is unimpressed.", QuizHost.Pose.DISAPPOINTED)
	elif winners.size() > 1:
		_host_say("A tie at the top! Split the pot.", QuizHost.Pose.SURPRISED)
	else:
		_host_say("%s takes the pot!" % _names_of(winners), QuizHost.Pose.HAPPY)
	if int(gains.get(local_id, 0)) > 0:
		Audio.play(&"minor_win", &"UI", -6.0)
	elif int(gains.get(local_id, 0)) < 0:
		Audio.play(&"loss_sting", &"UI", -10.0)


func _make_result_chip(p: int, choice: String, gain: int, won: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Result%d" % p
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var folded: bool = choice != ForeheadPokerLogic.STAY
	var sb: StyleBoxFlat = _panel_style(Color(_color(p), 0.55 if folded else 1.0), Palette.VIP_GOLD if won else Color(Palette.CASINO_BLACK, 0.6), 12)
	sb.set_border_width_all(3 if won else 2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override(&"panel", sb)
	var text_col: Color = Palette.CASINO_BLACK if _color(p).get_luminance() > 0.5 and not folded else Palette.CREAM
	var who: String = ("YOU" if p == local_id else _name(p)).left(9)
	var l := _label("%s  %s" % [who, "FOLD" if folded else ("%+d" % gain)], BOLD_FONT, 22, text_col)
	chip.add_child(l)
	chip.visible = false
	return chip


func _add_pop(p: int, gain: int, choice: String, delay: float) -> void:
	var text: String = "%+d" % gain if gain != 0 else "0"
	var col: Color = Palette.MONEY_GREEN if gain > 0 else (Palette.LOSS_RED if gain < 0 else Palette.CREAM)
	if choice != ForeheadPokerLogic.STAY:
		col = Color(Palette.CREAM, 0.8)
	var lbl := _label(text, BLACK_FONT, 54 if gain != 0 else 42, col)
	_shadow(lbl, 4)
	lbl.visible = false
	overlay.add_child(lbl)
	pops.append({"label": lbl, "player": p, "at": _clock + delay})
