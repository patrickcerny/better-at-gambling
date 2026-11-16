class_name ItemBar
extends Control
## Bottom-centre item HUD (0.8.19, "hold it in your hand"): three inventory slots, the one in your
## hand highlighted (nothing highlighted = hands empty). The slots show the items' 3D models, not
## their names (0.9.41, Patrick: "nicht namen der items zeigen sondern die 3d models und onscroll
## oder equip der name"): the other slots a still picture (`ItemThumbnails`), the one in your hand
## its model turning live, its name under it. Picking a slot flashes a card with the name, what the
## item does and how to use it for `SELECTION_SECONDS`; I opens the info card. A new item in the
## inventory gets its own bigger "NEW ITEM" card first (`PICKUP_SECONDS`, one after another), so
## nobody has to guess what they just got (Patrick: "Items erklären wichtiger").
## Above them: the half-ring luck gauge, running effects with their timers, the aim line
## ("Black Cat → Anna" / "No one in reach"), the two-button choice some items ask before they go
## out (Pickpocket's greed, the duel stake) and the "inventory full" discard choice.
## Pure display apart from the choice buttons: ItemController feeds it.

## A choice button was pressed (0 = first, 1 = second).
signal choice_made(index: int)

const SLOTS: int = 3
const LUCK_MAX: int = 3
const SELECTION_SECONDS: float = 3.5
## How long the "NEW ITEM" card stays (counted only while the bar is on screen).
const PICKUP_SECONDS: float = 6.0
## Slot size (square, the item picture fills it) and the held slot's pop.
const SLOT_SIZE: float = 84.0
const HELD_SCALE: float = 1.14
## Pixel size of the live render of the held item.
const LIVE_SIZE: int = 160
## Turn speed of the held item's live model (radians per second).
const LIVE_SPIN: float = 0.9

var slots: Array[PanelContainer] = []
## The item picture in each slot (texture null = empty slot).
var slot_icons: Array[TextureRect] = []
## The name under each slot: only the held one shows it.
var slot_names: Array[Label] = []
var slot_keys: Array[Label] = []
var luck_dial: Control
var luck_label: Label
var effects_label: Label
var target_label: Label
var discard_panel: PanelContainer
var discard_label: Label
var info_hint: Label
## "[LMB / E] use   [RMB] put away" while something is in your hand.
var keys_label: Label
var info_panel: PanelContainer
var info_label: Label
## The name + one-line description shown for a moment after picking a slot.
var selection_panel: PanelContainer
var selection_name: Label
## "RARE · ON OTHERS · 45 s" under the name.
var selection_tag: Label
var selection_desc: Label
## How to use it ("Look at a player, then [LMB]").
var selection_use: Label
var info_icon: TextureRect
var info_name: Label
var info_tag: Label
## The "NEW ITEM" card for something that just landed in the inventory.
var pickup_panel: PanelContainer
var pickup_icon: TextureRect
var pickup_title: Label
var pickup_name: Label
var pickup_desc: Label
var pickup_use: Label
## Items still waiting for their "NEW ITEM" card (the showing one is `pickup_item`).
var pickup_queue: Array[StringName] = []
var pickup_item: StringName = &""
var _pickup_left: float = 0.0
## Renders still item pictures for the slots (headless: blank).
var _thumbs: ItemThumbnails
## Live render of the held item (null headless).
var _live_vp: SubViewport
var _live_stand: Node3D
var _live_model: Node3D
var _live_item: StringName = &""
## Two-button choice before a use goes out.
var choice_panel: PanelContainer
var choice_title: Label
var choice_buttons: Array[Button] = []
## The slot in your hand (0–2), -1 = nothing held.
var selected: int = -1

var inventory: Array = []
var luck: int = 0
var seated: bool = false
var _selection_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_thumbs = ItemThumbnails.new()
	add_child(_thumbs)
	if DisplayServer.get_name() != "headless":
		_live_vp = SubViewport.new()
		_live_vp.name = "LiveItem"
		_live_vp.size = Vector2i(LIVE_SIZE, LIVE_SIZE)
		_live_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
		add_child(_live_vp)
		_live_stand = ItemThumbnails.build_stage(_live_vp)
	set_inventory([])


func _process(delta: float) -> void:
	if _selection_left > 0.0:
		_selection_left -= delta
		if _selection_left <= 0.0:
			selection_panel.visible = false
	if _live_model != null:
		_live_model.rotation.y += LIVE_SPIN * delta
	if pickup_item != &"":
		# The card waits while another card, a choice or a table seat has the space.
		var room: bool = not seated and not selection_panel.visible and not info_panel.visible and not choice_panel.visible and not discard_panel.visible
		pickup_panel.visible = room
		if room and is_visible_in_tree():
			_pickup_left -= delta
			if _pickup_left <= 0.0:
				_next_pickup()


## Shows the inventory (item ids, oldest first) in the three slots. Items that weren't there
## before get the "NEW ITEM" card.
func set_inventory(inv: Array) -> void:
	var fresh: Array[StringName] = new_items(inventory, inv)
	inventory = inv.duplicate()
	var held_id: StringName = selected_item()
	for i: int in SLOTS:
		var has: bool = i < inventory.size()
		var id: StringName = StringName(inventory[i]) if has else &""
		slot_names[i].text = RewardPanel.item_name(id) if has and i == selected else ""
		slot_names[i].add_theme_color_override(&"font_color", name_color(id))
		slot_icons[i].set_meta(&"item", id)
		if not has:
			slot_icons[i].texture = null
		elif i == selected and _live_vp != null:
			slot_icons[i].texture = _live_vp.get_texture()
		else:
			slot_icons[i].texture = ItemThumbnails.texture_for(id)
		var border: Color = _rarity_color(id) if has else Palette.WARM_CHARCOAL
		slots[i].add_theme_stylebox_override(&"panel", _slot_style(border, i == selected and has, true))
		var side: float = SLOT_SIZE * (HELD_SCALE if i == selected and has else 1.0)
		slots[i].custom_minimum_size = Vector2(side, side)
		slots[i].self_modulate.a = 1.0 if has else 0.55
	_set_live(held_id)
	_refresh_keys()
	for id: StringName in fresh:
		announce(id)
	var item: StringName = selected_item()
	info_hint.visible = item != &""
	keys_label.visible = item != &""
	keys_label.text = hint_text()
	if item == &"":
		selection_panel.visible = false
	if info_panel.visible:
		if item == &"":
			info_panel.visible = false
		else:
			_fill_info(item)


## Puts slot `slot` in your hand (-1 = hands empty) and flashes its name and description.
func set_held(slot: int) -> void:
	var changed: bool = slot != selected
	selected = slot if slot >= 0 and slot < SLOTS else -1
	set_inventory(inventory)
	if changed and selected_item() != &"":
		if selected_item() == pickup_item:
			dismiss_pickup()  # the flash says the same
		flash_selection()


## The item shown in slot `i` (&"" = empty).
func slot_item(i: int) -> StringName:
	return StringName(slot_icons[i].get_meta(&"item", &"")) if i >= 0 and i < SLOTS else &""


## Ids in `after` that `before` didn't have (each copy counts: a second Black Cat is new too).
static func new_items(before: Array, after: Array) -> Array[StringName]:
	var left: Array = before.duplicate()
	var out: Array[StringName] = []
	for v: Variant in after:
		var i: int = left.find(v)
		if i >= 0:
			left.remove_at(i)
		else:
			out.append(StringName(v))
	return out


## Queues the "NEW ITEM" card for `id` (shows at once when no other card is up).
func announce(id: StringName) -> void:
	if id == &"" or not Registry.items.has(id):
		return
	pickup_queue.append(id)
	if pickup_item == &"":
		_next_pickup()


func _next_pickup() -> void:
	if pickup_queue.is_empty():
		pickup_item = &""
		pickup_panel.visible = false
		return
	pickup_item = pickup_queue.pop_front()
	_pickup_left = PICKUP_SECONDS
	var def: ItemDefinition = Registry.items.get(pickup_item, null)
	var col: Color = _rarity_color(pickup_item)
	pickup_title.text = "NEW ITEM  ·  %s" % tag_text(pickup_item)
	pickup_name.add_theme_color_override(&"font_color", name_color(pickup_item))
	pickup_name.text = RewardPanel.item_name(pickup_item)
	pickup_desc.text = def.description if def != null else ""
	var slot: int = inventory.find(pickup_item)
	if slot < 0:
		slot = mini(inventory.size(), SLOTS - 1)
	pickup_use.text = take_out_text(slot) + "\n" + use_text(pickup_item)
	pickup_icon.texture = ItemThumbnails.texture_for(pickup_item)
	pickup_panel.add_theme_stylebox_override(&"panel", _card_style(col))
	pickup_panel.visible = not seated and not selection_panel.visible and not info_panel.visible
	pickup_panel.pivot_offset = pickup_panel.size * 0.5
	pickup_panel.scale = Vector2(0.85, 0.85)
	pickup_panel.modulate.a = 0.0
	var tw: Tween = pickup_panel.create_tween().set_parallel(true)
	tw.tween_property(pickup_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pickup_panel, "modulate:a", 1.0, 0.15)
	if is_inside_tree():
		Audio.play(&"card_flip", &"UI", -6.0)


## Skips the "NEW ITEM" card that is up (taking the item out explains it anyway).
func dismiss_pickup() -> void:
	if pickup_item != &"":
		_next_pickup()


## Puts the held item's model on the live stage (&"" = nothing held: the stage empties).
func _set_live(id: StringName) -> void:
	if _live_stand == null or id == _live_item:
		return
	_live_item = id
	if _live_model != null:
		_live_model.queue_free()
		_live_model = null
	if id == &"":
		return
	_live_model = ItemModels.make(id, 1.0)
	_live_model.rotation_degrees = Vector3(0.0, -28.0, 0.0)
	_live_stand.add_child(_live_model)


## The colour an item's name is written in: cream for common ones (the felt green border is too
## dark for text), the rarity colour otherwise.
func name_color(id: StringName) -> Color:
	var def: ItemDefinition = Registry.items.get(id, null)
	if def == null or def.rarity == ItemDefinition.Rarity.COMMON:
		return Palette.CREAM
	return _rarity_color(id).lightened(0.25)


## "RARE  ·  ON OTHERS  ·  45 s": rarity, who it is for, how long it lasts.
static func tag_text(item: StringName) -> String:
	var def: ItemDefinition = Registry.items.get(item, null)
	if def == null:
		return ""
	var parts: PackedStringArray = [rarity_name(def.rarity).to_upper(), target_kind(def)]
	if def.duration > 0.0:
		parts.append("%d s" % roundi(def.duration))
	return "  ·  ".join(parts)


## Who an item is for, in two words.
static func target_kind(def: ItemDefinition) -> String:
	match def.target_mode:
		ItemDefinition.TargetMode.PLACED:
			return "TRAP"
		ItemDefinition.TargetMode.SELF:
			return "FOR YOU"
	return "ON OTHERS"


## The key that uses the held item.
static func use_key() -> String:
	return InputGlyphs.fill("[{interact}]") if InputGlyphs.gamepad else "[LMB]"


## How to use an item once it is in your hand: aim at whom, which key.
static func use_text(item: StringName) -> String:
	var def: ItemDefinition = Registry.items.get(item, null)
	var k: String = use_key()
	if def == null:
		return "Use: %s" % k
	match def.target_mode:
		ItemDefinition.TargetMode.PLACED:
			return "Use: %s drops it at your feet." % k
		ItemDefinition.TargetMode.LEADER:
			return "Use: %s, it goes for whoever is in the lead." % k
		ItemDefinition.TargetMode.RANDOM:
			return "Use: %s, it picks a random player." % k
		ItemDefinition.TargetMode.SELF:
			return "Use: %s while you hold it." % k
	var m: int = roundi(ItemController.reach(def))
	if def.target_mode == ItemDefinition.TargetMode.NEAR_PLAYER or def.range_m > 0.0:
		return "Use: walk up to a player (%d m), look at them, %s." % [m, k]
	return "Use: look at a player (gold ring under them), %s." % k


## How to take the item in slot `slot` out.
static func take_out_text(slot: int) -> String:
	if InputGlyphs.gamepad:
		return InputGlyphs.fill("Take it out: [{bet_chip_prev} / {bet_chip_next}]")
	return "Take it out: [%d] or the mouse wheel" % (slot + 1)


## The item in your hand (&"" when nothing is held or the slot is empty).
func selected_item() -> StringName:
	return StringName(inventory[selected]) if selected >= 0 and selected < inventory.size() else &""


## Name and one-line description of the held item for SELECTION_SECONDS.
func flash_selection() -> void:
	var item: StringName = selected_item()
	if item == &"":
		selection_panel.visible = false
		return
	var col: Color = _rarity_color(item)
	selection_name.text = RewardPanel.item_name(item)
	selection_name.add_theme_color_override(&"font_color", name_color(item))
	selection_tag.text = tag_text(item)
	selection_desc.text = RewardPanel.item_description(item)
	selection_use.text = "" if seated else use_text(item)
	selection_use.visible = selection_use.text != ""
	selection_panel.add_theme_stylebox_override(&"panel", _card_style(col))
	selection_panel.visible = not info_panel.visible
	_selection_left = SELECTION_SECONDS


## The first sentence of an item's description (the info card has all of it).
static func short_description(item: StringName) -> String:
	var desc: String = RewardPanel.item_description(item)
	if desc == "":
		return ""
	var cut: int = desc.find(". ")
	return desc.substr(0, cut + 1) if cut > 0 else desc


## I toggles the info card for the held item; nothing happens with empty hands.
func toggle_info() -> void:
	if info_panel.visible:
		info_panel.visible = false
		return
	var item: StringName = selected_item()
	if item == &"":
		return
	_fill_info(item)
	info_panel.visible = true
	selection_panel.visible = false


func hide_info() -> void:
	info_panel.visible = false


## The key line next to the slots while you hold something.
func hint_text() -> String:
	if InputGlyphs.gamepad:
		return InputGlyphs.fill("[{interact}] use   [{leave_station}] put away   [{bet_chip_prev} / {bet_chip_next}] switch")
	if seated:
		return "[Shift+%d] again: use" % (selected + 1)
	if e_taken:
		return "[LMB] use   [RMB] put away   [wheel] switch"  # E is the table's / megaphone's now
	return InputGlyphs.fill("[LMB / {interact}] use   [RMB] put away   [wheel] switch")


## E belongs to something in reach (a table, the shop, the megaphone): the item is LMB only, and the
## key line says so instead of promising E.
var e_taken: bool = false


func set_e_taken(v: bool) -> void:
	if v != e_taken:
		e_taken = v
		keys_label.text = hint_text()


func _fill_info(item: StringName) -> void:
	var def: ItemDefinition = Registry.items.get(item, null)
	if def == null:
		info_label.text = RewardPanel.item_name(item)
		return
	var desc: String = def.description if def.description != "" else "No description yet."
	info_name.text = def.display_name
	info_name.add_theme_color_override(&"font_color", name_color(item))
	info_tag.text = tag_text(item)
	info_label.text = "%s\n%s" % [desc, use_text(item)]
	info_icon.texture = ItemThumbnails.texture_for(item)
	info_panel.add_theme_stylebox_override(&"panel", _card_style(_rarity_color(item)))


static func rarity_name(r: ItemDefinition.Rarity) -> String:
	match r:
		ItemDefinition.Rarity.LEGENDARY:
			return "Legendary"
		ItemDefinition.Rarity.RARE:
			return "Rare"
	return "Common"


## Seated players use Shift+1–3 for items (plain 1–4 pick chips).
func set_seated(v: bool) -> void:
	if v != seated:
		seated = v
		_refresh_keys()
		keys_label.text = hint_text()
		if seated:
			selection_panel.visible = false


## Fraction of the item cooldown still to run (0 = ready).
func set_cooldown(frac: float) -> void:
	var dim: float = 1.0 - 0.5 * clampf(frac, 0.0, 1.0) if frac > 0.0 else 1.0
	for p: PanelContainer in slots:
		p.modulate = Color(dim, dim, dim, 1.0)


## The private item state from the server: {luck, effects:[{item, left, uses}], discard?}.
func set_private(priv: Dictionary) -> void:
	luck = int(priv.get("luck", 0))
	luck_label.text = "LUCK %s%d" % ["+" if luck > 0 else "", luck]
	luck_label.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if luck > 0 else (Palette.LOSS_RED if luck < 0 else Palette.CREAM))
	_update_luck_dial()
	var lines: PackedStringArray = []
	for e: Dictionary in priv.get("effects", []):
		lines.append(effect_text(e))
	effects_label.text = "\n".join(lines)
	effects_label.visible = not lines.is_empty()
	var d: Dictionary = priv.get("discard", {})
	discard_panel.visible = not d.is_empty()
	if discard_panel.visible:
		var parts: PackedStringArray = ["INVENTORY FULL: drop one (%ds)" % ceili(float(d.get("left", 0.0)))]
		for i: int in inventory.size():
			parts.append("[%d] %s" % [i + 1, RewardPanel.item_name(StringName(inventory[i]))])
		parts.append("[%d] new %s" % [ItemSystem.DISCARD_INCOMING + 1, RewardPanel.item_name(StringName(d.get("item", "")))])
		discard_label.text = "\n".join(parts)


## "Lucky Clover 0:32", "Double Trouble (next win)", "Spring Glove ×2".
static func effect_text(e: Dictionary) -> String:
	var id: StringName = StringName(e.get("item", ""))
	var name: String = RewardPanel.item_name(id)
	var left: float = float(e.get("left", -1.0))
	var uses: int = int(e.get("uses", -1))
	if left >= 0.0:
		var s: int = ceili(left)
		name += "  %d:%02d" % [s / 60, s % 60]
	if uses > 0:
		name += "  ×%d" % uses
	elif left < 0.0:
		name += "  (ready)"
	return name


## The aim line ("" hides it).
func show_target(text: String) -> void:
	target_label.text = text
	target_label.visible = text != ""


## Opens the two-button choice (`labels` = two button texts with their keys).
func show_choice(title: String, labels: Array[String]) -> void:
	choice_title.text = title
	for i: int in choice_buttons.size():
		choice_buttons[i].text = labels[i] if i < labels.size() else ""
	choice_panel.visible = true
	selection_panel.visible = false


func hide_choice() -> void:
	choice_panel.visible = false


func is_choice_open() -> bool:
	return choice_panel.visible


func _update_luck_dial() -> void:
	if luck_dial != null:
		luck_dial.queue_redraw()


func _refresh_keys() -> void:
	for i: int in SLOTS:
		slot_keys[i].text = ("⇧%d" if seated else "%d") % (i + 1)
		slot_keys[i].modulate.a = 1.0 if i < inventory.size() else 0.45


func _rarity_color(id: StringName) -> Color:
	var def: ItemDefinition = Registry.items.get(id, null)
	if def == null:
		return Palette.WARM_CHARCOAL
	match def.rarity:
		ItemDefinition.Rarity.LEGENDARY:
			return Palette.VIP_GOLD
		ItemDefinition.Rarity.RARE:
			return Palette.CASINO_RED
	return Palette.FELT_GREEN


## The explanation cards: dark velvet, a rarity border, a soft drop shadow.
static func _card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.9)
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.border_width_top = 6
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	return sb


static func _slot_style(border: Color, highlighted: bool = false, square: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if square:
		# Item slots: the picture fills them, a warm glow behind the held one.
		sb.bg_color = Color(Palette.CASINO_BLACK.lerp(Palette.WARM_GOLD, 0.22), 0.88) if highlighted else Color(Palette.CASINO_BLACK, 0.72)
		sb.border_color = Palette.WARM_GOLD if highlighted else border
		sb.set_border_width_all(4 if highlighted else 3)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(4)
		if highlighted:
			sb.shadow_color = Color(Palette.WARM_GOLD, 0.35)
			sb.shadow_size = 8
		return sb
	sb.bg_color = Color(Palette.CASINO_BLACK.lerp(Palette.WARM_GOLD, 0.18), 0.9) if highlighted else Color(Palette.CASINO_BLACK, 0.82)
	sb.border_color = Palette.WARM_GOLD if highlighted else border
	sb.set_border_width_all(5 if highlighted else 3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override(&"panel", _slot_style(border))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	return p


## A square item picture `side` px wide (the model render, kept in proportion).
func _icon(side: float) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(side, side)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _label(variation: StringName, color: Color = Palette.CREAM) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 6)
	add_child(col)
	discard_panel = _panel(Palette.LOSS_RED)
	col.add_child(discard_panel)
	discard_label = _label(&"SmallLabel")
	discard_panel.add_child(discard_label)
	# Two-button choice (Pickpocket greed, duel stake).
	choice_panel = _panel(Palette.VIP_GOLD)
	col.add_child(choice_panel)
	var cv := VBoxContainer.new()
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_theme_constant_override(&"separation", 6)
	choice_panel.add_child(cv)
	choice_title = _label(&"HeadingLabel", Palette.VIP_GOLD)
	cv.add_child(choice_title)
	var ch := HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_theme_constant_override(&"separation", 12)
	cv.add_child(ch)
	for i: int in 2:
		var b := Button.new()
		b.custom_minimum_size = Vector2(230, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: choice_made.emit(i))
		ch.add_child(b)
		choice_buttons.append(b)
	target_label = _label(&"HeadingLabel", Palette.VIP_GOLD)
	target_label.visible = false
	col.add_child(target_label)
	keys_label = _label(&"SmallLabel", Palette.WARM_GOLD)
	keys_label.add_theme_font_size_override(&"font_size", 18)
	keys_label.visible = false
	col.add_child(keys_label)
	effects_label = _label(&"SmallLabel")
	effects_label.visible = false
	col.add_child(effects_label)
	# Luck dial gauge (red to green, swinging needle) centred over the slots, "LUCK +2" on top of
	# it (Patrick: "center the barometer. the luck thingy should be on top of the barometer").
	var luck_row := VBoxContainer.new()
	luck_row.name = "LuckRow"
	luck_row.alignment = BoxContainer.ALIGNMENT_CENTER
	luck_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	luck_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	luck_row.add_theme_constant_override(&"separation", 2)
	col.add_child(luck_row)
	luck_label = _label(&"SmallLabel")
	luck_label.text = "LUCK 0"
	luck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	luck_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	luck_row.add_child(luck_label)
	luck_dial = _create_luck_dial()
	luck_dial.custom_minimum_size = Vector2(150, 78)
	luck_dial.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	luck_row.add_child(luck_dial)
	# Item info card (I on the held item): picture, name, tag, the whole description, how to use.
	info_panel = _panel(Palette.WARM_GOLD)
	col.add_child(info_panel)
	var ih := HBoxContainer.new()
	ih.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ih.add_theme_constant_override(&"separation", 14)
	info_panel.add_child(ih)
	info_icon = _icon(96.0)
	ih.add_child(info_icon)
	var iv := VBoxContainer.new()
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.alignment = BoxContainer.ALIGNMENT_CENTER
	iv.add_theme_constant_override(&"separation", 2)
	ih.add_child(iv)
	info_name = _label(&"HeadingLabel")
	info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	iv.add_child(info_name)
	info_tag = _label(&"SmallLabel", Palette.WARM_GOLD)
	info_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_tag.add_theme_font_size_override(&"font_size", 16)
	iv.add_child(info_tag)
	info_label = _label(&"SmallLabel")
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(440, 0)
	iv.add_child(info_label)
	# "NEW ITEM": picture, name, what it does, how to take it out and use it.
	pickup_panel = _panel(Palette.WARM_GOLD)
	pickup_panel.name = "PickupCard"
	col.add_child(pickup_panel)
	var ph := HBoxContainer.new()
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_theme_constant_override(&"separation", 16)
	pickup_panel.add_child(ph)
	pickup_icon = _icon(120.0)
	ph.add_child(pickup_icon)
	var pv := VBoxContainer.new()
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override(&"separation", 2)
	ph.add_child(pv)
	pickup_title = _label(&"SmallLabel", Palette.VIP_GOLD)
	pickup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pv.add_child(pickup_title)
	pickup_name = _label(&"HeadingLabel", Palette.CREAM)
	pickup_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pickup_name.add_theme_font_size_override(&"font_size", 34)
	pv.add_child(pickup_name)
	pickup_desc = _label(&"SmallLabel")
	pickup_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pickup_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pickup_desc.custom_minimum_size = Vector2(440, 0)
	pv.add_child(pickup_desc)
	pickup_use = _label(&"SmallLabel", Palette.WARM_GOLD)
	pickup_use.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pickup_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pickup_use.custom_minimum_size = Vector2(440, 0)
	pv.add_child(pickup_use)
	# What you just picked: name, tag, what it does and how to use it.
	selection_panel = _panel(Palette.WARM_GOLD)
	col.add_child(selection_panel)
	var sv := VBoxContainer.new()
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_theme_constant_override(&"separation", 2)
	selection_panel.add_child(sv)
	selection_name = _label(&"HeadingLabel", Palette.VIP_GOLD)
	sv.add_child(selection_name)
	selection_tag = _label(&"SmallLabel", Palette.WARM_GOLD)
	selection_tag.add_theme_font_size_override(&"font_size", 16)
	sv.add_child(selection_tag)
	selection_desc = _label(&"SmallLabel")
	selection_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_desc.custom_minimum_size = Vector2(560, 0)
	sv.add_child(selection_desc)
	selection_use = _label(&"SmallLabel", Palette.WARM_GOLD)
	selection_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_use.custom_minimum_size = Vector2(560, 0)
	sv.add_child(selection_use)
	# Inventory slots: three squares with the item models, the held one bigger with its name under
	# it, the info hint to their right.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 18)
	col.add_child(row)
	for i: int in SLOTS:
		var sc := VBoxContainer.new()
		sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_theme_constant_override(&"separation", 6)
		row.add_child(sc)
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(p)
		var icon := _icon(SLOT_SIZE - 8.0)
		p.add_child(icon)
		# The key number in the top-left corner, over the picture.
		var k := _label(&"SmallLabel", Palette.WARM_GOLD)
		k.add_theme_font_size_override(&"font_size", 18)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		k.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		k.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		p.add_child(k)
		var n := _label(&"SmallLabel")
		n.add_theme_font_size_override(&"font_size", 17)
		n.custom_minimum_size = Vector2(SLOT_SIZE + 60.0, 24)
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sc.add_child(n)
		slots.append(p)
		slot_icons.append(icon)
		slot_keys.append(k)
		slot_names.append(n)
	info_hint = _label(&"SmallLabel", Palette.WARM_GOLD)
	info_hint.text = "[I] more info"
	info_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_hint.visible = false
	row.add_child(info_hint)
	for l: Label in [discard_label, choice_title, target_label, keys_label, effects_label, luck_label, info_label, info_name, info_tag, selection_name, selection_tag, selection_desc, selection_use, info_hint, pickup_title, pickup_name, pickup_desc, pickup_use] + slot_keys + slot_names:
		_outline(l)
	set_private({})


## Creates the luck barometer: a half ring (red on the left, gold in the middle, green on the
## right) with tick marks and a tapered needle swinging from a hub at the bottom centre.
func _create_luck_dial() -> Control:
	var dial := Control.new()
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial.draw.connect(func() -> void:
		var size: Vector2 = dial.size
		var hub := Vector2(size.x * 0.5, size.y - 6.0)
		var radius: float = minf(size.x * 0.5, size.y) - 14.0
		if radius < 8.0:
			return
		var band: float = maxf(radius * 0.3, 6.0)
		# Upper half circle runs from PI (left) over 1.5 PI (top) to 2 PI (right).
		dial.draw_arc(hub, radius, PI, TAU, 48, Palette.CASINO_BLACK, band + 6.0, true)
		var steps: int = 36
		for i: int in steps:
			var t0: float = float(i) / steps
			var t1: float = float(i + 1) / steps
			var mid: float = (t0 + t1) * 0.5
			var color: Color
			if mid < 0.5:
				color = Palette.LOSS_RED.lerp(Palette.WARM_GOLD, mid * 2.0)
			else:
				color = Palette.WARM_GOLD.lerp(Palette.MONEY_GREEN, (mid - 0.5) * 2.0)
			dial.draw_arc(hub, radius, PI + t0 * PI, PI + t1 * PI + 0.01, 4, color, band, true)
		# Ticks for each luck step (−3…+3); the ends and the centre are longer.
		for i: int in range(-3, 4):
			var a: float = PI + (float(i) + 3.0) / 6.0 * PI
			var dir := Vector2(cos(a), sin(a))
			var len: float = band * 0.9 if i % 3 == 0 else band * 0.45
			var outer: Vector2 = hub + dir * (radius + band * 0.5)
			dial.draw_line(outer, outer - dir * len, Palette.CREAM, 2.0, true)
		# Needle: tapered triangle pointing at the current luck, with a round hub.
		var needle_t: float = clampf((float(luck) + 3.0) / 6.0, 0.0, 1.0)
		var na: float = PI + needle_t * PI
		var ndir := Vector2(cos(na), sin(na))
		var side := Vector2(-ndir.y, ndir.x) * 3.5
		var tip: Vector2 = hub + ndir * (radius - band * 0.5 - 1.0)
		var needle := PackedVector2Array([tip, hub + side, hub - ndir * 5.0, hub - side])
		dial.draw_colored_polygon(needle, Palette.CASINO_BLACK)
		dial.draw_colored_polygon(PackedVector2Array([tip, hub + side * 0.6, hub - ndir * 3.0, hub - side * 0.6]), Palette.CREAM)
		dial.draw_circle(hub, 6.0, Palette.CASINO_BLACK)
		dial.draw_circle(hub, 4.0, Palette.WARM_GOLD)
	)
	return dial


static func _outline(l: Label) -> void:
	l.add_theme_constant_override(&"outline_size", 8)
	l.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
