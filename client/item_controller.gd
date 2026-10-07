class_name ItemController
extends Node3D
## Client side of items (0.8.6): turns item keys into `use_item` intents, runs the target picker
## (cycle with the mouse wheel or shoulder buttons, press the same key or E to confirm, 4 s to
## decide), draws the proximity ring for NEAR items and a marker over the chosen target, answers the
## "inventory full" choice (keys 1–6) and feeds the ItemBar from the private snapshot. Never decides
## anything: the server validates every use.

const PICK_SECONDS: float = 4.0
const PRIVATE_POLL: float = 0.2
const DISCARD_INCOMING: int = 3

var scene: MatchScene
var ring: MeshInstance3D
var marker: Label3D

## Target picker: the slot being aimed, its definition, ordered candidates, the chosen index.
var picking_slot: int = -1
var picking_def: ItemDefinition = null
var picking_candidates: Array[int] = []
var picking_index: int = 0
## Picker option, R cycles it: Pickpocket greed (0 safe 12%, 1 greedy 20% at 65%, 2 very greedy
## 30% at 40%) or the Rock Paper Scissors stake (5/10/15% of the poorer player's money).
var option: int = 0
const GREED_TEXT: Array[String] = ["safe 12%", "greedy 20% (65% odds)", "very greedy 30% (40% odds)"]
const STAKE_TEXT: Array[String] = ["stake 5%", "stake 10%", "stake 15%"]
## The local player's Rock Paper Scissors duel from the private snapshot ({} = none).
var duel: Dictionary = {}
var _pick_until: float = 0.0
var _cooldown_until: float = -INF
var _poll: float = 0.0
var _clock: float = 0.0
var _discard_open: bool = false
var _ring_until: float = -INF
var _ring_radius: float = 0.0


func _init(p_scene: MatchScene) -> void:
	scene = p_scene
	name = "ItemController"


func _ready() -> void:
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(Palette.VIP_GOLD, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.visible = false
	add_child(ring)
	marker = Label3D.new()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = true
	marker.pixel_size = 0.0012
	marker.font_size = 40
	marker.outline_size = 10
	marker.modulate = Palette.VIP_GOLD
	marker.visible = false
	add_child(marker)


## Item key `slot` (0–5) was pressed. Maps to actual inventory slot (may not equal visual position).
func on_slot(slot: int) -> void:
	if _discard_open:
		_discard(slot)
		return
	if picking_slot >= 0:
		if slot == picking_slot:
			confirm()
		else:
			cancel()
			on_slot(slot)
		return
	var inv: Array = _inventory()
	if slot >= inv.size():
		return
	if not _items_allowed():
		return
	if _clock < _cooldown_until:
		scene.hud.toast("Item cooldown", 0.8)
		return
	var def: ItemDefinition = Registry.items.get(StringName(inv[slot]), null)
	if def == null:
		return
	if not ItemSystem.targets_player(def):
		_send(slot, -1)
		return
	var cands: Array[int] = candidates(def)
	if cands.is_empty():
		scene.hud.toast("Nobody in range" if _near(def) else "No one to target", 1.2)
		_show_ring(def, 1.5)
		return
	if cands.size() == 1 and not _has_options(def):
		_send(slot, cands[0])
		return
	picking_slot = slot
	picking_def = def
	picking_candidates = cands
	picking_index = 0
	option = 1 if def.id == &"rock_paper_scissors" else 0
	_pick_until = _clock + PICK_SECONDS
	_update_picker()


## Sends the picked target.
func confirm() -> void:
	if picking_slot < 0:
		return
	var target: int = picking_candidates[picking_index] if picking_index < picking_candidates.size() else -1
	var slot: int = picking_slot
	var opt: int = option if _has_options(picking_def) else -1
	cancel()
	_send(slot, target, opt)


func cancel() -> void:
	picking_slot = -1
	picking_def = null
	picking_candidates.clear()
	marker.visible = false
	ring.visible = _clock < _ring_until
	scene.hud.items.show_target("")


func cycle(step: int) -> void:
	if picking_candidates.is_empty():
		return
	picking_index = posmod(picking_index + step, picking_candidates.size())
	_pick_until = _clock + PICK_SECONDS
	_update_picker()


## Who the local player could aim `def` at: present players other than us; NEAR items only within
## range (nearest first), others richest first (the usual sabotage pick).
func candidates(def: ItemDefinition) -> Array[int]:
	var out: Array[int] = []
	var me: PlayerAvatar = scene.local
	for pid: int in scene.avatars:
		if pid == scene.local_id:
			continue
		var a: PlayerAvatar = scene.avatars[pid]
		if a.state == PlayerAvatar.State.AWAY or not bool(scene.view.state.players.get(pid, {}).get("connected", true)):
			continue
		if _near(def) and (me == null or me.global_position.distance_to(a.global_position) > def.range_m):
			continue
		out.append(pid)
	if _near(def) and me != null:
		var origin: Vector3 = me.global_position
		out.sort_custom(func(x: int, y: int) -> bool: return origin.distance_to(scene.avatars[x].global_position) < origin.distance_to(scene.avatars[y].global_position))
	else:
		var st: ClientMatchState = scene.view.state
		out.sort_custom(func(x: int, y: int) -> bool: return st.balance(x) > st.balance(y) or (st.balance(x) == st.balance(y) and x < y))
	return out


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
			return "No one to target"
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
	return StationUi.rejection_text(error)


func _process(delta: float) -> void:
	_clock += delta
	if scene.local == null or scene.hud == null:
		return
	scene.hud.items.set_seated(scene.local.state == PlayerAvatar.State.SEATED)
	var cd: float = Registry.balance.item_cooldown
	scene.hud.items.set_cooldown(maxf(_cooldown_until - _clock, 0.0) / cd if cd > 0.0 else 0.0)
	_poll += delta
	if _poll >= PRIVATE_POLL:
		_poll = 0.0
		var priv: Dictionary = Net.request_private_snapshot().get("items", {})
		scene.hud.items.set_private(priv)
		_discard_open = priv.has("discard")
		duel = priv.get("duel", {})
		scene.hud.items.show_duel(duel_text())
	if picking_slot >= 0:
		if _clock > _pick_until or picking_slot >= _inventory().size() or not _items_allowed():
			cancel()
		else:
			# Players move: drop ones that left range, keep the chosen one if still valid.
			var chosen: int = picking_candidates[picking_index] if picking_index < picking_candidates.size() else -1
			var fresh: Array[int] = candidates(picking_def)
			if fresh.is_empty():
				cancel()
			elif fresh != picking_candidates:
				picking_candidates = fresh
				picking_index = maxi(fresh.find(chosen), 0)
				_update_picker()
	if picking_slot >= 0 or _clock < _ring_until:
		ring.global_position = scene.local.global_position + Vector3(0, 0.05, 0)
	elif ring.visible:
		ring.visible = false
	if marker.visible and picking_index < picking_candidates.size():
		var t: PlayerAvatar = scene.avatars.get(picking_candidates[picking_index], null)
		if t != null:
			marker.global_position = t.global_position + Vector3(0, 2.4, 0)


func _input(event: InputEvent) -> void:
	if _duel_input(event):
		get_viewport().set_input_as_handled()
		return
	if _discard_open and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			_discard(int(k - KEY_1))
			get_viewport().set_input_as_handled()
		return
	if _discard_open and event.is_action_pressed(&"bet_clear"):
		_discard(DISCARD_INCOMING)
		get_viewport().set_input_as_handled()
		return
	# Handle item slot keys (1-6) even when not picking, to support scrolling/inventory access
	if not _discard_open and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			on_slot(int(k - KEY_1))
			get_viewport().set_input_as_handled()
			return
	# Mouse wheel scrolls through inventory when not picking
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b: MouseButton = (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN:
			if picking_slot < 0:
				# Scroll inventory slots in the ItemBar
				scene.hud.items.scroll_slots(1 if b == MOUSE_BUTTON_WHEEL_DOWN else -1)
			else:
				# Scroll target picker when picking
				cycle(1 if b == MOUSE_BUTTON_WHEEL_DOWN else -1)
			get_viewport().set_input_as_handled()
			return
	if picking_slot < 0:
		return
	if event.is_action_pressed(&"bet_chip_next"):
		cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"bet_chip_prev"):
		cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"bet_repeat") and _has_options(picking_def):
		option = (option + 1) % _option_texts(picking_def).size()
		_pick_until = _clock + PICK_SECONDS
		_update_picker()
		get_viewport().set_input_as_handled()


func _discard(slot: int) -> void:
	Net.send_intent(Intents.make(&"discard_item", {"slot": slot}))
	_discard_open = false
	_poll = PRIVATE_POLL - 0.05


func _send(slot: int, target: int, opt: int = -1) -> void:
	var payload: Dictionary = {"slot": slot}
	if target >= 0:
		payload["target"] = target
	if opt >= 0:
		payload["option"] = opt
	var res: Dictionary = Net.send_intent(Intents.make(&"use_item", payload))
	if not res["ok"] and res["error"] != &"rate_limited":
		scene.hud.toast(rejection_text(res["error"]), 1.2)


func _update_picker() -> void:
	var tid: int = picking_candidates[picking_index]
	var name: String = scene.view.state.player_name(tid)
	marker.text = "▼ %s" % name
	marker.visible = true
	var key: String = InputGlyphs.key(StringName("item_%d" % (picking_slot + 1)))
	if not InputGlyphs.gamepad and scene.local.state == PlayerAvatar.State.SEATED:
		key = "Shift+" + key
	var switch: String = InputGlyphs.fill("{bet_chip_prev} / {bet_chip_next}" if InputGlyphs.gamepad else "wheel")
	var extra: String = ("\n%s %s" % [InputGlyphs.hint(&"bet_repeat"), _option_texts(picking_def)[option]]) if _has_options(picking_def) else ""
	scene.hud.items.show_target("%s → %s   (%s: switch, %s or %s: use)%s" % [picking_def.display_name, name, switch, key, InputGlyphs.key(&"interact"), extra])
	if _near(picking_def):
		_show_ring(picking_def, PICK_SECONDS)


func _show_ring(def: ItemDefinition, seconds: float) -> void:
	if not _near(def) or scene.local == null:
		return
	_ring_radius = def.range_m
	var torus: TorusMesh = ring.mesh as TorusMesh
	torus.inner_radius = maxf(_ring_radius - 0.06, 0.01)
	torus.outer_radius = _ring_radius
	ring.visible = true
	ring.global_position = scene.local.global_position + Vector3(0, 0.05, 0)
	_ring_until = _clock + seconds


## Items with a choice made in the picker (Pickpocket's greed, the duel stake).
func _has_options(def: ItemDefinition) -> bool:
	return def != null and (def.id == &"pickpocket" or def.id == &"rock_paper_scissors")


func _option_texts(def: ItemDefinition) -> Array[String]:
	return STAKE_TEXT if def != null and def.id == &"rock_paper_scissors" else GREED_TEXT


## The duel prompt for the local player ("" = nothing to show).
func duel_text() -> String:
	if duel.is_empty():
		return ""
	var me: int = scene.local_id
	var other: int = int(duel["b"]) if int(duel["a"]) == me else int(duel["a"])
	var who: String = scene.view.state.player_name(other)
	var left: int = ceili(float(duel.get("left", 0.0)))
	if str(duel["state"]) == "invite":
		if int(duel["b"]) == me:
			return "%s challenges you to Rock Paper Scissors for $%d\n[Y] Accept   [N] Decline   (%ds)" % [who, int(duel["stake"]), left]
		return "Waiting for %s to accept your challenge… (%ds)" % [who, left]
	if bool(duel.get("picked", false)):
		return "Waiting for %s to pick… (%ds)" % [who, left]
	return "ROCK PAPER SCISSORS vs %s for $%d\n[1] Rock   [2] Paper   [3] Scissors   (%ds)" % [who, int(duel["stake"]), left]


## Y/N to answer a challenge, 1–3 to pick. True if the event was used.
func _duel_input(event: InputEvent) -> bool:
	if duel.is_empty() or not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return false
	var k: Key = (event as InputEventKey).physical_keycode
	var id: int = int(duel["duel"])
	if str(duel["state"]) == "invite":
		if int(duel["b"]) != scene.local_id or not (k == KEY_Y or k == KEY_N):
			return false
		Net.send_intent(Intents.make(&"rps_answer", {"duel": id, "accept": k == KEY_Y}))
		duel = {}
		scene.hud.items.show_duel("")
		return true
	if bool(duel.get("picked", false)) or k < KEY_1 or k > KEY_3 or (event as InputEventKey).shift_pressed:
		return false
	Net.send_intent(Intents.make(&"rps_pick", {"duel": id, "pick": int(k - KEY_1)}))
	duel["picked"] = true
	scene.hud.items.show_duel(duel_text())
	return true


func _near(def: ItemDefinition) -> bool:
	return def != null and def.target_mode == ItemDefinition.TargetMode.NEAR_PLAYER


func _inventory() -> Array:
	return scene.view.state.players.get(scene.local_id, {}).get("inventory", [])


func _items_allowed() -> bool:
	var ph: Phase.Id = scene.view.state.phase
	return ph == Phase.Id.CASINO or ph == Phase.Id.PRE_MINIGAME
