extends Node
## `Log` autoload: tagged logging with levels. Use instead of bare `print`.
##
## `Log.info(&"net", "connected")` prints `[INFO][net] connected`. Errors also go
## through `push_error` so test scripts that grep for `ERROR` catch them.

enum Level { DEBUG, INFO, WARN, ERROR }

## Messages below this level are dropped.
var min_level: Level = Level.INFO
## Number of `error()` calls since start; smoke tests assert this stays 0.
var error_count: int = 0
## Number of `warn()` calls since start.
var warn_count: int = 0


func _ready() -> void:
	if OS.is_debug_build() and OS.get_environment("BAG_LOG_DEBUG") == "1":
		min_level = Level.DEBUG


## Verbose diagnostics, hidden by default.
func debug(tag: StringName, msg: String) -> void:
	_emit(Level.DEBUG, tag, msg)


## Normal operational messages.
func info(tag: StringName, msg: String) -> void:
	_emit(Level.INFO, tag, msg)


## Something unexpected that the game recovered from.
func warn(tag: StringName, msg: String) -> void:
	warn_count += 1
	_emit(Level.WARN, tag, msg)


## A bug or failed operation.
func error(tag: StringName, msg: String) -> void:
	error_count += 1
	_emit(Level.ERROR, tag, msg)


func _emit(level: Level, tag: StringName, msg: String) -> void:
	if level < min_level:
		return
	var line: String = "[%s][%s] %s" % [Level.keys()[level], tag, msg]
	match level:
		Level.ERROR:
			push_error(line)
		Level.WARN:
			push_warning(line)
		_:
			print(line)
