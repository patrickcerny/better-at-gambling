class_name JackpotClimbStage
extends WalkableStage
## Client presentation of Jackpot Climb in the climb room's chip towers (`ClimbRoom` "towers", a
## `WalkableStage`: real avatars, the normal camera). Every bean carries the casino's baseball bat
## (Bat Heist's model and swing); E swings it, the server decides the hit
## (`minigame_action {kind: "swing", target?}`) and the room's knockdown throws the ragdoll away
## from the attacker and up, off the ledge (`MatchScene._knock_down`). Reaching a tier lights its
## checkpoint flag for us (gold cloth, a burst, a banner); falling below it, the server puts us back
## at the flag (`minigame_player_moved`) and we show a puff there. The JACKPOT sign turns slowly
## over the pad, its warm bulbs chasing, and flashes each finisher's name. Lucky hosts from the
## podium by the apron. The overlay: the clock, a vertical ladder with a flag per checkpoint and
## every bean's marker, the finish order, the feed, Lucky's line and a context prompt.

const LADDER_H: float = 420.0
const MARKER: float = 30.0
const SIGN_TURN: float = 0.22
const FLASH_SECONDS: float = 3.5

var clock: float = 0.0
var done: bool = false
var winner: int = -1
var finish_groups: Array = []
var down_left: Dictionary[int, float] = {}
var immune_left: Dictionary[int, float] = {}
var last_call_left: float = -1.0
## player → checkpoint reached (1..3).
var checkpoints: Dictionary[int, int] = {}
var host: QuizHost = null
## player → the bat in their hand.
var bats: Dictionary[int, Node3D] = {}
var shimmers: Dictionary[int, ImmunityShimmer] = {}
var _cooldown: float = 0.0
## Our own swing shown at once: the server's echo then doesn't swing again.
var _predicted_swing: float = -1.0
var _view_bat: Node3D = null
var _sign: Node3D = null
var _bulbs: Array[StandardMaterial3D] = []
var _names: Array[Label3D] = []
var _flash_left: float = 0.0
var _chase: float = 0.0
var _ladder_track: Control = null
var _markers: Dictionary[int, Control] = {}
var _host_panel: PanelContainer = null
var _host_label: Label = null
var _status_left: float = 0.0
var _said_halfway: bool = false
## Checkpoint index → its flag's cloth (lit gold once we reached it).
var _cloths: Dictionary[int, MeshInstance3D] = {}
var _lit_cloth: StandardMaterial3D = null


func _build_room() -> Node3D:
	return ClimbRoom.build(self, JackpotClimbLogic.VARIANT)


func _build_game(_start: Dictionary) -> void:
	if _is_dedicated():
		return
	host = QuizHost.new()
	host.name = "LuckyHost"
	add_child(host)
	host.position = WalkableLogicBase.ROOM_ORIGIN + ClimbRoom.lucky_spot(JackpotClimbLogic.VARIANT)
	host.rotation.y = 2.3  # facing the towers and the apron
	host.scale = Vector3.ONE * 1.3
	_find_sign()
	_find_flags()
	_build_bats()
	if overlay != null:
		_build_ladder()
		_build_host_panel()
	set_clock(JackpotClimbLogic.GAME_SECONDS)
	_say("Welcome to the Jackpot Climb! Run up the ramps round the chips to my sign. Every tier has a flag to catch your fall. Bats are allowed, so mind the edge.", QuizHost.Pose.HAPPY)
	_refresh_status()


func apply_state(st: Dictionary) -> void:
	super.apply_state(st)
	clock = float(st.get("clock", clock))
	done = str(st.get("state", "")) == "done"
	winner = int(st.get("winner", -1))
	finish_groups.clear()
	for g: Variant in st.get("finish", []):
		var grp: Array[int] = []
		for p: Variant in g:
			grp.append(int(p))
		finish_groups.append(grp)
	down_left.clear()
	var dn: Dictionary = st.get("down", {})
	for k: Variant in dn:
		down_left[int(k)] = float(dn[k])
	immune_left.clear()
	var im: Dictionary = st.get("immune", {})
	for k: Variant in im:
		immune_left[int(k)] = float(im[k])
	last_call_left = float(st.get("last_call", -1.0))
	var cps: Dictionary = st.get("checkpoints", {})
	for k: Variant in cps:
		checkpoints[int(k)] = maxi(int(cps[k]), int(checkpoints.get(int(k), 0)))
	_light_flags()
	_refresh_status()


func is_up(pid: int) -> bool:
	for g: Array in finish_groups:
		if pid in g:
			return true
	return false


func finish_place(pid: int) -> int:
	var place: int = 1
	for g: Array in finish_groups:
		if pid in g:
			return place
		place += g.size()
	return 0


## Height of a bean (0..1): finishers 1, else from the body we see.
func height_of(pid: int) -> float:
	if is_up(pid):
		return 1.0
	var a: PlayerAvatar = avatar(pid)
	return ClimbRoom.progress(a.global_position, JackpotClimbLogic.VARIANT) if a != null else 0.0


func can_act() -> bool:
	return super.can_act() and not done and local_id in roster and not down_left.has(local_id) and not is_up(local_id)


# --- Input --------------------------------------------------------------------------------------

## E swings the bat (the server picks the hit; our pick goes along as a hint).
func on_action_pressed() -> bool:
	if not can_act():
		return going and not over
	if _cooldown > 0.0:
		return true
	var target: int = swing_target()
	var payload: Dictionary = {"kind": &"swing"}
	if target >= 0:
		payload["target"] = target
	_cooldown = JackpotClimbLogic.SWING_COOLDOWN
	_predicted_swing = 0.35
	_swing_bat(local_id)
	Net.send_intent(Intents.make(&"minigame_action", payload))
	return true


## The standing, hittable bean the bat would reach (the server's pick), or -1.
func swing_target() -> int:
	var me: PlayerAvatar = local_avatar()
	if me == null:
		return -1
	var candidates: Dictionary = {}
	for pid: int in roster:
		var a: PlayerAvatar = avatar(pid)
		if pid != local_id and a != null and not down_left.has(pid) and not immune_left.has(pid) and not is_up(pid):
			candidates[pid] = a.global_position
	return InteractionRules.pick_in_reach(me.global_position, me.facing(), candidates, local_id, JackpotClimbLogic.BAT_REACH)


# --- Events -------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	super.on_event(ev)
	if _is_dedicated():
		return
	match StringName(ev["type"]):
		&"minigame_go":
			banner("CLIMB!", Palette.VIP_GOLD, 1.4)
			Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
			_say("Go go go! First one under my sign takes the jackpot.", QuizHost.Pose.DRUMROLL)
		&"jackpot_climb_begin":
			feed("Reach the JACKPOT sign first", Palette.VIP_GOLD)
		&"jackpot_climb_clock":
			clock = float(ev.get("clock", clock))
		&"jackpot_climb_swing":
			var who: int = int(ev["player"])
			if who != local_id or _predicted_swing <= 0.0:
				_swing_bat(who)
			if who == local_id and StringName(ev.get("result", &"")) == &"immune":
				banner("THEY JUST GOT UP!", Color(Palette.CREAM, 0.9), 0.8)
		&"jackpot_climb_hit":
			_on_hit(int(ev["player"]), int(ev["target"]), float(ev.get("seconds", JackpotClimbLogic.KNOCK_SECONDS)))
		&"jackpot_climb_up":
			var p: int = int(ev["player"])
			down_left.erase(p)
			_set_immune(p, float(ev.get("immune", JackpotClimbLogic.IMMUNE_SECONDS)))
		&"jackpot_climb_top":
			_on_top(ev)
		&"jackpot_climb_checkpoint":
			_on_checkpoint(int(ev["player"]), int(ev.get("index", 1)))
		&"jackpot_climb_respawn":
			_on_respawn(int(ev["player"]), int(ev.get("index", 1)), Serializer.to_vec3(ev.get("pos", [])) if ev.has("pos") else Vector3.INF)
		&"jackpot_climb_last_call":
			last_call_left = float(ev.get("seconds", JackpotClimbLogic.LAST_CALL))
			banner("LAST CALL!", Palette.LOSS_RED, 1.4)
			Audio.play(&"last_call_bell", &"SFX", -6.0)
			var left: Array[int] = []
			for p: int in roster:
				if not is_up(p):
					left.append(p)
			if left.size() == 1:
				_say("Last call, %s! Ten seconds to the jackpot!" % player_name(left[0]), QuizHost.Pose.SURPRISED)
		&"minigame_eliminated":
			if StringName(ev.get("cause", &"")) == &"dropout":
				for p: Variant in ev.get("players", []):
					feed("%s left the game" % player_name(int(p)), Color(Palette.CREAM, 0.7))
					_remove_bat(int(p))
		&"jackpot_climb_over":
			done = true
			winner = int(ev.get("winner", -1))
			_announce(ev.get("ranking", []), StringName(ev.get("reason", &"")))
	_refresh_status()


func _on_hit(by: int, target: int, seconds: float) -> void:
	down_left[target] = seconds
	immune_left.erase(target)
	var ta: PlayerAvatar = avatar(target)
	if ta != null:
		var at: Vector3 = ta.global_position + Vector3(0, 1.1, 0)
		HitPop.at(self, at, 1.5)
		Audio.play_at(&"bonk", ta, 0.0, randf_range(0.65, 0.75))
		Vfx.floating_text(self, at + Vector3(0, 0.6, 0), "BONK!", Palette.VIP_GOLD, 120, 0.9, 1.0)
	feed("%s  bonked  %s off the chips" % [player_name(by), player_name(target)], player_color(by))
	if target == local_id:
		banner("KNOCKED OFF!", Palette.LOSS_RED, 1.0)
		if scene != null:
			scene._juice(0.05, 0.4)
	elif by == local_id:
		banner("BONK!", Palette.MONEY_GREEN, 0.8)
		if scene != null:
			scene._juice(0.04, 0.15)
	elif randf() < 0.3:
		_say("Ooh! %s takes the express elevator down." % player_name(target), QuizHost.Pose.SURPRISED)


func _on_checkpoint(pid: int, k: int) -> void:
	if k <= int(checkpoints.get(pid, 0)):
		return
	checkpoints[pid] = k
	var a: PlayerAvatar = avatar(pid)
	if pid == local_id:
		banner("CHECKPOINT %d!" % k, Palette.VIP_GOLD, 1.4)
		Audio.play(&"chime", &"SFX", -6.0, 1.1)
		_light_flags()
		var cloth: MeshInstance3D = _cloths.get(k, null)
		if cloth != null and is_instance_valid(cloth):
			WinFx.gold_burst(self, cloth.global_position, 0.7)
			var t: Tween = cloth.create_tween()
			cloth.scale = Vector3(1.0, 0.2, 1.0)
			t.tween_property(cloth, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif a != null:
		WinFx.coin_burst(self, a.global_position + Vector3(0, 1.2, 0), 8, 2.0)
	feed("%s reached checkpoint %d" % [player_name(pid), k], player_color(pid))
	if pid != local_id and randf() < 0.35:
		_say("%s plants a flag on tier %d!" % [player_name(pid), k], QuizHost.Pose.HAPPY)


func _on_respawn(pid: int, k: int, at: Vector3) -> void:
	if at != Vector3.INF:
		HitPop.at(self, at + Vector3(0, 1.0, 0), 1.0)
	if pid == local_id:
		banner("BACK TO CHECKPOINT %d" % k, Color(Palette.CREAM, 0.9), 1.0)
		Audio.play(&"whoosh", &"SFX", -8.0, 1.3)


## Our reached flags wear gold.
func _light_flags() -> void:
	var mine: int = int(checkpoints.get(local_id, 0))
	for k: int in _cloths:
		var cloth: MeshInstance3D = _cloths[k]
		if cloth != null and is_instance_valid(cloth) and k <= mine and cloth.material_override != _lit_cloth:
			cloth.material_override = _lit_cloth


func _find_flags() -> void:
	if room == null:
		return
	_lit_cloth = StandardMaterial3D.new()
	_lit_cloth.albedo_color = Palette.VIP_GOLD
	_lit_cloth.emission_enabled = true
	_lit_cloth.emission = Palette.WARM_GOLD
	_lit_cloth.emission_energy_multiplier = 0.9
	_lit_cloth.roughness = 0.5
	for cp: Dictionary in ChipTowers.checkpoints():
		var k: int = int(cp["index"])
		var flag: Node3D = room.find_child("Flag%d" % k, true, false) as Node3D
		if flag != null:
			_cloths[k] = flag.find_child("Cloth", true, false) as MeshInstance3D


func _on_top(ev: Dictionary) -> void:
	var place: int = int(ev.get("place", 1))
	var grp: Array[int] = []
	var names: PackedStringArray = []
	for p: Variant in ev.get("players", []):
		grp.append(int(p))
		names.append(player_name(int(p)))
	var placed: bool = false
	for p: int in grp:
		if is_up(p):
			placed = true
	if not placed:
		finish_groups.append(grp)
	for pid: int in grp:
		down_left.erase(pid)
		var a: PlayerAvatar = avatar(pid)
		if a != null:
			var at: Vector3 = a.global_position + Vector3(0, 1.2, 0)
			WinFx.gold_burst(self, at, 1.2 if place == 1 else 0.8)
			WinFx.coin_burst(self, at, 26 if place == 1 else 14, 3.6)
			Vfx.floating_text(self, a.global_position + Vector3(0, 2.3, 0), "#%d" % place, Palette.VIP_GOLD, 130, 1.2, 1.4)
			a.visuals.react(&"big_win" if place == 1 else &"win")
		if pid == local_id:
			banner("JACKPOT!  #%d" % place, Palette.VIP_GOLD, 2.0)
			Audio.play(&"big_win" if place == 1 else &"minor_win", &"SFX", -4.0)
	_flash_sign(("#%d  " % place) + " & ".join(names).to_upper())
	feed("%s hit the jackpot  (#%d)" % [" & ".join(names), place], Palette.VIP_GOLD)
	if place == 1:
		_say("%s rings the jackpot first!" % " and ".join(names), QuizHost.Pose.HAPPY)
		if local_id not in grp:
			banner("%s IS UP!" % " & ".join(names).to_upper(), Palette.VIP_GOLD, 1.4)
		Audio.play(&"chime", &"SFX", -4.0)
	elif randf() < 0.6:
		_say("%s made it! Number %d." % [" and ".join(names), place], QuizHost.Pose.HAPPY)


func _announce(ranking: Array, reason: StringName) -> void:
	var top: Array[int] = []
	for row: Variant in ranking:
		if int(row["rank"]) == 1:
			top.append(int(row["player"]))
	if top.size() == 1:
		var w: int = top[0]
		banner("YOU WIN!" if w == local_id else "%s WINS!" % player_name(w).to_upper(), Palette.VIP_GOLD, 3.0)
		feed("%s: %s" % [player_name(w), "first to the jackpot" if is_up(w) else "highest on the chips"], Palette.VIP_GOLD)
		if is_up(w):
			_say("%s climbed to the jackpot first. The winner!" % player_name(w), QuizHost.Pose.HAPPY, 4.0)
		else:
			_say("Time! Nobody made it, but %s climbed highest. The winner!" % player_name(w), QuizHost.Pose.HAPPY, 4.0)
		_flash_sign("WINNER  " + player_name(w).to_upper())
		var wa: PlayerAvatar = avatar(w)
		if wa != null:
			wa.visuals.react(&"big_win")
	else:
		banner("A TIE AT THE TOP!", Palette.VIP_GOLD, 3.0)
		_say("Dead heat! %s share it." % " and ".join(top.map(func(p: int) -> String: return player_name(p))), QuizHost.Pose.SURPRISED, 4.0)
	if reason == &"time":
		Audio.play(&"buzzer", &"SFX", -8.0)
	Audio.play(&"quiz_winner", &"SFX", -4.0)


# --- Per frame ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if going and not over and not done:
		clock = minf(clock + delta, JackpotClimbLogic.GAME_SECONDS)
	if _is_dedicated():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_predicted_swing = maxf(_predicted_swing - delta, 0.0) if _predicted_swing > 0.0 else -1.0
	for p: int in down_left.keys():
		down_left[p] -= delta
		if down_left[p] <= -1.0:
			down_left.erase(p)  # the server's "up" got lost: don't hold a stale "down" forever
	for p: int in immune_left.keys():
		immune_left[p] -= delta
		if immune_left[p] <= 0.0:
			immune_left.erase(p)
	if last_call_left > 0.0 and not done:
		last_call_left = maxf(last_call_left - delta, 0.0)
	if done or over:
		if clock_label != null:
			clock_label.text = "FINAL"
			clock_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	elif last_call_left > 0.0:
		set_clock(minf(last_call_left, JackpotClimbLogic.GAME_SECONDS - clock))
	else:
		set_clock(JackpotClimbLogic.GAME_SECONDS - clock)
	if not _said_halfway and going and clock >= JackpotClimbLogic.GAME_SECONDS - 60.0 and not done:
		_said_halfway = true
		_say("One minute left! The jackpot is still waiting.", QuizHost.Pose.DRUMROLL)
	_update_sign(delta)
	_update_shimmers()
	_update_view_bat()
	_update_ladder()
	_update_prompt()
	_status_left -= delta
	if _status_left <= 0.0:
		_status_left = 0.3
		_refresh_status()


func _update_prompt() -> void:
	if prompt_label == null:
		return
	if not going or over or done or local_id not in roster:
		set_prompt("")
		return
	if is_up(local_id):
		set_prompt("JACKPOT!  #%d" % finish_place(local_id))
		return
	if down_left.has(local_id):
		set_prompt("")
		return
	var me: PlayerAvatar = local_avatar()
	if me == null:
		set_prompt("")
		return
	var t: int = swing_target()
	var h: float = ClimbRoom.progress(me.global_position, JackpotClimbLogic.VARIANT)
	var cp: int = int(checkpoints.get(local_id, 0))
	if t >= 0 and _cooldown <= 0.0:
		set_prompt("[{interact}] SWING AT %s!" % player_name(t).to_upper())
	elif h < 0.02 and me.global_position.z > WalkableLogicBase.ROOM_ORIGIN.z - 1.0 and clock < 15.0:
		set_prompt("RUN UP THE RAMP: GREEN IS STEADY, RED HAS HOPS")
	elif h < 0.02 and cp == 0:
		set_prompt("ON THE NET: RUN ROUND TO THE RAMP AGAIN")
	elif h > 0.85:
		set_prompt("ALMOST AT THE JACKPOT!")
	elif cp > 0 and absf(h - ChipTowers.level_y(cp) / ClimbRoom.TOWER_TOP_Y) < 0.01:
		set_prompt("CHECKPOINT %d: PICK A RAMP AND RUN ON" % cp)
	else:
		set_prompt("KEEP RUNNING UP   [{jump}] HOP   [{interact}] SWING")


func _refresh_status() -> void:
	if status_label == null:
		return
	var lines: PackedStringArray = ["TO THE JACKPOT"]
	var place: int = 1
	for g: Array in finish_groups:
		for p: int in g:
			lines.append("#%d  %s" % [place, "YOU" if p == local_id else player_name(p)])
		place += g.size()
	var rest: Array[int] = []
	for p: int in roster:
		if not is_up(p):
			rest.append(p)
	rest.sort_custom(func(a: int, b: int) -> bool: return height_of(a) > height_of(b))
	for p: int in rest:
		var tag: String = "DOWN" if down_left.has(p) else "%dm" % roundi(height_of(p) * ClimbRoom.TOWER_TOP_Y)
		if checkpoints.has(p):
			tag += "  CP%d" % checkpoints[p]
		lines.append("%s  %s" % ["YOU" if p == local_id else player_name(p), tag])
	status_label.text = "\n".join(lines)
	status_label.add_theme_font_size_override(&"font_size", 26)


# --- The sign ---------------------------------------------------------------------------------------

func _find_sign() -> void:
	if room == null:
		return
	_sign = room.find_child("JackpotSign", true, false) as Node3D
	if _sign == null:
		return
	for n: String in ["BulbsA", "BulbsB"]:
		var mmi: MultiMeshInstance3D = _sign.find_child(n, true, false) as MultiMeshInstance3D
		if mmi != null:
			_bulbs.append(mmi.material_override as StandardMaterial3D)
	for n: String in ["NameFront", "NameBack"]:
		var l: Label3D = _sign.find_child(n, true, false) as Label3D
		if l != null:
			_names.append(l)


## The sign turns slowly; its two bulb sets chase (fast while it flashes a name).
func _update_sign(delta: float) -> void:
	if _sign == null:
		return
	_sign.rotation.y += SIGN_TURN * delta
	_flash_left = maxf(_flash_left - delta, 0.0)
	_chase += delta * (9.0 if _flash_left > 0.0 else 2.5)
	var on: bool = int(_chase) % 2 == 0
	for i: int in _bulbs.size():
		if _bulbs[i] != null:
			_bulbs[i].emission_energy_multiplier = 2.8 if (i == 0) == on else 0.35
	for l: Label3D in _names:
		l.modulate = Palette.VIP_GOLD.lerp(Palette.CREAM, 0.5 + 0.5 * sin(_chase * PI)) if _flash_left > 0.0 else Palette.CREAM


func _flash_sign(text: String) -> void:
	_flash_left = FLASH_SECONDS
	for l: Label3D in _names:
		l.text = text


# --- Bats -------------------------------------------------------------------------------------------

func _build_bats() -> void:
	for p: int in roster:
		var a: PlayerAvatar = avatar(p)
		if a == null:
			continue
		var bat: Node3D = ItemModels.make_held(&"baseball_bat")
		bat.name = "ClimbBat"
		ItemModels.attach_to_hand(a.visuals, bat)
		bats[p] = bat


## The bat whips round (Bat Heist's swing): wind up, a flat arc across the front, back to rest.
func _swing_bat(pid: int) -> void:
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	a.visuals.swing()
	Audio.play_at(&"whoosh", a, -8.0, randf_range(0.8, 0.95))
	if pid == local_id and _view_bat != null and is_instance_valid(_view_bat):
		var base: Vector3 = _view_bat.rotation
		var vt: Tween = _view_bat.create_tween()
		vt.tween_property(_view_bat, "rotation", base + Vector3(0.3, 0.0, 0.9), 0.08)
		vt.tween_property(_view_bat, "rotation", base + Vector3(-0.4, 0.0, -1.2), 0.13).set_ease(Tween.EASE_IN)
		vt.tween_property(_view_bat, "rotation", base, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bat: Node3D = bats.get(pid, null)
	if bat == null or not is_instance_valid(bat):
		return
	var rest: Vector3 = Vector3(ItemModels.HAND_UPRIGHT, 0.0, 0.0)
	var t: Tween = bat.create_tween()
	t.tween_property(bat, "rotation", rest + Vector3(-0.5, 0.0, 1.1), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(bat, "rotation", rest + Vector3(0.25, 0.0, -1.5), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(bat, "rotation", rest, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_view_bat() -> void:
	var me: PlayerAvatar = local_avatar()
	var want: bool = me != null and me.cam != null and me.cam.mode == PlayerCamera.Mode.FIRST and bats.has(local_id) and not done and not over
	if want and (_view_bat == null or not is_instance_valid(_view_bat)):
		_view_bat = ItemModels.make_view(&"baseball_bat")
		_view_bat.name = "ClimbViewBat"
		me.cam.camera.add_child(_view_bat)
	elif not want and _view_bat != null:
		if is_instance_valid(_view_bat):
			_view_bat.queue_free()
		_view_bat = null


func _remove_bat(pid: int) -> void:
	var bat: Node3D = bats.get(pid, null)
	if bat != null and is_instance_valid(bat):
		bat.queue_free()
	bats.erase(pid)


## The short grace after getting up shows as Bat Heist's shimmer.
func _set_immune(p: int, seconds: float) -> void:
	if seconds <= 0.0:
		return
	immune_left[p] = seconds
	var a: PlayerAvatar = avatar(p)
	if a == null:
		return
	if shimmers.has(p) and is_instance_valid(shimmers[p]):
		shimmers[p].restart(seconds)
		return
	var s := ImmunityShimmer.new(seconds)
	add_child(s)
	s.global_position = a.global_position
	shimmers[p] = s


func _update_shimmers() -> void:
	for p: int in shimmers.keys():
		var s: ImmunityShimmer = shimmers[p]
		if not is_instance_valid(s) or s.left <= 0.0:
			if is_instance_valid(s):
				s.queue_free()
			shimmers.erase(p)
			continue
		var a: PlayerAvatar = avatar(p)
		if a != null:
			s.global_position = a.global_position


# --- Overlay: the ladder and Lucky's line ---------------------------------------------------------

func _build_ladder() -> void:
	var ladder := PanelContainer.new()
	ladder.name = "ClimbLadder"
	var sb: StyleBoxFlat = plaque_style()
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	ladder.add_theme_stylebox_override(&"panel", sb)
	ladder.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	ladder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ladder.grow_vertical = Control.GROW_DIRECTION_BOTH
	ladder.offset_left = -24
	ladder.offset_right = -24
	ladder.offset_top = 40
	ladder.offset_bottom = 40
	ladder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ladder.add_child(col)
	var top: Label = label("JACKPOT", 22, Palette.VIP_GOLD)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(top)
	_ladder_track = Control.new()
	_ladder_track.custom_minimum_size = Vector2(96, LADDER_H)
	_ladder_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_ladder_track)
	var rail := ColorRect.new()
	rail.color = Color(Palette.WARM_GOLD, 0.8)
	rail.position = Vector2(46, 0)
	rail.size = Vector2(4, LADDER_H)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder_track.add_child(rail)
	# A small rung every two metres, a burgundy flag per checkpoint, a wide gold one for the pad.
	var y: float = 2.0
	while y < ClimbRoom.TOWER_TOP_Y - 0.5:
		var rung := ColorRect.new()
		rung.color = Color(Palette.CREAM, 0.35)
		rung.size = Vector2(16, 2)
		rung.position = Vector2(48 - 8, LADDER_H * (1.0 - y / ClimbRoom.TOWER_TOP_Y) - 1.0)
		rung.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ladder_track.add_child(rung)
		y += 2.0
	for cp: Dictionary in ChipTowers.checkpoints():
		var fy: float = LADDER_H * (1.0 - float(cp["y"]) / ClimbRoom.TOWER_TOP_Y)
		var bar := ColorRect.new()
		bar.color = Palette.VIP_BURGUNDY.lightened(0.25)
		bar.size = Vector2(44, 4)
		bar.position = Vector2(48 - 22, fy - 2.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ladder_track.add_child(bar)
		var tag: Label = label(str(int(cp["index"])), 16, Palette.VIP_GOLD)
		tag.position = Vector2(76, fy - 12.0)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ladder_track.add_child(tag)
	var pad := ColorRect.new()
	pad.color = Palette.VIP_GOLD
	pad.size = Vector2(60, 4)
	pad.position = Vector2(18, -2)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder_track.add_child(pad)
	var start: Label = label("NET", 18, Color(Palette.CREAM, 0.7))
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(start)
	for p: int in roster:
		var m := Panel.new()
		var ms := StyleBoxFlat.new()
		ms.bg_color = player_color(p)
		ms.set_corner_radius_all(int(MARKER * 0.5))
		ms.set_border_width_all(3 if p == local_id else 2)
		ms.border_color = Palette.CREAM if p == local_id else Palette.CASINO_BLACK
		m.add_theme_stylebox_override(&"panel", ms)
		var size_px: float = MARKER + (6.0 if p == local_id else 0.0)
		m.size = Vector2(size_px, size_px)
		m.position = Vector2(48.0 - size_px * 0.5, LADDER_H - size_px * 0.5)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var initial: Label = label(player_name(p).left(1).to_upper(), 18, Palette.CASINO_BLACK)
		initial.remove_theme_color_override(&"font_shadow_color")
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.add_child(initial)
		_ladder_track.add_child(m)
		_markers[p] = m
	overlay.add_child(ladder)


func _update_ladder() -> void:
	if _ladder_track == null:
		return
	# Markers at the same height fan out sideways so every head shows.
	var order: Array[int] = roster.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool: return height_of(a) > height_of(b))
	var prev_y: float = -INF
	var shift: int = 0
	for p: int in order:
		var m: Control = _markers.get(p, null)
		if m == null:
			continue
		var y: float = LADDER_H * (1.0 - height_of(p)) - m.size.y * 0.5
		shift = shift + 1 if absf(y - prev_y) < MARKER * 0.6 else 0
		prev_y = y
		var x: float = 48.0 - m.size.x * 0.5 + (float((shift + 1) / 2) * MARKER * 0.7 * (1.0 if shift % 2 == 1 else -1.0))
		m.position = m.position.lerp(Vector2(x, y), 0.25)
		m.modulate.a = 0.55 if down_left.has(p) else 1.0
		if p == local_id:
			m.move_to_front()


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
	_host_label.custom_minimum_size = Vector2(420, 0)
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


## The bats live on avatars outside this stage: they go with the stage.
func _exit_tree() -> void:
	done = true
	for p: int in bats.keys():
		_remove_bat(p)
	if _view_bat != null and is_instance_valid(_view_bat):
		_view_bat.queue_free()
	_view_bat = null
