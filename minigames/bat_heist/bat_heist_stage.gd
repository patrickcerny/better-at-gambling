class_name BatHeistStage
extends WalkableStage
## Client presentation of Bat Heist in the big vault arena (a `WalkableStage`: real avatars, the
## normal camera). Every bean carries the casino's baseball bat in the right hand; a left click
## swings it (the server decides the hit; E does the same). Right click grabs the bean in front
## (the casino's grab) and the next click throws them: they land knocked down like a bonk. Every
## left click over a downed bean steals one coin, each coin flying from the body to the thief with
## a cha-ching. A coin badge (the casino's gold coin and the count) floats over every other bean
## and drops onto the body with a pulsing "STEAL!" while they can be robbed. A brass shimmer ring
## marks the immunity after getting up. The overlay shows the clock, our coins on a plaque, the
## standings, a feed of hits and steals and a context prompt (swing / grab / throw / click to steal).
##
## Steal input: each click over a downed bean in reach sends `minigame_action {kind: "steal",
## target}` (at most `STEAL_RATE` a second, the server's limit too). The server moves every coin
## (see `BatHeistLogic`).

const BAT_REACH: float = BatHeistLogic.BAT_REACH
const STEAL_REACH: float = BatHeistLogic.STEAL_REACH
const SWING_COOLDOWN: float = BatHeistLogic.SWING_COOLDOWN
const GAME_SECONDS: float = BatHeistLogic.GAME_SECONDS
## Height of the coin badge over a standing bean, and over a body on the floor.
const BADGE_UP: float = 2.62
const BADGE_DOWN: float = 1.15
const STEAL_RATE: int = BatHeistLogic.STEAL_RATE

var coins: Dictionary[int, int] = {}
## pid → seconds left down / immune (client estimates, corrected by the state).
var down_left: Dictionary[int, float] = {}
var immune_left: Dictionary[int, float] = {}
var clock: float = 0.0
var done: bool = false
var bats: Dictionary[int, Node3D] = {}
var badges: Dictionary[int, CoinBadge] = {}
var shimmers: Dictionary[int, ImmunityShimmer] = {}
var coin_plaque: PanelContainer = null
var coin_label: Label = null
## Our steal clicks in the last second (sent ones only: the server's limit, mirrored).
var _steal_clicks: Array[float] = []
var _cooldown: float = 0.0
## Our own swings shown at once: the server's echo then doesn't swing again.
var _predicted_swing: float = -1.0
var _plaque_pop: float = 0.0
## First person hides our own bean (and its bat): the bat sits at the bottom of the view instead.
var _view_bat: Node3D = null


func _build_game(_start: Dictionary) -> void:
	for p: int in roster:
		coins[p] = BatHeistLogic.START_COINS
	_build_props()
	if overlay != null:
		_build_coin_plaque()
	set_clock(GAME_SECONDS)
	_refresh_status()


func apply_state(st: Dictionary) -> void:
	super.apply_state(st)
	clock = float(st.get("clock", clock))
	done = str(st.get("state", "")) == "done"
	var c: Dictionary = st.get("coins", {})
	for k: Variant in c:
		_set_coins(int(k), int(c[k]))
	down_left.clear()
	var d: Dictionary = st.get("down", {})
	for k: Variant in d:
		down_left[int(k)] = float(d[k])
	var im: Dictionary = st.get("immune", {})
	for k: Variant in im:
		_set_immune(int(k), float(im[k]))
	_refresh_status()


func alive_players() -> Array[int]:
	var out: Array[int] = []
	for p: int in roster:
		if coins.has(p):
			out.append(p)
	return out


func can_act() -> bool:
	return super.can_act() and not done and local_id in coins and not down_left.has(local_id)


# --- Input --------------------------------------------------------------------------------------

## The big vault (`BatHeistLogic.ARENA_SCALE`), matching the server's layout.
func _build_room() -> Node3D:
	return VaultArena.build(self, BatHeistLogic.ARENA_SCALE)


## E: the same as a left click.
func on_action_pressed() -> bool:
	return _click()


## Left click: steal from a downed bean in reach, else swing the bat.
func on_grab_pressed() -> bool:
	return _click()


## Right click: the casino's grab (the next click throws).
func on_shove_pressed() -> bool:
	if not can_act():
		return going and not over
	if scene != null:
		scene.grab_in_front()
	return true


func _click() -> bool:
	if holding():
		return false  # the match scene throws the bean we hold
	if not can_act():
		return going and not over
	var victim: int = steal_target()
	if victim >= 0:
		_send_steal(victim)
		return true
	if _cooldown > 0.0:
		return true
	var target: int = swing_target()
	var payload: Dictionary = {"kind": &"swing"}
	if target >= 0:
		payload["target"] = target
	_cooldown = SWING_COOLDOWN
	_predicted_swing = 0.35
	_swing_bat(local_id)
	Net.send_intent(Intents.make(&"minigame_action", payload))
	return true


## True while the local bean holds someone (the next click throws them).
func holding() -> bool:
	return scene != null and scene.local != null and scene._local_holding() >= 0


## One steal click (dropped past `STEAL_RATE` a second: the server would refuse it anyway).
func _send_steal(victim: int) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_steal_clicks = _steal_clicks.filter(func(t: float) -> bool: return t > now - 1.0)
	if _steal_clicks.size() >= STEAL_RATE:
		return
	_steal_clicks.append(now)
	var me: PlayerAvatar = local_avatar()
	if me != null:
		me.visuals.react(&"grab")
	Net.send_intent(Intents.make(&"minigame_action", {"kind": &"steal", "target": victim}))


## The downed, non-immune bean nearest to us within steal reach (any direction), or -1.
func steal_target() -> int:
	var me: PlayerAvatar = local_avatar()
	if me == null:
		return -1
	var best: int = -1
	var best_d: float = STEAL_REACH
	for p: int in down_left:
		if p == local_id or immune_left.has(p) or not coins.has(p):
			continue
		var d: Vector3 = body_position(p) - me.global_position
		d.y = 0.0
		if d.length() <= best_d:
			best_d = d.length()
			best = p
	return best


## The standing, non-immune bean the bat would reach (the server's pick), or -1.
func swing_target() -> int:
	var me: PlayerAvatar = local_avatar()
	if me == null:
		return -1
	var candidates: Dictionary = {}
	for pid: int in alive_players():
		var a: PlayerAvatar = avatar(pid)
		if pid != local_id and a != null and not down_left.has(pid) and not immune_left.has(pid):
			candidates[pid] = a.global_position
	return InteractionRules.pick_in_reach(me.global_position, me.facing(), candidates, local_id, BAT_REACH)


# --- Events -------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	super.on_event(ev)
	if _is_dedicated():
		return  # the dedicated server only needs the room's floor
	match StringName(ev["type"]):
		&"minigame_go":
			banner("BAT HEIST!", Palette.VIP_GOLD, 1.6)
			Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
		&"bat_heist_begin":
			var c: Dictionary = ev.get("coins", {})
			for k: Variant in c:
				_set_coins(int(k), int(c[k]))
			feed("Everyone starts with %d coins" % BatHeistLogic.START_COINS, Palette.VIP_GOLD)
		&"bat_heist_swing":
			var who: int = int(ev["player"])
			if who != local_id or _predicted_swing <= 0.0:
				_swing_bat(who)
			if StringName(ev.get("result", &"")) == &"immune":
				var t: int = int(ev["target"])
				var ta: PlayerAvatar = avatar(t)
				if ta != null:
					Audio.play_at(&"boing", ta, -6.0, 1.3)
					Vfx.floating_text(self, ta.global_position + Vector3(0, 2.2, 0), "IMMUNE", Palette.CREAM, 90, 0.6, 0.9)
				if who == local_id:
					set_prompt("")
		&"bat_heist_hit":
			_on_hit(int(ev["player"]), int(ev["target"]), float(ev.get("seconds", BatHeistLogic.KNOCK_SECONDS)), StringName(ev.get("cause", &"bat")))
		&"bat_heist_up":
			var p: int = int(ev["player"])
			down_left.erase(p)
			_set_immune(p, float(ev.get("immune", BatHeistLogic.IMMUNE_SECONDS)))
		&"bat_heist_stole":
			_on_stole(int(ev["player"]), int(ev["target"]), ev.get("coins", {}))
		&"minigame_eliminated":
			for p: Variant in ev.get("players", []):
				feed("%s left the game" % player_name(int(p)), Color(Palette.CREAM, 0.7))
				_drop_player(int(p))
		&"bat_heist_over":
			done = true
			var c: Dictionary = ev.get("coins", {})
			for k: Variant in c:
				_set_coins(int(k), int(c[k]))
			_announce_winner(ev.get("ranking", []))
	_refresh_status()


func _on_hit(by: int, target: int, seconds: float, cause: StringName = &"bat") -> void:
	down_left[target] = seconds
	immune_left.erase(target)
	var ta: PlayerAvatar = avatar(target)
	var ba: PlayerAvatar = avatar(by)
	if cause == &"throw":
		feed("%s  threw  %s" % [player_name(by), player_name(target)], player_color(by))
		if target == local_id:
			banner("THROWN! GET UP!", Palette.LOSS_RED, 1.0)
		elif by == local_id:
			banner("DOWN! CLICK FAST TO STEAL!", Palette.MONEY_GREEN, 1.0)
		return
	if ta != null:
		var at: Vector3 = ta.global_position + Vector3(0, 1.1, 0)
		HitPop.at(self, at, 1.4)
		Audio.play_at(&"bonk", ta, 0.0, randf_range(0.65, 0.75))
		Vfx.floating_text(self, at + Vector3(0, 0.6, 0), "BONK!", Palette.VIP_GOLD, 120, 0.9, 1.0)
		if ba != null:
			ta.visuals.hit(ta.global_position - ba.global_position, 1.0)
	feed("%s  bonked  %s" % [player_name(by), player_name(target)], player_color(by))
	if target == local_id:
		banner("BONKED! GET UP!", Palette.LOSS_RED, 1.0)
		if scene != null:
			scene._juice(0.05, 0.4)
	elif by == local_id:
		banner("BONK! CLICK FAST TO STEAL!", Palette.MONEY_GREEN, 1.0)
		if scene != null:
			scene._juice(0.04, 0.15)


func _on_stole(thief: int, victim: int, now: Dictionary) -> void:
	for k: Variant in now:
		_set_coins(int(k), int(now[k]))
	var from: Vector3 = body_position(victim) + Vector3(0, 0.5, 0)
	var ta: PlayerAvatar = avatar(thief)
	_fly_coin(from, ta)
	if ta != null:
		Audio.play_at(&"coin", ta, -4.0 if thief == local_id or victim == local_id else -10.0, randf_range(1.0, 1.25))
		if thief == local_id:
			Audio.play(&"cash_register", &"SFX", -9.0, randf_range(1.05, 1.3))  # cha-ching
		elif victim == local_id:
			banner("THEY'RE ROBBING YOU!", Palette.LOSS_RED, 0.6)
		Vfx.floating_text(self, ta.global_position + Vector3(0, 2.0, 0), "+1", Palette.MONEY_GREEN, 80, 0.7, 0.8)
	Vfx.floating_text(self, from + Vector3(0, 0.4, 0), "-1", Palette.LOSS_RED, 70, 0.6, 0.8)
	if thief == local_id or victim == local_id:
		_plaque_pop = 1.0


## A coin leaves the robbed body and flies into the thief (the casino's own coin and its flight).
func _fly_coin(from: Vector3, to: PlayerAvatar) -> void:
	if not Vfx.enabled() or to == null:
		return
	var holder := Node3D.new()
	holder.name = "StolenCoin"
	add_child(holder)
	holder.global_position = from
	holder.scale = Vector3.ONE * 3.0
	var coin := Coin.new()
	coin.gravity = 0.0
	coin.rotation = Vector3(PI * 0.5, randf() * TAU, 0.0)
	holder.add_child(coin)
	coin.fly_to(to)
	Vfx.free_after(holder, 0.6)


func _announce_winner(ranking: Array) -> void:
	var top: Array[int] = []
	var best: int = 0
	for row: Variant in ranking:
		if int(row["rank"]) == 1:
			top.append(int(row["player"]))
			best = int(row.get("coins", row.get("points", 0)))
	if top.size() == 1:
		var w: int = top[0]
		banner("YOU WIN WITH %d COINS!" % best if w == local_id else "%s WINS WITH %d COINS!" % [player_name(w).to_upper(), best], Palette.VIP_GOLD, 3.0)
	elif top.size() > 1:
		banner("TIME!  %d-WAY TIE ON %d COINS" % [top.size(), best], Palette.VIP_GOLD, 3.0)
	for w: int in top:
		var wa: PlayerAvatar = avatar(w)
		if wa != null:
			wa.visuals.react(&"big_win")
	Audio.play(&"quiz_winner", &"SFX", -4.0)


# --- Per frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if going and not done and not over:
		clock = minf(clock + delta, GAME_SECONDS)
		set_clock(GAME_SECONDS - clock)
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
	_update_props()
	_update_view_bat()
	_update_plaque(delta)
	_update_prompt()


func _update_prompt() -> void:
	if prompt_label == null:
		return
	if not going or over or done or local_id not in coins:
		set_prompt("")
		return
	if down_left.has(local_id):
		set_prompt("")
		return
	if holding():
		set_prompt("[{grab}] THROW!")
		return
	var victim: int = steal_target()
	if victim >= 0:
		set_prompt("CLICK FAST TO STEAL!  [{grab}]")
		return
	var t: int = swing_target()
	if t >= 0 and _cooldown <= 0.0:
		set_prompt("[{grab}] SWING AT %s   [{shove}] GRAB" % player_name(t).to_upper())
	elif t >= 0:
		set_prompt("[{shove}] GRAB %s" % player_name(t).to_upper())
	else:
		set_prompt("")


func _refresh_status() -> void:
	if status_label == null:
		return
	var order: Array[int] = alive_players()
	order.sort_custom(func(a: int, b: int) -> bool: return coins[a] > coins[b] if coins[a] != coins[b] else a < b)
	var lines: PackedStringArray = ["COINS"]
	var rank: int = 0
	for i: int in order.size():
		if i == 0 or coins[order[i]] != coins[order[i - 1]]:
			rank = i + 1
		var p: int = order[i]
		var who: String = "YOU" if p == local_id else player_name(p)
		lines.append("%d. %s  %d" % [rank, who, coins[p]])
	status_label.text = "\n".join(lines)
	status_label.add_theme_font_size_override(&"font_size", 26)


# --- Props: bats, coin badges, immunity ---------------------------------------------------------

func _build_props() -> void:
	if _is_dedicated():
		return
	for p: int in roster:
		var a: PlayerAvatar = avatar(p)
		if a == null:
			continue
		var bat: Node3D = ItemModels.make_held(&"baseball_bat")
		bat.name = "HeistBat"
		ItemModels.attach_to_hand(a.visuals, bat)
		bats[p] = bat
		if p != local_id:
			var badge := CoinBadge.new(coins.get(p, 0))
			add_child(badge)
			badges[p] = badge


func _update_props() -> void:
	for p: int in badges:
		var b: CoinBadge = badges[p]
		if not is_instance_valid(b):
			continue
		var down: bool = down_left.has(p)
		var target_pos: Vector3 = body_position(p) + Vector3(0, BADGE_DOWN if down else BADGE_UP, 0)
		b.global_position = b.global_position.lerp(target_pos, 0.35) if b.global_position.distance_to(target_pos) < 3.0 else target_pos
		b.set_stealable(down and not immune_left.has(p) and not done and not over)
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


func _set_immune(p: int, seconds: float) -> void:
	if seconds <= 0.0:
		return
	immune_left[p] = seconds
	if _is_dedicated() or avatar(p) == null:
		return
	if shimmers.has(p) and is_instance_valid(shimmers[p]):
		shimmers[p].restart(seconds)
		return
	var s := ImmunityShimmer.new(seconds)
	add_child(s)
	s.global_position = avatar(p).global_position
	shimmers[p] = s
	if p == local_id:
		Audio.play(&"chime", &"SFX", -8.0, 1.3)


func _set_coins(p: int, c: int) -> void:
	if not coins.has(p) and p not in roster:
		return
	coins[p] = c
	if badges.has(p) and is_instance_valid(badges[p]):
		badges[p].set_count(c)


func _drop_player(p: int) -> void:
	coins.erase(p)
	down_left.erase(p)
	immune_left.erase(p)
	for d: Dictionary in [badges, shimmers]:
		if d.has(p) and is_instance_valid(d[p]):
			(d[p] as Node).queue_free()
		d.erase(p)
	_remove_bat(p)


## Where a bean's body is: the ragdoll's when they're down, else the avatar.
func body_position(pid: int) -> Vector3:
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return Vector3.ZERO
	if a.ragdoll != null and is_instance_valid(a.ragdoll):
		return a.ragdoll.body_position()
	return a.global_position


## The bat whips round: wind up over the shoulder, a flat arc across the front, back to rest. The
## bean's own lunge (`visuals.swing`) carries the arm.
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
		_view_bat.name = "HeistViewBat"
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


# --- Our coin plaque ----------------------------------------------------------------------------

func _build_coin_plaque() -> void:
	coin_plaque = PanelContainer.new()
	coin_plaque.name = "CoinPlaque"
	var sb: StyleBoxFlat = plaque_style()
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	coin_plaque.add_theme_stylebox_override(&"panel", sb)
	coin_plaque.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	coin_plaque.grow_vertical = Control.GROW_DIRECTION_BEGIN
	coin_plaque.position = Vector2(24, -36)
	coin_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_plaque.add_child(row)
	row.add_child(_coin_icon(46))
	coin_label = label("", 52, Palette.VIP_GOLD)
	row.add_child(coin_label)
	var tag: Label = label("COINS", 26, Palette.CREAM)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(tag)
	coin_plaque.visible = local_id in roster
	overlay.add_child(coin_plaque)


## A flat gold coin for the 2D overlay: a rim, a face and an embossed "$".
func _coin_icon(px: int) -> Control:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(px, px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.VIP_GOLD
	sb.border_color = Palette.WARM_GOLD.darkened(0.25)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(px)
	c.add_theme_stylebox_override(&"panel", sb)
	var mark: Label = label("$", int(px * 0.62), Palette.WARM_GOLD.darkened(0.35))
	mark.remove_theme_color_override(&"font_shadow_color")
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(mark)
	return c


func _update_plaque(delta: float) -> void:
	if coin_label == null:
		return
	coin_label.text = str(coins.get(local_id, 0))
	_plaque_pop = maxf(_plaque_pop - delta * 2.5, 0.0)
	coin_label.pivot_offset = coin_label.size * 0.5
	coin_label.scale = Vector2.ONE * (1.0 + 0.35 * _plaque_pop * _plaque_pop)


## The bats live on avatars outside this stage: they go with the stage.
func _exit_tree() -> void:
	done = true
	for p: int in bats.keys():
		_remove_bat(p)
	if _view_bat != null and is_instance_valid(_view_bat):
		_view_bat.queue_free()
	_view_bat = null
