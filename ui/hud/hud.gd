class_name Hud
extends Control
## In-world HUD (docs/ART_DIRECTION.md): money top-left with +/- pops, timer top-right, rank
## bottom-right, item slots bottom-centre, event feed, interaction prompt, crosshair, toast,
## leaderboard on hold. Reads a ClientMatchState; never talks to the server.

const FEED_MAX: int = 6
const FEED_SECONDS: float = 6.0

var state: ClientMatchState = null
var local_id: int = -1

var money_label: Label
var timer_label: Label
var rank_label: Label
var phase_label: Label
var jackpot_label: Label
## "ON TABLES $75 · Roulette 1 $50 · Blackjack 2 $25": money you have riding right now.
var in_play_label: Label
var prompt_label: Label
var toast_label: Label
var crosshair: Control
var feed: VBoxContainer
var items: ItemBar
var leaderboard: PanelContainer
var leaderboard_rows: VBoxContainer
var last_call_banner: Label
var pops: Control
## Item activation banner (centre-top).
var item_banner: Label
## Under the timer: "QUIZ IN 1:12".
var next_quiz_label: Label
## Centre warning during the 10 s before a minigame.
var minigame_warning: Label
## Hot Table line under the timer ("HOT: Roulette 1 ×1.25 0:24").
var hot_label: Label
var _last_warning_second: int = -1

## Beer: the money counter shows "$???" and no +/- pops until you sober up.
var money_hidden: bool = false

var _toast_until: float = -INF
var _clock: float = 0.0
var _displayed_money: float = 0.0
var _feed_times: Array[float] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if state != null:
		bind(state, local_id)


## Connects the HUD to the client mirror.
func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	if state != null and state.money_changed.is_connected(_on_money_changed):
		state.money_changed.disconnect(_on_money_changed)
		state.feed_message.disconnect(_on_feed)
		state.phase_changed.disconnect(_on_phase)
	state = p_state
	local_id = p_local_id
	state.money_changed.connect(_on_money_changed)
	state.feed_message.connect(_on_feed)
	state.phase_changed.connect(_on_phase)
	if not state.players_changed.is_connected(_refresh_items):
		state.players_changed.connect(_refresh_items)
	_displayed_money = float(state.balance(local_id))
	_refresh_static()


## Interaction prompt ("" hides it).
func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = text != ""


## Big centred banner for item activations aimed at or by the local player.
func banner(text: String, color: Color = Palette.VIP_GOLD, seconds: float = 2.2) -> void:
	item_banner.text = text
	item_banner.add_theme_color_override(&"font_color", color)
	item_banner.visible = true
	item_banner.modulate.a = 1.0
	item_banner.scale = Vector2(1.25, 1.25)
	item_banner.pivot_offset = item_banner.size / 2.0
	var t: Tween = create_tween()
	t.tween_property(item_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(seconds)
	t.tween_property(item_banner, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void: item_banner.visible = false)


## Short centred message (rejections, VIP sign).
func toast(text: String, seconds: float = 2.0) -> void:
	toast_label.text = text
	toast_label.visible = true
	_toast_until = _clock + seconds


func show_leaderboard(shown: bool) -> void:
	leaderboard.visible = shown
	if shown:
		_fill_leaderboard()


func set_crosshair_visible(v: bool) -> void:
	crosshair.visible = v


## Spawns a floating +$X / -$X near the money counter.
func money_pop(amount: int) -> void:
	var l := Label.new()
	l.text = ("+$%d" if amount > 0 else "-$%d") % absi(amount)
	l.theme_type_variation = &"MoneyLabel"
	l.add_theme_font_size_override(&"font_size", 40)
	l.add_theme_color_override(&"font_color", Palette.delta_color(amount))
	l.position = Vector2(randf_range(0, 60), 70)
	pops.add_child(l)
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", 10.0, 1.2).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	t.chain().tween_callback(l.queue_free)


func _process(delta: float) -> void:
	_clock += delta
	if toast_label.visible and _clock > _toast_until:
		toast_label.visible = false
	for i: int in range(_feed_times.size() - 1, -1, -1):
		if _clock - _feed_times[i] > FEED_SECONDS and i < feed.get_child_count():
			feed.get_child(i).queue_free()
			_feed_times.remove_at(i)
	if state == null:
		return
	var target: float = float(state.balance(local_id))
	_displayed_money = lerpf(_displayed_money, target, minf(1.0, 12.0 * delta))
	if absf(_displayed_money - target) < 1.0:
		_displayed_money = target
	money_label.text = "$???" if money_hidden else "$%s" % _thousands(int(round(_displayed_money)))
	var t: int = int(ceil(maxf(state.time_left, 0.0)))
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
	rank_label.text = "%s / %d" % [_ordinal(state.rank_of(local_id)), maxi(state.balances.size(), 1)]
	jackpot_label.text = "JACKPOT $%s" % _thousands(state.jackpot)
	in_play_label.text = in_play_text(state, local_id)
	in_play_label.visible = in_play_label.text != ""
	if state.last_call:
		last_call_banner.visible = true
		last_call_banner.text = "LAST CALL  ×%.1f PAYOUTS  %02d:%02d" % [Registry.balance.last_call_multiplier, t / 60, t % 60]
		timer_label.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	if leaderboard.visible:
		_fill_leaderboard()
	_update_countdowns()


## Next-quiz countdown, the pre-minigame warning and the Hot Table line.
func _update_countdowns() -> void:
	var nm: float = state.next_minigame_in
	var casino: bool = state.phase == Phase.Id.CASINO or state.phase == Phase.Id.PRE_MINIGAME
	next_quiz_label.visible = casino and nm >= 0.0
	if next_quiz_label.visible:
		var n: int = ceili(nm)
		next_quiz_label.text = "QUIZ IN %d:%02d" % [n / 60, n % 60]
	var warn: bool = state.phase == Phase.Id.PRE_MINIGAME
	minigame_warning.visible = warn
	if warn:
		var sec: int = ceili(maxf(nm, 0.0))
		minigame_warning.text = "QUIZ TIME in %d…  Tables closing!" % sec
		if sec != _last_warning_second and sec > 0:
			_last_warning_second = sec
			Audio.play(&"countdown_beep", &"UI", -12.0, 1.0 + (10 - sec) * 0.03)
	hot_label.visible = casino and state.hot_station != &""
	if hot_label.visible:
		var h: int = ceili(state.hot_left)
		hot_label.text = "HOT: %s ×%.2f  0:%02d" % [ClientMatchState.station_label(state.hot_station), Registry.balance.hot_table_multiplier, h]


## A new match in the same room: clear Last Call colours and banners.
func reset_match() -> void:
	last_call_banner.visible = false
	timer_label.remove_theme_color_override(&"font_color")
	_last_warning_second = -1
	_displayed_money = float(state.balance(local_id)) if state != null else 0.0
	_refresh_items()


## Item slots show what's in the inventory.
func _refresh_items() -> void:
	if state == null or items == null:
		return
	items.set_inventory(state.players.get(local_id, {}).get("inventory", []))


func _on_money_changed(player: int, amount: int, _balance: int, reason: StringName) -> void:
	if player != local_id or amount == 0:
		return
	if not money_hidden:
		money_pop(amount)
	if reason == &"stake":
		Audio.play(&"chip_clack", &"SFX", -8.0)
	elif amount > 0:
		Audio.play(&"coin" if amount < 200 else &"big_win", &"SFX", -6.0)


func _on_feed(text: String, kind: StringName) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SmallLabel"
	var c: Color = Palette.CREAM
	match kind:
		&"win":
			c = Palette.MONEY_GREEN
		&"loss":
			c = Palette.LOSS_RED
		&"jackpot", &"last_call":
			c = Palette.VIP_GOLD
		&"chaos":
			c = Color("#F0B27A")
		&"item":
			c = Palette.VIP_GOLD
	l.add_theme_color_override(&"font_color", c)
	feed.add_child(l)
	_feed_times.append(_clock)
	while feed.get_child_count() > FEED_MAX:
		feed.get_child(0).free()
		_feed_times.remove_at(0)


func _on_phase(phase: Phase.Id) -> void:
	phase_label.text = "LOBBY" if phase == Phase.Id.LOBBY else ""
	phase_label.visible = phase_label.text != ""


func _refresh_static() -> void:
	_refresh_items()


func _fill_leaderboard() -> void:
	for c: Node in leaderboard_rows.get_children():
		c.free()
	var ids: Array = state.balances.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return state.balance(a) > state.balance(b))
	var rank: int = 0
	for id: int in ids:
		rank += 1
		var row := Label.new()
		row.text = "%s  %-14s  $%s" % [_ordinal(rank), state.player_name(id), _thousands(state.balance(id))]
		row.add_theme_font_size_override(&"font_size", 28)
		if id == local_id:
			row.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		leaderboard_rows.add_child(row)


func _build() -> void:
	# Top-left: money + jackpot.
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 20)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl)
	money_label = Label.new()
	money_label.theme_type_variation = &"MoneyLabel"
	money_label.add_theme_font_size_override(&"font_size", 64)
	money_label.text = "$0"
	tl.add_child(money_label)
	jackpot_label = Label.new()
	jackpot_label.theme_type_variation = &"SmallLabel"
	jackpot_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	tl.add_child(jackpot_label)
	in_play_label = Label.new()
	in_play_label.theme_type_variation = &"SmallLabel"
	in_play_label.add_theme_color_override(&"font_color", Palette.CREAM)
	in_play_label.add_theme_constant_override(&"outline_size", 6)
	in_play_label.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	in_play_label.visible = false
	tl.add_child(in_play_label)
	pops = Control.new()
	pops.position = Vector2(300, 10)
	pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pops)
	# Top-right: timer + phase.
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -300
	tr.offset_right = -28
	tr.offset_top = 20
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(tr)
	timer_label = Label.new()
	timer_label.theme_type_variation = &"MoneyLabel"
	timer_label.add_theme_font_size_override(&"font_size", 56)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label.text = "10:00"
	tr.add_child(timer_label)
	phase_label = Label.new()
	phase_label.theme_type_variation = &"HeadingLabel"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	phase_label.visible = false
	tr.add_child(phase_label)
	next_quiz_label = Label.new()
	next_quiz_label.theme_type_variation = &"SmallLabel"
	next_quiz_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_quiz_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	next_quiz_label.visible = false
	tr.add_child(next_quiz_label)
	hot_label = Label.new()
	hot_label.theme_type_variation = &"SmallLabel"
	hot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hot_label.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	hot_label.visible = false
	tr.add_child(hot_label)
	# Bottom-right: rank.
	rank_label = Label.new()
	rank_label.theme_type_variation = &"MoneyLabel"
	rank_label.add_theme_font_size_override(&"font_size", 44)
	rank_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	rank_label.anchor_left = 1.0
	rank_label.anchor_top = 1.0
	rank_label.offset_left = -300
	rank_label.offset_right = -28
	rank_label.offset_top = -90
	rank_label.offset_bottom = -24
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank_label.text = "1st / 1"
	add_child(rank_label)
	# Bottom-centre: item slots.
	items = ItemBar.new()
	items.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	items.anchor_left = 0.5
	items.anchor_right = 0.5
	items.anchor_top = 1.0
	items.anchor_bottom = 1.0
	items.offset_left = -340
	items.offset_right = 340
	items.offset_top = -420
	items.offset_bottom = -20
	add_child(items)
	# Left-bottom: feed.
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	feed.anchor_top = 1.0
	feed.anchor_bottom = 1.0
	feed.offset_left = 28
	feed.offset_right = 600
	feed.offset_top = -260
	feed.offset_bottom = -24
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed)
	# Centre: crosshair, prompt, toast, last call.
	crosshair = ColorRect.new()
	crosshair.color = Palette.CREAM
	crosshair.size = Vector2(6, 6)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -3
	crosshair.offset_top = -3
	crosshair.offset_right = 3
	crosshair.offset_bottom = 3
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)
	prompt_label = _centre_label(80, 30, Palette.CREAM)
	prompt_label.visible = false
	toast_label = _centre_label(-120, 40, Palette.VIP_GOLD)
	toast_label.visible = false
	last_call_banner = _centre_label(-320, 56, Palette.LOSS_RED)
	last_call_banner.theme_type_variation = &"TitleLabel"
	last_call_banner.visible = false
	minigame_warning = _centre_label(-250, 44, Palette.VIP_GOLD)
	minigame_warning.theme_type_variation = &"TitleLabel"
	minigame_warning.visible = false
	item_banner = _centre_label(-200, 48, Palette.VIP_GOLD)
	item_banner.theme_type_variation = &"TitleLabel"
	item_banner.visible = false
	# Leaderboard (hold Tab).
	leaderboard = PanelContainer.new()
	leaderboard.set_anchors_preset(Control.PRESET_CENTER)
	leaderboard.anchor_left = 0.5
	leaderboard.anchor_right = 0.5
	leaderboard.anchor_top = 0.5
	leaderboard.anchor_bottom = 0.5
	leaderboard.offset_left = -260
	leaderboard.offset_right = 260
	leaderboard.offset_top = -200
	leaderboard.offset_bottom = 200
	leaderboard.visible = false
	add_child(leaderboard)
	var lb := VBoxContainer.new()
	leaderboard.add_child(lb)
	var title := Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = "STANDINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_child(title)
	leaderboard_rows = VBoxContainer.new()
	lb.add_child(leaderboard_rows)
	_outline_labels(self)


## Every HUD label floats over the 3D scene, so each gets a dark outline to stay readable on
## bright walls and signs (Patrick: text running into the background).
func _outline_labels(node: Node) -> void:
	for c: Node in node.get_children():
		if c is Label and not (c as Label).has_theme_constant_override(&"outline_size"):
			(c as Label).add_theme_constant_override(&"outline_size", 4)
			(c as Label).add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
		if not c is PanelContainer:
			_outline_labels(c)


func _centre_label(offset_y: float, size: int, color: Color) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 0.5
	l.anchor_bottom = 0.5
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = offset_y
	l.offset_bottom = offset_y + size + 20
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Stakes the player has on tables that haven't settled yet (roulette chips, a blackjack hand).
static func in_play_text(st: ClientMatchState, pid: int) -> String:
	var parts: PackedStringArray = []
	var total: int = 0
	var ids: Array = st.stations.keys()
	ids.sort()
	for sid: Variant in ids:
		var pub: Dictionary = st.stations[sid]
		var amount: int = 0
		match StringName(pub.get("game", "")):
			&"roulette":
				if int(pub.get("state", 0)) != RouletteLogic.State.RESULT:
					for b: Dictionary in pub.get("bets", []):
						if int(b["player"]) == pid:
							amount += int(b["amount"])
			&"blackjack":
				if int(pub.get("state", 0)) != BlackjackLogic.State.PAYOUT:
					var hands: Dictionary = pub.get("hands", {})
					for k: Variant in hands:
						if int(k) == pid:
							amount += int(hands[k].get("stake", 0))
		if amount > 0:
			total += amount
			parts.append("%s $%d" % [ClientMatchState.station_label(StringName(sid)), amount])
	if total == 0:
		return ""
	return "ON TABLES $%d  ·  %s" % [total, "  ·  ".join(parts)]


static func _thousands(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


static func _ordinal(n: int) -> String:
	var suffix: String = "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]
