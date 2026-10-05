class_name PlinkoUi
extends StationUi
## Plinko overlay: risk row (LOW / MEDIUM / HIGH), multipliers for that row, bet size drops a chip.

var risk: StringName = &"medium"
var risk_buttons: Dictionary[StringName, Button] = {}
var mults_label: Label
var bet_panel: BetPanel


func _init() -> void:
	game_title = "PLINKO"


func _panel_height() -> float:
	return 300.0


func _dock_right() -> bool:
	return true


func _build() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	body.add_child(row)
	for r: StringName in PlinkoLogic.RISKS:
		var b := Button.new()
		b.text = String(r).to_upper()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(118, 48)
		var rr: StringName = r
		b.pressed.connect(func() -> void: _set_risk(rr))
		row.add_child(b)
		risk_buttons[r] = b
	mults_label = Label.new()
	mults_label.theme_type_variation = &"SmallLabel"
	mults_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mults_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mults_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	body.add_child(mults_label)
	bet_panel = BetPanel.new()
	bet_panel.confirmed.connect(func(a: int) -> void: send(&"place_bet", {"bet": {"amount": a, "risk": risk}}))
	body.add_child(bet_panel)
	_set_risk(&"medium")


func _on_open() -> void:
	var sizes: Array[int] = []
	for s: int in Registry.balance.plinko_bet_sizes:
		sizes.append(scaled(s))
	bet_panel.setup(sizes, sizes[0], sizes[sizes.size() - 1], "DROP", true)


func _set_risk(r: StringName) -> void:
	risk = r
	for k: StringName in risk_buttons:
		risk_buttons[k].button_pressed = k == r
	var parts: Array[String] = []
	for m: float in Registry.balance.plinko_multipliers(r):
		parts.append(("%d" if m == floor(m) else "%.1f") % m)
	mults_label.text = "×  " + "  ".join(parts)


func _refresh() -> void:
	var flying: int = 0
	for d: Dictionary in pub.get("drops", []):
		if int(d["player"]) == local_id:
			flying += 1
	status_label.text = ("Chip in flight…" if flying == 1 else "%d chips in flight…" % flying) if flying > 0 else "Pick a risk and a bet to drop a chip"
