class_name SwordTapperUi
extends StationUi
## Sword Tapper overlay: a compact column at the right of the screen (Patrick: "this ui field of
## sword tapper is very weird. make it better, probably also a bit smaller (make the ui the same as
## the game / the 3d model)"), so the pedestal fills the rest (the seat camera frames it on the
## left). Under the title: the result of your last pull once the reveal is over, then the pedestal
## top itself (`SwordRingView`): the gem lamps round the ring with the prize for the picked stake
## beside each, the ruby biggest at the top, the multiplier rule on the stone, and the gems the
## pedestal lights lit here too. Under it the stake chips and PULL (a chip worth more than you
## have pulls with everything you have; Space / E / gamepad A pull again), the last pulls and,
## folded away, how it works.

## The compact column's width and the ring picture's size.
const PANEL_WIDTH: float = 470.0
const RING_SIZE: float = 330.0

var bet_panel: BetPanel
var pull_btn: Button
var result_label: Label
## "PRIZES AT $25" over the ring.
var ring_title: Label
var ring: SwordRingView
var history_label: Label
## The serial of the pull whose result shows (−1 = none yet).
var _result_serial: int = -1


func _init() -> void:
	game_title = "SWORD TAPPER"


func _dock_column() -> bool:
	return true


func _column_width() -> float:
	return PANEL_WIDTH


func _column_fills_height() -> bool:
	return false


## Locked while you pick a stake and pull; free while the sword is moving.
func wants_camera_lock() -> bool:
	return not pulling()


## True while a pull here is still being revealed.
func pulling() -> bool:
	return bool(pub.get("pulling", false))


func _build() -> void:
	body.add_theme_constant_override(&"separation", 6)
	title.add_theme_font_size_override(&"font_size", 34)
	status_label.add_theme_font_size_override(&"font_size", 19)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(120, 0)
	result_label = _line("", 26, Palette.VIP_GOLD)
	result_label.name = "Result"
	result_label.visible = false
	ring_title = _line("", 16, Palette.WARM_GOLD)
	ring_title.name = "RingTitle"
	ring = SwordRingView.new()
	ring.name = "Ring"
	ring.custom_minimum_size = Vector2(RING_SIZE, RING_SIZE)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.centre_text = stone_text(Registry.balance)
	body.add_child(ring)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(76, 46)
	bet_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.confirmed.connect(func(_a: int) -> void: pull())  # Space / Enter / gamepad A
	bet_panel.chip_changed.connect(func(_v: int) -> void: _refresh())
	body.add_child(bet_panel)
	pull_btn = Button.new()
	pull_btn.name = "Pull"
	pull_btn.theme_type_variation = &"ActionButton"
	pull_btn.custom_minimum_size = Vector2(0, 62)
	pull_btn.focus_mode = Control.FOCUS_NONE
	pull_btn.add_theme_font_size_override(&"font_size", 28)
	pull_btn.pressed.connect(pull)
	body.add_child(pull_btn)
	history_label = _line("", 15, Color("#9A8F7A"))
	history_label.name = "History"


func _process(_delta: float) -> void:
	if ring == null or not is_visible_in_tree():
		return
	var node: SwordTapperStation = _station_node()
	if node != null:
		ring.set_lit(node.lit)  # the pedestal's lamps, as they light


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.sword_min_bet)
	var hi: int = scaled(Registry.balance.sword_max_bet)
	bet_panel.selected_chip = 1
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "PULL")
	bet_panel.configure_visibility(false, false, false, false)
	bet_panel.set_balance(my_balance())
	_set_result("")
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
	ring_title.text = "PRIZES AT %s" % money(amount)
	ring.set_stake(amount)
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
		_set_result("")  # never spoil the reveal
		if _station_node() == null:
			ring.set_lit([])
		return
	var serial: int = int(last.get("serial", -1))
	if last.is_empty() or serial == _result_serial:
		return
	_result_serial = serial
	_set_result(result_text(last))
	if _station_node() == null:
		ring.set_lit(lit_gems(last))  # no pedestal to copy (a test, a late overlay): the pull's gems
	var won: bool = int(last.get("returned", 0)) > int(last.get("stake", 0))
	result_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD if won else (Palette.CREAM if int(last.get("returned", 0)) > 0 else Palette.LOSS_RED))


## The result line, hidden while it has nothing to say (keeps the column short).
func _set_result(text: String) -> void:
	result_label.text = text
	result_label.visible = text != ""


## The ring indices a finished pull ({pull}) lit.
static func lit_gems(last: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var p: Dictionary = last.get("pull", {})
	if bool(p.get("free", false)):
		for g: Variant in p.get("gems", []):
			out.append(int(g))
	return out


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
	return "LAST PULLS  " + "  ".join(parts)


## The multiplier rule in short, on the ring's stone: "≤9 GEMS\n×2 ×3 ×5 ×10".
static func stone_text(cfg: BalanceConfig) -> String:
	return "≤%d GEMS\n%s" % [cfg.sword_mult_max_gems, " ".join(_mults(cfg))]


static func _mults(cfg: BalanceConfig) -> PackedStringArray:
	var ms: PackedStringArray = []
	for m: int in cfg.sword_mult_values:
		if m > 1:
			ms.append("×%d" % m)
	return ms


## The pedestal this overlay belongs to (client-side), or null.
func _station_node() -> SwordTapperStation:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"stations"):
		if n is SwordTapperStation and (n as SwordTapperStation).station_id == station_id:
			return n as SwordTapperStation
	return null


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
