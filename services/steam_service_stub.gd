extends Node
## `SteamSvc` autoload (stub). Real GodotSteam-backed implementation arrives in M8.
##
## The autoload is named `SteamSvc`, not `Steam`, because GodotSteam registers an
## engine singleton called `Steam` (see docs/DECISIONS.md).


## True when a Steam client is running and the API initialised.
func is_available() -> bool:
	return false


## Steam persona name, or the OS user name as a stand-in.
func get_persona_name() -> String:
	var user: String = OS.get_environment("USER")
	return user if not user.is_empty() else "Player"
