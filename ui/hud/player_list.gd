class_name PlayerList
extends PanelContainer
## The Tab list ("THE TABLE"), held open in the lobby and in the match: a burgundy card with gold
## trim, one row per player. Each row has a little live 3D portrait of the player's bean in its
## colour (`BeanPreviewView`), a colour bar, the name with the bean's colour, the HOST badge, a
## speaker while they talk (`VoiceChannel.is_talking`) and, for the local row, the ping. In the
## match rows are sorted by money with the standing (1ST, 2ND...) and a gold crown on the leader
## (`LeaderCrown.leader_of`, the same rule as the 3D crown); in the lobby they keep the join order
## and show the read-only READY / WAITING state of each pedestal. Nothing here sends an intent:
## getting ready only happens by standing on the pedestal. Portraits exist only while the list is
## shown and are freed when it hides. Never takes the mouse or focus.

const WIDTH: float = 780.0
const ROW_HEIGHT: float = 78.0
const PORTRAIT_SIZE := Vector2(64, 68)
const MUTED := Color("#A99C84")
const NAME_MAX_W: float = 300.0

var state: ClientMatchState = null
var local_id: int = -1

var title_label: Label
var subtitle_label: Label
var rows_box: VBoxContainer
var footer_label: Label
## Player id → {frame, bar, rank, crown, portrait, name, info, host, talk, ready_icon, ready, money, ping}.
var rows: Dictionary[int, Dictionary] = {}
## Tab was seen held while the list is open: its release closes the list even when the input
## router stopped forwarding it (a menu opened meanwhile).
var _held: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	set_process(false)
	_build()


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	if state != null and state.players_changed.is_connected(_refresh_if_open):
		state.players_changed.disconnect(_refresh_if_open)
		state.lobby_changed.disconnect(_refresh_if_open)
		state.money_changed.disconnect(_on_money)
		state.phase_changed.disconnect(_on_phase)
	state = p_state
	local_id = p_local_id
	state.players_changed.connect(_refresh_if_open)
	state.lobby_changed.connect(_refresh_if_open)
	state.money_changed.connect(_on_money)
	state.phase_changed.connect(_on_phase)


## Shows (builds the rows and portraits) or hides (frees them) the list.
func show_list(shown: bool) -> void:
	visible = shown
	set_process(shown)
	_held = false
	if shown:
		refresh()
	else:
		_clear_rows()


## True in the lobby (join order, ready states); false in the match (standings by money).
func is_lobby() -> bool:
	return state != null and state.phase == Phase.Id.LOBBY


## Player ids in display order.
func ordered_ids() -> Array[int]:
	var ids: Array[int] = []
	if state == null:
		return ids
	for pid: int in state.players:
		ids.append(pid)
	for pid: int in state.balances:
		if not ids.has(pid):
			ids.append(pid)
	if is_lobby():
		ids.sort()
	else:
		ids.sort_custom(func(a: int, b: int) -> bool:
			var ma: int = state.balance(a)
			var mb: int = state.balance(b)
			return ma > mb or (ma == mb and a < b))
	return ids


## Every portrait currently alive in the list.
func portraits() -> Array[BeanPreviewView]:
	var out: Array[BeanPreviewView] = []
	for pid: int in rows:
		out.append(rows[pid]["portrait"] as BeanPreviewView)
	return out


func refresh() -> void:
	if state == null or rows_box == null or not visible:
		return
	var lobby: bool = is_lobby()
	var ids: Array[int] = ordered_ids()
	for pid: int in rows.keys():
		if not ids.has(pid):
			(rows[pid]["frame"] as Node).free()
			rows.erase(pid)
	var lead: int = -1 if lobby else LeaderCrown.leader_of(state.balances)
	var ready_count: int = 0
	for i: int in ids.size():
		var pid: int = ids[i]
		if not rows.has(pid):
			rows[pid] = _make_row(pid)
		var r: Dictionary = rows[pid]
		rows_box.move_child(r["frame"] as Node, i)
		var p: Dictionary = state.players.get(pid, {})
		var col: Color = Palette.player_color(int(p.get("color", 0)))
		var bean: Color = Palette.bean_color(p)
		var mine: bool = pid == local_id
		(r["frame"] as PanelContainer).add_theme_stylebox_override(&"panel", _row_style(mine))
		(r["bar"] as ColorRect).color = col
		var portrait: BeanPreviewView = r["portrait"]
		if portrait.color != bean:
			portrait.set_bean_color(bean)
		(r["portrait_frame"] as PanelContainer).add_theme_stylebox_override(&"panel", _portrait_style(col))
		var rank: Label = r["rank"]
		rank.text = "%d" % (i + 1) if lobby else Hud._ordinal(i + 1).to_upper()
		rank.add_theme_color_override(&"font_color", Palette.VIP_GOLD if (not lobby and i == 0) else MUTED)
		(r["crown"] as Control).visible = pid == lead
		var name_label: Label = r["name"]
		name_label.text = str(p.get("name", state.player_name(pid)))
		# Clipped (with an ellipsis) only past NAME_MAX_W, so the badges sit right after the name.
		var font: Font = name_label.get_theme_font(&"font")
		var w: float = font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size(&"font_size")).x
		name_label.custom_minimum_size.x = minf(ceilf(w) + 4.0, NAME_MAX_W)
		(r["frame"] as CanvasItem).modulate.a = 1.0 if bool(p.get("connected", true)) else 0.6
		name_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD if mine else Palette.CREAM)
		var info: PackedStringArray = ["%s bean" % _color_name(int(p.get("bean_color", p.get("color", 0))))]
		if mine:
			info.append("you")
		if not bool(p.get("connected", true)):
			info.append("away")
		(r["info"] as Label).text = "  ·  ".join(info)
		(r["host"] as Control).visible = state.room_mode and pid == state.leader
		var is_ready: bool = bool(p.get("ready", false))
		if is_ready:
			ready_count += 1
		(r["ready_box"] as Control).visible = lobby
		(r["ready_icon"] as Glyph).tint = Palette.MONEY_GREEN if is_ready else Color(MUTED, 0.6)
		(r["ready_icon"] as Glyph).queue_redraw()
		var ready_label: Label = r["ready"]
		ready_label.text = "READY" if is_ready else "WAITING"
		ready_label.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if is_ready else MUTED)
		var money: Label = r["money"]
		money.visible = not lobby
		money.text = "$%s" % Hud._thousands(state.balance(pid))
		money.add_theme_color_override(&"font_color", Palette.VIP_GOLD if pid == lead else Palette.CREAM)
	title_label.text = "THE TABLE"
	if lobby:
		subtitle_label.text = "LOBBY  ·  %d / %d READY" % [ready_count, ids.size()]
		footer_label.text = "Stand on your pedestal to get ready"
	else:
		subtitle_label.text = "STANDINGS  ·  %d PLAYERS" % ids.size()
		footer_label.text = "The crown goes to the richest player"
	_update_live()
	# Stay centred whatever the number of rows: zero height, grown both ways to the content.
	offset_top = 0.0
	offset_bottom = 0.0
	update_minimum_size()


func _process(_delta: float) -> void:
	if InputMap.has_action(&"leaderboard"):
		if Input.is_action_pressed(&"leaderboard"):
			_held = true
		elif _held:
			show_list(false)
			return
	_update_live()


## Talking speakers and the local ping, polled while the list is open.
func _update_live() -> void:
	var voice: VoiceChannel = VoiceChannel.current
	for pid: int in rows:
		var r: Dictionary = rows[pid]
		var talking: bool = voice != null and is_instance_valid(voice) and voice.is_talking(pid)
		(r["talk"] as Control).visible = talking
		var ping: Label = r["ping"]
		var rtt: float = Net.clock.rtt if Net.clock != null else -1.0
		ping.visible = pid == local_id and Net.mode == Net.Mode.CLIENT and rtt >= 0.0
		if ping.visible:
			ping.text = "%d ms" % roundi(rtt * 1000.0)


func _refresh_if_open() -> void:
	if visible:
		refresh()


func _on_money(_player: int, _amount: int, _balance: int, _reason: StringName) -> void:
	_refresh_if_open()


func _on_phase(_phase: Phase.Id) -> void:
	_refresh_if_open()


func _clear_rows() -> void:
	for pid: int in rows:
		(rows[pid]["frame"] as Node).free()
	rows.clear()


func _build() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.VIP_BURGUNDY.darkened(0.35)
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override(&"separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override(&"separation", 14)
	v.add_child(head)
	head.add_child(_suit_glyph(&"spade"))
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = &"TitleLabel"
	title_label.add_theme_font_size_override(&"font_size", 54)
	title_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title_label.text = "THE TABLE"
	head.add_child(title_label)
	head.add_child(_suit_glyph(&"diamond"))
	subtitle_label = Label.new()
	subtitle_label.name = "Subtitle"
	subtitle_label.theme_type_variation = &"SmallLabel"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.15))
	v.add_child(subtitle_label)
	v.add_child(_gold_rule())
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows_box.add_theme_constant_override(&"separation", 6)
	v.add_child(rows_box)
	v.add_child(_gold_rule())
	footer_label = Label.new()
	footer_label.name = "Footer"
	footer_label.theme_type_variation = &"MutedLabel"
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(footer_label)


func _make_row(pid: int) -> Dictionary:
	var frame := PanelContainer.new()
	frame.name = "Row%d" % pid
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	rows_box.add_child(frame)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", 12)
	frame.add_child(h)
	var bar := ColorRect.new()
	bar.name = "ColorBar"
	bar.custom_minimum_size = Vector2(8, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	# Standing (or seat number in the lobby) with the leader's crown above it.
	var rank_box := VBoxContainer.new()
	rank_box.custom_minimum_size = Vector2(52, 0)
	rank_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_box.add_theme_constant_override(&"separation", -4)
	rank_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(rank_box)
	var crown := Glyph.make(&"crown", Palette.VIP_GOLD, Vector2(34, 24))
	crown.name = "Crown"
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rank_box.add_child(crown)
	var rank := Label.new()
	rank.name = "Rank"
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.add_theme_font_override(&"font", _font(&"TitleLabel"))
	rank.add_theme_font_size_override(&"font_size", 28)
	rank_box.add_child(rank)
	var pframe := PanelContainer.new()
	pframe.name = "PortraitFrame"
	pframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pframe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pframe)
	var p: Dictionary = state.players.get(pid, {})
	var portrait := BeanPreviewView.make(Palette.bean_color(p), PORTRAIT_SIZE)
	portrait.name = "Portrait"
	portrait.portrait = true
	pframe.add_child(portrait)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override(&"separation", -2)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(names)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(top)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.add_theme_font_override(&"font", _font(&"HeadingLabel"))
	name_label.add_theme_font_size_override(&"font_size", 32)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(name_label)
	var host := _host_badge()
	top.add_child(host)
	var talk := Glyph.make(&"speaker", Palette.CREAM, Vector2(26, 24))
	talk.name = "Talking"
	talk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	talk.tooltip_text = "Talking"
	top.add_child(talk)
	var info := Label.new()
	info.name = "Info"
	info.theme_type_variation = &"SmallLabel"
	info.add_theme_color_override(&"font_color", MUTED)
	names.add_child(info)
	var ready_box := HBoxContainer.new()
	ready_box.name = "ReadyState"
	ready_box.add_theme_constant_override(&"separation", 8)
	ready_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ready_box)
	var ready_icon := Glyph.make(&"pedestal", Palette.MONEY_GREEN, Vector2(34, 30))
	ready_icon.name = "Pedestal"
	ready_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ready_box.add_child(ready_icon)
	var ready := Label.new()
	ready.name = "Ready"
	ready.custom_minimum_size = Vector2(92, 0)
	ready.add_theme_font_override(&"font", _font(&"HeadingLabel"))
	ready.add_theme_font_size_override(&"font_size", 24)
	ready.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ready_box.add_child(ready)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override(&"separation", -4)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	var money := Label.new()
	money.name = "Money"
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.custom_minimum_size = Vector2(150, 0)
	money.add_theme_font_override(&"font", _font(&"TitleLabel"))
	money.add_theme_font_size_override(&"font_size", 36)
	right.add_child(money)
	var ping := Label.new()
	ping.name = "Ping"
	ping.theme_type_variation = &"MutedLabel"
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping.add_theme_font_size_override(&"font_size", 16)
	right.add_child(ping)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(4, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	return {"frame": frame, "bar": bar, "rank": rank, "crown": crown, "portrait": portrait, "portrait_frame": pframe,
		"name": name_label, "info": info, "host": host, "talk": talk, "ready_box": ready_box, "ready_icon": ready_icon,
		"ready": ready, "money": money, "ping": ping}


func _host_badge() -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "Host"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.tooltip_text = "Lobby host"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.VIP_GOLD
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 7
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	badge.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(h)
	var star := Glyph.make(&"star", Palette.VIP_BURGUNDY, Vector2(16, 16))
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(star)
	var l := Label.new()
	l.text = "HOST"
	l.add_theme_font_override(&"font", _font(&"TitleLabel"))
	l.add_theme_font_size_override(&"font_size", 18)
	l.add_theme_color_override(&"font_color", Palette.VIP_BURGUNDY)
	h.add_child(l)
	return badge


func _row_style(mine: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.VIP_BURGUNDY.darkened(0.05) if mine else Palette.WARM_CHARCOAL.lerp(Palette.VIP_BURGUNDY, 0.25)
	sb.border_color = Palette.VIP_GOLD if mine else Palette.WARM_GOLD.darkened(0.55)
	sb.set_border_width_all(2 if mine else 1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 0
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	if mine:
		sb.shadow_color = Color(Palette.VIP_GOLD, 0.25)
		sb.shadow_size = 6
	return sb


func _portrait_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.55).lerp(Palette.CASINO_BLACK, 0.3)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(2)
	return sb


func _gold_rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(Palette.WARM_GOLD, 0.7)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _suit_glyph(kind: StringName) -> Glyph:
	var g := Glyph.make(kind, Palette.CASINO_RED if kind == &"diamond" else Palette.CREAM, Vector2(26, 30))
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return g


func _font(type: StringName) -> Font:
	var t: Theme = ThemeDB.get_project_theme()
	if t != null and t.has_font(&"font", type):
		return t.get_font(&"font", type)
	return ThemeDB.fallback_font


func _color_name(index: int) -> String:
	var n: int = Palette.PLAYER_COLOR_NAMES.size()
	return Palette.PLAYER_COLOR_NAMES[posmod(index, n)] if n > 0 else ""


## Small drawn icons (no font glyph needed): crown, pedestal, speaker, star and card suits.
class Glyph:
	extends Control

	var kind: StringName = &"crown"
	var tint: Color = Color.WHITE

	static func make(p_kind: StringName, p_tint: Color, min_size: Vector2) -> Glyph:
		var g := Glyph.new()
		g.kind = p_kind
		g.tint = p_tint
		g.custom_minimum_size = min_size
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return g

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var dark := Color(Palette.CASINO_BLACK, 0.85)
		match kind:
			&"crown":
				var pts := PackedVector2Array([
					Vector2(w * 0.08, h * 0.92), Vector2(w * 0.04, h * 0.28), Vector2(w * 0.3, h * 0.55),
					Vector2(w * 0.5, h * 0.08), Vector2(w * 0.7, h * 0.55), Vector2(w * 0.96, h * 0.28),
					Vector2(w * 0.92, h * 0.92)])
				draw_colored_polygon(pts, tint)
				var outline := pts.duplicate()
				outline.append(pts[0])
				draw_polyline(outline, dark, 1.5, true)
				draw_rect(Rect2(w * 0.1, h * 0.74, w * 0.8, h * 0.1), tint.darkened(0.3))
				for x: float in [0.04, 0.5, 0.96]:
					draw_circle(Vector2(w * x, h * (0.08 if x == 0.5 else 0.28)), w * 0.06, Palette.CREAM)
				draw_circle(Vector2(w * 0.5, h * 0.66), w * 0.07, Palette.CASINO_RED)
			&"pedestal":
				# A round podium seen from the side, its top lit when ready.
				draw_rect(Rect2(w * 0.12, h * 0.45, w * 0.76, h * 0.42), tint.darkened(0.35))
				draw_rect(Rect2(w * 0.04, h * 0.82, w * 0.92, h * 0.14), tint.darkened(0.5))
				draw_rect(Rect2(w * 0.08, h * 0.34, w * 0.84, h * 0.14), tint)
				draw_line(Vector2(w * 0.5, h * 0.02), Vector2(w * 0.5, h * 0.26), Color(tint, 0.6), 2.0)
				draw_line(Vector2(w * 0.2, h * 0.1), Vector2(w * 0.3, h * 0.26), Color(tint, 0.45), 2.0)
				draw_line(Vector2(w * 0.8, h * 0.1), Vector2(w * 0.7, h * 0.26), Color(tint, 0.45), 2.0)
			&"speaker":
				var body := PackedVector2Array([
					Vector2(w * 0.05, h * 0.36), Vector2(w * 0.25, h * 0.36), Vector2(w * 0.5, h * 0.1),
					Vector2(w * 0.5, h * 0.9), Vector2(w * 0.25, h * 0.64), Vector2(w * 0.05, h * 0.64)])
				draw_colored_polygon(body, tint)
				var pulse: float = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 140.0))
				draw_arc(Vector2(w * 0.5, h * 0.5), w * 0.22, -0.9, 0.9, 10, Color(Palette.MONEY_GREEN, pulse), 2.5)
				draw_arc(Vector2(w * 0.5, h * 0.5), w * 0.4, -0.9, 0.9, 12, Color(Palette.MONEY_GREEN, pulse * 0.7), 2.5)
			&"star":
				var star := PackedVector2Array()
				for i: int in 10:
					var a: float = -PI / 2.0 + i * PI / 5.0
					var rad: float = (0.5 if i % 2 == 0 else 0.22) * minf(w, h)
					star.append(Vector2(w / 2.0, h / 2.0) + Vector2(cos(a), sin(a)) * rad)
				draw_colored_polygon(star, tint)
			&"spade":
				draw_circle(Vector2(w * 0.32, h * 0.52), w * 0.22, tint)
				draw_circle(Vector2(w * 0.68, h * 0.52), w * 0.22, tint)
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.05), Vector2(w * 0.94, h * 0.5), Vector2(w * 0.06, h * 0.5)]), tint)
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.55), Vector2(w * 0.7, h * 0.95), Vector2(w * 0.3, h * 0.95)]), tint)
			&"diamond":
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.04), Vector2(w * 0.92, h * 0.5), Vector2(w * 0.5, h * 0.96), Vector2(w * 0.08, h * 0.5)]), tint)

	func _process(_delta: float) -> void:
		if kind == &"speaker" and is_visible_in_tree():
			queue_redraw()
