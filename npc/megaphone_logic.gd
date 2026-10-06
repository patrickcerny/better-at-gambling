class_name MegaphoneLogic
extends RefCounted
## Server side of the Megaphone prop (M7): a megaphone on a stand by the bar. A player standing
## next to it presses E (`megaphone` intent) and for `SECONDS` their voice reaches everyone at
## full volume (the voice relay asks `is_holder`). Then it goes back on the stand for a short
## cooldown. One holder at a time; money and rules are untouched.

## Where the stand is (in front of the bar, between the stools and the floor, see `CasinoFloor`).
const STAND_POS: Vector3 = Vector3(16.0, 0.0, 2.5)
const RANGE: float = 2.2
const SECONDS: float = 10.0
const COOLDOWN: float = 4.0

var players: Dictionary
var rules: InteractionRules
var world: WorldQuery

## Player holding it (-1: on the stand) and until when.
var holder: int = -1
var until: float = -INF
var available_at: float = 0.0

var events: Array[Dictionary] = []
var _now: float = 0.0


func _init(p_players: Dictionary, p_rules: InteractionRules, p_world: WorldQuery) -> void:
	players = p_players
	rules = p_rules
	world = p_world


## True while `player` holds the megaphone (their voice is global).
func is_holder(player: int) -> bool:
	return holder >= 0 and player == holder


## A player picks it up. Returns {ok, error}.
func take(player: int, now: float) -> Dictionary:
	if not players.has(player):
		return StationLogicBase.fail(&"unknown_player")
	if holder >= 0:
		return StationLogicBase.fail(&"megaphone_taken")
	if now < available_at:
		return StationLogicBase.fail(&"megaphone_cooldown")
	var st: InteractionRules.Status = rules.status(player)
	if st.seated or st.away or rules.is_knocked_down(player, now):
		return StationLogicBase.fail(&"not_standing")
	var d: Vector3 = world.get_position(player) - STAND_POS
	if Vector2(d.x, d.z).length() > RANGE or absf(d.y) > 1.5:
		return StationLogicBase.fail(&"too_far")
	holder = player
	until = now + SECONDS
	events.append(GameEvents.make(&"megaphone_taken", {"player": player, "seconds": SECONDS}))
	return StationLogicBase.OK_RESULT


## Time's up (or the holder left, got knocked out or thrown out): back on the stand.
func tick(now: float) -> void:
	_now = now
	if holder < 0:
		return
	var gone: bool = not players.has(holder) or rules.status(holder).away
	if now >= until or gone:
		drop(now, &"gone" if gone and now < until else &"time")


func drop(now: float, reason: StringName) -> void:
	if holder < 0:
		return
	events.append(GameEvents.make(&"megaphone_dropped", {"player": holder, "reason": reason}))
	holder = -1
	until = -INF
	available_at = now + COOLDOWN


## For the join/reconnect snapshot.
func wire() -> Dictionary:
	return {"holder": holder, "left": snappedf(maxf(until - _now, 0.0), 0.1) if holder >= 0 else 0.0}


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out
