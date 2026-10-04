class_name ClientMatchView
extends Node
## Feeds `Net` events into a ClientMatchState mirror and refreshes station states from
## snapshots when a sequence gap is detected (§4.1).

var state: ClientMatchState = ClientMatchState.new()
## Seconds between station-state refreshes (station public state isn't event-replicated yet).
var station_refresh_interval: float = 0.25

var _since_refresh: float = 0.0


func _ready() -> void:
	Net.event_received.connect(_on_event)
	resync()


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)


## Pulls a full snapshot.
func resync() -> void:
	var snap: Dictionary = Net.request_snapshot()
	if not snap.is_empty():
		state.apply_snapshot(snap)


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= station_refresh_interval:
		_since_refresh = 0.0
		var snap: Dictionary = Net.request_snapshot()
		if snap.is_empty():
			return
		state.time_left = float(snap.get("time_left", state.time_left))
		state.next_minigame_in = float(snap.get("next_minigame_in", -1.0))
		state.casino_time = float(snap.get("casino_time", state.casino_time))
		state.jackpot = int(snap.get("jackpot", state.jackpot))
		var st: Dictionary = snap.get("stations", {})
		for sid: Variant in st:
			state.stations[sid] = st[sid]
			state.station_changed.emit(StringName(sid))
		# Positions of the other players (full replication arrives in M3; this keeps bots in place).
		var players: Dictionary = snap.get("players", {})
		for id: Variant in players:
			if state.players.has(int(id)):
				state.players[int(id)]["pos"] = players[id].get("pos", state.players[int(id)].get("pos", [0, 0, 0]))


func _on_event(ev: Dictionary) -> void:
	if not state.apply_event(ev):
		Log.warn(&"client", "event gap at seq %d, resyncing" % int(ev.get("seq", -1)))
		resync()
