class_name SwordTapperUi
extends StationUi
## Sword Tapper overlay: a column down the right third of the screen, so the pedestal fills the
## rest (the seat camera frames it on the left). Pick a stake with the chips (a chip worth more
## than you have pulls with everything you have), tap PULL (or Space / E / gamepad A to pull again
## with the same stake). Shows the ring's prizes for that stake, the multiplier rule, the result of
## your last pull once the reveal is over, the last 8 pulls and, folded away, how it works.

## Ring tiers in the prize list: how many to a row.
const TIER_COLUMNS: int = 4

var bet_panel: BetPanel
var pull_btn: Button
var result_label: Label
var ring_title: Label
var ring_grid: GridContainer
## One per ring tier (highest first): the prize label.
var tier_labels: Array[Label] = []
var mult_label: Label
var history_label: Label
## The ring's tiers, highest first: {value (× stake), count, ruby}.
var tiers: Array[Dictionary] = []
## The serial of the pull whose result shows (−1 = none yet).
var _result_serial: int = -1


func _init() -> void:
	game_title = "SWORD TAPPER"


func _dock_column() -> bool:
	return true


## Locked while you pick a stake and pull; free while the sword is moving.
func wants_camera_lock() -> bool:
	return not pulling()


## True while a pull here is still being revealed.
func pulling() -> bool:
	return bool(pub.get("pulling", false))


func _build() -> void:
	body.add_theme_constant_override(&"separation", 10)
	status_label.add_theme_font_size_override(&"font_size", 22)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(120, 0)
	result_label = _line("", 30, Palette.VIP_GOLD)
	result_label.name = "Result"
	ring_title = _line("", 17, Palette.WARM_GOLD)
	ring_title.name = "RingTitle"
	tiers = ring_tiers(Registry.balance)
	ring_grid = GridContainer.new()
	ring_grid.name = "Ring"
	ring_grid.columns = TIER_COLUMNS
	ring_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring_grid.add_theme_constant_override(&"h_separation", 8)
	ring_grid.add_theme_constant_override(&"v_separation", 8)
	body.add_child(ring_grid)
	for tier: Dictionary in tiers:
		ring_grid.add_child(_tier_cell(tier))
	mult_label = _line(multiplier_text(Registry.balance), 16, Palette.CREAM.darkened(0.1))
	mult_label.name = "MultiplierRule"
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(84, 52)
	bet_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.confirmed.connect(func(_a: int) -> void: pull())  # Space / Enter / gamepad A
	bet_panel.chip_changed.connect(func(_v: int) -> void: _refresh())
	body.add_child(bet_panel)
	pull_btn = Button.new()
	pull_btn.name = "Pull"
	pull_btn.theme_type_variation = &"ActionButton"
	pull_btn.custom_minimum_size = Vector2(0, 76)
	pull_btn.focus_mode = Control.FOCUS_NONE
	pull_btn.add_theme_font_size_override(&"font_size", 30)
	pull_btn.pressed.connect(pull)
	body.add_child(pull_btn)
	history_label = _line("", 16, Color("#9A8F7A"))
	history_label.name = "History"


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.sword_min_bet)
	var hi: int = scaled(Registry.balance.sword_max_bet)
	bet_panel.selected_chip = 1
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "PULL")
	bet_panel.configure_visibility(false, false, false, false)
	bet_panel.set_balance(my_balance())
	result_label.text = ""
	_result_serial = int((pub.get("last", {}) as Dictionary).get("serial", -1))  # an older pull's result is not news


## The stake the next pull goes with: the selected chip, all-in when it is worth more than you have.
func stake() -> int:
	return bet_panel.chip_value() if bet_panel.balance < 0 else BetClamp.clamp_amount(bet_panel.chip_value(), bet_panel.balance, bet_panel.min_bet, bet_panel.max_bet)


## Taps PULL: sends the stake (the server checks it, all-in over the balance, and decides the pull).
func pull() -> bool:
	if pull_btn.disabled:
		return false
	return send(&"place_bet", {"bet": {"amount": bet_panel.chip_stake()}})


func _hint_text() -> String:
	return InputGlyphs.fill("[1-4] stake   ·   [{bet_confirm}] / [{interact}] pull again\n[{leave_station}] step away")


func _rules_text() -> String:
	var def: GameDefinition = Registry.games.get(&"sword_tapper", null)
	return def.rules_text if def != null else ""


func _relabel() -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"interact") and not (event is InputEventKey and (event as InputEventKey).echo):
		pull()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if pull_btn == null:
		return
	var lo: int = bet_panel.min_bet
	var amount: int = stake()
	var broke: bool = my_balance() < lo
	var mine: bool = int(pub.get("player", -1)) == local_id
	if pulling():
		status_label.text = "THE SWORD IS MOVING…" if mine else "Someone is pulling"
	elif broke:
		status_label.text = "Not enough money for the minimum (%s)" % money(lo)
	else:
		status_label.text = "Pick a stake, then PULL"
	_show_result()
	ring_title.text = "THE RING: PRIZES FOR A %s PULL" % money(amount)
	for i: int in tiers.size():
		var t: Dictionary = tiers[i]
		var cents: int = roundi(float(t["value"]) * 100.0) * amount
		tier_labels[i].text = "%s%s" % [SwordTapperStation.cents_text(cents), ("  ×%d" % int(t["count"])) if int(t["count"]) > 1 else ""]
	pull_btn.disabled = pulling() or broke
	pull_btn.text = "PULL  %s   %s" % [money(amount), InputGlyphs.hint(&"bet_confirm")]
	pull_btn.tooltip_text = StationUi.all_in_text(amount) if bet_panel.balance >= 0 and amount < bet_panel.chip_value() else ""
	history_label.text = history_text(pub.get("history", []))
	if not pulling():
		var node: SwordTapperStation = _station_node()
		if node != null:
			node.set_stake(amount)  # the lamps print the prizes for the stake you picked


## The result of your last pull, once its reveal is over.
func _show_result() -> void:
	var last: Dictionary = pub.get("last", {})
	if pulling():
		result_label.text = ""  # never spoil the reveal
		return
	var serial: int = int(last.get("serial", -1))
	if last.is_empty() or serial == _result_serial:
		return
	_result_serial = serial
	result_label.text = result_text(last)
	var won: bool = int(last.get("returned", 0)) > int(last.get("stake", 0))
	result_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD if won else (Palette.CREAM if int(last.get("returned", 0)) > 0 else Palette.LOSS_RED))


## "STUCK!  −$25", or "FREE!  7 GEMS  ×3  +$420" for a pull ({pull, stake, returned}).
static func result_text(last: Dictionary) -> String:
	var p: Dictionary = last.get("pull", {})
	var st: int = int(last.get("stake", 0))
	var back: int = int(last.get("returned", 0))
	if not bool(p.get("free", false)):
		return "STUCK!  −%s" % money(st)
	var n: int = (p.get("gems", []) as Array).size()
	var m: int = int(p.get("mult", 1))
	var net: int = back - st
	var tail: String = ("+%s" % money(net)) if net > 0 else (("−%s" % money(-net)) if net < 0 else "stake back")
	return "FREE!  %d GEMS%s  %s" % [n, ("  ×%d" % m) if m > 1 else "", tail]


## "LAST PULLS  $40  —  $90 ×3  —" from the public state's history (newest first).
static func history_text(h: Array) -> String:
	if h.is_empty():
		return ""
	var parts: PackedStringArray = []
	for e: Variant in h:
		var d: Dictionary = e
		if not bool(d.get("free", false)):
			parts.append("—")
		else:
			var m: int = int(d.get("mult", 1))
			parts.append("%s%s" % [money(int(d.get("returned", 0))), (" ×%d" % m) if m > 1 else ""])
	return "LAST PULLS   " + "   ".join(parts)


## The multiplier rule as printed on the panel.
static func multiplier_text(cfg: BalanceConfig) -> String:
	var ms: PackedStringArray = []
	for m: int in cfg.sword_mult_values:
		if m > 1:
			ms.append("×%d" % m)
	return "%d or fewer gems lit: the win may be multiplied by %s" % [cfg.sword_mult_max_gems, ", ".join(ms)]


## The ring's prize tiers, highest first: {value (× stake), count, ruby}.
static func ring_tiers(cfg: BalanceConfig) -> Array[Dictionary]:
	var counts: Dictionary = {}
	for v: float in cfg.sword_ring:
		var key: int = roundi(v * 100.0)
		counts[key] = int(counts.get(key, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	keys.reverse()
	var out: Array[Dictionary] = []
	for k: Variant in keys:
		out.append({"value": int(k) / 100.0, "count": int(counts[k]), "ruby": out.is_empty()})
	return out


## The pedestal this overlay belongs to (client-side), or null.
func _station_node() -> SwordTapperStation:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"stations"):
		if n is SwordTapperStation and (n as SwordTapperStation).station_id == station_id:
			return n as SwordTapperStation
	return null


func _tier_cell(tier: Dictionary) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(128, 54)
	var sb := StyleBoxFlat.new()
	sb.bg_color = SwordTapperStation.VELVET if not bool(tier["ruby"]) else SwordTapperStation.RUBY.darkened(0.35)
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	cell.add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	cell.add_child(v)
	var gem := Label.new()
	gem.text = "◆ RUBY" if bool(tier["ruby"]) else "◆"
	gem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem.add_theme_font_size_override(&"font_size", 13)
	gem.add_theme_color_override(&"font_color", SwordTapperStation.RUBY.lightened(0.3) if bool(tier["ruby"]) else SwordTapperStation.GEM_IDLE)
	v.add_child(gem)
	var prize := Label.new()
	prize.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prize.add_theme_font_size_override(&"font_size", 19)
	prize.add_theme_color_override(&"font_color", Palette.CREAM)
	v.add_child(prize)
	tier_labels.append(prize)
	return cell


func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(120, 0)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	body.add_child(l)
	return l
