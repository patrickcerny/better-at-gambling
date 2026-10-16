class_name FunRoom
extends RefCounted
## The waiting room's play-money games (Patrick: "a blackjack table just for fun. It doesn't
## add money or anything, it's just to play when you're bored"). Server side, while an online room
## waits in LOBBY: the same station logic as the casino (blackjack, slots) on its own `Economy`,
## its own empty `ModifierStack` (no luck, no items) and no progressive jackpot. Nothing here ever
## touches the real ledger, so the real balance, the leaderboard, stats, House Comps, items and the
## Hot Table never see it. Every event it produces is tagged `fun: true`.
##
## Everyone who walks in gets PLAY_CHIPS fresh (every visit). The match server shuts it when the
## match starts (`close`): everyone stands up and the room is locked until the next lobby.

## Station ids of the waiting room start with this.
const PREFIX: String = "fun_"
## Play chips on every visit.
const PLAY_CHIPS: int = 1000
## Ledger reason for the chips handed out on the way in.
const REASON_CHIPS: StringName = &"play_chips"

var economy: Economy = Economy.new()
var stations: StationManager = StationManager.new()
var area: AABB
## False once the match started: no seats, no bets, nobody inside.
var open: bool = true

## Player → true while inside the room (a step back in counts as a new visit).
var _inside: Dictionary[int, bool] = {}


## `games`: station id → game id (`MapDefinition.fun_stations`).
func _init(games: Dictionary, logic_scripts: Dictionary, balance: BalanceConfig, rng: SeededRng, p_area: AABB) -> void:
	area = p_area
	stations.setup(games, logic_scripts, balance, economy, ModifierStack.new(balance.luck_clamp), rng, null)
	stations.set_limits_multiplier(balance.limits_multiplier(0))


## True for a waiting-room station id.
static func is_fun(station_id: Variant) -> bool:
	return str(station_id).begins_with(PREFIX)


## True when `pos` (feet) is in the room.
func contains(pos: Vector3) -> bool:
	return area.has_point(pos)


## Play balance (0 for someone who never came in).
func balance(player: int) -> int:
	return economy.balance(player)


## Hands the player a fresh stack of play chips (PLAY_CHIPS), whatever they had.
func reset_chips(player: int) -> void:
	if not economy.has_player(player):
		economy.add_player(player, 0)
	economy.apply(player, PLAY_CHIPS - economy.balance(player), REASON_CHIPS)


## Called with each player's position while the room is open. Walking in starts a new visit with
## fresh chips (not while a spin or hand of theirs is still open). Returns true on a new visit.
func update_presence(player: int, pos: Vector3) -> bool:
	var now: bool = open and contains(pos)
	var was: bool = _inside.get(player, false)
	if now == was:
		return false
	if not now:
		_inside.erase(player)
		return false
	if stations.is_seated(player) or stations.has_stake(player):
		return false  # still settling: the chips are reset on the next visit
	_inside[player] = true
	reset_chips(player)
	return true


## Seats a player at a play-money station (chips first if they have none yet).
func sit(player: int, station_id: StringName) -> Dictionary:
	if not open:
		return StationLogicBase.fail(&"room_closed")
	if not economy.has_player(player):
		reset_chips(player)
	return stations.sit(player, station_id)


## Routes place_bet / clear_bets / action for a waiting-room station.
func route(player: int, intent: Dictionary) -> Dictionary:
	if not open:
		return StationLogicBase.fail(&"room_closed")
	return stations.route(player, intent)


func tick(delta: float) -> void:
	if open:
		stations.tick(delta)


## Shuts the room for the match: every open round settles on play money and the room locks.
## Returns who was seated (the server stands them up).
func close() -> Array[int]:
	var seated: Array[int] = []
	for p: int in stations.seat_of.keys():
		if stations.is_seated(p):
			seated.append(p)
	stations.auto_resolve_all()
	open = false
	_inside.clear()
	return seated


## A lobby participant left for good.
func remove_player(player: int) -> void:
	if stations.is_seated(player):
		stations.leave(player)
	_inside.erase(player)
	economy.remove_player(player)


## Collects station and money events, each tagged `fun: true`.
func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = stations.drain_events()
	out.append_array(economy.drain_events())
	for ev: Dictionary in out:
		ev["fun"] = true
	return out


## Public state of the stations (each tagged `fun: true`) for the snapshot.
func public_states() -> Dictionary:
	var out: Dictionary = stations.public_states()
	for sid: Variant in out:
		out[sid]["fun"] = true
	return out


func balances() -> Dictionary:
	var out: Dictionary = {}
	var b: Dictionary[int, int] = economy.balances()
	for p: int in b:
		out[p] = b[p]
	return out


func to_wire() -> Dictionary:
	return {"open": open, "balances": balances(), "chips": PLAY_CHIPS}
