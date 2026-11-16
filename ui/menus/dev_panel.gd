class_name DevPanel
extends PanelContainer
## The Dev Dashboard (`DevMode`; Patrick only), opened by the small "</>" button in the main menu's
## bottom-right corner (`DevButton`, Patrick 2026-11-16: "Devmode kleiner button unten rechts. Auch
## menu für das Dev dashboard besser"). A framed overlay over the dimmed menu like the leaderboards:
##
## first column: PROGRESS (level and Coins big, set either to any number, Daily Spin and tutorial
## again) and PRACTICE (dummies stepper and the big PRACTICE CASINO with the dev tools on, pause
## menu: DEV TOOLS); second column: COSMETICS (own everything on/off, remove one piece or all,
## forget achievements, Patrick 2026-11-16: "The dev mode should also be able to remove skins etc
## ... and level and stuff") and RESET (stats, the whole profile);
## right, the MINIGAMES card: a picture tile per minigame that drops straight into it.
## BACK or Esc closes it.

## BACK / Esc.
signal closed
## A practice match was chosen: the main menu starts it with these settings.
signal practice_requested(settings: Dictionary)

const TILE_PICTURE: Vector2 = Vector2(200, 112)
const MAX_DUMMIES: int = 7

var dummies: SpinBox
## On: the developer owns every cosmetic. Off: plays as a normal player (`DevMode.set_as_player`).
var own_all_toggle: CheckButton
var level_spin: SpinBox
var coins_spin: SpinBox
## The pieces REMOVE can take (`DevMode.removable`), and the ids in its order.
var remove_pick: OptionButton
var _remove_ids: Array[StringName] = []
var remove_button: Button
## "Level 12   ·   48,000 Coins" (tests and the look-dev shot read it).
var profile_line: Label
var level_value: Label
var coins_value: Label
## Minigame id -> its tile button.
var minigame_tiles: Dictionary = {}
var casino_button: Button
var back_button: Button
var _dim: ColorRect


func _ready() -> void:
	name = "Dev"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 56
	offset_right = -56
	offset_top = 40
	offset_bottom = -40
	visible = false
	add_theme_stylebox_override(&"panel", LevelPassPanel._panel_style())
	_dim = ColorRect.new()
	_dim.name = "DevDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.05, 0.03, 0.03, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	add_child(v)
	# Header: title left, the achievements note right.
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 16)
	v.add_child(top)
	var title := Label.new()
	title.name = "Title"
	title.text = "DEV DASHBOARD"
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var badge := Label.new()
	badge.text = "Steam achievements are off for a run once you use anything here"
	badge.theme_type_variation = &"SmallLabel"
	badge.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.55))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(badge)
	v.add_child(HSeparator.new())
	# Body.
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 400
	left.add_theme_constant_override(&"separation", 20)
	body.add_child(left)
	left.add_child(_build_profile())
	var practice := _build_practice()
	practice.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(practice)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size.x = 400
	mid.add_theme_constant_override(&"separation", 20)
	body.add_child(mid)
	var cos := _build_cosmetics()
	cos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(cos)
	mid.add_child(_build_reset())
	var games := _build_minigames()
	games.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(games)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(260, 44)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(close)
	v.add_child(back_button)
	ProfileManager.changed.connect(_refresh)


func _build_profile() -> Control:
	var card := _card("PROGRESS")
	var box: VBoxContainer = card.get_child(0)
	profile_line = Label.new()
	profile_line.name = "ProfileLine"
	profile_line.visible = false  # the two stats below say it; kept for tests and tools
	box.add_child(profile_line)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 12)
	box.add_child(stats)
	level_value = _stat(stats, "LEVEL", Palette.VIP_GOLD)
	coins_value = _stat(stats, "COINS", Palette.COIN_GOLD)
	var lrow := _row(box, "Level")
	level_spin = _spin(lrow, "LevelSpin", 1, ProfileManager.profile.config.max_level)
	_button(lrow, "SET", func() -> void: DevMode.set_level(int(level_spin.value))).name = "SetLevel"
	_button(lrow, "+1", func() -> void: DevMode.set_level(ProfileManager.profile.level + 1)).name = "Level1"
	var crow := _row(box, "Coins")
	coins_spin = _spin(crow, "CoinsSpin", 0, PlayerProfile.MAX_COINS)
	coins_spin.step = 1000
	_button(crow, "SET", func() -> void: DevMode.set_coins(int(coins_spin.value))).name = "SetCoins"
	_button(crow, "+10K", func() -> void: DevMode.add_coins(10000)).name = "Coins"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	box.add_child(grid)
	# The local Daily Spin timer only: with Steam, Steam still allows one spin per window.
	_button(grid, "DAILY SPIN AGAIN", func() -> void: ProfileManager.mark_daily_spin(0)).name = "DailyReset"
	_button(grid, "SHOW TUTORIAL AGAIN", func() -> void:
		Settings.set_value("tutorial", "seen", false)
		Settings.save()).name = "ResetTutorial"
	return card


func _build_cosmetics() -> Control:
	var card := _card("COSMETICS")
	var box: VBoxContainer = card.get_child(0)
	own_all_toggle = CheckButton.new()
	own_all_toggle.name = "OwnAll"
	own_all_toggle.text = "Own every cosmetic"
	own_all_toggle.tooltip_text = "Off: you play as a normal player until the game closes (no dev unlock, Steam inventory hidden), so the shop, COLLECT and removed pieces behave like for everyone else."
	own_all_toggle.toggled.connect(func(on: bool) -> void: DevMode.set_as_player(not on))
	box.add_child(own_all_toggle)
	var note := _muted("Turn it off to see what you really own. Removing needs it off to show.")
	box.add_child(note)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override(&"separation", 8)
	box.add_child(rrow)
	remove_pick = OptionButton.new()
	remove_pick.name = "RemovePick"
	remove_pick.custom_minimum_size = Vector2(0, 46)
	remove_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_pick.clip_text = true
	rrow.add_child(remove_pick)
	remove_button = _button(rrow, "REMOVE", func() -> void:
		var i: int = remove_pick.selected
		if i >= 0 and i < _remove_ids.size():
			DevMode.remove_cosmetic(_remove_ids[i]))
	remove_button.name = "Remove"
	remove_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	remove_button.custom_minimum_size.x = 120
	_button(box, "REMOVE ALL BOUGHT & COLLECTED", func() -> void:
		ConfirmDialog.ask(self, "REMOVE ALL?", "Every piece you bought, collected or won goes. Free and level pieces stay.", "REMOVE ALL", DevMode.remove_all_cosmetics)).name = "RemoveAll"
	_button(box, "FORGET ACHIEVEMENTS (COLLECT)", DevMode.clear_achievements).name = "ClearAchievements"
	box.add_child(_muted("Until the next start, when Steam brings them back. Steam itself is not changed."))
	return card


func _build_reset() -> Control:
	var card := _card("RESET")
	var box: VBoxContainer = card.get_child(0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 8)
	box.add_child(grid)
	_button(grid, "STATS", DevMode.reset_stats).name = "ResetStats"
	var whole := _button(grid, "WHOLE PROFILE", func() -> void:
		ConfirmDialog.ask(self, "RESET PROFILE?", "Level 1, no Coins, nothing bought or collected, no stats. Saved at once.", "RESET", DevMode.reset_profile))
	whole.name = "ResetProfile"
	whole.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	return card


func _build_practice() -> Control:
	var card := _card("PRACTICE")
	var box: VBoxContainer = card.get_child(0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	box.add_child(row)
	var dl := Label.new()
	dl.text = "Dummies at the tables"
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dl)
	dummies = SpinBox.new()
	dummies.name = "Dummies"
	dummies.min_value = 0
	dummies.max_value = MAX_DUMMIES
	dummies.value = 3
	dummies.alignment = HORIZONTAL_ALIGNMENT_CENTER
	dummies.custom_minimum_size = Vector2(120, 48)
	row.add_child(dummies)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	casino_button = _button(box, "PRACTICE CASINO", func() -> void:
		practice_requested.emit(DevMode.casino_settings(int(dummies.value))))
	casino_button.name = "Casino"
	casino_button.tooltip_text = "A practice casino with the dummies and the dev tools on (pause menu: DEV TOOLS)."
	casino_button.theme_type_variation = &"ActionButton"
	casino_button.custom_minimum_size = Vector2(0, 60)
	var hint := _muted("Dev tools in the pause menu: money, items, a minigame now")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	return card


func _build_minigames() -> Control:
	var card := _card("PLAY A MINIGAME NOW")
	var box: VBoxContainer = card.get_child(0)
	var sub := Label.new()
	sub.text = "Straight into it, with the dummies"
	sub.theme_type_variation = &"SmallLabel"
	sub.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.55))
	box.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Minigames"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	scroll.add_child(grid)
	for id: Variant in Registry.minigames:
		var def: MinigameDefinition = Registry.minigames[id]
		var tile := Button.new()
		tile.name = String(def.id)
		tile.custom_minimum_size = Vector2(TILE_PICTURE.x * 0.8, TILE_PICTURE.y + 48)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tooltip_text = def.rules_text
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		SettingsPanel.style_tab(tile)
		var tv := VBoxContainer.new()
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_theme_constant_override(&"separation", 4)
		tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		tile.add_child(tv)
		var pic := TextureRect.new()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.custom_minimum_size = Vector2(0, TILE_PICTURE.y)
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture = MinigameSelector.picture(def.id)
		tv.add_child(pic)
		var nl := Label.new()
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.text = def.display_name
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tv.add_child(nl)
		var mid: StringName = def.id
		tile.pressed.connect(func() -> void: practice_requested.emit(DevMode.minigame_settings(mid, int(dummies.value))))
		grid.add_child(tile)
		minigame_tiles[def.id] = tile
	return card


func open() -> void:
	var host: Node = get_parent()
	if host != null:
		if _dim.get_parent() == null:
			host.add_child(_dim)
		host.move_child(_dim, -1)
		host.move_child(self, -1)
		_dim.visible = true
	visible = true
	back_button.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	_refresh()
	casino_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_dim.visible = false
	closed.emit()


func _refresh() -> void:
	if profile_line == null:
		return
	var p: PlayerProfile = ProfileManager.profile
	var coins: String = DevMatchPanel._thousands(p.coins)
	profile_line.text = "Level %d   ·   %s Coins" % [p.level, coins]
	level_value.text = str(p.level)
	coins_value.text = coins
	level_spin.set_value_no_signal(p.level)
	coins_spin.set_value_no_signal(p.coins)
	own_all_toggle.set_pressed_no_signal(not DevMode.as_player())
	var keep: StringName = _remove_ids[remove_pick.selected] if remove_pick.selected >= 0 and remove_pick.selected < _remove_ids.size() else &""
	_remove_ids = DevMode.removable()
	remove_pick.clear()
	for id: StringName in _remove_ids:
		var d: CosmeticDef = p.shop.find(id)
		remove_pick.add_item("%s  (%s)" % [d.display_name, String(d.kind)] if d != null else String(id))
	if _remove_ids.is_empty():
		remove_pick.add_item("Nothing bought or collected")
		remove_pick.disabled = true
	else:
		remove_pick.disabled = false
		remove_pick.select(maxi(_remove_ids.find(keep), 0))
	remove_button.disabled = _remove_ids.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## A section card: dark felt-brown box with a thin gold rim and a small gold heading.
## Its first child is the VBoxContainer to fill.
func _card(heading: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = heading.capitalize().replace(" ", "") + "Card"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2C1E1C")
	sb.border_color = Color(Palette.WARM_GOLD, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(18)
	card.add_theme_stylebox_override(&"panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	card.add_child(box)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = &"HeadingLabel"
	h.add_theme_font_size_override(&"font_size", 24)
	h.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	box.add_child(h)
	return card


## A big number with its caption on a darker plate ("LEVEL 12", "COINS 48,000").
func _stat(parent: Control, caption: String, col: Color) -> Label:
	var plate := PanelContainer.new()
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1A1211")
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	plate.add_theme_stylebox_override(&"panel", sb)
	parent.add_child(plate)
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override(&"separation", 0)
	plate.add_child(col_box)
	var cap := Label.new()
	cap.text = caption
	cap.theme_type_variation = &"SmallLabel"
	cap.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.55))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_box.add_child(cap)
	var val := Label.new()
	val.name = caption.capitalize() + "Value"
	val.add_theme_font_size_override(&"font_size", 34)
	val.add_theme_color_override(&"font_color", col)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_box.add_child(val)
	return val


## A labelled row: "Level  [spin] [SET] [+1]".
func _row(parent: Control, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size.x = 64
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


func _spin(parent: Control, node_name: String, lo: int, hi: int) -> SpinBox:
	var sp := SpinBox.new()
	sp.name = node_name
	sp.min_value = lo
	sp.max_value = hi
	sp.alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp.custom_minimum_size = Vector2(0, 46)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sp)
	return sp


func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SmallLabel"
	l.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.55))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
