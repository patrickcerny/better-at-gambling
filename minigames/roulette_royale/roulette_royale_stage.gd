class_name RouletteRoyaleStage
extends MinigameStage
## Client presentation for Roulette Royale: the casino's roulette wheel (Patrick's model with
## `RouletteWheelFx`, the same 3.4 s spin as the table) on a small felt stage, three big colour
## buttons, and a hearts board. Keys 1-3, mouse, or gamepad B / X / A.
##
## Screen layout (1920×1080 base): status card top centre (spin count, what to do, timer bar); the
## wheel fills the middle; RED / BLACK / GREEN at the bottom; hearts board on the right. Results
## wait for the ball to drop into its pocket before hearts change (presentation only: the server
## already decided).

const COLOR_ORDER: Array[StringName] = [&"red", &"black", &"green"]
const COLOR_NAMES: Array[String] = ["RED", "BLACK", "GREEN"]
const COLOR_ODDS: Array[String] = ["18 in 37", "18 in 37", "1 in 37 · +1 heart"]
const PAD_BUTTONS: Array[JoyButton] = [JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_A]
const PAD_NAMES: Array[String] = ["B", "X", "A"]
const WHEEL_SCALE: float = 0.55
const TABLE_TOP: float = 0.9

var players: Array[int] = []
var hearts: Dictionary = {}
var alive: Array[int] = []
var spin: int = -1
var max_spins: int = RouletteRoyaleLogic.MAX_SPINS
var pick_time: float = RouletteRoyaleLogic.PICK_TIME
var spin_time: float = 3.4
## Our pick this spin (-1 = none yet).
var my_pick: int = -1
var picking: bool = false
var time_left: float = 0.0
var finished: bool = false
## Players who locked in this spin, and what everyone picked on the last result.
var picked: Dictionary = {}
var shown_picks: Dictionary = {}
var shown_deltas: Dictionary = {}
## player → final place, once known (eliminated beans show "OUT").
var places: Dictionary = {}
## A result waiting for the ball to land ({} = none).
var pending_result: Dictionary = {}
var _pending_left: float = 0.0
var _last_tick: int = -1

var wheel_fx: RouletteWheelFx
var root: Control
var card: PanelContainer
var header: Label
var status_label: Label
var timer_bar: ProgressBar
var banner: Label
var sub_banner: Label
var buttons: Array[Button] = []
var button_row: HBoxContainer
var board: VBoxContainer


func _build(start: Dictionary) -> void:
	for p: Variant in start.get("players", []):
		players.append(int(p))
		hearts[int(p)] = RouletteRoyaleLogic.INITIAL_HEARTS
	alive = players.duplicate()
	if Registry.balance != null:
		spin_time = Registry.balance.roulette_spin_time
	_build_set()
	_build_ui()
	_show_banner("ROULETTE ROYALE", "3 hearts each · wrong colour costs one · green call wins one back")
	_set_status("Get ready…", Palette.CREAM)
	_set_buttons_enabled(false)
	_refresh_board()


func _process(delta: float) -> void:
	if picking:
		time_left = maxf(time_left - delta, 0.0)
		timer_bar.value = time_left / maxf(pick_time, 0.01) * 100.0
		var t: int = ceili(time_left)
		if t <= 2 and t > 0 and t != _last_tick and my_pick < 0 and _is_alive(local_id):
			_last_tick = t
			Audio.play(&"countdown_beep", &"UI", -10.0, 1.2)
	if not pending_result.is_empty():
		_pending_left -= delta
		if _pending_left <= 0.0:
			_flush_result()


# --- Events ------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	var type: StringName = StringName(ev.get("type", &""))
	if not String(type).begins_with("roulette_royale_"):
		return
	if type != &"roulette_royale_result":
		_flush_result()  # anything newer shows a pending result first
	match type:
		&"roulette_royale_started":
			_set_players(ev.get("players", []))
			hearts = _int_table(ev.get("hearts", {}))
			max_spins = int(ev.get("max_spins", max_spins))
			pick_time = float(ev.get("pick_time", pick_time))
			spin_time = float(ev.get("spin_time", spin_time))
			_refresh_board()
		&"roulette_royale_pick_open":
			_open_picks(int(ev.get("spin", spin + 1)), float(ev.get("seconds", pick_time)), _int_list(ev.get("alive", alive)), _int_table(ev.get("hearts", hearts)))
		&"roulette_royale_picked":
			if int(ev.get("spin", -1)) == spin:
				picked[int(ev.get("player", -1))] = true
				_refresh_board()
		&"roulette_royale_spin":
			_start_spin(float(ev.get("seconds", spin_time)))
		&"roulette_royale_result":
			_begin_result(ev)
		&"roulette_royale_finished":
			_finish(ev.get("ranking", []))


func on_private(priv: Dictionary) -> void:
	var mine: Dictionary = priv.get("minigame", {})
	if picking and my_pick < 0 and mine.has("pick") and int(mine.get("spin", -2)) == spin:
		_lock(int(mine["pick"]))


func apply_state(st: Dictionary) -> void:
	if st.has("players"):
		_set_players(st["players"])
	hearts = _int_table(st.get("hearts", hearts))
	alive = _int_list(st.get("alive", alive))
	max_spins = int(st.get("max_spins", max_spins))
	spin_time = float(st.get("spin_time", spin_time))
	spin = int(st.get("spin", spin))
	picked.clear()
	for p: Variant in st.get("picked", []):
		picked[int(p)] = true
	if st.has("last_result"):
		var r: Dictionary = st["last_result"]
		shown_picks = r.get("picks", {})
		shown_deltas = _int_table(r.get("deltas", {}))
		for p: Variant in r.get("eliminated", []):
			places[int(p)] = 0
	var s: int = int(st.get("state", RouletteRoyaleLogic.State.INTRO))
	var timer: float = float(st.get("timer", 0.0))
	match s:
		RouletteRoyaleLogic.State.PICK:
			var who: Array[int] = alive.duplicate()
			var seen: Dictionary = picked.duplicate()
			_open_picks(spin, timer, who, hearts)
			picked = seen
		RouletteRoyaleLogic.State.SPIN:
			_hide_banner()
			_set_header()
			_start_spin(timer)
		RouletteRoyaleLogic.State.RESULT:
			_hide_banner()
			_set_header()
			if st.has("last_result"):
				_show_result(st["last_result"], false)
	if st.has("ranking"):
		_finish(st["ranking"])
	_refresh_board()


func _unhandled_input(event: InputEvent) -> void:
	if not picking or my_pick >= 0:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).keycode
		for i: int in COLOR_ORDER.size():
			if k == KEY_1 + i or k == KEY_KP_1 + i:
				_pick(i)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var i: int = PAD_BUTTONS.find((event as InputEventJoypadButton).button_index)
		if i >= 0:
			_pick(i)
			get_viewport().set_input_as_handled()


# --- Flow --------------------------------------------------------------------------------------

func _open_picks(p_spin: int, seconds: float, p_alive: Array[int], p_hearts: Dictionary) -> void:
	spin = p_spin
	alive = p_alive
	hearts = p_hearts
	picked.clear()
	shown_picks = {}
	shown_deltas = {}
	my_pick = -1
	_last_tick = -1
	time_left = seconds
	_hide_banner()
	_set_header()
	timer_bar.visible = true
	timer_bar.value = 100.0
	for b: Button in buttons:
		b.modulate = Color.WHITE
	if _is_alive(local_id):
		picking = true
		_set_buttons_enabled(true)
		_set_status("PICK A COLOUR!", Palette.VIP_GOLD)
		Audio.play(&"chime", &"UI", -8.0)
	else:
		picking = true  # keep the timer running for spectators
		_set_buttons_enabled(false)
		_set_status("You're out: watch who survives", Palette.CREAM.darkened(0.2))
	_refresh_board()


func _pick(i: int) -> void:
	if not picking or my_pick >= 0 or not _is_alive(local_id) or i < 0 or i >= COLOR_ORDER.size():
		return
	_lock(i)
	Audio.play(&"ui_click", &"UI", -4.0)
	Net.send_intent(Intents.make(&"submit_answer", {"question": spin, "index": i}))


func _lock(i: int) -> void:
	my_pick = i
	picked[local_id] = true
	for j: int in buttons.size():
		buttons[j].modulate = Color.WHITE if j == i else Color(1, 1, 1, 0.4)
	_set_buttons_enabled(false)
	_style_color_button(buttons[i], i, true)
	_set_status("Locked in: %s" % COLOR_NAMES[i], _ui_color(i))
	_refresh_board()


func _start_spin(seconds: float) -> void:
	picking = false
	timer_bar.visible = false
	_set_buttons_enabled(false)
	_set_status("No more bets!", Palette.CREAM)
	if wheel_fx != null:
		wheel_fx.start_spin(seconds)
	Audio.play(&"roulette_spin", &"SFX", -6.0)


## The server's result: the ball drops first, then hearts change.
func _begin_result(ev: Dictionary) -> void:
	picking = false
	pending_result = ev
	_pending_left = wheel_fx.land(int(ev.get("number", 0))) if wheel_fx != null else 0.0
	if _pending_left <= 0.0:
		_flush_result()


func _flush_result() -> void:
	if pending_result.is_empty():
		return
	var ev: Dictionary = pending_result
	pending_result = {}
	_show_result(ev, true)


func _show_result(ev: Dictionary, live: bool) -> void:
	picking = false
	timer_bar.visible = false
	_set_buttons_enabled(false)
	var number: int = int(ev.get("number", 0))
	var landed: StringName = StringName(ev.get("color", RouletteLogic.color_of(number)))
	var li: int = COLOR_ORDER.find(landed)
	hearts = _int_table(ev.get("hearts", hearts))
	alive = _int_list(ev.get("alive", alive))
	shown_picks = ev.get("picks", {})
	shown_deltas = _int_table(ev.get("deltas", {}))
	for p: Variant in ev.get("eliminated", []):
		places[int(p)] = 0
	header.text = "%d %s" % [number, COLOR_NAMES[maxi(li, 0)]]
	header.add_theme_color_override(&"font_color", _ui_color(li))
	for j: int in buttons.size():
		buttons[j].modulate = Color.WHITE if j == li else Color(1, 1, 1, 0.35)
	var d: int = int(shown_deltas.get(local_id, 0))
	var mine: Variant = _pick_of(local_id)
	if not shown_deltas.has(local_id):
		_set_status("%s!" % COLOR_NAMES[maxi(li, 0)], _ui_color(li))
	elif local_id in _int_list(ev.get("eliminated", [])):
		_set_status("OUT OF HEARTS!", Palette.LOSS_RED)
		if live:
			Audio.play(&"loss_sting", &"SFX", -6.0)
	elif d > 0:
		_set_status("GREEN CALLED! +1 HEART", Palette.MONEY_GREEN)
		if live:
			Audio.play(&"big_win", &"SFX", -6.0)
	elif d < 0:
		_set_status("No pick! -1 heart" if mine == null else "Wrong colour! -1 heart", Palette.LOSS_RED)
		if live:
			Audio.play(&"buzzer", &"SFX", -10.0)
	else:
		_set_status("Safe! Hearts kept", Palette.MONEY_GREEN)
		if live:
			Audio.play(&"chip_clack", &"SFX", -6.0)
	_refresh_board()


func _finish(ranking: Array) -> void:
	finished = true
	picking = false
	pending_result = {}
	timer_bar.visible = false
	_set_buttons_enabled(false)
	button_row.visible = false
	var winners: Array[String] = []
	var my_rank: int = 0
	for row: Variant in ranking:
		var r: Dictionary = row
		var pid: int = int(r.get("player", -1))
		places[pid] = int(r.get("rank", 0))
		if int(r.get("rank", 0)) == 1:
			winners.append(_name(pid))
		if pid == local_id:
			my_rank = int(r.get("rank", 0))
	card.visible = false
	if winners.size() == 1:
		_show_banner("%s WINS!" % winners[0].to_upper(), "Last bean with hearts")
	elif winners.size() > 1:
		_show_banner("SHARED WIN!", " & ".join(winners))
	else:
		_show_banner("ROYALE OVER", "")
	if my_rank == 1:
		Audio.play(&"big_win", &"SFX", -4.0)
	_refresh_board()


# --- Presentation helpers ----------------------------------------------------------------------

func _set_players(list: Variant) -> void:
	var ids: Array[int] = _int_list(list)
	if ids.is_empty():
		return
	for p: int in ids:
		if not p in players:
			players.append(p)
			hearts[p] = hearts.get(p, RouletteRoyaleLogic.INITIAL_HEARTS)


func _set_header() -> void:
	card.visible = true
	header.text = "SPIN %d / %d" % [spin + 1, max_spins] if spin + 1 < max_spins else "FINAL SPIN"
	header.add_theme_color_override(&"font_color", Palette.WARM_GOLD)


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override(&"font_color", color)


func _set_buttons_enabled(on: bool) -> void:
	for b: Button in buttons:
		b.disabled = not on


func _show_banner(title: String, sub: String) -> void:
	banner.text = title
	sub_banner.text = sub
	banner.visible = true
	sub_banner.visible = sub != ""


func _hide_banner() -> void:
	banner.visible = false
	sub_banner.visible = false


func _is_alive(pid: int) -> bool:
	return pid in alive


## What `pid` picked on the last result (null = no pick).
func _pick_of(pid: int) -> Variant:
	for k: Variant in shown_picks:
		if int(k) == pid:
			var c: StringName = StringName(shown_picks[k])
			return null if c == &"" else c
	return null


func _name(pid: int) -> String:
	return state.player_name(pid) if state != null else "Player %d" % pid


func _player_color(pid: int) -> Color:
	var info: Dictionary = state.players.get(pid, {}) if state != null else {}
	return Palette.player_color(int(info.get("color", pid - 1)))


## Readable on-screen colour for a wheel colour (black needs to show on a dark UI).
static func _ui_color(i: int) -> Color:
	match i:
		0:
			return Palette.LOSS_RED
		1:
			return Palette.CREAM
		2:
			return Palette.MONEY_GREEN
	return Palette.CREAM


static func _int_table(d: Variant) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for k: Variant in d:
			out[int(k)] = int(d[k])
	return out


static func _int_list(a: Variant) -> Array[int]:
	var out: Array[int] = []
	if a is Array:
		for v: Variant in a:
			out.append(int(v))
	return out


func _refresh_board() -> void:
	if board == null:
		return
	for c: Node in board.get_children():
		board.remove_child(c)
		c.free()  # detached: free now (no orphans waiting for the frame end)
	var order: Array[int] = players.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		var aa: bool = a in alive
		var ba: bool = b in alive
		if aa != ba:
			return aa
		if int(hearts.get(a, 0)) != int(hearts.get(b, 0)):
			return int(hearts.get(a, 0)) > int(hearts.get(b, 0))
		return a < b)
	for pid: int in order:
		board.add_child(_board_row(pid))


func _board_row(pid: int) -> Control:
	var is_alive: bool = pid in alive
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.WARM_CHARCOAL if pid != local_id else Palette.VIP_BURGUNDY.darkened(0.2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if pid == local_id:
		sb.set_border_width_all(2)
		sb.border_color = Palette.WARM_GOLD
	row.add_theme_stylebox_override(&"panel", sb)
	row.modulate = Color.WHITE if is_alive or finished else Color(1, 1, 1, 0.55)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	row.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	v.add_child(top)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(16, 16)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = _player_color(pid)
	top.add_child(dot)
	var n := Label.new()
	n.text = _name(pid) + ("  (you)" if pid == local_id else "")
	n.add_theme_font_size_override(&"font_size", 26)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	top.add_child(n)
	var tag := Label.new()
	tag.add_theme_font_size_override(&"font_size", 22)
	var place: int = int(places.get(pid, -1))
	if finished and place > 0:
		tag.text = "WINNER" if place == 1 else "#%d" % place
		tag.add_theme_color_override(&"font_color", Palette.VIP_GOLD if place == 1 else Palette.CREAM)
	elif not is_alive:
		tag.text = "OUT"
		tag.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	elif not shown_picks.is_empty():
		var c: Variant = _pick_of(pid)
		tag.text = COLOR_NAMES[COLOR_ORDER.find(c)] if c != null else "NO PICK"
		tag.add_theme_color_override(&"font_color", _ui_color(COLOR_ORDER.find(c)) if c != null else Palette.CREAM.darkened(0.4))
	elif picked.has(pid):
		tag.text = "LOCKED IN"
		tag.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	elif picking:
		tag.text = "thinking…"
		tag.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.4))
	top.add_child(tag)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 10)
	v.add_child(bottom)
	var hv := HeartsView.new()
	hv.count = int(hearts.get(pid, 0))
	hv.slots = maxi(RouletteRoyaleLogic.MAX_HEARTS, hv.count)
	bottom.add_child(hv)
	var d: int = int(shown_deltas.get(pid, 0))
	if d != 0 and not finished:
		var dl := Label.new()
		dl.text = "%+d" % d
		dl.add_theme_font_size_override(&"font_size", 24)
		dl.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if d > 0 else Palette.LOSS_RED)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(dl)
	return row


func _style_color_button(b: Button, i: int, selected: bool) -> void:
	var base: Color = [Palette.CASINO_RED, Palette.CASINO_BLACK, Palette.FELT_GREEN][i]
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = base.lightened(0.12) if st == "hover" else base
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(6 if selected else 3)
		sb.border_color = Palette.VIP_GOLD if selected else Palette.CREAM.darkened(0.35)
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 4)
		b.add_theme_stylebox_override(st, sb)


# --- Building ----------------------------------------------------------------------------------

func _build_set() -> void:
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(24, 0.2, 18)
	floor_mesh.mesh = fm
	floor_mesh.position.y = -0.1
	floor_mesh.material_override = _mat(Palette.VIP_BURGUNDY.darkened(0.3))
	add_child(floor_mesh)
	# Round felt table with a gold rim; the wheel sits in the middle.
	var table := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 1.9
	tm.bottom_radius = 1.9
	tm.height = 0.12
	tm.radial_segments = 48
	table.mesh = tm
	table.position.y = TABLE_TOP - 0.06
	table.material_override = _mat(Palette.FELT_GREEN)
	add_child(table)
	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 1.86
	rm.outer_radius = 2.02
	rm.rings = 48
	rim.mesh = rm
	rim.position.y = TABLE_TOP
	rim.material_override = _mat(Palette.WARM_GOLD, 0.7)
	add_child(rim)
	var leg := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.5
	lm.bottom_radius = 0.9
	lm.height = TABLE_TOP - 0.12
	leg.mesh = lm
	leg.position.y = (TABLE_TOP - 0.12) * 0.5
	leg.material_override = _mat(Palette.WARM_CHARCOAL)
	add_child(leg)
	_add_wheel()
	# Warm key light from above, gold fills.
	var key := SpotLight3D.new()
	key.position = Vector3(0, 6, 1.5)
	key.rotation_degrees = Vector3(-80, 0, 0)
	key.spot_range = 12.0
	key.spot_angle = 40.0
	key.light_energy = 3.5
	key.light_color = Color("#FFE2B0")
	key.shadow_enabled = true
	add_child(key)
	for sx: float in [-4.0, 4.0]:
		var fill := OmniLight3D.new()
		fill.position = Vector3(sx, 3, 2)
		fill.omni_range = 8.0
		fill.light_energy = 0.9
		fill.light_color = Palette.VIP_GOLD
		add_child(fill)
	# One camera: looking down at the wheel, framed left of centre so the hearts board on the
	# right and the buttons at the bottom leave it clear.
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 90.0  # the casino floor is 400 m away: keep its always-on-top labels out
	add_child(camera)
	camera.position = Vector3(0.75, 4.1, 3.3)
	camera.look_at(global_position + Vector3(0.75, TABLE_TOP - 0.1, 0.25))


## Patrick's wheel (the roulette table's model and spin FX), minus its own camera, lights and floor.
func _add_wheel() -> void:
	var ps: PackedScene = load(RouletteStation.WHEEL_MODEL) as PackedScene
	if ps == null:
		return
	var model: Node3D = ps.instantiate()
	model.name = "Wheel"
	add_child(model)
	for n: Node in model.find_children("*", "", true, false):
		if is_instance_valid(n) and (n is Camera3D or n is Light3D or String(n.name) == "Plane"):
			n.get_parent().remove_child(n)
			n.free()
	model.scale = Vector3.ONE * WHEEL_SCALE
	model.position = Vector3(0, TABLE_TOP + 0.512 * WHEEL_SCALE, 0)  # its base sits 0.51 m below its origin
	if Vfx.enabled():
		wheel_fx = RouletteWheelFx.new()
		model.add_child(wheel_fx)


func _mat(c: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.45 if metallic > 0.0 else 0.8
	return m


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	ui.add_child(root)
	# Status card, top centre.
	card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -420
	card.offset_right = 420
	card.offset_top = 20
	card.visible = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 6)
	card.add_child(cv)
	header = Label.new()
	header.theme_type_variation = &"HeadingLabel"
	header.add_theme_font_size_override(&"font_size", 30)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(header)
	status_label = Label.new()
	status_label.add_theme_font_size_override(&"font_size", 44)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	status_label.add_theme_constant_override(&"outline_size", 6)
	cv.add_child(status_label)
	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(0, 12)
	timer_bar.value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.WARM_GOLD
	fill.set_corner_radius_all(6)
	timer_bar.add_theme_stylebox_override(&"fill", fill)
	timer_bar.visible = false
	cv.add_child(timer_bar)
	# Colour buttons, bottom centre.
	button_row = HBoxContainer.new()
	button_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	button_row.anchor_left = 0.5
	button_row.anchor_right = 0.5
	button_row.anchor_top = 1.0
	button_row.anchor_bottom = 1.0
	button_row.offset_left = -560
	button_row.offset_right = 560
	button_row.offset_top = -150
	button_row.offset_bottom = -24
	button_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button_row.add_theme_constant_override(&"separation", 20)
	root.add_child(button_row)
	for i: int in COLOR_ORDER.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 126)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		_style_color_button(b, i, false)
		b.pressed.connect(_pick.bind(i))
		button_row.add_child(b)
		var bv := VBoxContainer.new()
		bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.add_theme_constant_override(&"separation", 0)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var t := Label.new()
		t.theme_type_variation = &"HeadingLabel"
		t.text = COLOR_NAMES[i]
		t.add_theme_font_size_override(&"font_size", 48)
		t.add_theme_color_override(&"font_color", Palette.CREAM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_child(t)
		var o := Label.new()
		o.text = "%s   ·   %d / %s" % [COLOR_ODDS[i], i + 1, PAD_NAMES[i]]
		o.add_theme_font_size_override(&"font_size", 22)
		o.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.2))
		o.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_child(o)
		buttons.append(b)
	# Hearts board, right.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -400
	panel.offset_right = -20
	panel.offset_top = 200
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override(&"separation", 6)
	panel.add_child(pv)
	var pt := Label.new()
	pt.theme_type_variation = &"HeadingLabel"
	pt.text = "HEARTS"
	pv.add_child(pt)
	board = VBoxContainer.new()
	board.add_theme_constant_override(&"separation", 6)
	pv.add_child(board)
	# Banners, top centre (intro / winner; hidden while the status card is up).
	banner = Label.new()
	banner.theme_type_variation = &"TitleLabel"
	banner.add_theme_font_size_override(&"font_size", 76)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -760
	banner.offset_right = 760
	banner.offset_top = 14
	banner.offset_bottom = 110
	banner.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	banner.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	banner.add_theme_constant_override(&"outline_size", 14)
	root.add_child(banner)
	sub_banner = Label.new()
	sub_banner.theme_type_variation = &"HeadingLabel"
	sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub_banner.anchor_left = 0.5
	sub_banner.anchor_right = 0.5
	sub_banner.offset_left = -760
	sub_banner.offset_right = 760
	sub_banner.offset_top = 104
	sub_banner.offset_bottom = 150
	sub_banner.add_theme_color_override(&"font_color", Palette.CREAM)
	sub_banner.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	sub_banner.add_theme_constant_override(&"outline_size", 10)
	root.add_child(sub_banner)


## A row of drawn hearts: filled for each heart left, hollow outlines for lost ones (Barlow
## Condensed has no heart glyph, and emoji would not match the art direction).
class HeartsView:
	extends Control

	const SIZE: float = 26.0
	const GAP: float = 6.0

	var count: int = 0:
		set(v):
			count = v
			queue_redraw()
	var slots: int = 3:
		set(v):
			slots = v
			custom_minimum_size = Vector2(v * (SIZE + GAP), SIZE)
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(slots * (SIZE + GAP), SIZE)

	func _draw() -> void:
		for i: int in slots:
			var pts: PackedVector2Array = _heart(Vector2(i * (SIZE + GAP) + SIZE * 0.5, SIZE * 0.5), SIZE * 0.5)
			if i < count:
				draw_colored_polygon(pts, Palette.CASINO_RED.lightened(0.1))
				draw_polyline(pts + PackedVector2Array([pts[0]]), Palette.CASINO_BLACK, 2.0, true)
			else:
				draw_polyline(pts + PackedVector2Array([pts[0]]), Palette.CREAM.darkened(0.55), 2.0, true)

	static func _heart(c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k: int in 32:
			var t: float = TAU * float(k) / 32.0
			# Classic heart curve, scaled to fit a 2r box, point down.
			var x: float = 16.0 * pow(sin(t), 3)
			var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
			pts.append(c + Vector2(x, -y - 2.5) * (r / 17.0))
		return pts
