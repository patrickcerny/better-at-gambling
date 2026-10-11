class_name WalkableStage
extends MinigameStage
## Client side of a walkable minigame ("W"): no stage camera and no puppets. The real avatars play
## in a room the subclass builds (`_build_room`, e.g. `VaultArena.build`) at
## `WalkableLogicBase.ROOM_ORIGIN`, and the normal third/first-person camera follows the local bean.
## The match scene builds this stage the moment `minigame_started` arrives (also on the dedicated
## server, so ragdolls have a floor) and frees it, room and all, at the regroup.
##
## What it does for every walkable game:
## - puts the bodies this process owns on their spawn (`minigame_started.room`) and wherever the
##   server moves them later (`minigame_player_moved`: the gallery after an elimination, a clamp);
## - input: STAGE mode (free cursor) during the rules briefing and the rewards, WALK while playing;
## - the action button: E goes to `on_action_pressed` → `minigame_action {kind, target?}`;
## - a 2D overlay on `ui` with helpers: a clock, a status line, a centre banner, a feed, a prompt.
## Subclasses override `_build_room`, `_build_game(start)`, `action_kind()`, `action_range()`,
## `can_act()` and react to their events in `on_event` (call super).

## The match scene (avatars, router, server when hosting). Null in dev renders.
var scene: MatchScene = null
var room: Node3D = null
var roster: Array[int] = []
var spawns: Dictionary = {}
var spawn_yaws: Dictionary = {}
var arena: AABB = AABB()
var gallery: AABB = AABB()
## True once the game runs (`minigame_go`, or a snapshot without a briefing).
var going: bool = false
## After the game: the rewards own the screen.
var over: bool = false

var overlay: Control = null
var clock_label: Label = null
var status_label: Label = null
var prompt_label: Label = null
var _banner: Label = null
var _feed: VBoxContainer = null
var _clock_panel: PanelContainer = null


func _build(start: Dictionary) -> void:
	position = Vector3.ZERO  # rooms are built in world coordinates around ROOM_ORIGIN
	for p: Variant in start.get("players", []):
		roster.append(int(p))
	var wire: Dictionary = start.get("room", {})
	_read_room(wire)
	room = _build_room()
	if not _is_dedicated():
		_build_overlay()
	_build_game(start)
	if not wire.is_empty():
		_place_all_at_spawns()
	var hold: Variant = start.get("briefing", 0.0)
	going = not (hold is Dictionary) and float(hold) <= 0.0


func apply_state(st: Dictionary) -> void:
	if st.has("room"):
		_read_room(st["room"])
		_place_local_from_state(st)
	going = not st.has("briefing")
	_apply_input_mode()


## Subclass: the room's nodes (a child of this stage). Default: the vault arena.
func _build_room() -> Node3D:
	return VaultArena.build(self)


## Subclass: game-specific nodes and overlay parts.
func _build_game(_start: Dictionary) -> void:
	pass


## Subclass: the action's `kind` ("tag", "steal", ...), or &"" when the button does nothing now.
func action_kind() -> StringName:
	return &""


## Subclass: reach of the action for the local target hint (centre to centre, metres).
func action_range() -> float:
	return InteractionRules.REACH


## Subclass: whether the local player may act right now (alive, holding the bomb, ...).
func can_act() -> bool:
	return going and not over


func on_event(ev: Dictionary) -> void:
	match StringName(ev["type"]):
		&"minigame_go":
			going = true
			_apply_input_mode()
		&"minigame_player_moved":
			place(int(ev["player"]), Serializer.to_vec3(ev["pos"]), NAN)
		&"rewards_started":
			over = true
			_apply_input_mode()


## The input mode this stage wants: walking while the game runs, a free cursor otherwise.
func input_mode() -> InputRouter.Mode:
	return InputRouter.Mode.WALK if going and not over else InputRouter.Mode.STAGE


func _apply_input_mode() -> void:
	if scene == null or scene.router == null or _is_dedicated():
		return
	if scene.briefing != null and is_instance_valid(scene.briefing) and not going:
		return  # the rules card keeps its cursor until the game goes
	if scene.pause_menu != null and scene.pause_menu.visible:
		return  # the pause menu returns to `input_mode()` on resume
	scene.router.set_mode(input_mode())


## E pressed (the match scene asks first). True if the stage used it.
func on_action_pressed() -> bool:
	if not can_act():
		return going and not over  # in the room E never sits, shops or uses items
	var kind: StringName = action_kind()
	if kind == &"":
		return true
	var payload: Dictionary = {"kind": kind}
	var target: int = local_target(action_range())
	if target >= 0:
		payload["target"] = target
	_on_action_sent(kind, target)
	Net.send_intent(Intents.make(&"minigame_action", payload))
	return true


## The grab click (LMB) pressed while not holding anyone (a held bean is thrown first). True if
## the stage used it; false leaves the casino's grab.
func on_grab_pressed() -> bool:
	return false


## The shove click (RMB) pressed while not holding anyone. True if the stage used it; false
## leaves the casino's shove.
func on_shove_pressed() -> bool:
	return false


## Subclass: feedback when the action goes out (a swing, a sound).
func _on_action_sent(_kind: StringName, _target: int) -> void:
	pass


## The alive player in front of the local bean within `range_m` (the same pick the server makes,
## `InteractionRules.pick_in_reach`), or -1.
func local_target(range_m: float) -> int:
	var me: PlayerAvatar = local_avatar()
	if me == null:
		return -1
	var candidates: Dictionary = {}
	for pid: int in alive_players():
		var a: PlayerAvatar = avatar(pid)
		if pid != local_id and a != null:
			candidates[pid] = a.global_position
	return InteractionRules.pick_in_reach(me.global_position, me.facing(), candidates, local_id, range_m)


## Subclass: who is still in play (default: everyone who started).
func alive_players() -> Array[int]:
	return roster


func avatar(pid: int) -> PlayerAvatar:
	return scene.avatars.get(pid, null) if scene != null else null


func local_avatar() -> PlayerAvatar:
	return avatar(local_id)


## Puts a body where the server says, wherever this process owns it (our own bean, the host's
## dummies and ragdolls); puppets are pointed there and snap (their owner streams the rest).
func place(pid: int, pos: Vector3, yaw: float) -> void:
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	if a.state == PlayerAvatar.State.RAGDOLL:
		a.end_ragdoll(pos + Vector3(0, 0.5, 0))
	elif a.state == PlayerAvatar.State.HELD and a.carrier == null:
		a.release_held()
	elif a.state == PlayerAvatar.State.SEATED:
		a.stand()
	if a.state == PlayerAvatar.State.STUNNED:
		a.state = PlayerAvatar.State.STANDING
	var owned: bool = a.is_local or a.drive != PlayerAvatar.Drive.PUPPET
	if owned:
		a.teleport(pos, yaw)
	else:
		a.target_position = pos
		if a.global_position.distance_to(pos) > 3.0:
			a.teleport(pos, yaw)
	if scene.server != null and scene.role != MatchScene.Role.CLIENT:
		scene.server.set_server_owned(pid, false)
	if scene.net_world != null:
		scene.net_world.reset_player(pid)


func _place_all_at_spawns() -> void:
	for pid: int in roster:
		if spawns.has(pid):
			place(pid, spawns[pid], float(spawn_yaws.get(pid, 0.0)))


## Late join / reconnect: our own body goes to its spawn (alive) or the gallery (out).
func _place_local_from_state(st: Dictionary) -> void:
	if local_id not in roster or not spawns.has(local_id):
		return
	var me: PlayerAvatar = local_avatar()
	if me == null:
		return
	var alive: Array = st.get("alive", roster)
	if alive.has(local_id):
		if not arena.has_point(me.global_position):
			place(local_id, spawns[local_id], float(spawn_yaws.get(local_id, 0.0)))
	elif not gallery.has_point(me.global_position):
		place(local_id, gallery.get_center() - Vector3(0, gallery.size.y * 0.5 - 0.6, 0), NAN)


func _read_room(wire: Dictionary) -> void:
	if wire.is_empty():
		return
	var sp: Dictionary = wire.get("spawns", {})
	for k: Variant in sp:
		spawns[int(k)] = Serializer.to_vec3(sp[k])
	var yw: Dictionary = wire.get("yaws", {})
	for k: Variant in yw:
		spawn_yaws[int(k)] = float(yw[k])
	arena = WalkableLogicBase.aabb_from_wire(wire.get("arena", []))
	gallery = WalkableLogicBase.aabb_from_wire(wire.get("gallery", []))
	if roster.is_empty():
		for pid: int in spawns:
			roster.append(pid)


func _is_dedicated() -> bool:
	return scene != null and scene.role == MatchScene.Role.SERVER


func player_color(pid: int) -> Color:
	var a: PlayerAvatar = avatar(pid)
	if a != null:
		return a.color
	return Palette.player_color(int(state.players.get(pid, {}).get("color", pid)) if state != null else pid)


func player_name(pid: int) -> String:
	return state.player_name(pid) if state != null else "Player %d" % pid


# --- Overlay ----------------------------------------------------------------------------------

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.name = "WalkableOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(overlay)
	# Clock: a dark plaque with a gold rim at the top centre.
	_clock_panel = PanelContainer.new()
	_clock_panel.add_theme_stylebox_override(&"panel", plaque_style())
	_clock_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clock_panel.position.y = 14
	_clock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_clock_panel)
	clock_label = label("", 40, Palette.CREAM)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label.custom_minimum_size = Vector2(150, 0)
	_clock_panel.add_child(clock_label)
	# Status (top left), feed (top right), prompt (bottom centre), banner (centre).
	status_label = label("", 30, Palette.CREAM)
	status_label.position = Vector2(24, 18)
	overlay.add_child(status_label)
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position = Vector2(-24, 18)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override(&"separation", 4)
	overlay.add_child(_feed)
	prompt_label = label("", 34, Palette.CASINO_BLACK)
	var pill := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Palette.VIP_GOLD
	ps.set_corner_radius_all(22)
	ps.content_margin_left = 26
	ps.content_margin_right = 26
	ps.content_margin_top = 4
	ps.content_margin_bottom = 4
	ps.border_color = Palette.CREAM
	ps.set_border_width_all(2)
	pill.add_theme_stylebox_override(&"panel", ps)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.position.y = -120
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.visible = false
	pill.name = "PromptPill"
	pill.add_child(prompt_label)
	overlay.add_child(pill)
	_banner = label("", 84, Palette.VIP_GOLD)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position.y -= 140
	_banner.add_theme_constant_override(&"outline_size", 14)
	_banner.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	_banner.modulate.a = 0.0
	overlay.add_child(_banner)


## Seconds → "M:SS" on the clock plaque (red in the last 10 s).
func set_clock(seconds: float) -> void:
	if clock_label == null:
		return
	var s: int = ceili(maxf(seconds, 0.0))
	clock_label.text = "%d:%02d" % [s / 60, s % 60]
	clock_label.add_theme_color_override(&"font_color", Palette.LOSS_RED if s <= 10 else Palette.CREAM)


## The bottom prompt pill ("" hides it). `{interact}` style glyphs are filled in.
func set_prompt(text: String) -> void:
	if prompt_label == null:
		return
	var pill: Control = prompt_label.get_parent() as Control
	pill.visible = text != ""
	prompt_label.text = InputGlyphs.fill(text) if text != "" else ""


## A big centre line that pops in and fades after `seconds`.
func banner(text: String, color: Color = Palette.VIP_GOLD, seconds: float = 2.0) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.add_theme_color_override(&"font_color", color)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2.ONE * 1.5
	_banner.modulate.a = 1.0
	var t: Tween = _banner.create_tween()
	t.tween_property(_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(seconds)
	t.tween_property(_banner, "modulate:a", 0.0, 0.35)


## A line on top of the feed (the last `keep` stay).
func feed(text: String, color: Color = Palette.CREAM, keep: int = 6) -> void:
	if _feed == null:
		return
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.72)
	sb.border_color = Color(Palette.WARM_GOLD, 0.6)
	sb.border_width_left = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	row.add_theme_stylebox_override(&"panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = label(text, 24, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)
	_feed.add_child(row)
	_feed.move_child(row, 0)
	while _feed.get_child_count() > keep:
		var old: Node = _feed.get_child(_feed.get_child_count() - 1)
		_feed.remove_child(old)
		old.queue_free()


func label(text: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", Vfx.font())
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override(&"shadow_offset_x", 2)
	l.add_theme_constant_override(&"shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func plaque_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.82)
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb
