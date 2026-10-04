class_name Cmdline
extends RefCounted
## Parses user command-line arguments (everything after `--` on the Godot command line).
##
## Supports `--flag`, `--key value` and `--key=value`. Pure logic: pass the argument
## array in (normally `OS.get_cmdline_user_args()`), no engine state is touched.

## Flags that never take a value, so `--server --port 1` does not read `--port` as a value.
const BOOL_FLAGS: Array[String] = [
	"server", "autostart", "autoplay", "smoke-test", "skip-intro", "minigame-now",
	"practice", "compat",
]

var _values: Dictionary[String, String] = {}
var _flags: Dictionary[String, bool] = {}
var _positional: Array[String] = []


## Builds a parser from a raw argument list.
static func parse(args: PackedStringArray) -> Cmdline:
	var c := Cmdline.new()
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if not arg.begins_with("--"):
			c._positional.append(arg)
			i += 1
			continue
		var body: String = arg.substr(2)
		var eq: int = body.find("=")
		if eq >= 0:
			c._values[body.substr(0, eq)] = body.substr(eq + 1)
		elif body in BOOL_FLAGS or i + 1 >= args.size() or args[i + 1].begins_with("--"):
			c._flags[body] = true
		else:
			c._values[body] = args[i + 1]
			i += 1
		i += 1
	return c


## Builds a parser from the current process' user arguments.
static func from_os() -> Cmdline:
	return parse(OS.get_cmdline_user_args())


## True if `--name` was given as a flag, or with a truthy value.
func has_flag(name: String) -> bool:
	if _flags.has(name):
		return true
	return _values.get(name, "").to_lower() in ["1", "true", "yes", "on"]


## True if `--name` was given in any form.
func has(name: String) -> bool:
	return _flags.has(name) or _values.has(name)


## String value of `--name`, or `default` when absent.
func get_string(name: String, default: String = "") -> String:
	return _values.get(name, default)


## Integer value of `--name`, or `default` when absent or not an integer.
func get_int(name: String, default: int = 0) -> int:
	var v: String = _values.get(name, "")
	return v.to_int() if v.is_valid_int() else default


## Float value of `--name`, or `default` when absent or not a number.
func get_float(name: String, default: float = 0.0) -> float:
	var v: String = _values.get(name, "")
	return v.to_float() if v.is_valid_float() else default


## Arguments that were not `--` options.
func positional() -> Array[String]:
	return _positional.duplicate()
