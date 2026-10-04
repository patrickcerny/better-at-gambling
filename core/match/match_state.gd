class_name MatchState
extends RefCounted
## Authoritative match state owned by the MatchServer. `to_wire` is the snapshot sent on join and
## reconnect; it never includes secrets (RNG state, shoe order, quiz answers).

var match_seed: int = 0
var phase: Phase.Id = Phase.Id.LOBBY
var duration_minutes: int = 10
var casino_time: float = 0.0
var segment_index: int = 0
var players: Dictionary[int, PlayerState] = {}
var balances: Dictionary[int, int] = {}
var jackpot: int = 0
var event_seq: int = 0
## Public station states by station id.
var stations: Dictionary = {}


## Adds or replaces a player.
func add_player(p: PlayerState) -> void:
	players[p.id] = p


## Snapshot dictionary.
func to_wire() -> Dictionary:
	var ps: Dictionary = {}
	for id: int in players:
		ps[id] = players[id].to_wire()
	var bs: Dictionary = {}
	for id: int in balances:
		bs[id] = balances[id]
	return {
		"phase": phase, "duration": duration_minutes, "casino_time": snappedf(casino_time, 0.001),
		"segment": segment_index, "players": ps, "balances": bs, "jackpot": jackpot, "seq": event_seq,
		"stations": stations.duplicate(true),
	}


## Rebuilds from a snapshot dictionary.
static func from_wire(d: Dictionary) -> MatchState:
	var s := MatchState.new()
	s.phase = int(d.get("phase", 0)) as Phase.Id
	s.duration_minutes = int(d.get("duration", 10))
	s.casino_time = float(d.get("casino_time", 0.0))
	s.segment_index = int(d.get("segment", 0))
	var ps: Dictionary = d.get("players", {})
	for id: Variant in ps:
		s.players[int(id)] = PlayerState.from_wire(ps[id])
	var bs: Dictionary = d.get("balances", {})
	for id: Variant in bs:
		s.balances[int(id)] = int(bs[id])
	s.jackpot = int(d.get("jackpot", 0))
	s.event_seq = int(d.get("seq", 0))
	s.stations = (d.get("stations", {}) as Dictionary).duplicate(true)
	return s
