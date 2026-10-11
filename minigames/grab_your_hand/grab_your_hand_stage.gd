class_name GrabYourHandStage
extends WalkableStage
## Client presentation of Grab Your Hand in the card hall (`CardHall`; a `WalkableStage`: real
## avatars, the normal camera). Lucky deals from the table at the far wall and hosts: giant cards
## fall onto the marble (`HallCard`: upright, turning, a gold glow under each), a bean that walks
## over one takes it (it shrinks into their hand) and every bean's hand is fanned over their head
## (`HandFan`, with its name: "PAIR", "FLUSH"...). The overlay shows the clock, everyone's hand
## name (top left), the feed, Lucky's lines (bottom left) and our own hand as five big cards along
## the bottom: number keys 1–5 or the mouse wheel pick the card E drops (the worst card unless we
## picked one). At the whistle the hands fan out big over every head and a showdown table lists
## them best first; Lucky names the winner.
##
## The server decides every pickup, drop and shove-drop; this side only sends
## `minigame_action {kind: "drop", target: slot}`.

const GAME_SECONDS: float = GrabYourHandLogic.GAME_SECONDS
const HAND_MAX: int = GrabYourHandLogic.HAND_MAX
## Height of a fan's base over a standing bean.
const FAN_UP: float = 2.25
const FAN_UP_BIG: float = 2.6
## The bottom hand bar's card height (px).
const BAR_CARD_H: float = 120.0

var clock: float = 0.0
var done: bool = false
## pid → cards in pickup order (slot order); pid → hand name.
var hands: Dictionary[int, Array] = {}
var hand_names: Dictionary[int, String] = {}
## floor id → the card node on the floor.
var floor_nodes: Dictionary[int, HallCard] = {}
var fans: Dictionary[int, HandFan] = {}
var gone: Array[int] = []
## The slot E drops; `_manual` once the player picked one (until the hand changes).
var selected: int = -1
var _manual: bool = false
var final_ranking: Array = []
var host: QuizHost = null
var _spin: Node3D = null
var _bar: HBoxContainer = null
var _bar_panel: PanelContainer = null
var _bar_title: Label = null
var _bar_hint: Label = null
var _showdown: PanelContainer = null
var _host_panel: PanelContainer = null
var _host_label: Label = null
var _said_half: bool = false
var _said_ten: bool = false
var _full_warned: float = 0.0


func _build_room() -> Node3D:
	return CardHall.build(self)


func _build_game(_start: Dictionary) -> void:
	for p: int in roster:
		hands[p] = []
		hand_names[p] = "NO CARDS"
	if room != null:
		_spin = room.get_node_or_null(^"Centerpiece/Spin") as Node3D
	if _is_dedicated():
		return
	host = QuizHost.new()
	host.name = "LuckyHost"
	add_child(host)
	host.position = WalkableLogicBase.ROOM_ORIGIN + CardHall.LUCKY_SPOT
	host.scale = Vector3.ONE * 1.1
	for p: int in roster:
		var fan := HandFan.new()
		add_child(fan)
		fans[p] = fan
		fan.visible = false
	if overlay != null:
		_build_host_panel()
		_build_bar()
		var pill: Control = overlay.get_node_or_null(^"PromptPill") as Control
		if pill != null:
			pill.position.y = -290
	_say("Welcome to my card hall! Grab the best poker hand you can carry. Five cards max!", QuizHost.Pose.HAPPY, 3.0)
	_refresh_hud()


func apply_state(st: Dictionary) -> void:
	super.apply_state(st)
	clock = float(st.get("clock", clock))
	done = str(st.get("state", "")) == "reveal" or bool(st.get("finished", false))
	var hw: Dictionary = st.get("hands", {})
	for k: Variant in hw:
		_set_hand(int(k), hw[k])
	var seen: Array[int] = []
	for f: Variant in st.get("floor", []):
		var fd: Dictionary = f
		seen.append(int(fd["id"]))
		if not floor_nodes.has(int(fd["id"])):
			_add_floor_card(fd, false)
	for fid: int in floor_nodes.keys():
		if fid not in seen:
			_remove_floor_card(fid, null)
	if st.has("ranking"):
		final_ranking = st["ranking"]
	_refresh_hud()


func alive_players() -> Array[int]:
	var res: Array[int] = []
	for p: int in roster:
		if p not in gone:
			res.append(p)
	return res


func action_kind() -> StringName:
	return &"drop"


func can_act() -> bool:
	return super.can_act() and not done and local_id in roster and local_id not in gone and not my_hand().is_empty()


func my_hand() -> Array:
	return hands.get(local_id, [])


## E: drop the selected card (the server lays it in front of us).
func on_action_pressed() -> bool:
	if not can_act():
		return going and not over
	var hand: Array = my_hand()
	var slot: int = selected if selected >= 0 and selected < hand.size() else PokerHand.worst_index(hand)
	Net.send_intent(Intents.make(&"minigame_action", {"kind": &"drop", "target": slot}))
	return true


## Picks the slot E drops (number keys, the wheel).
func select_slot(slot: int) -> void:
	var n: int = my_hand().size()
	if n == 0 or slot < 0 or slot >= n:
		return
	if slot != selected:
		Audio.play(&"card_flip", &"UI", -14.0, 1.4)
	selected = slot
	_manual = true
	_refresh_bar()


func _input(event: InputEvent) -> void:
	if not going or over or done or my_hand().is_empty():
		return
	if scene != null and scene.router != null and scene.router.mode != InputRouter.Mode.WALK:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var k: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if k >= KEY_1 and k <= KEY_5:
			select_slot(int(k - KEY_1))
			get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var n: int = my_hand().size()
		var cur: int = selected if selected >= 0 else 0
		select_slot(posmod(cur + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), n))
		get_viewport().set_input_as_handled()


# --- Events -------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	super.on_event(ev)
	var type: StringName = StringName(ev["type"])
	match type:
		&"minigame_go":
			if not _is_dedicated():
				banner("GRAB YOUR HAND!", Palette.VIP_GOLD, 1.4)
				Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
		&"grab_your_hand_begin":
			clock = 0.0
			if not _is_dedicated():
				_say("Cards are coming! Walk over one to pick it up. Shove a rival and they drop one!", QuizHost.Pose.HAPPY, 3.0)
				Audio.play(&"whistle", &"SFX", -4.0)
		&"grab_your_hand_spawned":
			var i: int = 0
			for f: Variant in ev.get("cards", []):
				_add_floor_card(f, true, 0.06 * float(i))
				i += 1
			if not _is_dedicated() and i > 0:
				Audio.play(&"card_deal", &"UI", -8.0)
		&"grab_your_hand_picked":
			_on_picked(int(ev["player"]), int(ev["id"]), int(ev["card"]), ev.get("hand", []))
		&"grab_your_hand_dropped":
			_on_dropped(ev)
		&"grab_your_hand_over":
			_on_over(ev)
		&"grab_your_hand_finished":
			final_ranking = ev.get("ranking", final_ranking)
		&"minigame_eliminated":
			for p: Variant in ev.get("players", []):
				_drop_player(int(p))
				if StringName(ev.get("cause", &"")) == &"dropout":
					feed("%s left the game" % player_name(int(p)), Color(Palette.CREAM, 0.7))
		&"rewards_started":
			_close_showdown()
	_refresh_hud()


func _on_picked(pid: int, fid: int, card: int, hand: Array) -> void:
	_remove_floor_card(fid, avatar(pid))
	_set_hand(pid, hand)
	if _is_dedicated():
		return
	var a: PlayerAvatar = avatar(pid)
	if a != null:
		Audio.play_at(&"card_flip", a, -4.0, 1.1)
	if pid == local_id:
		Audio.play(&"chime", &"SFX", -10.0, 1.4)
		feed("You picked up the %s" % PokerHand.card_name(card).to_lower(), Palette.MONEY_GREEN)
		var tuple: Array[int] = PokerHand.evaluate(hand)
		if int(tuple[0]) >= PokerHand.Category.PAIR and hand_names.get(pid, "") != "":
			_flash_bar_title()
	elif hand.size() >= HAND_MAX:
		feed("%s has a full hand: %s" % [player_name(pid), PokerHand.name_of(PokerHand.evaluate(hand)).to_lower()], player_color(pid))


func _on_dropped(ev: Dictionary) -> void:
	var pid: int = int(ev["player"])
	_set_hand(pid, ev.get("hand", []))
	var node: HallCard = _add_floor_card(ev, false)
	if _is_dedicated():
		return
	var a: PlayerAvatar = avatar(pid)
	var from: Vector3 = a.global_position + Vector3(0, 1.3, 0) if a != null else Serializer.to_vec3(ev.get("from", ev["pos"]))
	if node != null:
		node.land_from(from)
	var how: StringName = StringName(ev.get("how", &"drop"))
	var card: int = int(ev["card"])
	if how == &"shove":
		var by: int = int(ev.get("attacker", -1))
		Audio.play(&"whoosh", &"SFX", -6.0, 1.3)
		if a != null:
			Vfx.floating_text(self, a.global_position + Vector3(0, 2.2, 0), "DROPPED!", Palette.LOSS_RED, 90, 0.8, 1.0)
		feed("%s knocked the %s out of %s's hand" % [player_name(by), PokerHand.card_name(card).to_lower(), player_name(pid)], player_color(by))
		if pid == local_id:
			banner("SHOVED! YOU DROPPED A CARD", Palette.LOSS_RED, 1.2)
		elif by == local_id:
			banner("THEY DROPPED THE %s!" % PokerHand.card_name(card), Palette.MONEY_GREEN, 1.0)
	else:
		Audio.play(&"card_flip", &"UI", -8.0, 0.9)
		if pid == local_id:
			feed("You dropped the %s" % PokerHand.card_name(card).to_lower(), Color(Palette.CREAM, 0.8))


func _on_over(ev: Dictionary) -> void:
	done = true
	clock = GAME_SECONDS
	var hw: Dictionary = ev.get("hands", {})
	for k: Variant in hw:
		_set_hand(int(k), hw[k])
	final_ranking = ev.get("ranking", [])
	if _is_dedicated():
		return
	for p: int in fans:
		fans[p].set_big(true)
		fans[p].visible = not (hands.get(p, []) as Array).is_empty()
	Audio.play(&"whistle", &"SFX", -2.0)
	_open_showdown()
	var top: Array[int] = []
	var top_name: String = ""
	for row: Variant in final_ranking:
		if int(row["rank"]) == 1:
			top.append(int(row["player"]))
			top_name = str(row.get("describe", row.get("name", "")))
	if top.size() == 1:
		var w: int = top[0]
		banner("YOU WIN!" if w == local_id else "%s WINS!" % player_name(w).to_upper(), Palette.VIP_GOLD, 3.0)
		_say("Time! Show your cards... %s takes it with %s!" % [player_name(w), top_name.to_lower()], QuizHost.Pose.HAPPY, 5.0)
		var wa: PlayerAvatar = avatar(w)
		if wa != null:
			wa.visuals.react(&"big_win")
	elif top.size() > 1:
		var names: PackedStringArray = []
		for w: int in top:
			names.append(player_name(w))
		banner("SPLIT POT!", Palette.VIP_GOLD, 3.0)
		_say("Time! A split pot: %s tie with %s!" % [" and ".join(names), top_name.to_lower()], QuizHost.Pose.SURPRISED, 5.0)
	Audio.play(&"quiz_winner", &"SFX", -4.0)


# --- Floor cards and hands ----------------------------------------------------------------------

func _add_floor_card(f: Dictionary, deal: bool, delay: float = 0.0) -> HallCard:
	var fid: int = int(f["id"])
	if floor_nodes.has(fid):
		return floor_nodes[fid]
	var node: HallCard = HallCard.make(fid, int(f["card"]), float(f.get("yaw", 0.0)))
	add_child(node)
	node.global_position = Serializer.to_vec3(f["pos"])
	floor_nodes[fid] = node
	if deal and not _is_dedicated():
		node.deal_in(delay)
	return node


## A floor card leaves: into `to`'s hand (an avatar) or just gone.
func _remove_floor_card(fid: int, to: Node3D) -> void:
	if not floor_nodes.has(fid):
		return
	var node: HallCard = floor_nodes[fid]
	floor_nodes.erase(fid)
	if not is_instance_valid(node):
		return
	if to != null and not _is_dedicated():
		node.fly_to(to)
	else:
		node.queue_free()


func _set_hand(pid: int, cards: Variant) -> void:
	var hand: Array = []
	if cards is Array:
		for c: Variant in cards:
			hand.append(int(c))
	var before: Array = hands.get(pid, [])
	hands[pid] = hand
	hand_names[pid] = PokerHand.name_of(PokerHand.evaluate(hand))
	if fans.has(pid) and is_instance_valid(fans[pid]):
		fans[pid].set_cards(hand, hand_names[pid] if not hand.is_empty() else "")
	if pid == local_id and before != hand:
		_manual = false
		selected = PokerHand.worst_index(hand)
		_refresh_bar()


func _drop_player(pid: int) -> void:
	if pid not in gone:
		gone.append(pid)
	hands.erase(pid)
	if fans.has(pid) and is_instance_valid(fans[pid]):
		fans[pid].queue_free()
	fans.erase(pid)


## The floor card nearest to the local bean (flat distance), or -1.
func nearest_floor_card(within: float) -> int:
	var me: PlayerAvatar = local_avatar()
	if me == null:
		return -1
	var best: int = -1
	var best_d: float = within
	for fid: int in floor_nodes:
		var n: HallCard = floor_nodes[fid]
		if not is_instance_valid(n):
			continue
		var d: Vector3 = n.global_position - me.global_position
		d.y = 0.0
		if d.length() <= best_d:
			best_d = d.length()
			best = fid
	return best


# --- Per frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if going and not done and not over:
		clock = minf(clock + delta, GAME_SECONDS)
	if _spin != null:
		_spin.rotate_y(delta * (0.35 if not done else 1.2))
	_update_fans()
	_update_clock()
	_update_prompt(delta)
	if not done and not over and not _is_dedicated():
		var left: float = GAME_SECONDS - clock
		if going and not _said_half and left <= 25.0:
			_said_half = true
			_say("Halfway! Check those hands. A pair beats nothing!", QuizHost.Pose.DRUMROLL, 2.5)
		if going and not _said_ten and left <= 10.0:
			_said_ten = true
			_say("Ten seconds! Last chance to trade up!", QuizHost.Pose.SURPRISED, 2.5)
			Audio.play(&"countdown_beep", &"SFX", -6.0)


func _update_fans() -> void:
	for p: int in fans:
		var fan: HandFan = fans[p]
		if not is_instance_valid(fan):
			continue
		var a: PlayerAvatar = avatar(p)
		var hidden: bool = a == null or (p == local_id and not done and _first_person())
		fan.visible = not hidden and not (hands.get(p, []) as Array).is_empty()
		if a == null:
			continue
		var at: Vector3 = a.global_position
		if a.ragdoll != null and is_instance_valid(a.ragdoll):
			at = a.ragdoll.body_position()
		var goal: Vector3 = at + Vector3(0, FAN_UP_BIG if done else FAN_UP, 0)
		fan.global_position = fan.global_position.lerp(goal, 0.4) if fan.global_position.distance_to(goal) < 3.0 else goal


func _first_person() -> bool:
	var me: PlayerAvatar = local_avatar()
	return me != null and me.cam != null and me.cam.mode == PlayerCamera.Mode.FIRST


func _update_clock() -> void:
	if clock_label == null:
		return
	if done or over:
		clock_label.text = "TIME!"
		clock_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	else:
		set_clock(GAME_SECONDS - clock)


func _update_prompt(delta: float) -> void:
	_full_warned = maxf(_full_warned - delta, 0.0)
	if prompt_label == null:
		return
	if not going or over or done or local_id not in roster or local_id in gone:
		set_prompt("")
		return
	var hand: Array = my_hand()
	var near: int = nearest_floor_card(GrabYourHandLogic.PICK_REACH + 0.6)
	if hand.size() >= HAND_MAX and near >= 0:
		set_prompt("HAND FULL!  DROP A CARD  [{interact}]")
		if _full_warned <= 0.0:
			_full_warned = 4.0
			Audio.play(&"buzzer", &"SFX", -16.0, 1.5)
	elif hand.is_empty() and clock < 8.0:
		set_prompt("WALK OVER A CARD TO PICK IT UP")
	else:
		set_prompt("")


func _refresh_hud() -> void:
	_refresh_bar()
	if status_label == null:
		return
	var lines: PackedStringArray = ["HANDS"]
	for p: int in roster:
		if p in gone:
			continue
		var who: String = "YOU" if p == local_id else player_name(p)
		var n: int = (hands.get(p, []) as Array).size()
		lines.append("%s  %s  (%d)" % [who, hand_names.get(p, "NO CARDS"), n])
	status_label.text = "\n".join(lines)
	status_label.add_theme_font_size_override(&"font_size", 24)


# --- Our hand bar -------------------------------------------------------------------------------

func _build_bar() -> void:
	_bar_panel = PanelContainer.new()
	_bar_panel.name = "HandBar"
	var sb: StyleBoxFlat = plaque_style()
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	_bar_panel.add_theme_stylebox_override(&"panel", sb)
	_bar_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar_panel.offset_top = -16
	_bar_panel.offset_bottom = -16
	_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_bar_panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 4)
	_bar_panel.add_child(col)
	_bar_title = label("YOUR HAND", 28, Palette.VIP_GOLD)
	_bar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_bar_title)
	_bar = HBoxContainer.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override(&"separation", 10)
	col.add_child(_bar)
	_bar_hint = label("", 20, Color(Palette.CREAM, 0.85))
	_bar_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_bar_hint)
	_refresh_bar()


func _refresh_bar() -> void:
	if _bar == null:
		return
	for ch: Node in _bar.get_children():
		_bar.remove_child(ch)
		ch.queue_free()
	var hand: Array = my_hand()
	if selected >= hand.size():
		selected = PokerHand.worst_index(hand)
	for i: int in HAND_MAX:
		var slot := VBoxContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_constant_override(&"separation", 2)
		var holder := PanelContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hs := StyleBoxFlat.new()
		hs.set_corner_radius_all(10)
		hs.content_margin_left = 4
		hs.content_margin_right = 4
		hs.content_margin_top = 4
		hs.content_margin_bottom = 4
		var picked: bool = i == selected and i < hand.size()
		hs.bg_color = Color(Palette.VIP_GOLD, 0.35) if picked else Color(0, 0, 0, 0)
		hs.border_color = Palette.VIP_GOLD if picked else Color(Palette.CREAM, 0.25 if i >= hand.size() else 0.0)
		hs.set_border_width_all(3 if picked else 2)
		holder.add_theme_stylebox_override(&"panel", hs)
		if i < hand.size():
			var face: CardFace = CardFace.make(int(hand[i]), BAR_CARD_H)
			holder.add_child(face)
		else:
			var empty := Control.new()
			empty.custom_minimum_size = Vector2(roundf(BAR_CARD_H * CardFace.ASPECT), BAR_CARD_H)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(empty)
		slot.add_child(holder)
		var num: Label = label(("DROP" if picked else str(i + 1)), 20, Palette.VIP_GOLD if picked else Color(Palette.CREAM, 0.7))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(num)
		_bar.add_child(slot)
	var tuple: Array[int] = PokerHand.evaluate(hand)
	_bar_title.text = PokerHand.describe(tuple) if not hand.is_empty() else "YOUR HAND"
	_bar_hint.text = InputGlyphs.fill("[{interact}] DROP  ·  1-5 / WHEEL: PICK A CARD") if not hand.is_empty() else "WALK OVER CARDS TO PICK THEM UP"
	_bar_panel.visible = local_id in roster and local_id not in gone and not over and not done


func _flash_bar_title() -> void:
	if _bar_title == null:
		return
	_bar_title.pivot_offset = _bar_title.size * 0.5
	_bar_title.scale = Vector2.ONE * 1.35
	_bar_title.create_tween().tween_property(_bar_title, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- The showdown table -------------------------------------------------------------------------

func _open_showdown() -> void:
	if overlay == null or final_ranking.is_empty():
		return
	_close_showdown()
	if _bar_panel != null:
		_bar_panel.visible = false
	_showdown = PanelContainer.new()
	_showdown.name = "Showdown"
	var sb: StyleBoxFlat = plaque_style()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.88)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 18
	_showdown.add_theme_stylebox_override(&"panel", sb)
	_showdown.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_showdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_showdown.grow_vertical = Control.GROW_DIRECTION_BOTH
	_showdown.position.y += 60
	_showdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_showdown)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 8)
	_showdown.add_child(col)
	var title: Label = label("SHOWDOWN", 44, Palette.VIP_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var card_h: float = 78.0 if final_ranking.size() <= 5 else 58.0
	var i: int = 0
	for row: Variant in final_ranking:
		var r: Dictionary = row
		var pid: int = int(r["player"])
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override(&"separation", 14)
		var first: bool = int(r["rank"]) == 1
		var rank: Label = label("%d." % int(r["rank"]), 32, Palette.VIP_GOLD if first else Palette.CREAM)
		rank.custom_minimum_size = Vector2(44, 0)
		line.add_child(rank)
		var who: Label = label("YOU" if pid == local_id else player_name(pid), 30, player_color(pid))
		who.custom_minimum_size = Vector2(190, 0)
		who.clip_text = true
		line.add_child(who)
		var cards := HBoxContainer.new()
		cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards.add_theme_constant_override(&"separation", 4)
		cards.custom_minimum_size = Vector2((roundf(card_h * CardFace.ASPECT) + 4.0) * HAND_MAX, card_h)
		var hand: Array = r.get("hand", hands.get(pid, []))
		var k: int = 0
		for c: Variant in hand:
			var face: CardFace = CardFace.make(int(c), card_h)
			cards.add_child(face)
			face.deal_in(0.15 * float(i) + 0.06 * float(k))
			k += 1
		line.add_child(cards)
		var hn: Label = label(str(r.get("describe", r.get("name", ""))), 28, Palette.VIP_GOLD if first else Palette.CREAM)
		hn.custom_minimum_size = Vector2(330, 0)
		line.add_child(hn)
		col.add_child(line)
		i += 1
	_showdown.modulate.a = 0.0
	_showdown.create_tween().tween_property(_showdown, "modulate:a", 1.0, 0.3)


func _close_showdown() -> void:
	if _showdown != null and is_instance_valid(_showdown):
		_showdown.queue_free()
	_showdown = null


# --- Lucky ----------------------------------------------------------------------------------------

func _build_host_panel() -> void:
	_host_panel = PanelContainer.new()
	_host_panel.name = "LuckyLine"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CREAM
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = Palette.WARM_GOLD
	sb.content_margin_left = 16
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6
	_host_panel.add_theme_stylebox_override(&"panel", sb)
	_host_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_host_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_host_panel.position = Vector2(24, -40)
	_host_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_panel.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_panel.add_child(row)
	var tag: Label = label("LUCKY", 24, Palette.VIP_BURGUNDY)
	tag.remove_theme_color_override(&"font_shadow_color")
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tag)
	_host_label = label("", 24, Palette.CASINO_BLACK)
	_host_label.remove_theme_color_override(&"font_shadow_color")
	_host_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_label.custom_minimum_size = Vector2(380, 0)
	row.add_child(_host_label)
	overlay.add_child(_host_panel)


## Lucky says `text` (bottom-left line) and strikes `pose`.
func _say(text: String, pose: QuizHost.Pose = QuizHost.Pose.IDLE, hold: float = 2.2) -> void:
	if host != null:
		host.say(text)
		if pose != QuizHost.Pose.IDLE:
			host.set_pose(pose, hold)
	if _host_label == null:
		return
	_host_label.text = text
	_host_panel.visible = text != ""
	_host_panel.pivot_offset = Vector2(0, _host_panel.size.y)
	_host_panel.scale = Vector2.ONE * 0.85
	_host_panel.create_tween().tween_property(_host_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
