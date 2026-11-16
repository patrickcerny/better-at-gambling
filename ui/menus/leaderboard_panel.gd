class_name LeaderboardPanel
extends PanelContainer
## LEADERBOARDS and MY STATS (Patrick 2026-11-16: "globale leaderboards (Most money made in a single
## lobby). Einfach lobby übergreifend ... Es gibt auch eigene statistiken game übergreifend"),
## opened by the trophy in the main menu's bottom-right corner (`TrophyButton`).
##
## LEADERBOARDS: the boards (`LeaderboardRules.BOARDS`) on the left, GLOBAL / FRIENDS / AROUND ME
## on top, the rows from Steam (`SteamSvc.boards`) below, your own row in gold. Only ranked online
## matches count (see `LeaderboardRules`). Without Steam the page says so.
## MY STATS: the lifetime numbers from the local profile (`PlayerProfile.lifetime` and friends),
## Practice included except where a line says "online".

signal closed

const PAGE_BOARDS: int = 0
const PAGE_STATS: int = 1
const SCOPES: Array[Dictionary] = [
	{"scope": LeaderboardRules.SCOPE_GLOBAL, "text": "GLOBAL"},
	{"scope": LeaderboardRules.SCOPE_FRIENDS, "text": "FRIENDS"},
	{"scope": LeaderboardRules.SCOPE_AROUND_ME, "text": "AROUND ME"},
]

var page_buttons: Array[Button] = []
var board_buttons: Dictionary[StringName, Button] = {}
var scope_buttons: Array[Button] = []
var boards_page: Control
var stats_page: Control
var rows_box: VBoxContainer
var status_label: Label
var hint_label: Label
var stats_grid: GridContainer
var back_button: Button
var title_label: Label
var board: StringName = LeaderboardRules.BEST_MATCH_MONEY
var scope: int = LeaderboardRules.SCOPE_GLOBAL
## The rows on show (for name refreshes).
var _rows: Array[Dictionary] = []
var _dim: ColorRect


func _ready() -> void:
	name = "Leaderboards"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 56
	offset_right = -56
	offset_top = 40
	offset_bottom = -40
	visible = false
	add_theme_stylebox_override(&"panel", LevelPassPanel._panel_style())
	_dim = ColorRect.new()
	_dim.name = "LeaderboardsDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.05, 0.03, 0.03, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	v.add_child(top)
	title_label = Label.new()
	title_label.theme_type_variation = &"TitleLabel"
	title_label.text = "LEADERBOARDS"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	var group := ButtonGroup.new()
	for i: int in 2:
		var b := Button.new()
		b.name = "PageBoards" if i == PAGE_BOARDS else "PageStats"
		b.text = "LEADERBOARDS" if i == PAGE_BOARDS else "MY STATS"
		b.theme_type_variation = &"ChipButton"
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(190, 48)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		SettingsPanel.style_tab(b)
		b.pressed.connect(show_page.bind(i))
		top.add_child(b)
		page_buttons.append(b)
	v.add_child(HSeparator.new())
	boards_page = _build_boards()
	boards_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(boards_page)
	stats_page = _build_stats()
	stats_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stats_page)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.custom_minimum_size = Vector2(260, 44)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(close)
	v.add_child(back_button)
	SteamSvc.boards.entries_received.connect(_on_entries)
	SteamSvc.boards.entries_failed.connect(_on_failed)
	SteamSvc.boards.name_ready.connect(func(_id: int) -> void: _draw_rows())
	show_page(PAGE_BOARDS)


func _build_boards() -> Control:
	var body := HBoxContainer.new()
	body.name = "BoardsPage"
	body.add_theme_constant_override(&"separation", 24)
	# The boards.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 340
	left.add_theme_constant_override(&"separation", 6)
	body.add_child(left)
	var bgroup := ButtonGroup.new()
	for b: Dictionary in LeaderboardRules.BOARDS:
		var id: StringName = b["id"]
		var btn := Button.new()
		btn.name = "Board" + String(id).capitalize().replace(" ", "")
		btn.text = str(b["title"])
		btn.toggle_mode = true
		btn.button_group = bgroup
		btn.custom_minimum_size = Vector2(0, 52)
		SettingsPanel.style_tab(btn)
		btn.pressed.connect(select_board.bind(id))
		left.add_child(btn)
		board_buttons[id] = btn
	var note := Label.new()
	note.theme_type_variation = &"SmallLabel"
	note.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Only online matches with at least two players count. Practice never does."
	left.add_child(note)
	# The rows.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 6)
	body.add_child(right)
	var scopes := HBoxContainer.new()
	scopes.add_theme_constant_override(&"separation", 8)
	right.add_child(scopes)
	var sgroup := ButtonGroup.new()
	for i: int in SCOPES.size():
		var sb := Button.new()
		sb.name = "Scope" + str(SCOPES[i]["text"]).capitalize().replace(" ", "")
		sb.text = str(SCOPES[i]["text"])
		sb.theme_type_variation = &"ChipButton"
		sb.toggle_mode = true
		sb.button_group = sgroup
		sb.custom_minimum_size = Vector2(150, 44)
		SettingsPanel.style_tab(sb)
		sb.pressed.connect(select_scope.bind(int(SCOPES[i]["scope"])))
		scopes.add_child(sb)
		scope_buttons.append(sb)
	hint_label = Label.new()
	hint_label.name = "Hint"
	hint_label.theme_type_variation = &"SmallLabel"
	hint_label.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override(&"separation", 2)
	scroll.add_child(rows_box)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	right.add_child(status_label)
	return body


func _build_stats() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "StatsPage"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	stats_grid = GridContainer.new()
	stats_grid.name = "Stats"
	stats_grid.columns = 4
	stats_grid.add_theme_constant_override(&"h_separation", 28)
	stats_grid.add_theme_constant_override(&"v_separation", 10)
	center.add_child(stats_grid)
	return scroll


## The MY STATS lines: [label, value text], from the local profile.
static func stat_lines(p: PlayerProfile) -> Array[Array]:
	var rate: String = "-" if p.matches == 0 else "%d%%" % roundi(100.0 * float(p.wins) / float(p.matches))
	return [
		["Matches played", LeaderboardRules.group(p.matches)],
		["Online matches", LeaderboardRules.group(p.stat(&"online_matches"))],
		["Matches won", LeaderboardRules.group(p.wins)],
		["Online wins", LeaderboardRules.group(p.online_wins)],
		["Win rate", rate],
		["Podium finishes (top 3)", LeaderboardRules.group(p.stat(&"podiums"))],
		["Best online match", "$" + LeaderboardRules.group(p.stat(&"best_money"))],
		["Biggest single win", "$" + LeaderboardRules.group(p.biggest_win)],
		["Biggest bet", "$" + LeaderboardRules.group(p.stat(&"biggest_bet"))],
		["Total winnings", "$" + LeaderboardRules.group(p.stat(&"winnings"))],
		["Total losses", "$" + LeaderboardRules.group(p.stat(&"losses"))],
		["Online winnings", "$" + LeaderboardRules.group(p.stat(&"online_winnings"))],
		["Hands played", LeaderboardRules.group(p.stat(&"hands"))],
		["Minigames won", LeaderboardRules.group(p.stat(&"minigames_won"))],
		["Jackpot money won", "$" + LeaderboardRules.group(p.stat(&"jackpot_won"))],
		["Quiz points", LeaderboardRules.group(p.stat(&"quiz_points"))],
		["Knockouts dealt", LeaderboardRules.group(p.stat(&"knockouts_dealt"))],
		["Times knocked out", LeaderboardRules.group(p.stat(&"knockouts_suffered"))],
		["Thrown out by security", LeaderboardRules.group(p.stat(&"thrown_out"))],
		["Level", str(p.level)],
	]


func _fill_stats() -> void:
	for c: Node in stats_grid.get_children():
		c.queue_free()
	for line: Array in stat_lines(ProfileManager.profile):
		var l := Label.new()
		l.text = str(line[0])
		l.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
		stats_grid.add_child(l)
		var val := Label.new()
		val.text = str(line[1])
		val.theme_type_variation = &"HeadingLabel"
		val.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		val.custom_minimum_size.x = 150
		stats_grid.add_child(val)


func open(page: int = PAGE_BOARDS) -> void:
	var host: Node = get_parent()
	if host != null:
		if _dim.get_parent() == null:
			host.add_child(_dim)
		host.move_child(_dim, -1)
		host.move_child(self, -1)
		_dim.visible = true
	visible = true
	back_button.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	show_page(page)
	page_buttons[page].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_dim.visible = false
	closed.emit()


func show_page(page: int) -> void:
	for i: int in page_buttons.size():
		page_buttons[i].set_pressed_no_signal(i == page)
	title_label.text = "MY STATS" if page == PAGE_STATS else "LEADERBOARDS"
	boards_page.visible = page == PAGE_BOARDS
	stats_page.visible = page == PAGE_STATS
	if page == PAGE_STATS:
		_fill_stats()
	elif visible:
		select_board(board)


func select_board(id: StringName) -> void:
	board = id
	for k: StringName in board_buttons:
		board_buttons[k].set_pressed_no_signal(k == id)
	hint_label.text = str(LeaderboardRules.board(id).get("hint", ""))
	_refresh()


func select_scope(s: int) -> void:
	scope = s
	_refresh()


func _refresh() -> void:
	for i: int in SCOPES.size():
		scope_buttons[i].set_pressed_no_signal(int(SCOPES[i]["scope"]) == scope)
	_rows = []
	_draw_rows()
	if not SteamSvc.boards.available():
		status_label.text = "Leaderboards need Steam. Start the game from Steam to see them."
		return
	status_label.text = "Loading..."
	SteamSvc.boards.download(board, scope)


func _on_entries(id: StringName, s: int, rows: Array[Dictionary], total: int) -> void:
	if id != board or s != scope:
		return
	_rows = rows
	_draw_rows()
	if rows.is_empty():
		status_label.text = "Nobody on this board yet. Win an online match to be the first!" if scope != LeaderboardRules.SCOPE_AROUND_ME \
			else "You're not on this board yet. Play an online match!"
	else:
		status_label.text = "%s players on this board" % LeaderboardRules.group(total) if total > 0 else ""


func _on_failed(id: StringName, s: int) -> void:
	if id == board and s == scope:
		status_label.text = "Steam didn't answer. Try again in a moment."


func _draw_rows() -> void:
	if rows_box == null:
		return
	for c: Node in rows_box.get_children():
		c.queue_free()
	for r: Dictionary in _rows:
		rows_box.add_child(_row(r))


func _row(r: Dictionary) -> Control:
	var me: bool = bool(r["me"])
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"RowPanelHighlight" if me else &"RowPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	panel.add_child(h)
	var rank := Label.new()
	rank.text = "#%d" % int(r["rank"])
	rank.custom_minimum_size.x = 80
	var rank_n: int = int(r["rank"])
	rank.add_theme_color_override(&"font_color", Palette.VIP_GOLD if rank_n <= 3 else CosmeticsPanel.MUTED)
	h.add_child(rank)
	var who := Label.new()
	var n: String = SteamSvc.get_persona_name() if me else SteamSvc.boards.name_of(int(r["steam_id"]))
	who.text = (n if n != "" else "...") + ("  (you)" if me else "")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_theme_color_override(&"font_color", Palette.VIP_GOLD if me else Palette.CREAM)
	h.add_child(who)
	var score := Label.new()
	score.text = LeaderboardRules.format_score(board, int(r["score"]))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.custom_minimum_size.x = 160
	score.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if bool(LeaderboardRules.board(board).get("money", false)) else Palette.CREAM)
	h.add_child(score)
	return panel


func _exit_tree() -> void:
	if _dim != null and _dim.get_parent() == null:
		_dim.free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
