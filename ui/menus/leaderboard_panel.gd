class_name LeaderboardPanel
extends PanelContainer
## LEADERBOARDS and MY STATS (Patrick 2026-11-16: "globale leaderboards (Most money made in a single
## lobby). Einfach lobby übergreifend ... Es gibt auch eigene statistiken game übergreifend"),
## opened by the trophy in the main menu's bottom-right corner (`TrophyButton`).
##
## Reworked in 0.10.53 (Patrick: "make the leaderboard overall visually better. rework the whole
## thing", "show current skin in leaderboard", "Steam link"): a walnut-and-brass table panel
## (`TableSkin`), the boards and GLOBAL / FRIENDS / MY RANK as tabs on top, a podium for the top
## three (each bean in the look its player last uploaded, `LeaderboardRules.skin_from_details`, on a
## lacquer step with its medal), the rest as rows with a small live bean, and your own place
## pinned at the bottom. Any player opens their Steam profile in the overlay. FRIENDS counts 1, 2, 3
## among your friends ("warum ist hier 2 und 3 und keine 1"), the global rank stays beside it.
## MY STATS: the lifetime numbers from the local profile in four cards.

signal closed

const PAGE_BOARDS: int = 0
const PAGE_STATS: int = 1
const SCOPES: Array[Dictionary] = [
	{"scope": LeaderboardRules.SCOPE_GLOBAL, "text": "GLOBAL"},
	{"scope": LeaderboardRules.SCOPE_FRIENDS, "text": "FRIENDS"},
	{"scope": LeaderboardRules.SCOPE_AROUND_ME, "text": "MY RANK"},
]
## Short explanations under the tabs (Patrick asked what AROUND ME was).
const SCOPE_HINTS: Dictionary = {
	LeaderboardRules.SCOPE_GLOBAL: "The best players worldwide.",
	LeaderboardRules.SCOPE_FRIENDS: "You and your Steam friends.",
	LeaderboardRules.SCOPE_AROUND_ME: "Your place on the global board and the players just above and below you.",
}
## MY STATS cards: title -> the `stat_lines` labels in it.
const STAT_GROUPS: Array[Dictionary] = [
	{"title": "MATCHES", "lines": ["Matches played", "Online matches", "Matches won", "Online wins", "Win rate", "Podium finishes (top 3)"]},
	{"title": "MONEY", "lines": ["Best online match", "Online winnings", "Total winnings", "Total losses", "Biggest single win", "Biggest bet", "Jackpot money won"]},
	{"title": "AT THE TABLES", "lines": ["Hands played", "Minigames won", "Quiz points", "Level"]},
	{"title": "CHAOS", "lines": ["Knockouts dealt", "Times knocked out", "Thrown out by security"]},
]
## Podium order on screen: 2nd, 1st, 3rd.
const PODIUM_ORDER: Array[int] = [2, 1, 3]
## Step heights by place (index 0 unused).
const STEP_HEIGHTS: Array[float] = [0.0, 104.0, 80.0, 62.0]

var page_buttons: Array[Button] = []
var board_buttons: Dictionary[StringName, Button] = {}
var scope_buttons: Array[Button] = []
var boards_page: Control
var stats_page: Control
var podium: HBoxContainer
var rows_box: VBoxContainer
var status_label: Label
var hint_label: Label
var mine_bar: PanelContainer
var stats_grid: GridContainer
## Stat label -> its value label (MY STATS).
var stat_values: Dictionary[String, Label] = {}
var back_button: Button
var title_label: Label
var board: StringName = LeaderboardRules.BEST_MATCH_MONEY
var scope: int = LeaderboardRules.SCOPE_GLOBAL
## The rows on show (for name refreshes), with `place` (`LeaderboardRules.with_places`).
var _rows: Array[Dictionary] = []
## The local player's own entry on `board` ({} = not on it) and the board's size.
var _mine: Dictionary = {}
var _mine_total: int = 0
var _mine_known: bool = false
var _dim: ColorRect
var _scroll: ScrollContainer
## The live beans: on the podium (place -> view) and in the rows (only the ones on screen render).
var _podium_beans: Dictionary[int, BeanPreviewView] = {}
var _row_beans: Array[BeanPreviewView] = []
var _emote_wait: float = 1.2
var _live_wait: float = 0.0
## What the beans do now and then: the winner celebrates, the rest wave and cheer.
const WINNER_EMOTES: Array[StringName] = [&"dance", &"default_dance", &"thumbs_up"]
const OTHER_EMOTES: Array[StringName] = [&"wave", &"thumbs_up", &"laugh", &"gg", &"taunt"]


func _ready() -> void:
	name = "Leaderboards"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 56
	offset_right = -56
	offset_top = 36
	offset_bottom = -36
	visible = false
	add_theme_stylebox_override(&"panel", TableSkin.panel_box())
	draw.connect(TableSkin.draw_frame.bind(self))
	_dim = ColorRect.new()
	_dim.name = "LeaderboardsDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.05, 0.03, 0.03, 0.78)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	v.add_child(top)
	title_label = TableSkin.label("LEADERBOARDS", 46, Palette.CREAM)
	title_label.add_theme_font_override(&"font", TableSkin.black_font())
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	v.add_child(DecoRule.new(true, 0.0))
	boards_page = _build_boards()
	boards_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(boards_page)
	stats_page = _build_stats()
	stats_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stats_page)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.custom_minimum_size = Vector2(260, 46)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	TableSkin.style_button(back_button, &"ghost", 22)
	back_button.pressed.connect(close)
	v.add_child(back_button)
	SteamSvc.boards.entries_received.connect(_on_entries)
	SteamSvc.boards.entries_failed.connect(_on_failed)
	SteamSvc.boards.mine_received.connect(_on_mine)
	SteamSvc.boards.name_ready.connect(func(_id: int) -> void: _draw_rows())
	show_page(PAGE_BOARDS)


# --- Building ------------------------------------------------------------------------------------

func _build_boards() -> Control:
	var body := VBoxContainer.new()
	body.name = "BoardsPage"
	body.add_theme_constant_override(&"separation", 8)
	# The boards (left) and the scopes (right) as two rows of tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 8)
	body.add_child(tabs)
	var bgroup := ButtonGroup.new()
	for b: Dictionary in LeaderboardRules.BOARDS:
		var id: StringName = b["id"]
		var btn := Button.new()
		btn.name = "Board" + String(id).capitalize().replace(" ", "")
		btn.text = str(b["title"]).to_upper()
		btn.toggle_mode = true
		btn.button_group = bgroup
		btn.custom_minimum_size = Vector2(0, 46)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		SettingsPanel.style_tab(btn)
		btn.pressed.connect(select_board.bind(id))
		tabs.add_child(btn)
		board_buttons[id] = btn
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	tabs.add_child(gap)
	var sgroup := ButtonGroup.new()
	for i: int in SCOPES.size():
		var sb := Button.new()
		sb.name = "Scope" + str(SCOPES[i]["text"]).capitalize().replace(" ", "")
		sb.text = str(SCOPES[i]["text"])
		sb.toggle_mode = true
		sb.button_group = sgroup
		sb.custom_minimum_size = Vector2(130, 46)
		TableSkin.style_button(sb, &"ghost", 20)
		sb.pressed.connect(select_scope.bind(int(SCOPES[i]["scope"])))
		tabs.add_child(sb)
		scope_buttons.append(sb)
	hint_label = TableSkin.label("", 17, TableSkin.TEXT_MUTED)
	hint_label.name = "Hint"
	hint_label.add_theme_constant_override(&"outline_size", 0)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint_label)
	# The podium and the rows below it scroll together; your own place stays pinned under them.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(list)
	podium = HBoxContainer.new()
	podium.name = "Podium"
	podium.alignment = BoxContainer.ALIGNMENT_CENTER
	podium.add_theme_constant_override(&"separation", 18)
	podium.draw.connect(_draw_glow)
	list.add_child(podium)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override(&"separation", 4)
	list.add_child(rows_box)
	status_label = TableSkin.label("", 20, TableSkin.TEXT_MUTED)
	status_label.name = "Status"
	status_label.add_theme_constant_override(&"outline_size", 0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(status_label)
	mine_bar = PanelContainer.new()
	mine_bar.name = "Mine"
	var mb: StyleBoxFlat = TableSkin.band_box(Color(Palette.VIP_BURGUNDY, 0.92), Palette.VIP_GOLD, 12)
	mb.set_border_width_all(2)
	mb.content_margin_top = 6
	mb.content_margin_bottom = 6
	mine_bar.add_theme_stylebox_override(&"panel", mb)
	body.add_child(mine_bar)
	return body


func _build_stats() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "StatsPage"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override(&"margin_right", 32)  # room for the scrollbar
	scroll.add_child(margin)
	stats_grid = GridContainer.new()
	stats_grid.name = "Stats"
	stats_grid.columns = 2
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override(&"h_separation", 18)
	stats_grid.add_theme_constant_override(&"v_separation", 18)
	margin.add_child(stats_grid)
	for g: Dictionary in STAT_GROUPS:
		var card := PanelContainer.new()
		card.name = "Card" + str(g["title"]).capitalize().replace(" ", "")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb: StyleBoxFlat = TableSkin.felt_box(12, 14.0)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		card.add_theme_stylebox_override(&"panel", sb)
		stats_grid.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override(&"separation", 4)
		card.add_child(cv)
		cv.add_child(TableSkin.caption(str(g["title"])))
		for line: String in g["lines"]:
			var h := HBoxContainer.new()
			cv.add_child(h)
			var l: Label = TableSkin.label(line, 19, Color(Palette.CREAM, 0.78))
			l.add_theme_constant_override(&"outline_size", 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
			var val: Label = TableSkin.label("0", 24, Palette.VIP_GOLD, true)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(val)
			stat_values[line] = val
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
	for line: Array in stat_lines(ProfileManager.profile):
		var val: Label = stat_values.get(str(line[0]), null)
		if val != null:
			val.text = str(line[1])


# --- Opening and switching ----------------------------------------------------------------------

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
	# Your current look goes up with your bests, so the board shows the outfit you wear now.
	SteamSvc.submit_profile_bests()
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
	_mine = {}
	_mine_known = false
	_mine_total = 0
	_refresh()
	if SteamSvc.boards.available():
		SteamSvc.boards.download_mine(board)


func select_scope(s: int) -> void:
	scope = s
	_refresh()


func _refresh() -> void:
	for i: int in SCOPES.size():
		scope_buttons[i].set_pressed_no_signal(int(SCOPES[i]["scope"]) == scope)
	hint_label.text = "%s  %s" % [str(LeaderboardRules.board(board).get("hint", "")), str(SCOPE_HINTS.get(scope, ""))]
	_rows = []
	_draw_rows()
	_draw_mine()
	if not SteamSvc.boards.available():
		status_label.text = "Leaderboards need Steam. Start the game from Steam to see them."
		return
	status_label.text = "Loading..."
	SteamSvc.boards.download(board, scope)


func _on_entries(id: StringName, s: int, rows: Array[Dictionary], total: int) -> void:
	if id != board or s != scope:
		return
	_rows = LeaderboardRules.with_places(rows, scope)
	_draw_rows()
	if rows.is_empty():
		status_label.text = "Nobody on this board yet. Win an online match to be the first!" if scope != LeaderboardRules.SCOPE_AROUND_ME \
			else "You're not on this board yet. Finish an online match with at least two players."
	elif scope == LeaderboardRules.SCOPE_GLOBAL and total > rows.size():
		status_label.text = "Top %d of %s players" % [rows.size(), LeaderboardRules.group(total)]
	else:
		status_label.text = ""


func _on_failed(id: StringName, s: int) -> void:
	if id == board and s == scope:
		status_label.text = "Steam didn't answer. Try again in a moment."


func _on_mine(id: StringName, row: Dictionary, total: int) -> void:
	if id != board:
		return
	_mine = row
	_mine_total = total
	_mine_known = true
	_draw_mine()


# --- Drawing -------------------------------------------------------------------------------------

func _draw_rows() -> void:
	if rows_box == null:
		return
	for c: Node in podium.get_children():
		c.queue_free()
	for c: Node in rows_box.get_children():
		c.queue_free()
	_podium_beans.clear()
	_row_beans.clear()
	_live_wait = 0.0
	# The podium: the first three places (not on MY RANK, which starts somewhere in the middle).
	var top: Dictionary = {}
	var rest: Array[Dictionary] = []
	for r: Dictionary in _rows:
		var place: int = int(r["place"])
		if scope != LeaderboardRules.SCOPE_AROUND_ME and place <= 3 and not top.has(place):
			top[place] = r
		else:
			rest.append(r)
	podium.visible = not top.is_empty()
	if podium.visible:
		for place: int in PODIUM_ORDER:
			podium.add_child(_podium_spot(place, top.get(place, {})))
	for r: Dictionary in rest:
		rows_box.add_child(_row(r))


## A warm spotlight glow behind the winner (no neon: soft gold, very low alpha).
func _draw_glow() -> void:
	var c := Vector2(podium.size.x * 0.5, podium.size.y * 0.42)
	for i: int in 24:
		podium.draw_circle(c, 40.0 + 10.0 * i, Color(Palette.VIP_GOLD, 0.012))


## One podium spot: the bean in its look, the medal, name and score on a lacquer step.
func _podium_spot(place: int, r: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.name = "Place%d" % place
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override(&"separation", 2)
	col.custom_minimum_size.x = 250 if place == 1 else 220
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	if r.is_empty():
		var none: Label = TableSkin.label("-", 24, TableSkin.TEXT_MUTED, true)
		col.add_child(none)
	else:
		var me: bool = bool(r["me"])
		var pic_h: float = 190.0 if place == 1 else 160.0
		var btn := _profile_button(r)
		btn.custom_minimum_size = Vector2(pic_h * 0.8, pic_h)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(btn)
		var bean: BeanPreviewView = _bean(r, false)
		bean.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(bean)
		_podium_beans[place] = bean
		var who: Label = TableSkin.label(_name_of(r), 24 if place == 1 else 21, Palette.VIP_GOLD if me else Palette.CREAM, true)
		who.clip_text = true
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		who.custom_minimum_size.x = col.custom_minimum_size.x
		col.add_child(who)
		var score: Label = TableSkin.label(LeaderboardRules.format_score(board, int(r["score"])), 30 if place == 1 else 26, _score_color(), true)
		score.add_theme_font_override(&"font", TableSkin.black_font())
		col.add_child(score)
		if scope == LeaderboardRules.SCOPE_FRIENDS:
			var g: Label = TableSkin.label("#%s global" % LeaderboardRules.group(int(r["rank"])), 15, TableSkin.TEXT_MUTED)
			g.add_theme_constant_override(&"outline_size", 0)
			col.add_child(g)
	var step := PodiumStep.new()
	step.place = place
	step.custom_minimum_size = Vector2(col.custom_minimum_size.x, STEP_HEIGHTS[place])
	col.add_child(step)
	return col


## One row below the podium: medal coin, bean portrait, name (global rank on FRIENDS), score.
func _row(r: Dictionary) -> Control:
	var me: bool = bool(r["me"])
	var btn: Button = _profile_button(r)
	btn.custom_minimum_size.y = 64
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var face: Color = Color(Palette.VIP_BURGUNDY, 0.55) if me else Color(TableSkin.WALNUT_LIGHT, 0.9)
	var rim: Color = Palette.VIP_GOLD if me else Color(TableSkin.BRASS, 0.28)
	var normal: StyleBoxFlat = TableSkin.band_box(face, rim, 10)
	normal.set_border_width_all(2 if me else 1)
	var hover: StyleBoxFlat = TableSkin.band_box(face.lightened(0.08), Palette.VIP_GOLD, 10)
	btn.add_theme_stylebox_override(&"normal", normal)
	btn.add_theme_stylebox_override(&"hover", hover)
	btn.add_theme_stylebox_override(&"pressed", hover)
	btn.add_theme_stylebox_override(&"hover_pressed", hover)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -18
	h.add_theme_constant_override(&"separation", 14)
	btn.add_child(h)
	var badge: PlaceBadge = PlaceBadge.make(int(r["place"]), 46.0)
	if int(r["place"]) > 99:
		badge.visible = false
		var num: Label = TableSkin.label("#" + LeaderboardRules.group(int(r["place"])), 20, TableSkin.BRASS, true)
		num.custom_minimum_size.x = 46
		h.add_child(num)
	h.add_child(badge)
	var bean: BeanPreviewView = _bean(r, true)
	bean.custom_minimum_size = Vector2(48, 58)
	h.add_child(bean)
	_row_beans.append(bean)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_theme_constant_override(&"separation", -4)
	h.add_child(names)
	var who: Label = TableSkin.label(_name_of(r) + ("   YOU" if me else ""), 23, Palette.VIP_GOLD if me else Palette.CREAM, true)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(who)
	if scope == LeaderboardRules.SCOPE_FRIENDS:
		var g: Label = TableSkin.label("#%s global" % LeaderboardRules.group(int(r["rank"])), 15, TableSkin.TEXT_MUTED)
		g.add_theme_constant_override(&"outline_size", 0)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		names.add_child(g)
	var score: Label = TableSkin.label(LeaderboardRules.format_score(board, int(r["score"])), 26, _score_color(), true)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.custom_minimum_size.x = 170
	h.add_child(score)
	return btn


## Your own place, pinned under the list.
func _draw_mine() -> void:
	if mine_bar == null:
		return
	for c: Node in mine_bar.get_children():
		c.queue_free()
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	mine_bar.add_child(h)
	var me_row: Dictionary = {"me": true, "steam_id": SteamSvc.get_steam_id(), "skin": {}}
	var bean: BeanPreviewView = _bean(me_row, true)
	bean.custom_minimum_size = Vector2(46, 54)
	h.add_child(bean)
	var you: Label = TableSkin.label("YOU", 22, Palette.VIP_GOLD, true)
	h.add_child(you)
	var text: Label = TableSkin.label("", 22, Palette.CREAM, true)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(text)
	var score: Label = TableSkin.label("", 28, _score_color(), true)
	score.add_theme_font_override(&"font", TableSkin.black_font())
	h.add_child(score)
	if not _steam_on():
		text.text = "Start the game from Steam to see your place."
	elif not _mine_known:
		text.text = "Looking up your place..."
	elif _mine.is_empty():
		text.text = "Not on this board yet. Finish an online match with at least two players."
	else:
		text.text = "#%s of %s players" % [LeaderboardRules.group(int(_mine["rank"])), LeaderboardRules.group(maxi(_mine_total, int(_mine["rank"])))]
		score.text = LeaderboardRules.format_score(board, int(_mine["score"]))


func _profile_button(r: Dictionary) -> Button:
	var btn := Button.new()
	var clear := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		btn.add_theme_stylebox_override(st, clear)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "Open Steam profile"
	btn.add_theme_stylebox_override(&"focus", _focus_ring())
	var sid: int = int(r.get("steam_id", 0))
	btn.pressed.connect(func() -> void: SteamSvc.boards.open_profile(sid))
	return btn


func _focus_ring() -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Palette.VIP_GOLD
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(12)
	ring.set_expand_margin_all(2)
	ring.anti_aliasing = true
	return ring


## The look of a row ({color, outfit wire}): your own current look, else the look the player
## uploaded; a plain bean in a colour from their Steam ID when they never uploaded one.
func _look(r: Dictionary) -> Dictionary:
	if bool(r.get("me", false)):
		var p: PlayerProfile = ProfileManager.profile
		return {"color": p.preferred_color if p.preferred_color >= 0 else 0, "outfit": p.outfit_wire()}
	var skin: Dictionary = r.get("skin", {})
	if skin.is_empty():
		return {"color": absi(int(r.get("steam_id", 0))) % Cosmetics.SLOT_COLORS, "outfit": PackedStringArray()}
	return skin


## A live bean in the row's look (Patrick 2026-11-17: "Animated beans on the leaderboard ... Use
## self rendered"): the real `AvatarVisuals` in its own little viewport, swaying and blinking,
## now and then waving or dancing (`_tick_emotes`). `portrait`: head and shoulders.
func _bean(r: Dictionary, portrait: bool) -> BeanPreviewView:
	var look: Dictionary = _look(r)
	var v: BeanPreviewView = BeanPreviewView.make(Palette.player_color(int(look["color"])))
	v.portrait = portrait
	v.outfit = Cosmetics.outfit_dict(look["outfit"])
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _name_of(r: Dictionary) -> String:
	var n: String = SteamSvc.get_persona_name() if bool(r["me"]) else SteamSvc.boards.name_of(int(r["steam_id"]))
	return n if n != "" else "..."


## Whether Steam's boards are there (a look-dev scene says yes without Steam).
func _steam_on() -> bool:
	return SteamSvc.boards.available()


func _score_color() -> Color:
	return Palette.MONEY_GREEN if bool(LeaderboardRules.board(board).get("money", false)) else Palette.CREAM


func _process(delta: float) -> void:
	if not visible or not boards_page.visible:
		return
	_live_wait -= delta
	if _live_wait <= 0.0:
		_live_wait = 0.25
		_update_live_rows()
	_emote_wait -= delta
	if _emote_wait <= 0.0:
		_emote_wait = randf_range(1.6, 3.2)
		_tick_emotes()


## Only the row beans inside the scroll area render (a board has up to 50 rows).
func _update_live_rows() -> void:
	var view: Rect2 = _scroll.get_global_rect()
	for b: BeanPreviewView in _row_beans:
		if is_instance_valid(b) and b.is_inside_tree():
			b.set_live(view.intersects(b.get_global_rect()))


## Now and then one bean emotes: the winner dances most of the time, the others wave or cheer.
func _tick_emotes() -> void:
	var first: BeanPreviewView = _podium_beans.get(1, null)
	if first != null and is_instance_valid(first) and first.visuals != null and not first.visuals.is_emoting() and randf() < 0.55:
		first.visuals.emote(WINNER_EMOTES[randi() % WINNER_EMOTES.size()])
		return
	var pool: Array[BeanPreviewView] = []
	for place: int in [2, 3]:
		var b: BeanPreviewView = _podium_beans.get(place, null)
		if b != null:
			pool.append(b)
	var view: Rect2 = _scroll.get_global_rect()
	for b: BeanPreviewView in _row_beans:
		if is_instance_valid(b) and view.intersects(b.get_global_rect()):
			pool.append(b)
	pool.shuffle()
	for b: BeanPreviewView in pool:
		if is_instance_valid(b) and b.visuals != null and not b.visuals.is_emoting():
			b.visuals.emote(OTHER_EMOTES[randi() % OTHER_EMOTES.size()])
			return


func _exit_tree() -> void:
	if _dim != null and _dim.get_parent() == null:
		_dim.free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


## A podium step: burgundy lacquer with a gold top edge, a brass band and the place's medal coin.
class PodiumStep:
	extends Control

	var place: int = 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge: PlaceBadge = PlaceBadge.make(place, 48.0)
		add_child(badge)
		badge.size = Vector2(48.0, 48.0)
		badge.position = Vector2(size.x * 0.5 - 24.0, 8.0)
		resized.connect(func() -> void: badge.position = Vector2(size.x * 0.5 - 24.0, 8.0))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var body := StyleBoxFlat.new()
		body.bg_color = Palette.VIP_BURGUNDY.darkened(0.1 * (place - 1))
		body.corner_radius_top_left = 8
		body.corner_radius_top_right = 8
		body.border_color = Palette.VIP_GOLD if place == 1 else TableSkin.BRASS
		body.border_width_top = 3
		body.shadow_color = Color(0, 0, 0, 0.45)
		body.shadow_size = 8
		body.anti_aliasing = true
		draw_style_box(body, r)
		# Lacquer sheen and a brass band near the foot.
		draw_rect(Rect2(Vector2(6, 5), Vector2(size.x - 12, 3)), Color(1, 1, 1, 0.08))
		if size.y > 30.0:
			draw_rect(Rect2(Vector2(0, size.y - 10), Vector2(size.x, 3)), Color(TableSkin.BRASS, 0.6))
