class_name DailySpinPanel
extends PanelContainer
## The Daily Spin (`DailyWheel`), opened from DAILY SPIN on the main menu: the prize wheel on the
## left (`DailyWheelView`), on the right the jackpot (the Fortune skin turning on a bean), the
## odds, the SPIN button with the time to the next spin, and what was won.
##
## With Steam, SPIN asks Steam for the day's drop (`SteamSvc.daily_spin`); the wheel already turns
## while it answers and then eases out onto the slice Steam picked. Without Steam (or before the
## wheel's item definitions are on Steam) the spin is local (`ProfileManager.spin_local`): Coins and
## mystery pieces only, the Gold and jackpot slices dimmed.

signal closed

## Steam didn't answer in time: the wheel stops on nothing.
const STEAM_TIMEOUT_S: float = 12.0

var wheel: DailyWheelView
var spin_button: Button
var back_button: Button
var status_label: Label
var prize_title: Label
var prize_detail: Label
var wear_button: Button
var jackpot_preview: BeanPreviewView
var odds_box: GridContainer
var _dim: ColorRect
## Waiting for Steam's answer (seconds so far, -1 = not waiting).
var _waiting: float = -1.0
## The prize being shown once the wheel lands: {index, coins, piece, gold}.
var _prize: Dictionary = {}
var _steam_spin: bool = false
var _tick: float = 0.0


func _ready() -> void:
	name = "DailySpin"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 56
	offset_right = -56
	offset_top = 40
	offset_bottom = -40
	visible = false
	add_theme_stylebox_override(&"panel", LevelPassPanel._panel_style())
	_dim = ColorRect.new()
	_dim.name = "DailySpinDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.05, 0.03, 0.03, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	add_child(v)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "DAILY SPIN"
	v.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"SmallLabel"
	sub.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	sub.text = "One free spin every day. Win Coins, mystery pieces, Gold Coins, or with a lot of luck the Fortune skin you can't get anywhere else."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	wheel = DailyWheelView.new()
	wheel.name = "Wheel"
	wheel.custom_minimum_size = Vector2(520, 520)
	wheel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wheel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wheel.landed.connect(_on_landed)
	wheel.clicked.connect(spin)
	body.add_child(wheel)
	body.add_child(_build_side())


func _build_side() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 420
	col.add_theme_constant_override(&"separation", 6)
	# The jackpot on a turning bean.
	var spot := PanelContainer.new()
	spot.add_theme_stylebox_override(&"panel", CosmeticsPanel._stage_style())
	col.add_child(spot)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override(&"separation", 2)
	spot.add_child(sv)
	var cap := Label.new()
	cap.theme_type_variation = &"SmallLabel"
	cap.text = "JACKPOT  ·  %s" % DailyWheel.chance_text(DailyWheel.index_of_item(_skin_item()))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	sv.add_child(cap)
	jackpot_preview = BeanPreviewView.make(Palette.player_color(0), Vector2(300, 170))
	jackpot_preview.interactive = true
	jackpot_preview.tooltip_text = "Drag to turn"
	jackpot_preview.set_outfit({CosmeticDef.KIND_SKIN: DailyWheel.SKIN_ID})
	sv.add_child(jackpot_preview)
	var jn := Label.new()
	jn.theme_type_variation = &"HeadingLabel"
	jn.text = "FORTUNE SKIN"
	jn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jn.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	sv.add_child(jn)
	var jd := Label.new()
	jd.theme_type_variation = &"SmallLabel"
	jd.text = "Only on the Daily Spin. Never sold."
	jd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jd.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	sv.add_child(jd)
	# The odds.
	var oc := Label.new()
	oc.theme_type_variation = &"SmallLabel"
	oc.text = "THE ODDS"
	oc.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	col.add_child(oc)
	odds_box = GridContainer.new()
	odds_box.name = "Odds"
	odds_box.columns = 4
	odds_box.add_theme_constant_override(&"h_separation", 14)
	odds_box.add_theme_constant_override(&"v_separation", 2)
	col.add_child(odds_box)
	var order: Array[int] = []
	for i: int in DailyWheel.count():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return DailyWheel.chance(a) > DailyWheel.chance(b))
	for i: int in order:
		var name_l := Label.new()
		name_l.theme_type_variation = &"SmallLabel"
		name_l.text = DailyWheel.label(i)
		name_l.add_theme_font_size_override(&"font_size", 14)
		var kind: StringName = DailyWheel.segment(i)["kind"]
		name_l.add_theme_color_override(&"font_color", Palette.COIN_GOLD if kind == DailyWheel.KIND_GOLD or kind == DailyWheel.KIND_SKIN else Palette.CREAM)
		var pct := Label.new()
		pct.theme_type_variation = &"SmallLabel"
		pct.text = DailyWheel.chance_text(i)
		pct.add_theme_font_size_override(&"font_size", 14)
		pct.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
		odds_box.add_child(name_l)
		odds_box.add_child(pct)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	# What was won.
	prize_title = Label.new()
	prize_title.name = "PrizeTitle"
	prize_title.theme_type_variation = &"HeadingLabel"
	prize_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prize_title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	col.add_child(prize_title)
	prize_detail = Label.new()
	prize_detail.name = "PrizeDetail"
	prize_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prize_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(prize_detail)
	wear_button = Button.new()
	wear_button.name = "WearFortune"
	wear_button.text = "WEAR THE FORTUNE SKIN"
	wear_button.visible = false
	wear_button.custom_minimum_size = Vector2(0, 44)
	wear_button.pressed.connect(func() -> void:
		if ProfileManager.wear(DailyWheel.SKIN_ID):
			wear_button.visible = false
			prize_detail.text = "Your bean wears it from the next match on.")
	col.add_child(wear_button)
	spin_button = Button.new()
	spin_button.name = "Spin"
	spin_button.text = "SPIN"
	spin_button.custom_minimum_size = Vector2(0, 56)
	spin_button.theme_type_variation = &"MenuEntry"
	spin_button.pressed.connect(spin)
	col.add_child(spin_button)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"SmallLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override(&"font_color", CosmeticsPanel.MUTED)
	col.add_child(status_label)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.custom_minimum_size = Vector2(0, 44)
	back_button.pressed.connect(close)
	col.add_child(back_button)
	return col


static func _skin_item() -> int:
	var d: CosmeticDef = CosmeticShop.default().find(DailyWheel.SKIN_ID)
	return d.steam_item if d != null else 0


## Seconds until the next spin (0 = now).
static func wait_s() -> int:
	return DailyWheel.wait_s(ProfileManager.profile.daily_last, SteamSvc.now())


## Whether a spin is free now (the main menu's entry shines then).
static func ready_now() -> bool:
	return wait_s() <= 0


func open() -> void:
	var host: Node = get_parent()
	if host != null:
		if _dim.get_parent() == null:
			host.add_child(_dim)
		host.move_child(_dim, -1)
		host.move_child(self, -1)
		_dim.visible = true
	visible = true
	if not SteamSvc.daily_ready():
		wheel.dimmed = []
		for i: int in DailyWheel.count():
			if DailyWheel.needs_steam(i):
				wheel.dimmed.append(i)
	else:
		wheel.dimmed = []
	back_button.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	if not wheel.busy():
		prize_title.text = ""
		prize_detail.text = ""
		wear_button.visible = false
	if not SteamSvc.daily_redeemed.is_connected(_on_redeemed):
		SteamSvc.daily_redeemed.connect(_on_redeemed)
		SteamSvc.daily_spun.connect(_on_spun)
	_refresh()
	(spin_button if not spin_button.disabled else back_button).grab_focus()


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


func _process(delta: float) -> void:
	if not visible:
		return
	if _waiting >= 0.0:
		_waiting += delta
		if _waiting > STEAM_TIMEOUT_S:
			_waiting = -1.0
			wheel.stop_anywhere()
			status_label.text = "Steam didn't answer. Try again in a moment."
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_refresh()


## SPIN: Steam's drop, or the local roll.
func spin() -> void:
	if wheel.busy() or wait_s() > 0:
		return
	prize_title.text = ""
	prize_detail.text = ""
	wear_button.visible = false
	_prize = {}
	Audio.play(&"slots_lever", &"UI", -4.0)
	if SteamSvc.daily_ready():
		if not SteamSvc.daily_spin():
			status_label.text = "Steam is busy. Try again in a moment."
			return
		_steam_spin = true
		_waiting = 0.0
		wheel.rev()
		status_label.text = "Spinning…"
	else:
		_steam_spin = false
		var got: Dictionary = ProfileManager.spin_local(SteamSvc.now())
		if got.is_empty():
			return
		_prize = got
		wheel.rev()
		# A short run-up before it eases out, like the Steam spin.
		get_tree().create_timer(0.7).timeout.connect(func() -> void: wheel.stop_at(int(got["index"])))
		status_label.text = "Spinning…"
	_refresh()


func _on_spun(result: Dictionary) -> void:
	if not _steam_spin or _waiting < 0.0:
		return
	_waiting = -1.0
	var i: int = int(result.get("index", -1))
	if i < 0:
		# Steam has no spin for this account yet (spun on another PC, or it wants a bit of play).
		ProfileManager.mark_daily_retry(SteamSvc.now())
		wheel.stop_anywhere()
		status_label.text = "Steam has no spin for you yet. Try again a little later."
		return
	ProfileManager.mark_daily_spin(SteamSvc.now())
	if _prize.is_empty() or int(_prize.get("index", -1)) != i:
		_prize = {"index": i, "coins": 0, "piece": &"", "gold": 0}
	wheel.stop_at(i)


## A token was paid out (maybe before the wheel has landed): its details go into the prize card.
func _on_redeemed(prize: Dictionary) -> void:
	if _prize.is_empty() or int(prize.get("index", -2)) != int(_prize.get("index", -1)):
		return
	_prize = prize
	if not wheel.busy():
		_show_prize()


func _on_landed(index: int) -> void:
	if index < 0:
		_refresh()
		return
	var kind: StringName = DailyWheel.segment(index)["kind"]
	if kind == DailyWheel.KIND_SKIN:
		Audio.play(&"jackpot_siren", &"UI", -4.0)
		Audio.play(&"jackpot_prize", &"UI", -2.0)
	elif kind == DailyWheel.KIND_GOLD or int(DailyWheel.segment(index)["amount"]) >= 1000:
		Audio.play(&"big_win", &"UI", -4.0)
	else:
		Audio.play(&"minor_win", &"UI", -4.0)
	_show_prize()
	_refresh()


func _show_prize() -> void:
	if _prize.is_empty():
		return
	var i: int = int(_prize.get("index", -1))
	if i < 0:
		return
	var seg: Dictionary = DailyWheel.segment(i)
	match seg["kind"]:
		DailyWheel.KIND_COINS:
			prize_title.text = "%s COINS!" % DailyWheel.thousands(int(seg["amount"]))
			prize_detail.text = "Added to your Coins. Spend them in the shop."
		DailyWheel.KIND_GOLD:
			prize_title.text = "%d GOLD COINS!" % int(seg["amount"])
			prize_detail.text = "In your Steam inventory. Gold buys the premium pieces and sets."
		DailyWheel.KIND_PIECE:
			var piece: StringName = _prize.get("piece", &"")
			var d: CosmeticDef = CosmeticShop.default().find(piece)
			prize_title.text = "MYSTERY PIECE!"
			if d != null:
				prize_detail.text = "%s is yours. Find it in your cosmetics." % d.display_name
			elif int(_prize.get("coins", 0)) > 0:
				prize_detail.text = "You own every piece already, so it pays %s Coins." % DailyWheel.thousands(int(_prize.get("coins", 0)))
			else:
				prize_detail.text = "Unwrapping it…"
		_:
			prize_title.text = "JACKPOT!"
			prize_detail.text = "The Fortune skin is yours. Only the Daily Spin has it."
			wear_button.visible = true


func _refresh() -> void:
	var w: int = wait_s()
	wheel.clickable = not wheel.busy() and w <= 0
	if wheel.busy():
		spin_button.disabled = true
		spin_button.text = "SPINNING…"
		return
	spin_button.disabled = w > 0
	spin_button.text = "SPIN" if w <= 0 else "NEXT SPIN IN %s" % DailyWheel.wait_text(w)
	if w > 0:
		spin_button.add_theme_font_size_override(&"font_size", 26)
	else:
		spin_button.remove_theme_font_size_override(&"font_size")
	if w <= 0 and status_label.text in ["", "Spinning…"]:
		status_label.text = "" if SteamSvc.daily_ready() else ("Gold Coins and the jackpot need Steam." if not SteamSvc.is_available() else "Gold Coins and the jackpot are coming soon.")
	elif w > 0 and status_label.text in ["", "Spinning…"]:
		status_label.text = "One spin a day. Come back tomorrow for the next one."
