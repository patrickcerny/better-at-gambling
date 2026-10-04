class_name WorldQuery
extends RefCounted
## Server-side view of where everyone is. Positions arrive through `move` intents (client-authoritative
## while standing) or are set by the server while a player is ragdolled/held. Line of sight comes
## from the world scene when one is attached (`los_callback`), else is assumed clear.

var positions: Dictionary[int, Vector3] = {}
var yaws: Dictionary[int, float] = {}
var airborne: Dictionary[int, bool] = {}
## Callable(from: Vector3, to: Vector3) -> bool, set by the world scene.
var los_callback: Callable


## Records a player's reported transform.
func set_transform(player: int, pos: Vector3, yaw: float, is_airborne: bool = false) -> void:
	positions[player] = pos
	yaws[player] = yaw
	airborne[player] = is_airborne


func get_position(player: int) -> Vector3:
	return positions.get(player, Vector3.ZERO)


func get_yaw(player: int) -> float:
	return yaws.get(player, 0.0)


## Unit vector the player faces (horizontal).
func get_facing(player: int) -> Vector3:
	var yaw: float = get_yaw(player)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func is_airborne(player: int) -> bool:
	return airborne.get(player, false)


## Horizontal distance between two players.
func distance(a: int, b: int) -> float:
	var d: Vector3 = get_position(a) - get_position(b)
	d.y = 0.0
	return d.length()


## True if nothing blocks the line between two points.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if los_callback.is_valid():
		return bool(los_callback.call(from, to))
	return true
