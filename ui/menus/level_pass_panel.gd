class_name LevelPassPanel
extends PanelContainer
## The level pass (Patrick 2026-11-15: "level click opens menu with all stuff that you get, like a
## season pass"): one card per level along a track you scroll sideways, each with the Coins that
## level pays (`ProgressionConfig.level_coins`: more every ten levels, a bonus every 5th, a big one
## every 10th) and the cosmetics it unlocks (`CosmeticDef.level`). Reached levels are ticked off,
## the next one is lit, later ones are dimmed. Clicking a cosmetic opens it in the shop. Opened by
## clicking the profile line on the main menu (`ProfileBadge.pressed`).

signal closed
## A cosmetic on the track was clicked (the menu opens the shop on it).
signal item_pressed(id: StringName)

const CARD: Vector2 = Vector2(176, 330)
const DONE := Color("#5BA36B")

var track: HBoxContainer
var scroll: ScrollContainer
var level_label: Label
var xp_label: Label
var xp_bar: ProgressBar
var back_button: Button
## Level -> its card.
var cards: Dictionary[int, PanelContainer] = {}
var _dim: ColorRect


func _ready() -> void:
	name = "LevelPass"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 56
	offset_right = -56
	offset_top = 40
	offset_bottom = -40
	visible = false
	add_theme_stylebox_override(&"panel", CosmeticsPanel._panel_style())
	_dim = ColorRect.new()
	_dim.name = "LevelPassDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.05, 0.03, 0.03, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 24)
	v.add_child(head)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "LEVEL PASS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var now := VBoxContainer.new()
	now.alignment = BoxContainer.ALIGNMENT_CENTER
	now.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(now)
	level_label = Label.new()
	level_label.theme_type_variation = &"HeadingLabel"
	level_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	now.add_child(level_label)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(320, 14)
	xp_bar.max_value = 1.0
	xp_bar.step = 0.0
	now.add_child(xp_bar)
	xp_label = Label.new()
	xp_label.theme_type_variation = &"SmallLabel"
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	now.add_child(xp_label)
	var hint := Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	hint.text = "Every match earns XP. Every level pays Coins, every 5th a bonus, every 10th a big one, and some unlock cosmetics for free. Free, no pass to buy."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	scroll = ScrollContainer.new()
	scroll.name = "Track"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	track = HBoxContainer.new()
	track.add_theme_constant_override(&"separation", 14)
	track.size_flags_vertical = Control.SIZE_EXPAND_FILL  # the cards run the full height
	scroll.add_child(track)
	var cfg: ProgressionConfig = ProgressionConfig.default()
	for lvl: int in range(2, cfg.max_level + 1):
		var card: PanelContainer = _card(lvl, cfg)
		track.add_child(card)
		cards[lvl] = card
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(240, 52)
	back_button.pressed.connect(close)
	bottom.add_child(back_button)
	ProfileManager.changed.connect(refresh)


## The cosmetics level `lvl` unlocks.
static func unlocks(lvl: int) -> Array[CosmeticDef]:
	var out: Array[CosmeticDef] = []
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.level == lvl:
			out.append(d)
	return out


func _card(lvl: int, cfg: ProgressionConfig) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Level%d" % lvl
	card.custom_minimum_size = CARD
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	card.add_child(v)
	var num := Label.new()
	num.name = "Num"
	num.theme_type_variation = &"HeadingLabel"
	num.text = "LV %d" % lvl
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	var items: Array[CosmeticDef] = unlocks(lvl)
	var mid := VBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override(&"separation", 4)
	v.add_child(mid)
	if items.is_empty():
		var big := CoinIcon.make(110.0 if lvl % 10 == 0 else (90.0 if lvl % 5 == 0 else 64.0))
		big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mid.add_child(big)
	for d: CosmeticDef in items:
		var b := Button.new()
		b.name = String(d.id)
		b.flat = true
		b.icon = CosmeticThumbnails.texture_for(d.id)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(0, 220.0 / float(items.size()))
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.tooltip_text = d.display_name
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func() -> void: item_pressed.emit(d.id))
		mid.add_child(b)
		var name_l := Label.new()
		name_l.theme_type_variation = &"SmallLabel"
		name_l.text = d.display_name.to_upper()
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.clip_text = true
		mid.add_child(name_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	v.add_child(row)
	var coins := Label.new()
	coins.name = "Coins"
	coins.theme_type_variation = &"HeadingLabel"
	coins.add_theme_color_override(&"font_color", Palette.COIN_GOLD)
	coins.text = "+%s" % Hud._thousands(cfg.level_coins(lvl))
	row.add_child(coins)
	var ci := CoinIcon.make(26.0)
	ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ci)
	var state := Label.new()
	state.name = "State"
	state.theme_type_variation = &"SmallLabel"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(state)
	return card


func refresh() -> void:
	if level_label == null:
		return
	var p: PlayerProfile = ProfileManager.profile
	level_label.text = "LEVEL %d" % p.level
	xp_bar.value = p.level_progress()
	var need: int = p.xp_needed()
	xp_label.text = "%d / %d XP to level %d" % [p.xp_into_level(), need, p.level + 1] if need > 0 else "MAX LEVEL"
	for lvl: int in cards:
		var card: PanelContainer = cards[lvl]
		var reached: bool = p.level >= lvl
		var next: bool = lvl == p.level + 1
		var milestone: bool = lvl % 5 == 0 or not unlocks(lvl).is_empty()
		var border: Color = Palette.VIP_GOLD if next else (DONE if reached else Color(Palette.WARM_GOLD, 0.7 if milestone else 0.3))
		var fill: Color = Color("#3A2626") if next else (Color("#24302A") if reached else (Color("#2E1C1C") if milestone else Color("#261919")))
		card.add_theme_stylebox_override(&"panel", CosmeticsPanel._box(fill, border, 4 if next else (3 if milestone else 2), 18, 14))
		card.modulate = Color.WHITE if reached or next else Color(1, 1, 1, 0.78)
		var state: Label = card.find_child("State", true, false) as Label
		state.text = "UNLOCKED" if reached else ("NEXT" if next else "")
		state.add_theme_color_override(&"font_color", DONE if reached else Palette.VIP_GOLD)


func open() -> void:
	refresh()
	var host: Node = get_parent()
	if host != null:
		if _dim.get_parent() == null:
			host.add_child(_dim)
		host.move_child(_dim, -1)
		host.move_child(self, -1)
		_dim.visible = true
	visible = true
	back_button.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	# The unlock pictures first (the shop's tiles can wait).
	var ids: Array[StringName] = []
	for lvl: int in cards:
		for d: CosmeticDef in unlocks(lvl):
			ids.append(d.id)
	ids.reverse()
	for id: StringName in ids:
		CosmeticThumbnails.texture_for(id, true)
	_scroll_to_current.call_deferred()
	back_button.grab_focus()


## Puts the next level's card near the left of the track (a few reached ones still in view).
func _scroll_to_current() -> void:
	var lvl: int = clampi(ProfileManager.profile.level + 1, 2, ProgressionConfig.default().max_level)
	var card: Control = cards.get(lvl, null)
	if card != null:
		scroll.scroll_horizontal = maxi(int(card.position.x - CARD.x * 1.5), 0)


func close() -> void:
	if not visible:
		return
	visible = false
	_dim.visible = false
	closed.emit()


func _exit_tree() -> void:
	if _dim != null and _dim.get_parent() == null:
		_dim.free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
