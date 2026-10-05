class_name ClientMatchState
extends RefCounted
## Client-side mirror of the replicated match state, rebuilt from snapshots and events. UI reads
## this, never the server.

signal money_changed(player: int, amount: int, balance: int, reason: StringName)
signal phase_changed(phase: Phase.Id)
signal station_changed(station_id: StringName)
signal players_changed
signal feed_message(text: String, kind: StringName)
## Lobby data changed (leader, settings, countdown, ready, cosmetics).
signal lobby_changed

var phase: Phase.Id = Phase.Id.LOBBY
var casino_time: float = 0.0
var time_left: float = 0.0
var next_minigame_in: float = -1.0
var segment_index: int = 0
var last_call: bool = false
var duration_minutes: int = 10
var players: Dictionary[int, Dictionary] = {}
var balances: Dictionary[int, int] = {}
var stations: Dictionary = {}
var jackpot: int = 0
var last_seq: int = 0
var piles: Dictionary[int, Dictionary] = {}
var standings: Array = []
## Seated station of each player.
var seat_of: Dictionary[int, StringName] = {}
## Online lobby: party leader, host settings, start countdown (-1 = none), room or Practice.
var leader: int = -1
var lobby_settings: Dictionary = {}
var countdown: float = -1.0
var room_mode: bool = false


## Replaces everything from a snapshot.
func apply_snapshot(snap: Dictionary) -> void:
	phase = int(snap.get("phase", 0)) as Phase.Id
	casino_time = float(snap.get("casino_time", 0.0))
	time_left = float(snap.get("time_left", 0.0))
	next_minigame_in = float(snap.get("next_minigame_in", -1.0))
	segment_index = int(snap.get("segment", 0))
	last_call = bool(snap.get("last_call", false))
	duration_minutes = int(snap.get("duration", 10))
	players.clear()
	seat_of.clear()
	for id: Variant in snap.get("players", {}):
		players[int(id)] = snap["players"][id]
		seat_of[int(id)] = StringName(snap["players"][id].get("station", ""))
	balances.clear()
	for id: Variant in snap.get("balances", {}):
		balances[int(id)] = int(snap["balances"][id])
	stations = (snap.get("stations", {}) as Dictionary).duplicate(true)
	jackpot = int(snap.get("jackpot", 0))
	last_seq = int(snap.get("seq", 0))
	piles.clear()
	for p: Dictionary in snap.get("piles", []):
		piles[int(p["pile"])] = p
	var lobby: Dictionary = snap.get("lobby", {})
	leader = int(lobby.get("leader", -1))
	lobby_settings = lobby.get("settings", {})
	countdown = float(lobby.get("countdown", -1.0))
	room_mode = bool(snap.get("room", false))
	players_changed.emit()
	lobby_changed.emit()
	phase_changed.emit(phase)
	for sid: Variant in stations:
		station_changed.emit(StringName(sid))


## Applies one event. Returns false if a sequence gap was detected (caller should resnapshot).
func apply_event(ev: Dictionary) -> bool:
	if ev.has("seq") and int(ev["seq"]) <= last_seq:
		return true  # already in the snapshot we applied
	var seq: int = int(ev.get("seq", last_seq))
	var gap: bool = seq > last_seq + 1 and last_seq > 0
	last_seq = maxi(last_seq, seq)
	var type: StringName = ev["type"]
	match type:
		&"player_joined":
			var p: Dictionary = ev["player"]
			players[int(p["id"])] = p
			players_changed.emit()
		&"phase_changed":
			phase = int(ev["phase"]) as Phase.Id
			casino_time = float(ev.get("casino_time", casino_time))
			segment_index = int(ev.get("segment", segment_index))
			phase_changed.emit(phase)
		&"last_call":
			last_call = true
			feed_message.emit("LAST CALL! All winnings ×%.1f" % float(ev["multiplier"]), &"last_call")
		&"money_changed":
			balances[int(ev["player"])] = int(ev["balance"])
			money_changed.emit(int(ev["player"]), int(ev["amount"]), int(ev["balance"]), StringName(ev["reason"]))
		&"player_sat":
			seat_of[int(ev["player"])] = StringName(ev["station"])
			players_changed.emit()
		&"player_stood":
			seat_of[int(ev["player"])] = &""
			players_changed.emit()
		&"round_result":
			var net: int = int(ev["net"])
			if net != 0:
				feed_message.emit("%s %s$%d at %s" % [player_name(int(ev["player"])), "+" if net > 0 else "−", absi(net), ev["station"]], &"win" if net > 0 else &"loss")
		&"jackpot_won":
			feed_message.emit("%s hit the JACKPOT for $%d!" % [player_name(int(ev["player"])), int(ev["amount"])], &"jackpot")
		&"jackpot_changed":
			jackpot = int(ev["amount"])
		&"chips_dropped":
			piles[int(ev["pile"])] = ev
		&"chips_collected", &"pickup_expired":
			piles.erase(int(ev["pile"]))
		&"player_knocked_out":
			feed_message.emit("%s got knocked out!" % player_name(int(ev["target"])), &"chaos")
		&"chips_shaken_out":
			feed_message.emit("%s shook $%d out of %s" % [player_name(int(ev["attacker"])), int(ev["amount"]), player_name(int(ev["target"]))], &"chaos")
		&"player_thrown_out":
			feed_message.emit("Security threw %s out!" % player_name(int(ev["target"])), &"chaos")
		&"player_ready":
			if players.has(int(ev["player"])):
				players[int(ev["player"])]["ready"] = bool(ev["ready"])
			lobby_changed.emit()
		&"player_cosmetics":
			if players.has(int(ev["player"])):
				players[int(ev["player"])]["color"] = int(ev["color"])
				players[int(ev["player"])]["hat"] = StringName(ev["hat"])
			players_changed.emit()
			lobby_changed.emit()
		&"leader_changed":
			leader = int(ev["player"])
			lobby_changed.emit()
		&"lobby_settings":
			lobby_settings = ev["settings"]
			lobby_changed.emit()
		&"lobby_countdown":
			countdown = float(ev["seconds"])
			lobby_changed.emit()
		&"lobby_countdown_cancelled":
			countdown = -1.0
			lobby_changed.emit()
		&"player_left", &"player_rejoined":
			if players.has(int(ev["player"])):
				players[int(ev["player"])]["connected"] = ev["type"] == &"player_rejoined"
				if ev["type"] == &"player_left":
					players[int(ev["player"])]["ready"] = false
			feed_message.emit("%s %s" % [player_name(int(ev["player"])), "lost connection" if ev["type"] == &"player_left" else "is back"], &"info")
			players_changed.emit()
			lobby_changed.emit()
		&"player_removed":
			players.erase(int(ev["player"]))
			balances.erase(int(ev["player"]))
			players_changed.emit()
			lobby_changed.emit()
		&"match_started":
			duration_minutes = int(ev["duration"])
			countdown = -1.0
		&"match_ended":
			standings = ev["standings"]
			phase = Phase.Id.RESULTS
			phase_changed.emit(phase)
	if ev.has("station") and stations.has(ev["station"]):
		station_changed.emit(StringName(ev["station"]))
	return not gap


## Display name of a player.
func player_name(id: int) -> String:
	return str(players.get(id, {}).get("name", "Player %d" % id))


## Balance of a player.
func balance(id: int) -> int:
	return balances.get(id, 0)


## Rank (1-based) of a player by money.
func rank_of(id: int) -> int:
	var mine: int = balance(id)
	var rank: int = 1
	for other: int in balances:
		if other != id and balances[other] > mine:
			rank += 1
	return rank
