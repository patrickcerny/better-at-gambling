class_name ItemBar
extends Control
## Bottom-centre item HUD (0.8.6): six inventory slots with mouse wheel scrolling, dial gauge
## for luck (red to green with swinging needle), running effects with their timers, the target
## picker line and the "inventory full" discard choice. Pure display: ItemController feeds it.

const SLOTS: int = 6
const LUCK_MAX: int = 3
const VISIBLE_SLOTS: int = 3  # Display 3 slots at a time, scroll through 6

var slots: Array[PanelContainer] = []
var slot_names: Array[Label] = []
var slot_keys: Array[Label] = []
var luck_dial: Control
var luck_label: Label
var effects_label: Label
var target_label: Label
var discard_panel: PanelContainer
var discard_label: Label
var duel_panel: PanelContainer
var duel_label: Label
var slot_scroll_index: int = 0  # Which slot is first on screen (0-3)

var inventory: Array = []
var luck: int = 0
var seated: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_inventory([])


## Shows the inventory (item ids, oldest first), with 3 visible slots that scroll through 6 total.
func set_inventory(inv: Array) -> void:
	inventory = inv.duplicate()
	# Clamp scroll position to valid range
	slot_scroll_index = clampi(slot_scroll_index, 0, maxf(SLOTS - VISIBLE_SLOTS, 0))
	for i: int in VISIBLE_SLOTS:
		var inv_idx: int = slot_scroll_index + i
		var has: bool = inv_idx < inventory.size()
		slot_names[i].text = RewardPanel.item_name(StringName(inventory[inv_idx])) if has else "—"
		slot_names[i].modulate.a = 1.0 if has else 0.45
		slots[i].add_theme_stylebox_override(&"panel", _slot_style(_rarity_color(StringName(inventory[inv_idx])) if has else Palette.WARM_CHARCOAL))
	_refresh_keys()


## Seated players use Shift+1–3 for items (plain 1–4 pick chips).
func set_seated(v: bool) -> void:
	if v != seated:
		seated = v
		_refresh_keys()


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
	# Update dial gauge: needle position based on luck (−3…+3 mapped to 0…1)
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
		parts.append("[6] new %s" % RewardPanel.item_name(StringName(d.get("item", ""))))
		discard_label.text = "\n".join(parts)


## "Lucky Clover 0:32", "Double Trouble (next win)", "Spring Glove ×2".
static func effect_text(e: Dictionary) -> String:
	var name: String = RewardPanel.item_name(StringName(e.get("item", "")))
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


## The Rock Paper Scissors prompt ("" hides it).
func show_duel(text: String) -> void:
	duel_label.text = text
	duel_panel.visible = text != ""


## The target picker line ("" hides it).
func show_target(text: String) -> void:
	target_label.text = text
	target_label.visible = text != ""


## Scroll inventory slots (direction: 1 = right, -1 = left).
func scroll_slots(direction: int) -> void:
	slot_scroll_index = posmod(slot_scroll_index + direction, SLOTS - VISIBLE_SLOTS + 1)
	set_inventory(inventory)


## Update the dial gauge based on current luck value.
func _update_luck_dial() -> void:
	if luck_dial == null:
		return
	# Redraw the dial with updated needle position
	luck_dial.queue_redraw()


func _refresh_keys() -> void:
	for i: int in VISIBLE_SLOTS:
		var slot_num: int = slot_scroll_index + i + 1
		slot_keys[i].text = ("⇧%d" if seated else "%d") % slot_num
		# Grayed out if no item at that slot
		var has: bool = (slot_scroll_index + i) < inventory.size()
		slot_keys[i].modulate.a = 1.0 if has else 0.45


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


static func _slot_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.82)
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 6)
	add_child(col)
	discard_panel = PanelContainer.new()
	discard_panel.add_theme_stylebox_override(&"panel", _slot_style(Palette.LOSS_RED))
	discard_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	discard_panel.visible = false
	col.add_child(discard_panel)
	discard_label = Label.new()
	discard_label.theme_type_variation = &"SmallLabel"
	discard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_panel.add_child(discard_label)
	duel_panel = PanelContainer.new()
	duel_panel.add_theme_stylebox_override(&"panel", _slot_style(Palette.VIP_GOLD))
	duel_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	duel_panel.visible = false
	col.add_child(duel_panel)
	duel_label = Label.new()
	duel_label.theme_type_variation = &"HeadingLabel"
	duel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	duel_panel.add_child(duel_label)
	target_label = Label.new()
	target_label.theme_type_variation = &"HeadingLabel"
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	target_label.visible = false
	col.add_child(target_label)
	effects_label = Label.new()
	effects_label.theme_type_variation = &"SmallLabel"
	effects_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effects_label.add_theme_color_override(&"font_color", Palette.CREAM)
	effects_label.visible = false
	col.add_child(effects_label)
	# Luck dial gauge: "LUCK +2" with dial meter (red to green, swinging needle).
	var luck_row := HBoxContainer.new()
	luck_row.alignment = BoxContainer.ALIGNMENT_CENTER
	luck_row.add_theme_constant_override(&"separation", 12)
	col.add_child(luck_row)
	luck_label = Label.new()
	luck_label.theme_type_variation = &"SmallLabel"
	luck_label.text = "LUCK 0"
	luck_label.custom_minimum_size = Vector2(80, 0)
	luck_row.add_child(luck_label)
	luck_dial = _create_luck_dial()
	luck_dial.custom_minimum_size = Vector2(150, 78)
	luck_row.add_child(luck_dial)
	# Inventory slots: 3 visible, scrollable through 6 total.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 14)
	col.add_child(row)
	for i: int in VISIBLE_SLOTS:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(180, 52)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(p)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		p.add_child(h)
		var k := Label.new()
		k.theme_type_variation = &"HeadingLabel"
		k.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
		h.add_child(k)
		var n := Label.new()
		n.theme_type_variation = &"SmallLabel"
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(n)
		slots.append(p)
		slot_keys.append(k)
		slot_names.append(n)
	for l: Label in [discard_label, duel_label, target_label, effects_label, luck_label]:
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
