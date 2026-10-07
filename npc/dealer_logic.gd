class_name DealerLogic
extends RefCounted
## Server side of the dealer NPC (v0.8.4): stands at a table and can be attacked.
## When a player shoves or bats a dealer, that player goes to jail, the current round is
## cancelled, and all bets at the table are refunded. The dealer's position is reported by
## the scene node (`Dealer`). All decisions come from the server.

## Shove/bat range detection
const ATTACK_RANGE: float = 2.2

## Where the dealer stands relative to its table's origin, per game (the scene's `Dealer` node
## uses the same offsets).
const OFFSETS: Dictionary = {&"blackjack": Vector3(0.0, 0.5, -1.2), &"roulette": Vector3(-1.5, 0.5, 0.0)}

var station_id: StringName
var players: Dictionary
var rules: InteractionRules
var world: WorldQuery
var rng: SeededRng
var stations: StationManager
var map_def: MapDefinition
var offset: Vector3 = Vector3.ZERO

## Position reported by a scene node (host); Vector3.INF = derive it from the map.
var position: Vector3 = Vector3.INF
var yaw: float = 0.0

var events: Array[Dictionary] = []


func _init(p_station_id: StringName, p_players: Dictionary, p_rules: InteractionRules,
		p_world: WorldQuery, p_rng: SeededRng, p_stations: StationManager, p_map_def: MapDefinition, p_offset: Vector3) -> void:
	station_id = p_station_id
	players = p_players
	rules = p_rules
	world = p_world
	rng = p_rng
	stations = p_stations
	map_def = p_map_def
	offset = p_offset


## The dealer's spot: the scene's report when there is one, else the table's map position plus
## the game's offset, else Vector3.INF (unknown table position, e.g. a bare test fixture).
func where() -> Vector3:
	if position.is_finite():
		return position
	var spos: Variant = map_def.station_positions.get(station_id, null) if map_def != null else null
	return Vector3(spos) + offset if spos != null else Vector3.INF


## A player's shove: attacks the dealer if they are in range. Returns true if it did.
func shove(player: int, aim: Vector3, now: float) -> bool:
	if not _in_reach(player, aim):
		return false
	_dealer_attacked(player, now, &"shove")
	return true


## Bat attack on the dealer (same reach, different cause).
func bat(player: int, aim: Vector3, now: float) -> bool:
	if not _in_reach(player, aim):
		return false
	_dealer_attacked(player, now, &"bat")
	return true


## True if the dealer is within ATTACK_RANGE and in front of the player's swing.
func _in_reach(player: int, aim: Vector3) -> bool:
	var at: Vector3 = where()
	if not at.is_finite() or not players.has(player) or not world.positions.has(player):
		return false
	var origin: Vector3 = world.get_position(player)
	var to: Vector3 = at - origin
	to.y = 0.0
	var dir: Vector3 = Vector3(aim.x, 0.0, aim.z)
	dir = dir.normalized() if dir.length() > 0.01 else world.get_facing(player)
	if to.length() > ATTACK_RANGE or absf(at.y - origin.y) > 1.2:
		return false
	if to.length() > 0.3 and dir.dot(to.normalized()) < 0.5:
		return false
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
	var logic: StationLogicBase = stations.logics.get(station_id)
	if logic != null:
		logic.refund_all()
		events.append_array(logic.drain_events())
