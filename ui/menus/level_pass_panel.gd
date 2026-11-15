class_name LevelPassPanel
extends PanelContainer
## The level pass (Patrick 2026-11-15: "level click opens menu with all stuff that you get, like a
## season pass"). Reworked the same day ("SUPER ugly stretched"): fixed-size reward cards that never
## stretch, standing on a track that runs sideways through every level (a numbered node per level,
## the line filled in gold up to where you are, the next stretch filled by your XP), and on the left
## a spotlight on the next cosmetic you unlock, turning on a bean. Every level pays Coins
## (`ProgressionConfig.level_coins`: more every ten levels, a bonus every 5th, a big one every 10th);
## some unlock cosmetics (`CosmeticDef.level`), a few of them only here (no price: the shop shows
## them but can't sell them). Clicking a cosmetic opens it in the shop. Opened by clicking the
## profile line on the main menu (`ProfileBadge.pressed`).

signal closed
## A cosmetic on the track was clicked (the menu opens the shop on it).
signal item_pressed(id: StringName)

## One level's column: the card and, under it, its stretch of the track.
const COLUMN: float = 212.0
const CARD: Vector2 = Vector2(192, 316)
const NODE_H: float = 64.0
const DONE := Color("#5BA36B")
const DARK := Color("#1A1010")

var track: HBoxContainer
var scroll: ScrollContainer
var level_label: Label
var xp_label: Label
var xp_bar: ProgressBar
var back_button: Button
## Level -> its card.
var cards: Dictionary[int, PanelContainer] = {}
## Level -> its node on the track.
var nodes: Dictionary[int, PassNode] = {}
## The spotlight: the next cosmetic reward on a turning bean.
var spot_preview: BeanPreviewView
var spot_name: Label
var spot_kind: Label
var spot_when: Label
var spot_button: Button
## The cosmetic the spotlight shows.
var spot_id: StringName = &""
var _dim: ColorRect


func _ready() -> void:
	name = "LevelPass"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 56
	offset_right = -56
	offset_top = 40
	offset_bottom = -40
	visible = false
	add_theme_stylebox_override(&"panel", _panel_style())
	_dim = ColorRect.new()
	_dim.name = "LevelPassDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.05, 0.03, 0.03, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	add_child(v)
	# Header: the title and season line; on the right where you are.
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 24)
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "LEVEL PASS"
	titles.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"SmallLabel"
	sub.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	sub.text = "Free for everyone. Every match earns XP, every level pays Coins, and some unlock cosmetics you can't buy anywhere else."
	titles.add_child(sub)
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
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	body.add_child(_build_spotlight())
	# Right: the track, centred in its space (never stretched to the full height).
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(right)
	var cap := Label.new()
	cap.theme_type_variation = &"SmallLabel"
	cap.text = "REWARDS"
	cap.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	right.add_child(cap)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override(&"panel", CosmeticsPanel._box(Color("#1C1212"), Color(Palette.WARM_GOLD, 0.25), 2, 22, 16))
	right.add_child(well)
	scroll = ScrollContainer.new()
	scroll.name = "Track"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	well.add_child(scroll)
	track = HBoxContainer.new()
	track.add_theme_constant_override(&"separation", 0)  # the track's line runs on unbroken
	scroll.add_child(track)
	var cfg: ProgressionConfig = ProgressionConfig.default()
	for lvl: int in range(2, cfg.max_level + 1):
		var col := VBoxContainer.new()
		col.name = "Column%d" % lvl
		col.custom_minimum_size.x = COLUMN
		col.add_theme_constant_override(&"separation", 8)
		track.add_child(col)
		var card: PanelContainer = _card(lvl, cfg)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(card)
		cards[lvl] = card
		var node := PassNode.new()
		node.level = lvl
		node.milestone = lvl % 5 == 0
		node.custom_minimum_size = Vector2(COLUMN, NODE_H)
		node.first = lvl == 2
		node.last = lvl == cfg.max_level
		col.add_child(node)
		nodes[lvl] = node
	var legend := Label.new()
	legend.theme_type_variation = &"SmallLabel"
	legend.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	legend.text = "Every 5th level pays a bonus, every 10th a big one. Click a cosmetic to see it in the shop."
	right.add_child(legend)
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


## The spotlight on the left: the next cosmetic reward on a turning bean, its name and when.
func _build_spotlight() -> PanelContainer:
	var spot := PanelContainer.new()
	spot.name = "Spotlight"
	spot.custom_minimum_size.x = 400
	spot.add_theme_stylebox_override(&"panel", CosmeticsPanel._stage_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	spot.add_child(col)
	var cap := Label.new()
	cap.theme_type_variation = &"SmallLabel"
	cap.text = "NEXT COSMETIC REWARD"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	col.add_child(cap)
	spot_preview = BeanPreviewView.make(Palette.player_color(0), Vector2(320, 260))
	spot_preview.interactive = true
	spot_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spot_preview.tooltip_text = "Drag to turn"
	col.add_child(spot_preview)
	spot_kind = Label.new()
	spot_kind.name = "SpotKind"
	spot_kind.theme_type_variation = &"SmallLabel"
	spot_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spot_kind.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	col.add_child(spot_kind)
	spot_name = Label.new()
	spot_name.name = "SpotName"
	spot_name.theme_type_variation = &"HeadingLabel"
	spot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(spot_name)
	spot_when = Label.new()
	spot_when.name = "SpotWhen"
	spot_when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spot_when.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	col.add_child(spot_when)
	spot_button = Button.new()
	spot_button.name = "SpotShop"
	spot_button.text = "SEE IN SHOP"
	spot_button.custom_minimum_size = Vector2(0, 48)
	spot_button.pressed.connect(func() -> void:
		if spot_id != &"":
			item_pressed.emit(spot_id))
	col.add_child(spot_button)
	return spot


## The cosmetics level `lvl` unlocks.
static func unlocks(lvl: int) -> Array[CosmeticDef]:
	var out: Array[CosmeticDef] = []
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.level == lvl:
			out.append(d)
	return out


## The first cosmetic reward above level `from`, null when none is left.
static func next_unlock(from: int) -> CosmeticDef:
	var best: CosmeticDef = null
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.level > from and (best == null or d.level < best.level):
			best = d
	return best


## A level's card, always CARD-sized: the cosmetics it unlocks (or a coin for a Coins-only level)
## and the Coins it pays.
func _card(lvl: int, cfg: ProgressionConfig) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Level%d" % lvl
	card.custom_minimum_size = CARD
	card.clip_contents = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var tag := Label.new()
	tag.name = "Tag"
	tag.theme_type_variation = &"SmallLabel"
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tag)
	var tick := Label.new()
	tick.name = "Tick"
	tick.theme_type_variation = &"SmallLabel"
	tick.text = "✔"
	tick.add_theme_color_override(&"font_color", DONE)
	top.add_child(tick)
	var items: Array[CosmeticDef] = unlocks(lvl)
	var mid := HBoxContainer.new()
	mid.name = "Rewards"
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override(&"separation", 2)
	v.add_child(mid)
	if items.is_empty():
		var big := CoinIcon.make(110.0 if lvl % 10 == 0 else (90.0 if lvl % 5 == 0 else 68.0))
		big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mid.add_child(big)
	var px: float = 168.0 if items.size() == 1 else 92.0
	for d: CosmeticDef in items:
		var b := Button.new()
		b.name = String(d.id)
		b.flat = true
		b.icon = CosmeticThumbnails.texture_for(d.id)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(px, px)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = d.display_name + ("  (level pass only)" if pass_only(d) else "")
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void: item_pressed.emit(d.id))
		mid.add_child(b)
	var name_l := Label.new()
	name_l.name = "Name"
	name_l.theme_type_variation = &"SmallLabel"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	if items.size() == 1:
		name_l.text = items[0].display_name.to_upper()
	elif items.size() > 1:
		name_l.text = "%d COSMETICS" % items.size()
	else:
		name_l.text = "BIG BONUS" if lvl % 10 == 0 else ("BONUS" if lvl % 5 == 0 else "COINS")
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	v.add_child(row)
	var coins := Label.new()
	coins.name = "Coins"
	coins.theme_type_variation = &"HeadingLabel"
	coins.add_theme_color_override(&"font_color", Palette.COIN_RED)
	coins.text = "+%s" % Hud._thousands(cfg.level_coins(lvl))
	row.add_child(coins)
	var ci := CoinIcon.make(24.0)
	ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ci)
	return card


## Only the level pass gives it: no Coins or Gold price.
static func pass_only(d: CosmeticDef) -> bool:
	return d.level > 0 and d.price <= 0 and d.gold <= 0


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
		var items: Array[CosmeticDef] = unlocks(lvl)
		var exclusive: bool = false
		for d: CosmeticDef in items:
			exclusive = exclusive or pass_only(d)
		var special: bool = lvl % 5 == 0 or not items.is_empty()
		var border: Color = Palette.VIP_GOLD if next else (DONE if reached else (Palette.COIN_GOLD if exclusive else Color(Palette.WARM_GOLD, 0.65 if special else 0.3)))
		var fill: Color = Color("#3A2626") if next else (Color("#22302A") if reached else (Color("#33241A") if exclusive else (Color("#2E1C1C") if special else Color("#261919"))))
		card.add_theme_stylebox_override(&"panel", CosmeticsPanel._box(fill, border, 4 if next else (3 if special else 2), 18, 12))
		card.modulate = Color.WHITE if reached or next else Color(1, 1, 1, 0.82)
		var tag: Label = card.find_child("Tag", true, false) as Label
		tag.text = "NEXT" if next else ("EXCLUSIVE" if exclusive else "")
		tag.add_theme_color_override(&"font_color", Palette.VIP_GOLD if next else Palette.COIN_GOLD)
		(card.find_child("Tick", true, false) as Label).visible = reached
		var node: PassNode = nodes[lvl]
		node.reached = reached
		node.next = next
		# The line from your level to the next fills with your XP: the first half out of your node,
		# the second half into the next one.
		var prog: float = p.level_progress()
		node.fill_in = 1.0 if reached else (clampf(prog * 2.0 - 1.0, 0.0, 1.0) if next else 0.0)
		node.fill_out = 1.0 if lvl < p.level else (clampf(prog * 2.0, 0.0, 1.0) if lvl == p.level else 0.0)
		node.queue_redraw()
	_refresh_spotlight(p)


func _refresh_spotlight(p: PlayerProfile) -> void:
	var d: CosmeticDef = next_unlock(p.level)
	spot_id = d.id if d != null else &""
	spot_button.visible = d != null
	var color: int = p.preferred_color if p.preferred_color >= 0 else 0
	if d == null:
		spot_kind.text = ""
		spot_name.text = "ALL UNLOCKED"
		spot_when.text = "Every cosmetic reward is yours."
		spot_preview.set_bean_color(Palette.player_color(color))
		spot_preview.set_outfit(p.outfit.duplicate())
		return
	var kind_title: String = str(CosmeticsPanel.KIND_TITLES.get(d.kind, "")).trim_suffix("S").replace("TROUSER", "TROUSERS")
	spot_kind.text = kind_title + ("  ·  LEVEL PASS ONLY" if pass_only(d) else "")
	spot_name.text = d.display_name.to_upper()
	var to_go: int = d.level - p.level
	spot_when.text = "AT LEVEL %d  ·  %d LEVEL%s TO GO" % [d.level, to_go, "" if to_go == 1 else "S"]
	# The reward on a plain bean, so it stands out.
	if d.kind == CosmeticDef.KIND_COLOR:
		spot_preview.set_bean_color(Palette.player_color(d.color_index))
		spot_preview.set_outfit({})
	else:
		spot_preview.set_bean_color(Palette.player_color(color))
		spot_preview.set_outfit({d.kind: d.id})
	spot_preview.face(d.kind == CosmeticDef.KIND_CAPE)
	spot_preview.focus(&"")  # the whole bean: a close-up crops it in this frame


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


## Puts the next level near the left of the track (a reached one still in view).
func _scroll_to_current() -> void:
	var lvl: int = clampi(ProfileManager.profile.level + 1, 2, ProgressionConfig.default().max_level)
	scroll.scroll_horizontal = maxi(int(COLUMN * float(lvl - 2) - COLUMN), 0)


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


static func _panel_style() -> StyleBoxFlat:
	var sb := CosmeticsPanel._panel_style()
	sb.content_margin_top = 36  # no awning here
	return sb


## One level's stretch of the track: the line (gold where reached, filling with XP towards the next
## level) and a numbered node, bigger and gold-rimmed every 5th level.
class PassNode:
	extends Control
	var level: int = 2
	var milestone: bool = false
	var reached: bool = false
	var next: bool = false
	var first: bool = false
	var last: bool = false
	## How far the line into this node is filled (0..1), and the line out of it.
	var fill_in: float = 0.0
	var fill_out: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cy: float = size.y * 0.5
		var cx: float = size.x * 0.5
		var thick: float = 8.0
		var x0: float = 0.0 if not first else cx
		var x1: float = size.x if not last else cx
		draw_rect(Rect2(x0, cy - thick * 0.5, x1 - x0, thick), Color("#3A2A22"))
		# The incoming half fills with XP (the next level), the outgoing half once reached.
		if fill_in > 0.0 and not first:
			draw_rect(Rect2(0.0, cy - thick * 0.5, cx * fill_in, thick), Palette.VIP_GOLD)
		if fill_out > 0.0 and not last:
			draw_rect(Rect2(cx, cy - thick * 0.5, (size.x - cx) * fill_out, thick), Palette.VIP_GOLD)
		var r: float = 24.0 if milestone else 19.0
		if next:
			draw_circle(Vector2(cx, cy), r + 7.0, Color(Palette.VIP_GOLD, 0.25))
		var rim: Color = Palette.VIP_GOLD if reached or next else (Palette.WARM_GOLD if milestone else Color("#6B5440"))
		draw_circle(Vector2(cx, cy), r, rim)
		draw_circle(Vector2(cx, cy), r - 3.0, Color("#2A4A36") if reached else (Color("#3A2626") if next else Color("#1A1010")))
		var font: Font = get_theme_default_font()
		var fs: int = 20 if milestone else 17
		var text: String = str(level)
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col: Color = Palette.CREAM if reached or next else Color(Palette.CREAM, 0.6)
		draw_string(font, Vector2(cx - w * 0.5, cy + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
