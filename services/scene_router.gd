extends Node
## `SceneRouter` autoload: boot-time routing and scene changes.
##
## Reads the command line once at startup. `--smoke-test [--frames N]` lets the
## main scene run N frames (default 60) and then quits, exiting 1 if anything was
## logged through `Log.error`.

const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"
const MATCH: String = "res://match/match_scene.tscn"

## Parsed user arguments for this process.
var cmdline: Cmdline

var _smoke_frames_left: int = -1
var _smoke_seconds_left: float = -1.0
var _capture_clock: float = 0.0
var _captured: bool = false


func _ready() -> void:
	cmdline = Cmdline.from_os()
	if cmdline.has_flag("smoke-test"):
		_smoke_frames_left = maxi(cmdline.get_int("frames", 60), 1)
		if cmdline.has("seconds"):
			# Game-time budget instead of frames (headless frame rates vary wildly).
			_smoke_seconds_left = cmdline.get_float("seconds", 60.0)
			_smoke_frames_left = 1 << 30
		Log.info(&"boot", "smoke test: running %d frames / %.0f s" % [_smoke_frames_left, _smoke_seconds_left])
	if cmdline.has_flag("server"):
		_boot_server.call_deferred()
	elif cmdline.has("connect") or cmdline.has("join-code") or cmdline.has_flag("create-room"):
		_boot_client.call_deferred()
	elif cmdline.has_flag("practice") or cmdline.has_flag("autoplay"):
		# Straight into a Practice match (dev/CI shortcut; the menu's Practice button does the same).
		goto.call_deferred(MATCH)


## Player-facing name: the saved profile name, or a fresh "Player####" (`--name` overrides).
func profile_name() -> String:
	if cmdline != null and cmdline.has("name"):
		return cmdline.get_string("name")
	var n: String = str(Settings.get_value("profile", "name", ""))
	if n == "":
		n = "Player%04d" % randi_range(1000, 9999)
		Settings.set_value("profile", "name", n)
		Settings.save()
	return n


## Saved look: {color, skin}.
func profile_cosmetics() -> Dictionary:
	return {
		"color": cmdline.get_int("color", int(Settings.get_value("profile", "color", -1))) if cmdline != null else -1,
		"skin": StringName(cmdline.get_string("skin", str(Settings.get_value("profile", "skin", "bean")))) if cmdline != null else &"bean",
	}


## Network test options from the command line ({latency_ms, loss, seed}).
func net_opts() -> Dictionary:
	var opts: Dictionary = {}
	if cmdline.has("net-latency"):
		opts["latency_ms"] = cmdline.get_float("net-latency", 0.0)
	if cmdline.has("net-loss"):
		opts["loss"] = cmdline.get_float("net-loss", 0.0)
	if cmdline.has("net-seed"):
		opts["seed"] = cmdline.get_int("net-seed", 0)
	return opts


## `--server --port P [--room-id --room-code --room-secret --orchestrator --empty-timeout]`:
## the headless dedicated room server.
func _boot_server() -> void:
	Engine.max_fps = 60
	var opts: Dictionary = net_opts()
	for key: String in ["orchestrator", "room-id", "room-code", "room-secret"]:
		if cmdline.has(key):
			opts[key.replace("-", "_")] = cmdline.get_string(key)
	if cmdline.has("empty-timeout"):
		opts["empty_timeout"] = cmdline.get_float("empty-timeout", 0.0)
	var port: int = cmdline.get_int("port", Protocol.DEFAULT_PORT)
	if Net.start_server(port, opts) != OK:
		get_tree().quit(3)
		return
	goto(MATCH)


## `--connect host:port` (direct, dev), `--join-code CODE` or `--create-room` (orchestrator).
func _boot_client() -> void:
	var display: String = profile_name()
	var err: Error = OK
	Net.connected.connect(_on_boot_connected, CONNECT_ONE_SHOT)
	Net.disconnected.connect(_on_boot_failed, CONNECT_ONE_SHOT)
	if cmdline.has("connect"):
		var parts: PackedStringArray = cmdline.get_string("connect").rsplit(":", true, 1)
		var host: String = parts[0] if parts[0] != "" else "127.0.0.1"
		var port: int = int(parts[1]) if parts.size() > 1 else Protocol.DEFAULT_PORT
		var hello: Dictionary = profile_cosmetics()
		hello["name"] = display
		if cmdline.has("uid"):
			hello["uid"] = cmdline.get_string("uid")
		if cmdline.has("build"):
			hello["build"] = cmdline.get_string("build")  # version-mismatch tests
		err = Net.join_server(host, port, hello, net_opts())
	else:
		var room: Dictionary
		if cmdline.has_flag("create-room"):
			room = await Net.online.create_party(display)
		else:
			room = await Net.online.join_party(display, cmdline.get_string("join-code"))
		if room.is_empty():
			_on_boot_failed(Net.online.last_error)
			return
		Log.info(&"boot", "room %s at %s:%d" % [room.get("room_code", ""), room.get("host", ""), int(room.get("port", 0))])
		err = Net.online.connect_room(room, display, profile_cosmetics(), net_opts())
	if err != OK:
		_on_boot_failed(Net.last_error)


func _on_boot_connected() -> void:
	if Net.disconnected.is_connected(_on_boot_failed):
		Net.disconnected.disconnect(_on_boot_failed)
	goto(MATCH)


func _on_boot_failed(reason: String) -> void:
	if Net.connected.is_connected(_on_boot_connected):
		Net.connected.disconnect(_on_boot_connected)
	Log.warn(&"boot", "could not join: %s" % reason)
	if quit_on_disconnect():
		get_tree().quit(4)
	else:
		goto(MAIN_MENU)


## Scripted/headless clients exit instead of falling back to the menu.
func quit_on_disconnect() -> bool:
	return cmdline.has_flag("autoplay") or cmdline.has_flag("quit-on-disconnect") or DisplayServer.get_name() == "headless"


func _process(delta: float) -> void:
	if cmdline.has("capture") and not _captured:
		# Dev/screenshots of real sessions: `--capture out.png --capture-at 8` (seconds since boot).
		_capture_clock += delta
		if _capture_clock >= cmdline.get_float("capture-at", 5.0):
			_captured = true
			var img: Image = get_viewport().get_texture().get_image()
			var err: Error = img.save_png(cmdline.get_string("capture")) if img != null else ERR_UNAVAILABLE
			Log.info(&"boot", "capture saved to %s (%d)" % [cmdline.get_string("capture"), err])
	if _smoke_frames_left < 0:
		return
	_smoke_frames_left -= 1
	if _smoke_seconds_left > 0.0:
		_smoke_seconds_left -= delta
		if _smoke_seconds_left <= 0.0:
			_smoke_frames_left = 0
	if _smoke_frames_left == 0:
		var code: int = 1 if Log.error_count > 0 else 0
		Log.info(&"boot", "smoke test finished, errors=%d, exit=%d" % [Log.error_count, code])
		get_tree().quit(code)


## Replaces the current scene, logging failures. Going into a match shows the loading screen
## first (the match scene takes it down when its world is built).
func goto(path: String) -> void:
	if path == MATCH and DisplayServer.get_name() != "headless" and not cmdline.has("capture"):
		Loading.begin()
		# Let the loading screen draw before the match scene blocks the main thread.
		await get_tree().process_frame
		await get_tree().process_frame
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		Log.error(&"router", "could not change scene to %s (error %d)" % [path, err])
