class_name SecurityView
extends Node
## The match scene's side of the start room and the jail (0.8.19). All decisions are the server's;
## this shows them and puts the bodies this process owns where the server says:
## - `player_sent_back`: someone got past the shut lobby doors while the room waits in LOBBY
##   (thrown, a physics glitch): their ragdoll ends and they stand on their start-room spot again.
## - `player_jailed`: the nearest bouncer carries them to the cell gate (`Guard.carry` to the jail)
##   or, with no bouncer at hand, they are knocked out on the spot for a moment; then they are
##   locked in the barred cell. The jailed player watches the floor from above the cage and the
##   HUD shows the time left and the fine.
## - `player_released_from_jail`: the curtain closes, they come out at the lobby doors, it opens.
## Built and fed by `CasinoFloor`.

## No bouncer close enough: how long the player lies knocked out before they are in the cell.
const KNOCKOUT_SECONDS: float = 1.0
## Facing out of the cell, through the gate (+x).
const CELL_YAW: float = -PI * 0.5

var scene: MatchScene
var map: LuckyLounge
## The jailed player's HUD line (time left, fine); null on the dedicated server.
var jail_label: Label = null
## player → scene clock when they go into the cell (knockout over, or a carry that never arrived).
var _deliver_at: Dictionary[int, float] = {}
## player → their spot in the cell (from the server's event).
var _cell_spot: Dictionary[int, Vector3] = {}
## Players this view has locked in (until their release).
var _locked: Dictionary[int, bool] = {}
## Local player: jail time left (counted down here; the server releases them) and the fine.
var jail_left: float = 0.0
var jail_fine: int = 0
var _clock: float = 0.0


func setup(p_scene: MatchScene) -> void:
	scene = p_scene
	map = scene.map
	name = "SecurityView"
	if scene.role != MatchScene.Role.SERVER and scene.ui_layer != null:
		jail_label = Label.new()
		jail_label.name = "JailTimer"
		jail_label.theme_type_variation = &"HeadingLabel"
		jail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		jail_label.add_theme_color_override(&"font_color", Palette.CREAM)
		jail_label.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
		jail_label.add_theme_constant_override(&"outline_size", 10)
		jail_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		jail_label.offset_top = 130
		jail_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		jail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		jail_label.visible = false
		scene.ui_layer.add_child(jail_label)
	# Joining mid-sentence (reconnect): the snapshot says we are jailed.
	var me: Dictionary = scene.view.state.players.get(scene.local_id, {})
	if float(me.get("jail_time", 0.0)) > 0.0:
		_start_local_jail(float(me["jail_time"]), int(me.get("jail_fine", 0)))
		_spectate(true)


func _exit_tree() -> void:
	if jail_label != null and is_instance_valid(jail_label):
		jail_label.queue_free()


## True while the local player sits in jail.
func is_local_jailed() -> bool:
	return jail_left > 0.0


func on_event(ev: Dictionary) -> void:
	match StringName(ev["type"]):
		&"player_sent_back":
			_sent_back(int(ev["player"]), Serializer.to_vec3(ev["pos"]))
		&"player_jailed":
			_jailed(ev)
		&"player_released_from_jail":
			_released(ev)


func _process(delta: float) -> void:
	_clock += delta
	for pid: int in _deliver_at.keys():
		if _clock < _deliver_at[pid]:
			continue
		var a: PlayerAvatar = scene.avatars.get(pid, null)
		if a != null and a.carrier != null and is_instance_valid(a.carrier):
			continue  # still on the bouncer's shoulders: he sets them down (`delivered`)
		_deliver_at.erase(pid)
		_lock_in(pid)
	if jail_left > 0.0:
		jail_left = maxf(jail_left - delta, 0.0)
		if jail_label != null:
			jail_label.text = "IN JAIL   %d s   ·   FINE $%d" % [ceili(jail_left), jail_fine]
			jail_label.visible = true
	elif jail_label != null and jail_label.visible:
		jail_label.visible = false


## True when this process moves `a`'s body (a host's own simulation, or our own avatar).
static func _owns_body(a: PlayerAvatar) -> bool:
	if a.state == PlayerAvatar.State.RAGDOLL:
		return a.ragdoll != null and not a.ragdoll.puppet
	return a.drive != PlayerAvatar.Drive.PUPPET or a.is_local


func _is_host() -> bool:
	return scene.role != MatchScene.Role.CLIENT and scene.server != null


## Puts a player's body at `pos` wherever this process owns it (ragdolls end there); puppets are
## pointed at it and follow their owner's stream.
func _place(a: PlayerAvatar, pos: Vector3, yaw: float) -> void:
	if a.state == PlayerAvatar.State.RAGDOLL:
		a.end_ragdoll(pos + Vector3(0, 0.5, 0))
	elif a.state == PlayerAvatar.State.HELD and a.carrier == null:
		a.release_held()
	elif a.state == PlayerAvatar.State.SEATED:
		a.stand()
	if a.state == PlayerAvatar.State.STUNNED:
		a.state = PlayerAvatar.State.STANDING
	if _owns_body(a):
		a.teleport(pos, yaw)
	else:
		a.target_position = pos
	if _is_host():
		scene.server.set_server_owned(a.player_id, false)
	if scene.net_world != null:
		scene.net_world.reset_player(a.player_id)


# --- Start room ---------------------------------------------------------------------------------

func _sent_back(pid: int, pos: Vector3) -> void:
	var a: PlayerAvatar = scene.avatars.get(pid, null)
	if a == null:
		return
	_place(a, pos, 0.0)
	if pid == scene.local_id and scene.hud != null:
		scene.hud.toast("The casino isn't open yet! Back to the start room.", 2.0)


# --- Jail ---------------------------------------------------------------------------------------

func _jailed(ev: Dictionary) -> void:
	var pid: int = int(ev["player"])
	if pid == scene.local_id:
		_start_local_jail(float(ev.get("time", 0.0)), int(ev.get("fine", 0)))
	var a: PlayerAvatar = scene.avatars.get(pid, null)
	if a == null or not ev.has("pos"):
		return  # no cell on this map: jail is just the timer and the fine
	_cell_spot[pid] = Serializer.to_vec3(ev["pos"])
	_locked.erase(pid)
	a.say("BUSTED!", 1.5)
	Audio.play_at(&"whistle", a, -4.0)
	if a.state == PlayerAvatar.State.SEATED:
		a.stand()
	# The bouncer carries them over where this process simulates both of them.
	if _is_host() and _owns_body(a) and a.is_standing():
		var g: Guard = _nearest_guard(a)
		if g != null and g.carry(a, LuckyLounge.JAIL_DOOR, true):
			if not g.delivered.is_connected(_on_delivered):
				g.delivered.connect(_on_delivered)
			_deliver_at[pid] = _clock + Guard.JAIL_CARRY_SECONDS + 1.0  # in case the carry breaks off
			return
	# Nobody at hand (or a puppet here): knocked out for a moment, then they are inside.
	if a.state != PlayerAvatar.State.RAGDOLL:
		a.visuals.set_knocked_out(true)
		a.stun(KNOCKOUT_SECONDS)
	_deliver_at[pid] = _clock + KNOCKOUT_SECONDS


func _nearest_guard(a: PlayerAvatar) -> Guard:
	var best: Guard = null
	var best_d: float = INF
	for g: Guard in scene.guards:
		if not is_instance_valid(g) or g.puppet or g.carrying != null:
			continue
		var d: float = g.global_position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = g
	return best


func _on_delivered(pid: int) -> void:
	_deliver_at.erase(pid)
	_lock_in(pid)


## Into the cell: on their spot, facing the gate; the gate swings; the jailed player watches the
## floor from above the cage.
func _lock_in(pid: int) -> void:
	if _locked.has(pid) or not _cell_spot.has(pid):
		return
	var a: PlayerAvatar = scene.avatars.get(pid, null)
	if a == null:
		return
	_locked[pid] = true
	a.visuals.set_knocked_out(false)
	_place(a, _cell_spot[pid], CELL_YAW)
	if _is_host() and scene.server.state.players.has(pid) and scene.server.state.players[pid].jail_time_remaining > 0.0:
		scene.server.set_server_position(pid, _cell_spot[pid])
	map.swing_jail_gate()
	if pid == scene.local_id:
		_spectate(true)


func _released(ev: Dictionary) -> void:
	var pid: int = int(ev["player"])
	_deliver_at.erase(pid)
	_locked.erase(pid)
	_cell_spot.erase(pid)
	var a: PlayerAvatar = scene.avatars.get(pid, null)
	if pid == scene.local_id:
		jail_left = 0.0
		if jail_label != null:
			jail_label.visible = false
		var fine: int = int(ev.get("fine", 0))
		if scene.hud != null:
			scene.hud.toast("Released! Fine paid: $%d" % fine if fine > 0 else "Released!", 2.5)
	if a == null:
		return
	a.visuals.set_knocked_out(false)
	if not ev.has("pos"):
		if pid == scene.local_id:
			_spectate(false)
		return
	var out: Vector3 = Serializer.to_vec3(ev["pos"])
	# The local player's walk-out hides behind the minigame curtain (unless a minigame is taking
	# the screen right now: its own curtain is already closing).
	var busy: bool = scene.stage != null or scene.view.state.phase == Phase.Id.MINIGAME or (scene.curtain_tween != null and scene.curtain_tween.is_valid())
	if pid != scene.local_id or busy or scene.curtain_left == null:
		_walk_out(pid, out)
		return
	# Same close / hold / open sequence as the minigame curtain, titled for the release.
	scene._curtain_sequence("Released", "JAIL", 0.0, _walk_out.bind(pid, out))


func _walk_out(pid: int, out: Vector3) -> void:
	var a: PlayerAvatar = scene.avatars.get(pid, null)
	if a == null:
		return
	_place(a, out, 0.0)
	map.swing_jail_gate()
	if pid == scene.local_id:
		_spectate(false)


func _start_local_jail(seconds: float, fine: int) -> void:
	jail_left = seconds
	jail_fine = fine
	if scene.hud != null:
		scene.hud.banner("BUSTED! %d s in jail, $%d fine" % [ceili(seconds), fine], Palette.LOSS_RED, 2.5)


## The jailed player's view: from above the cage over the floor (look around with the mouse).
func _spectate(on: bool) -> void:
	var local: PlayerAvatar = scene.local
	if local == null or local.cam == null or map.jail_camera == null:
		return
	if on:
		local.cam.set_anchor(map.jail_camera)
	elif local.cam.anchor == map.jail_camera:
		local.cam.set_anchor(null)
