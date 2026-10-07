class_name DealerLogic
extends RefCounted
## Server side of the dealer NPC (v0.8.4): stands at a table and can be attacked.
## When a player shoves or bats a dealer, that player goes to jail, the current round is
## cancelled, and all bets at the table are refunded. The dealer's position is reported by
## the scene node (`Dealer`). All decisions come from the server.

## Shove/bat range detection
const ATTACK_RANGE: float = 2.2

var station_id: StringName
var players: Dictionary
var rules: InteractionRules
var world: WorldQuery
var rng: SeededRng
var stations: StationManager

## Where the dealer stands (Vector3.INF until a world reports one)
var position: Vector3 = Vector3.INF
var yaw: float = 0.0

var events: Array[Dictionary] = []


func _init(p_station_id: StringName, p_players: Dictionary, p_rules: InteractionRules,
		p_world: WorldQuery, p_rng: SeededRng, p_stations: StationManager) -> void:
	station_id = p_station_id
	players = p_players
	rules = p_rules
	world = p_world
	rng = p_rng
	stations = p_stations


## A player's shove: attacks the dealer if they are in range. Returns true if it did.
func shove(player: int, aim: Vector3, now: float) -> bool:
	if not position.is_finite() or not players.has(player) or not world.positions.has(player):
		return false

	var origin: Vector3 = world.get_position(player)
	var to: Vector3 = position - origin
	to.y = 0.0
	var dir: Vector3 = Vector3(aim.x, 0.0, aim.z)
	dir = dir.normalized() if dir.length() > 0.01 else world.get_facing(player)

	# Check if dealer is in range and in front of the player
	if to.length() > ATTACK_RANGE or absf(position.y - origin.y) > 1.2:
		return false
	if to.length() > 0.3 and dir.dot(to.normalized()) < 0.5:
		return false

	# Dealer attacked!
	_dealer_attacked(player, now, &"shove")
	return true


## Bat attack on the dealer (similar to shove but different cause)
func bat(player: int, aim: Vector3, now: float) -> bool:
	if not position.is_finite() or not players.has(player) or not world.positions.has(player):
		return false

	var origin: Vector3 = world.get_position(player)
	var to: Vector3 = position - origin
	to.y = 0.0
	var dir: Vector3 = Vector3(aim.x, 0.0, aim.z)
	dir = dir.normalized() if dir.length() > 0.01 else world.get_facing(player)

	# Check if dealer is in range and in front of the player
	if to.length() > ATTACK_RANGE or absf(position.y - origin.y) > 1.2:
		return false
	if to.length() > 0.3 and dir.dot(to.normalized()) < 0.5:
		return false

	# Dealer attacked!
	_dealer_attacked(player, now, &"bat")
	return true


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _dealer_attacked(attacker: int, now: float, cause: StringName) -> void:
	# Emit dealer_attacked event
	events.append(GameEvents.make(&"dealer_attacked", {
		"station": station_id,
		"player": attacker,
		"cause": cause
	}))

	# Call station to cancel hand and refund all bets
	var logic: StationLogicBase = stations.get_logic(station_id)
	if logic != null:
		logic.refund_all()
		events.append_array(logic.drain_events())
