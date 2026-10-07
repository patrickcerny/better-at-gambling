extends GutTest
## Slots overlay: the 3D machine is the display, so the overlay has no reels; a small bet strip at
## the bottom and a paytable on the right that matches the real payout rules.

var root: Control
var ui: SlotsUi


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	ui = SlotsUi.new()
	root.add_child(ui)
	var st := ClientMatchState.new()
	st.stations[&"slot_1"] = {"game": &"slots", "player": 1, "spinning": false, "line": [], "stake": 0}
	st.balances[1] = 1000
	st.jackpot = 777
	ui.open(&"slot_1", 1, st)
	await wait_process_frames(3)


func _texts(n: Node, out: Array[String]) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c: Node in n.get_children():
		_texts(c, out)


func test_bet_strip_has_no_reel_display() -> void:
	assert_false("reels" in ui, "no 2D reels on the overlay")
	var texts: Array[String] = []
	_texts(ui.panel, texts)
	for t: String in texts:
		assert_false(t.strip_edges() == "?", "no placeholder reels")
	assert_lt(ui.panel.get_global_rect().size.x, 700.0, "the strip is small")
	assert_lt(ui.panel.get_global_rect().size.y, 300.0)
	assert_true(ui.bet_panel.visible, "chips to pull the lever")
	assert_string_contains(ui.info_label.text, "$1,000", "shows the balance")


func test_paytable_matches_the_payout_rules() -> void:
	var cfg: BalanceConfig = Registry.balance
	var entries: Array[Dictionary] = SlotsUi.paytable_entries(cfg)
	assert_eq(ui.pay_rows.size(), entries.size())
	var filler: Array[int] = [SlotsLogic.Sym.LEMON, SlotsLogic.Sym.BELL]  # never completes a pattern below
	var seen_three: Array[int] = []
	for i: int in entries.size():
		var e: Dictionary = entries[i]
		var line: Array[int] = []
		var f: int = 0
		for s: int in e["symbols"]:
			if s == SlotsUi.ANY:
				line.append(filler[f])
				f += 1
			else:
				line.append(s)
		assert_eq(SlotsLogic.payout_multiplier(line, cfg), int(e["mult"]), "row %s pays what the logic pays" % e["text"])
		assert_eq(SlotsLogic.is_jackpot(line), bool(e["jackpot"]), "only the Diamonds row wins the jackpot")
		assert_eq(SlotsUi.entry_index(line, entries), i, "a %s line highlights its own row" % e["text"])
		var mult_label: Label = ui.pay_rows[i].find_child("Mult", true, false) as Label
		assert_eq(mult_label.text, "×%d" % int(e["mult"]))
		if e["kind"] == &"three":
			seen_three.append(int(e["sym"]))
	assert_eq(seen_three.size(), SlotsLogic.SYMBOL_NAMES.size(), "every three-of-a-kind is listed")
	for k: int in range(1, entries.size()):
		assert_true(int(entries[k - 1]["mult"]) >= int(entries[k]["mult"]), "highest pays first")
	assert_string_contains(ui.jackpot_label.text, "$777", "the live jackpot pot")
	assert_eq(SlotsUi.entry_index([SlotsLogic.Sym.LEMON, SlotsLogic.Sym.CHERRY, SlotsLogic.Sym.BELL] as Array[int], entries), -1, "a loss highlights nothing")
	assert_eq(SlotsUi.entry_index([SlotsLogic.Sym.CLOVER, SlotsLogic.Sym.CLOVER, SlotsLogic.Sym.CLOVER] as Array[int], entries), 1, "three clovers are the Clovers row, not the jackpot")


func test_paytable_shows_pictures_not_glyphs() -> void:
	var icons: Array[Node] = ui.paytable.find_children("Icon", "TextureRect", true, false)
	assert_gt(icons.size(), ui.pay_rows.size(), "every paying symbol is a picture")
	for n: Node in icons:
		assert_not_null((n as TextureRect).texture)
	var row_labels: Array[String] = []
	for row: PanelContainer in ui.pay_rows:
		_texts(row, row_labels)
	for t: String in row_labels:
		for glyph: String in ["CH", "LEM", "BELL", "♣", "◆"]:
			assert_ne(t.strip_edges(), glyph, "no text glyph left in the paytable")
	var wild: Node = ui.paytable.find_child("WildNote", true, false)
	assert_not_null(wild, "the wild note shows the clover picture")
	var clover: TextureRect = wild.find_child("Icon", true, false) as TextureRect
	assert_eq(clover.texture, SlotReelsFx.symbol_texture(SlotsLogic.Sym.CLOVER))


func test_paytable_sits_on_the_right_clear_of_the_strip() -> void:
	var pay: Rect2 = ui.paytable.get_global_rect()
	var strip: Rect2 = ui.panel.get_global_rect()
	assert_gt(pay.position.x, root.size.x * 0.5, "paytable on the right half")
	assert_true(pay.end.x <= root.size.x, "paytable fully on screen")
	assert_true(pay.position.y >= 0.0 and pay.end.y <= root.size.y)
	assert_false(pay.intersects(strip), "paytable does not cover the bet strip")
	assert_true(strip.end.y <= root.size.y - 100.0, "strip clears the item bar")
