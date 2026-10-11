class_name ItemController
extends Node3D
## Client side of items (0.8.19, "hold it in your hand"). The mouse wheel or keys 1–3 (Shift+1–3
## seated, the d-pad and shoulder buttons on a gamepad) pick a slot and the item appears in the
## bean's hand (ItemModels). Left click or E uses it, right click puts it away; pressing the held
## slot's key again uses it too. Items aimed at a player hit whoever you are looking at: the nearest
## other player inside a forward cone (`AIM_CONE_DEG`) and the item's range, marked with a ring on
## the floor and an outline while you hold the item ("No one in reach" otherwise). Pickpocket's
## greed and the duel stake are a two-button choice on the item bar before the use goes out.
## Also runs the Rock Paper Scissors duel screen, the "inventory full" choice (keys 1–4), the item
## info card (I), the Sunglasses x-ray on the dealer's hole card and feeds the ItemBar from the
## private snapshot. Never decides anything: the server validates every use.

const PRIVATE_POLL: float = 0.2
const DISCARD_INCOMING: int = ItemSystem.DISCARD_INCOMING
## Half-angle of the aim cone, degrees, and the reach of aimed items without a range of their own.
const AIM_CONE_DEG: float = 30.0
const AIM_RANGE: float = 15.0
## Seconds the two-button choice waits before it closes by itself.
const CHOICE_SECONDS: float = 6.0
## The two choices (option values sent with `use_item`) for items that ask before they go out.
const CHOICES: Dictionary = {
	&"pickpocket": {"title": "How deep do you reach?", "options": [0, 1], "labels": ["SAFE  12%", "GREEDY  20% · 65% odds"]},
	&"rock_paper_scissors": {"title": "Duel stake", "options": [0, 2], "labels": ["LOW  5%", "HIGH  15%"]},
}

var scene: MatchScene
## Floor ring under the player you aim at.
var ring: MeshInstance3D
## Slot in your hand (-1 = hands empty) and the item that was in it when you picked it.
var held: int = -1
var held_item: StringName = &""
## Who the held item would hit right now (-1 = nobody in reach / not an aimed item).
var aimed: int = -1
## The model in the bean's hand, or in front of the camera in first person (null = nothing held).
var held_model: Node3D = null
var _model_first_person: bool = false
## Waiting two-button choice: {slot, target, item, until} ({} = none).
var pending: Dictionary = {}
## The local player's Rock Paper Scissors duel from the private snapshot ({} = none).
var duel: Dictionary = {}
var duel_panel: RpsDuelPanel
## Input mode to go back to when the duel screen closes (MENU = the duel didn't change it).
var _mode_before_duel: InputRouter.Mode = InputRouter.Mode.MENU
var _cooldown_until: float = -INF
var _poll: float = 0.0
var _clock: float = 0.0
var _discard_open: bool = false
var _outlined: Array[GeometryInstance3D] = []
var _outline_mat: StandardMaterial3D
## Blackjack table whose hole card is x-rayed for us (Sunglasses), &"" = none.
var _xray_station: StringName = &""


func _init(p_scene: MatchScene) -> void:
	scene = p_scene
	name = "ItemController"


func _ready() -> void:
	ring = MeshInstance3D.new()
	ring.name = "AimRing"
	var torus := TorusMesh.new()
	torus.rings = 48
	torus.ring_segments = 6
	torus.inner_radius = 0.5
	torus.outer_radius = 0.62
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(Palette.VIP_GOLD, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Palette.VIP_GOLD
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.035
	duel_panel = RpsDuelPanel.new()
	duel_panel.picked.connect(_pick_duel)
	add_child(duel_panel)
	if not Net.event_received.is_connected(_on_event):
		Net.event_received.connect(_on_event)


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)
	_clear_outline()


# --- Picking and using -------------------------------------------------------------------------

## Item key `slot` (0–2) was pressed (router: 1–3 walking, Shift+1–3 seated, d-pad).
func on_slot(slot: int) -> void:
	if _discard_open:
		_discard(slot)
		return
	if duel_panel.is_open():
		duel_panel.choose(slot)
		return
	if not pending.is_empty():
		cancel()
	if slot < 0 or slot >= _inventory().size():
		return
	if slot == held:
		use_held()
	else:
		hold(slot)


## Puts the item in `slot` in your hand (-1 = put it away).
func hold(slot: int) -> void:
	var inv: Array = _inventory()
	if slot >= inv.size():
		slot = -1
	held = slot
	held_item = StringName(inv[slot]) if slot >= 0 else &""
	scene.hud.items.set_held(held)
	_refresh_model()
	if held < 0:
		_set_aimed(-1)
		scene.hud.items.show_target("")


func put_away() -> void:
	cancel()
	hold(-1)


## Moves the hand to the next (step 1) or previous (-1) filled slot; from empty hands the first
## (or last) one.
func cycle(step: int) -> void:
	var inv: Array = _inventory()
	if inv.is_empty():
		return
	cancel()
	var from: int = held
	if from < 0:
		hold(0 if step > 0 else inv.size() - 1)
		return
	hold(posmod(from + step, inv.size()))


## Left click / E / the held slot's key: use the item in your hand.
func use_held() -> void:
	if held < 0:
		return
	var inv: Array = _inventory()
	if held >= inv.size():
		put_away()
		return
	if not _items_allowed():
		return
	if _clock < _cooldown_until:
		scene.hud.toast("Item cooldown", 0.8)
		return
	var def: ItemDefinition = Registry.items.get(StringName(inv[held]), null)
	if def == null:
		return
	var target: int = -1
	if aims(def):
		target = _find_aimed(def)
		if target < 0:
			scene.hud.toast("No one in reach", 1.2)
			return
	if CHOICES.has(def.id):
		_open_choice(held, target, def)
		return
	_send(held, target, -1, def)


## The two-button choice was answered (0 = first button).
func _confirm_choice(index: int) -> void:
	if pending.is_empty():
		return
	var c: Dictionary = CHOICES.get(StringName(pending["item"]), {})
	var p: Dictionary = pending
	cancel()
	if c.is_empty() or index < 0 or index >= (c["options"] as Array).size():
		return
	var inv: Array = _inventory()
	if int(p["slot"]) >= inv.size() or StringName(inv[int(p["slot"])]) != StringName(p["item"]):
		return
	_send(int(p["slot"]), int(p["target"]), int(c["options"][index]), Registry.items.get(StringName(p["item"]), null))


## Closes the two-button choice without using anything.
func cancel() -> void:
	if pending.is_empty():
		return
	pending = {}
	scene.hud.items.hide_choice()


func _open_choice(slot: int, target: int, def: ItemDefinition) -> void:
	var c: Dictionary = CHOICES[def.id]
	pending = {"slot": slot, "target": target, "item": def.id, "until": _clock + CHOICE_SECONDS}
	var keys: Array = ["[%s]" % InputGlyphs.key(&"interact"), "[%s]" % InputGlyphs.key(&"bet_repeat")]
	if not InputGlyphs.gamepad:
		keys = ["[LMB / %s]" % InputGlyphs.key(&"interact"), "[RMB / %s]" % InputGlyphs.key(&"bet_repeat")]
	var labels: Array[String] = []
	for i: int in 2:
		var text: String = "%s  %s" % [keys[i], c["labels"][i]]
		if def.id == &"rock_paper_scissors" and target >= 0:
			text += "  ($%d)" % stake_preview(scene.view.state.balance(scene.local_id), scene.view.state.balance(target), int(c["options"][i]))
		labels.append(text)
	var who: String = (" → %s" % scene.view.state.player_name(target)) if target >= 0 else ""
	scene.hud.items.show_choice("%s%s: %s" % [def.display_name, who, c["title"]], labels)


## What a duel at stake tier `tier` would be worth (the server decides; same rule as RpsDuels).
static func stake_preview(money_a: int, money_b: int, tier: int) -> int:
	return maxi(int(floor(mini(money_a, money_b) * RpsDuels.STAKES[clampi(tier, 0, RpsDuels.STAKES.size() - 1)])), RpsDuels.MIN_STAKE)


## The `use_item` intent for slot `slot` on `target` (-1 = none) with choice `option` (-1 = none).
## Same schema as ever: {slot, target?, option?}.
static func use_intent(slot: int, target: int, option: int) -> Dictionary:
	var payload: Dictionary = {"slot": slot}
	if target >= 0:
		payload["target"] = target
	if option >= 0:
		payload["option"] = option
	return Intents.make(&"use_item", payload)


func _send(slot: int, target: int, option: int, def: ItemDefinition) -> void:
	var res: Dictionary = Net.send_intent(use_intent(slot, target, option))
	if not res["ok"]:
		if res["error"] != &"rate_limited":
			scene.hud.toast(rejection_text(res["error"]), 1.2)
		return
	if def != null and target >= 0 and held_model != null:
		_throw_at(def.id, target)


## Visual only: the item's model flies from your hand to the player it was aimed at.
func _throw_at(item: StringName, target: int) -> void:
	var t: PlayerAvatar = scene.avatars.get(target, null)
	if t == null or held_model == null or not held_model.is_inside_tree():
		return
	var fly: Node3D = ItemModels.make(item)
	add_child(fly)
	fly.global_position = held_model.global_position
	var tw: Tween = fly.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fly, ^"global_position", t.global_position + Vector3(0, 1.0, 0), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(fly, ^"rotation:x", TAU * 1.5, 0.32)
	tw.chain().tween_callback(fly.queue_free)


# --- Aiming ------------------------------------------------------------------------------------

## True for items that hit another player you aim at (not the Robin Hood leader pick).
static func aims(def: ItemDefinition) -> bool:
	return def != null and ItemSystem.targets_player(def) and def.target_mode != ItemDefinition.TargetMode.LEADER


## How far an aimed item reaches.
static func reach(def: ItemDefinition) -> float:
	return def.range_m if def != null and def.range_m > 0.0 else AIM_RANGE


## The player `forward` (from `origin`) points at: the nearest of `candidates` (player id →
## position) inside the cone (half-angle `cone_deg`, measured flat on the floor) and `range_m`.
## -1 when nobody is. Ties go to the lower id.
static func pick_aimed(origin: Vector3, forward: Vector3, candidates: Dictionary, range_m: float, cone_deg: float = AIM_CONE_DEG) -> int:
	var fwd := Vector2(forward.x, forward.z)
	if fwd.length() < 0.001:
		return -1
	fwd = fwd.normalized()
	var limit: float = cos(deg_to_rad(cone_deg))
	var best: int = -1
	var best_d: float = INF
	var ids: Array = candidates.keys()
	ids.sort()
	for id: Variant in ids:
		var to: Vector3 = Vector3(candidates[id]) - origin
		var d: float = to.length()
		if d > range_m:
			continue
		var flat := Vector2(to.x, to.z)
		if flat.length() > 0.05 and fwd.dot(flat.normalized()) < limit:
			continue
		if d < best_d - 0.0001:
			best = int(id)
			best_d = d
	return best


func _find_aimed(def: ItemDefinition) -> int:
	var me: PlayerAvatar = scene.local
	if me == null:
		return -1
	var cands: Dictionary = {}
	for pid: int in scene.avatars:
		if pid == scene.local_id:
			continue
		var a: PlayerAvatar = scene.avatars[pid]
		if a.state == PlayerAvatar.State.AWAY or a.connection_away or not bool(scene.view.state.players.get(pid, {}).get("connected", true)):
			continue
		cands[pid] = a.global_position
	return pick_aimed(me.global_position, me.facing(), cands, reach(def))


func _set_aimed(pid: int) -> void:
	if pid == aimed:
		return
	aimed = pid
	_clear_outline()
	var a: PlayerAvatar = scene.avatars.get(pid, null) if pid >= 0 else null
	ring.visible = a != null
	if a == null:
		return
	for n: Node in a.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n
		if g is MeshInstance3D and g.visible and g.material_overlay == null:
			g.material_overlay = _outline_mat
			_outlined.append(g)


func _clear_outline() -> void:
	for g: GeometryInstance3D in _outlined:
		if is_instance_valid(g) and g.material_overlay == _outline_mat:
			g.material_overlay = null
	_outlined.clear()


# --- Server feedback ---------------------------------------------------------------------------

## The local player used an item (from the server's event): start the cooldown shade.
func on_local_use() -> void:
	_cooldown_until = _clock + Registry.balance.item_cooldown


## A discard choice opened for the local player.
func on_discard_needed() -> void:
	cancel()
	_discard_open = true
	_poll = PRIVATE_POLL  # refresh the panel at once


static func rejection_text(error: StringName) -> String:
	match error:
		&"cooldown":
			return "Item cooldown"
		&"need_target", &"no_target":
			return "No one in reach"
		&"out_of_range":
			return "Out of range"
		&"target_protected":
			return "They're protected right now"
		&"target_away":
			return "They're not around"
		&"grace":
			return "They just got hit, give them a second"
		&"target_broke":
			return "Their pockets are empty"
		&"incapacitated":
			return "Can't use items right now"
		&"seated":
			return "Stand up first"
		&"items_off":
			return "Items are off this match"
		&"wrong_phase":
			return "Not now"
		&"busy":
			return "They're already in a duel"
		&"no_station":
			return "Stand next to a table or machine"
		&"already_bought":
			return "One gift shop buy per round"
		&"too_far":
			return "Walk up to the gift shop"
		&"no_duel":
			return "That duel is over"
		&"not_seated":
			return "They're not sitting at a table"
		&"you_lead":
			return "You're the leader: nobody richer to rob"
		&"bounced":
			return "The bouncer won't let you sit yet"
		&"no_tips_here":
			return "No dealer to tip here"
	return StationUi.rejection_text(error)


func _on_event(ev: Dictionary) -> void:
	if ev.get("type", &"") != &"rps_result" or scene == null:
		return
	var me: int = scene.local_id
	var a: int = int(ev["a"])
	var b: int = int(ev["b"])
	if me != a and me != b:
		return
	var other: int = b if me == a else a
	var winner: int = int(ev["winner"])
	var won: int = 0 if winner < 0 else (1 if winner == me else -1)
	duel_panel.show_result(str(ev["pick_a"] if me == a else ev["pick_b"]), str(ev["pick_b"] if me == a else ev["pick_a"]), won, int(ev["amount"]), bool(ev["replay"]), scene.view.state.player_name(other))


func _pick_duel(choice: int) -> void:
	if duel.is_empty():
		return
	Net.send_intent(Intents.make(&"rps_pick", {"duel": int(duel["duel"]), "pick": choice}))


## Opens / updates / closes the duel screen from the private snapshot (forced: no accept step).
func _sync_duel() -> void:
	if not duel.is_empty():
		var me: int = scene.local_id
		var other: int = int(duel["b"]) if int(duel["a"]) == me else int(duel["a"])
		var was_open: bool = duel_panel.is_open()
		duel_panel.show_duel(duel, scene.view.state.player_name(other))
		if not was_open:
			cancel()
			_mode_before_duel = scene.router.mode
			scene.router.set_play_mode(InputRouter.Mode.MENU)  # pulled in: free cursor, no walking
	elif duel_panel.is_open() and not duel_panel.is_settling():
		duel_panel.close()
	if not duel_panel.is_open() and _mode_before_duel != InputRouter.Mode.MENU:
		if scene.router.mode == InputRouter.Mode.MENU:
			scene.router.set_play_mode(_mode_before_duel)
		_mode_before_duel = InputRouter.Mode.MENU


# --- Frame -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if scene.local == null or scene.hud == null or scene.hud.items == null:
		return
	var bar: ItemBar = scene.hud.items
	if not bar.choice_made.is_connected(_confirm_choice):
		bar.choice_made.connect(_confirm_choice)
	var seated: bool = scene.local.state == PlayerAvatar.State.SEATED
	bar.set_seated(seated)
	var cd: float = Registry.balance.item_cooldown
	bar.set_cooldown(maxf(_cooldown_until - _clock, 0.0) / cd if cd > 0.0 else 0.0)
	_poll += delta
	if _poll >= PRIVATE_POLL:
		_poll = 0.0
		var snap: Dictionary = Net.request_private_snapshot()
		var priv: Dictionary = snap.get("items", {})
		bar.set_private(priv)
		_discard_open = priv.has("discard")
		duel = priv.get("duel", {})
		_update_xray(snap.get("station", {}))
	if duel_panel.is_open() or not duel.is_empty() or _mode_before_duel != InputRouter.Mode.MENU:
		_sync_duel()
	# The hand follows the inventory: a used or dropped item leaves it.
	var inv: Array = _inventory()
	if held >= 0 and (held >= inv.size() or StringName(inv[held]) != held_item or not _items_allowed()):
		put_away()
	if not pending.is_empty() and (_clock > float(pending["until"]) or held < 0):
		cancel()
	if held_model != null and not is_instance_valid(held_model):
		held_model = null  # the avatar was rebuilt (back in the lobby, respawn)
		if held >= 0:
			_refresh_model()
	if held >= 0 and _first_person() != _model_first_person:
		_refresh_model()  # V switched the camera
	if held_model != null:
		held_model.visible = not seated and scene.local.is_standing()
	# The usual "[E / LMB] Grab Anna" line would lie while the hand holds an item.
	if held >= 0 and _free_to_use() and _nothing_to_interact():
		scene.hud.set_prompt("")
	_update_aim(bar)


func _update_aim(bar: ItemBar) -> void:
	var def: ItemDefinition = Registry.items.get(held_item, null) if held >= 0 else null
	if def == null or not aims(def) or not scene.local.is_standing():
		_set_aimed(-1)
		bar.show_target("")
		return
	var pid: int = _find_aimed(def)
	_set_aimed(pid)
	if pid >= 0:
		var a: PlayerAvatar = scene.avatars[pid]
		ring.global_position = a.global_position + Vector3(0, 0.05, 0)
		bar.show_target("%s → %s" % [def.display_name, scene.view.state.player_name(pid)])
	else:
		bar.show_target("%s: no one in reach" % def.display_name)


## Sunglasses: while the server shows us the dealer's hole card, the face-down card is x-rayed.
func _update_xray(station_priv: Dictionary) -> void:
	var sid: StringName = StringName(scene.view.state.players.get(scene.local_id, {}).get("station", ""))
	var hole: int = int(station_priv.get("hole_card", -1))
	if _xray_station != &"" and (_xray_station != sid or hole < 0):
		var old: BlackjackStation = scene.map.stations.get(_xray_station, null) as BlackjackStation if scene.map != null else null
		if old != null:
			old.cards.set_xray(-1)
		_xray_station = &""
	if hole < 0 or sid == &"" or scene.map == null:
		return
	var st: BlackjackStation = scene.map.stations.get(sid, null) as BlackjackStation
	if st != null:
		st.cards.set_xray(hole)
		_xray_station = sid


## The held item's model: in the bean's hand, or at the bottom of the view in first person
## (where your own bean is hidden).
func _refresh_model() -> void:
	if held_model != null and is_instance_valid(held_model):
		held_model.queue_free()
	held_model = null
	_model_first_person = _first_person()
	if held < 0 or scene.local == null or scene.local.visuals == null:
		return
	if _model_first_person:
		held_model = ItemModels.make_view(held_item)
		scene.local.cam.camera.add_child(held_model)
	else:
		held_model = ItemModels.make_held(held_item)
		ItemModels.attach_to_hand(scene.local.visuals, held_model)


func _first_person() -> bool:
	return scene.local != null and scene.local.cam != null and scene.local.cam.mode == PlayerCamera.Mode.FIRST


# --- Input -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _duel_input(event) or _discard_input(event):
		get_viewport().set_input_as_handled()
		return
	var walking: bool = scene.router.mode == InputRouter.Mode.WALK
	var seated: bool = scene.router.mode == InputRouter.Mode.SEATED
	if not (walking or seated):
		return
	if not pending.is_empty() and _choice_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).physical_keycode == KEY_I:
		scene.hud.items.toggle_info()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b: MouseButton = (event as InputEventMouseButton).button_index
		if (b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN) and walking and scene.stage is WalkableStage:
			return  # a walkable minigame room has no items; the stage may use the wheel (Grab Your Hand)
		if (b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN) and walking:
			cycle(1 if b == MOUSE_BUTTON_WHEEL_DOWN else -1)
			get_viewport().set_input_as_handled()
			return
		if held >= 0 and walking and _free_to_use():
			if b == MOUSE_BUTTON_LEFT:
				use_held()
				get_viewport().set_input_as_handled()
			elif b == MOUSE_BUTTON_RIGHT:
				put_away()
				get_viewport().set_input_as_handled()
		return
	if held < 0:
		return  # empty hands: shoulder buttons shove / talk as usual, the d-pad takes an item out
	if event.is_action_pressed(&"interact") and (seated or (_free_to_use() and _nothing_to_interact())):
		use_held()
		get_viewport().set_input_as_handled()
	elif walking and event is InputEventJoypadButton and (event.is_action_pressed(&"bet_chip_next") or event.is_action_pressed(&"bet_chip_prev")):
		cycle(1 if event.is_action_pressed(&"bet_chip_next") else -1)
		get_viewport().set_input_as_handled()
	elif walking and event is InputEventJoypadButton and event.is_action_pressed(&"leave_station"):
		put_away()
		get_viewport().set_input_as_handled()


## LMB / E / gamepad X = first button, RMB / R / gamepad Y = second; the wheel cancels.
func _choice_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b: MouseButton = (event as InputEventMouseButton).button_index
		if scene.router.mode != InputRouter.Mode.WALK and (b == MOUSE_BUTTON_LEFT or b == MOUSE_BUTTON_RIGHT):
			return false  # seated: the cursor clicks the buttons themselves
		match b:
			MOUSE_BUTTON_LEFT:
				_confirm_choice(0)
			MOUSE_BUTTON_RIGHT:
				_confirm_choice(1)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				cancel()
			_:
				return false
		return true
	if event.is_action_pressed(&"interact"):
		_confirm_choice(0)
		return true
	if event.is_action_pressed(&"bet_repeat"):
		_confirm_choice(1)
		return true
	return false


## In the duel, keys 1–3 pick (the d-pad comes through `on_slot`).
func _duel_input(event: InputEvent) -> bool:
	if not duel_panel.is_open() or not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return false
	var k: Key = (event as InputEventKey).physical_keycode
	if k < KEY_1 or k > KEY_3:
		return false
	duel_panel.choose(int(k - KEY_1))
	return true


## While the "inventory full" choice is open, 1–4 answer it and Backspace drops the newcomer.
func _discard_input(event: InputEvent) -> bool:
	if not _discard_open:
		return false
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_1 + DISCARD_INCOMING:
			_discard(int(k - KEY_1))
			return true
	if event.is_action_pressed(&"bet_clear"):
		_discard(DISCARD_INCOMING)
		return true
	return false


## Standing on your own feet with empty arms (not carrying a grabbed player).
func _free_to_use() -> bool:
	return scene.local != null and scene.local.is_standing() and scene._local_holding() < 0


## E belongs to tables, the shop and the lobby spots when one is in reach.
func _nothing_to_interact() -> bool:
	if scene.nearest_station != null or scene._near_shop() or scene._lobby_spot() != &"":
		return false
	return scene.casino_floor == null or scene.casino_floor.prompt() == ""


func _discard(slot: int) -> void:
	Net.send_intent(Intents.make(&"discard_item", {"slot": slot}))
	_discard_open = false
	_poll = PRIVATE_POLL - 0.05


func _inventory() -> Array:
	return scene.view.state.players.get(scene.local_id, {}).get("inventory", [])


func _items_allowed() -> bool:
	var ph: Phase.Id = scene.view.state.phase
	return ph == Phase.Id.CASINO or ph == Phase.Id.PRE_MINIGAME
