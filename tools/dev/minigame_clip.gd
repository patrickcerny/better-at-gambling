extends Node
## Dev: records the short looping preview clip a minigame's rules card plays
## (tools/minigame_clips.sh → assets/minigames/clips/<id>.webp, a sprite sheet).
## Table games run their real logic in real time with every seat played by a simple bot that
## submits random legal intents; walkable games use their dev shot (tools/dev/<id>_shot.tscn) with
## the beans walking about and the camera drifting. Frames go to `--out <dir>` as f000.png...
##   xvfb-run -a tools/godot/godot --path . --rendering-method gl_compatibility --fixed-fps 30
##     --resolution 1280x720 --audio-driver Dummy res://tools/dev/minigame_clip.tscn --
##     --game quiz --out /tmp/clip [--skip S] [--seconds 4] [--every 3] [--warmup 1.0]
## Quits by itself after the last frame.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy", "Snake Eyes"]
const CLUE_WORDS: Array[String] = ["shiny", "loud", "round", "lucky", "cold", "fast", "red", "rich"]
## Frame size of the clip (16:9).
const FRAME: Vector2i = Vector2i(384, 216)
## Walkable games: the beans' wander radius per game (climbs stay on their ledges).
const WANDER: Dictionary = {&"dodge_the_dice": 0.25, &"jackpot_climb": 0.25, &"roulette_sumo": 0.5}
const SWINGERS: Array[StringName] = [&"bat_heist", &"jackpot_climb"]

var game: StringName
var out_dir: String = ""
var seconds: float = 4.0
var every: int = 3
var warmup: float = 1.0
var logic: MinigameLogicBase
var stage: Node
var now: float = 0.0
var walkable: bool = false
var _t: float = 0.0
var _frame: int = 0
var _tick: int = 0
var _rng := RandomNumberGenerator.new()
## player → next time the bot acts.
var _next_act: Dictionary = {}
## Walkable: [visuals, base position, phase, speed].
var _beans: Array[Array] = []
var _cam: Camera3D
var _cam_base: Transform3D
var _cam_pivot: Vector3


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	game = StringName(c.get_string("game", "quiz"))
	out_dir = c.get_string("out", "user://clip")
	seconds = c.get_float("seconds", 4.0)
	every = maxi(c.get_int("every", 3), 1)
	warmup = c.get_float("warmup", 1.0)
	_rng.seed = 11
	DirAccess.make_dir_recursive_absolute(out_dir)
	var shot: String = "res://tools/dev/%s_shot.tscn" % game
	walkable = Registry.minigames[game].logic_script.new() is WalkableLogicBase
	if walkable:
		add_child((load(shot) as PackedScene).instantiate())
		_collect_beans.call_deferred()
	else:
		_start_table(c.get_float("skip", 0.0))


# --- Table games: real logic, bot seats ---------------------------------------------------------

func _start_table(skip: float) -> void:
	_environment()
	var def: MinigameDefinition = Registry.minigames[game]
	var st := ClientMatchState.new()
	var ids: Array[int] = []
	var n: int = clampi(maxi(def.min_players, 5), 2, NAMES.size())
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = def.logic_script.new() as MinigameLogicBase
	logic.setup(ids, SeededRng.new(5), BalanceConfig.new(), def.params, {"bank": Registry.quiz_bank, "used": {}, "stats": {}})
	stage = def.stage_script.new()
	if &"send_intent" in stage:
		stage.set(&"send_intent", func(i: Dictionary) -> Dictionary: return logic.submit(1, i, now))
	add_child(stage)
	stage.call(&"begin", st, 1, {"minigame": game, "players": ids}, {})
	if stage.has_method(&"on_event"):
		stage.call(&"on_event", {"type": &"minigame_go"})
	for p: int in ids:
		_next_act[p] = _rng.randf_range(0.4, 2.0)
	while now < skip:
		_step_table(0.1)


func _step_table(delta: float) -> void:
	now += delta
	logic.tick(delta, now)
	for p: int in _next_act:
		if now < float(_next_act[p]):
			continue
		var options: Array[Dictionary] = _intents(p)
		var ok: bool = false
		if not options.is_empty():
			var intent: Dictionary = options[_rng.randi() % options.size()]
			ok = bool(logic.submit(p, intent, now).get("ok", false))
			if ok and p == 1 and game == &"lonely_number":
				stage.set(&"my_pick", int(intent["number"]))  # light "your" number on the board
		var pace: float = 2.0 if game == &"lonely_number" else 1.0  # its board is the show
		_next_act[p] = now + (_rng.randf_range(0.8, 2.6) * pace if ok else 0.3)
	for ev: Dictionary in logic.drain_events():
		stage.call(&"on_event", ev)
	if stage.has_method(&"on_private"):
		stage.call(&"on_private", {"minigame": logic.private_state(1)})


## Intents a seat might send right now (most get rejected outside their window; that's fine).
func _intents(p: int) -> Array[Dictionary]:
	var others: Array[int] = []
	for q: int in _next_act:
		if q != p:
			others.append(q)
	var out: Array[Dictionary] = []
	match game:
		&"quiz":
			for q: int in 3:
				out.append({"question": q, "index": _rng.randi() % 4})
		&"lonely_number":
			out.append({"number": _rng.randi_range(1, 20)})
		&"bust_or_bank":
			out.append({"action": "hit" if _rng.randf() < 0.55 else "stand"})
		&"find_the_lady":
			out.append({"slot": _rng.randi() % 4})
		&"roulette_royale":
			out.append({"question": int(logic.get(&"spin")), "index": _rng.randi() % 3})
		&"split_or_steal":
			out.append({"choice": "SPLIT" if _rng.randf() < 0.5 else "STEAL"})
		&"vote_race":
			out.append({"target": others[_rng.randi() % others.size()]})
		&"forehead_poker":
			out.append({"round": int(logic.get(&"round_index")), "action": "stay" if _rng.randf() < 0.6 else "fold"})
		&"spy":
			out.append({"type": &"spy_clue", "text": CLUE_WORDS[_rng.randi() % CLUE_WORDS.size()]})
			out.append({"type": &"spy_vote", "target": others[_rng.randi() % others.size()]})
	return out


func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Palette.CASINO_BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.85, 0.65)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_bloom = 0.1
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.25
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)


# --- Walkable games: the dev shot, brought to life ---------------------------------------------

func _collect_beans() -> void:
	var radius: float = float(WANDER.get(game, 0.8))
	for v: Node in find_children("*", "AvatarVisuals", true, false):
		var b := v as AvatarVisuals
		if absf(b.rotation.z) > 0.3 or b.knocked_out or b.sitting:
			continue  # lying down or seated: leave the pose alone
		# One lap per clip (either way round) so the loop joins up.
		_beans.append([b, b.position, _rng.randf() * TAU, TAU / seconds * (1.0 if _rng.randf() < 0.5 else -1.0), radius])
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		_cam_base = _cam.global_transform
		_cam_pivot = _cam.global_position - _cam.global_basis.z * 8.0


func _step_walk(delta: float) -> void:
	for entry: Array in _beans:
		var b: AvatarVisuals = entry[0]
		var base: Vector3 = entry[1]
		var ph: float = entry[2] + (_t - warmup) * float(entry[3])
		var r: float = entry[4]
		var pos: Vector3 = base + Vector3(cos(ph) * r, 0.0, sin(ph) * r * 0.7)
		var vel: Vector3 = (pos - b.position) / maxf(delta, 0.001)
		b.position = pos
		if vel.length() > 0.05:
			b.look_at(b.global_position + vel.normalized(), Vector3.UP, true)
		b.update_motion(vel, true, delta)
		if game in SWINGERS and fmod(_t - warmup + float(entry[2]), seconds * 0.5) < delta:
			b.swing()
	if _cam != null:
		# A slow side drift round the scene and back, so the loop joins up.
		var a: float = sin((_t - warmup) / seconds * TAU) * deg_to_rad(5.0)
		var off: Vector3 = (_cam_base.origin - _cam_pivot).rotated(Vector3.UP, a)
		_cam.global_transform = Transform3D(_cam_base.basis.rotated(Vector3.UP, a), _cam_pivot + off)


# --- Recording ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if walkable:
		_step_walk(delta)
	elif logic != null:
		_step_table(delta)
	if _t < warmup:
		return
	_tick += 1
	if (_tick - 1) % every != 0:
		return
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(FRAME.x, FRAME.y, Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/f%03d.png" % [out_dir, _frame])
	_frame += 1
	if _frame >= int(round(seconds / (delta * every))):
		get_tree().quit()
