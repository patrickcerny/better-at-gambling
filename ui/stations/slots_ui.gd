class_name SlotsUi
extends StationUi
## Slot machine overlay. The machine's own 3D reels are the display (SlotReelsFx); the overlay is
## only a small bet strip at the bottom (chips pull the lever, STOP skips the spin, balance and the
## last result) and a "how you win" paytable docked on the right, built from the balance data.

const STRIP_WIDTH: float = 560.0
const PAYTABLE_WIDTH: float = 400.0
## Gap to the right screen edge (clear of the HUD's right column).
const PAYTABLE_MARGIN: float = 28.0
## Placeholder for "any symbol" in a paytable pattern.
const ANY: int = -1

var bet_panel: BetPanel
var stop_btn: Button
var info_label: Label
var paytable: PanelContainer
var jackpot_label: Label
## One per paytable entry, same order as `paytable_entries`.
var pay_rows: Array[PanelContainer] = []
var _entries: Array[Dictionary] = []
var _last_line: Array = []
var _last_stake: int = 0
## Seconds until the 3D reels have landed and the result may show (< 0 = nothing pending).
var _result_in: float = -1.0
var _saw_spin: bool = false


func _init() -> void:
	game_title = "SLOTS"


func _panel_height() -> float:
	return 170.0


## Every way to win, highest first: `symbols` is the pattern on the payline (ANY = anything),
## `mult` the payout as a multiple of the bet, `jackpot` true for the progressive jackpot line.
static func paytable_entries(cfg: BalanceConfig) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d: int = SlotsLogic.Sym.DIAMOND
	var c: int = SlotsLogic.Sym.CLOVER
	out.append({"kind": &"three", "sym": d, "symbols": [d, d, d], "mult": cfg.slots_three_pay[d], "jackpot": true, "text": "Diamonds"})
	out.append({"kind": &"three", "sym": c, "symbols": [c, c, c], "mult": cfg.slots_three_pay[c], "jackpot": false, "text": "Clovers"})
	var rest: Array[int] = []
	for s: int in SlotsLogic.SYMBOL_NAMES.size():
		if s != d and s != c:
			rest.append(s)
	rest.sort_custom(func(a: int, b: int) -> bool: return cfg.slots_three_pay[a] > cfg.slots_three_pay[b])
	for s: int in rest:
		out.append({"kind": &"three", "sym": s, "symbols": [s, s, s], "mult": cfg.slots_three_pay[s], "jackpot": false, "text": _plural(s)})
	var ch: int = SlotsLogic.Sym.CHERRY
	out.append({"kind": &"two_cherry", "sym": ch, "symbols": [ch, ch, ANY], "mult": cfg.slots_two_cherry_pay, "jackpot": false, "text": "Any two Cherries"})
	out.append({"kind": &"left_cherry", "sym": ch, "symbols": [ch, ANY, ANY], "mult": cfg.slots_one_cherry_pay, "jackpot": false, "text": "Cherry on the left: bet back"})
	return out


## Index into `paytable_entries` of the line that paid for `line`, or -1 for a loss.
static func entry_index(line: Array[int], entries: Array[Dictionary]) -> int:
	if line.size() < 3:
		return -1
	var cherries: int = line.count(SlotsLogic.Sym.CHERRY)
	for i: int in entries.size():
		var e: Dictionary = entries[i]
		var sym: int = int(e["sym"])
		match e["kind"]:
			&"three":
				var all_match: bool = true
				for s: int in line:
					if s != sym and s != SlotsLogic.Sym.CLOVER:
						all_match = false
				if all_match and (sym == SlotsLogic.Sym.CLOVER or line.has(sym)):
					return i
			&"two_cherry":
				if cherries >= 2:
					return i
			&"left_cherry":
				if line[0] == SlotsLogic.Sym.CHERRY:
					return i
	return -1


static func _plural(sym: int) -> String:
	match sym:
		SlotsLogic.Sym.CHERRY:
			return "Cherries"
		SlotsLogic.Sym.LEMON:
			return "Lemons"
		SlotsLogic.Sym.BELL:
			return "Bells"
		SlotsLogic.Sym.BAR:
			return "Bars"
		SlotsLogic.Sym.SEVEN:
			return "Sevens"
	return String(SlotsLogic.SYMBOL_NAMES[sym]).capitalize()


func _build() -> void:
	# Small strip at the bottom centre instead of the base's wide panel.
	panel.offset_left = -STRIP_WIDTH * 0.5
	panel.offset_right = STRIP_WIDTH * 0.5
	body.add_theme_constant_override(&"separation", 4)
	title.visible = false  # the machine's marquee says what it is
	status_label.add_theme_font_size_override(&"font_size", 24)
	var row := HBoxContainer.new()
	row.name = "BetRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	body.add_child(row)
	bet_panel = BetPanel.new()
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.confirmed.connect(func(a: int) -> void:
		_last_stake = a
		send(&"place_bet", {"bet": {"amount": a}}))
	row.add_child(bet_panel)
	stop_btn = Button.new()
	stop_btn.name = "Stop"
	stop_btn.text = "STOP  [Enter]"
	stop_btn.custom_minimum_size = Vector2(200, 52)
	stop_btn.pressed.connect(func() -> void: send(&"action", {"action": &"stop"}))
	row.add_child(stop_btn)
	info_label = Label.new()
	info_label.name = "Info"
	info_label.theme_type_variation = &"SmallLabel"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override(&"font_color", Palette.CREAM)
	body.add_child(info_label)
	_build_paytable()


## The "how you win" window on the right edge, vertically centred.
func _build_paytable() -> void:
	paytable = PanelContainer.new()
	paytable.name = "Paytable"
	paytable.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paytable.anchor_left = 1.0
	paytable.anchor_right = 1.0
	paytable.anchor_top = 0.5
	paytable.anchor_bottom = 0.5
	paytable.offset_left = -(PAYTABLE_WIDTH + PAYTABLE_MARGIN)
	paytable.offset_right = -PAYTABLE_MARGIN
	paytable.offset_top = -300.0
	paytable.offset_bottom = 300.0
	paytable.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	paytable.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(paytable)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 5)
	paytable.add_child(v)
	var head := Label.new()
	head.theme_type_variation = &"HeadingLabel"
	head.text = "HOW YOU WIN"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var sub := Label.new()
	sub.theme_type_variation = &"SmallLabel"
	sub.text = "One payline  •  pays × your bet"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	v.add_child(sub)
	_entries = paytable_entries(Registry.balance)
	for e: Dictionary in _entries:
		var row: PanelContainer = _pay_row(e)
		v.add_child(row)
		pay_rows.append(row)
	for note: String in [
		"%s Clover is WILD: it completes any three of a kind." % SlotReelsFx.SYMBOL_TEXT[&"clover"],
		"Only three real Diamonds win the JACKPOT pot.",
	]:
		var l := Label.new()
		l.theme_type_variation = &"SmallLabel"
		l.text = note
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override(&"font_color", Color("#B8AD95"))
		v.add_child(l)


func _pay_row(e: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"RowPanel"
	p.name = "Pay%s" % ("Jackpot" if e["jackpot"] else String(e["text"]).replace(" ", ""))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 4)
	p.add_child(h)
	for s: int in e["symbols"]:
		h.add_child(_symbol_tile(s))
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override(&"separation", -4)
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(name_box)
	var n := Label.new()
	n.text = "  " + String(e["text"])
	n.add_theme_font_size_override(&"font_size", 20)
	name_box.add_child(n)
	if e["jackpot"]:
		jackpot_label = Label.new()
		jackpot_label.name = "Jackpot"
		jackpot_label.text = "  + JACKPOT"
		jackpot_label.add_theme_font_size_override(&"font_size", 18)
		jackpot_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		name_box.add_child(jackpot_label)
	var m := Label.new()
	m.name = "Mult"
	m.text = "×%d" % int(e["mult"])
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	m.custom_minimum_size = Vector2(72, 0)
	m.add_theme_font_size_override(&"font_size", 22)
	m.add_theme_color_override(&"font_color", Palette.VIP_GOLD if e["jackpot"] else Palette.MONEY_GREEN)
	h.add_child(m)
	return p


## A small reel window showing a symbol as the machine shows it (same text and colour).
func _symbol_tile(sym: int) -> Control:
	var tile := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CASINO_BLACK
	sb.border_color = Color(Palette.WARM_GOLD, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	tile.add_theme_stylebox_override(&"panel", sb)
	tile.custom_minimum_size = Vector2(44, 34)
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", 18)
	if sym == ANY:
		l.text = "–"
		l.add_theme_color_override(&"font_color", Color("#6E6656"))
	else:
		var key: StringName = SlotsLogic.SYMBOL_NAMES[sym]
		l.text = SlotReelsFx.SYMBOL_TEXT[key]
		l.add_theme_color_override(&"font_color", SlotReelsFx.SYMBOL_COLORS[key])
	tile.add_child(l)
	return tile


func _on_open() -> void:
	var sizes: Array[int] = []
	for s: int in Registry.balance.slots_bet_sizes:
		sizes.append(scaled(s))
	bet_panel.setup(sizes, sizes[0], sizes[sizes.size() - 1], "PULL", true)
	_highlight(-1)
	_update_info()


func _relabel() -> void:
	stop_btn.text = "STOP  [%s]" % InputGlyphs.keys(&"bet_confirm")


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"bet_confirm") and stop_btn.visible:
		stop_btn.pressed.emit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if _result_in >= 0.0:
		_result_in -= delta
		if _result_in < 0.0:
			_show_result()
	_update_info()


func _update_info() -> void:
	if info_label == null:
		return
	var bal: int = state.balance(local_id) if state != null else 0
	var stake: int = int(pub.get("stake", _last_stake))
	info_label.text = "BALANCE %s   •   BET %s" % [money(bal), money(stake) if stake > 0 else "—"]
	if jackpot_label != null and state != null:
		jackpot_label.text = "  + JACKPOT %s" % money(state.jackpot)


func _show_result() -> void:
	var line: Array[int] = _ints(_last_line)
	var mult: int = SlotsLogic.payout_multiplier(line, Registry.balance)
	if SlotsLogic.is_jackpot(line):
		status_label.text = "JACKPOT!  ×%d" % mult
	elif mult > 1:
		status_label.text = "WIN ×%d" % mult
	elif mult == 1:
		status_label.text = "Cherry — bet back"
	else:
		status_label.text = "No luck — pull again"
	status_label.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if mult > 1 else Palette.CREAM)
	_highlight(entry_index(line, _entries))


## Marks the paytable row that just paid (-1 clears).
func _highlight(index: int) -> void:
	for i: int in pay_rows.size():
		pay_rows[i].theme_type_variation = &"RowPanelHighlight" if i == index else &"RowPanel"


func _refresh() -> void:
	var spinning: bool = bool(pub.get("spinning", false))
	var line: Array = pub.get("line", [])
	stop_btn.visible = spinning
	bet_panel.visible = not spinning
	if spinning:
		status_label.text = "Spinning…"
		status_label.remove_theme_color_override(&"font_color")
		_highlight(-1)
		_result_in = -1.0
		_saw_spin = true
	elif line.is_empty():
		status_label.text = "Pick a bet to pull the lever"
	elif _saw_spin:
		# A new result: wait for the machine's reels to land, then show the payout.
		_saw_spin = false
		_last_line = line.duplicate()
		status_label.text = "…"
		_result_in = SlotReelsFx.land_seconds()
	elif _result_in < 0.0:
		_last_line = line.duplicate()
		_show_result()
	_update_info()


func _ints(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in a:
		out.append(int(v))
	return out
