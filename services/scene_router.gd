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


func _ready() -> void:
	cmdline = Cmdline.from_os()
	if cmdline.has_flag("smoke-test"):
		_smoke_frames_left = maxi(cmdline.get_int("frames", 60), 1)
		if cmdline.has("seconds"):
			# Game-time budget instead of frames (headless frame rates vary wildly).
			_smoke_seconds_left = cmdline.get_float("seconds", 60.0)
			_smoke_frames_left = 1 << 30
		Log.info(&"boot", "smoke test: running %d frames / %.0f s" % [_smoke_frames_left, _smoke_seconds_left])
	if cmdline.has_flag("practice") or cmdline.has_flag("autoplay"):
		# Straight into a Practice match (dev/CI shortcut; the menu's Practice button does the same).
		goto.call_deferred(MATCH)


func _process(delta: float) -> void:
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


## Replaces the current scene, logging failures.
func goto(path: String) -> void:
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		Log.error(&"router", "could not change scene to %s (error %d)" % [path, err])
