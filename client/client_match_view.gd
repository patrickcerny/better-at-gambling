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
	Net.snapshot_received.connect(_on_snapshot)
	resync()


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)
	if Net.snapshot_received.is_connected(_on_snapshot):
		Net.snapshot_received.disconnect(_on_snapshot)


func _on_snapshot(snap: Dictionary) -> void:
	state.apply_snapshot(snap)


## Pulls a full snapshot.
func resync() -> void:
	var snap: Dictionary = Net.request_snapshot()
	if not snap.is_empty():
		state.apply_snapshot(snap)
		for ev: Dictionary in Net.events_since_snapshot():
			state.apply_event(ev)


func _process(delta: float) -> void:
	if state.hot_station != &"" and (state.phase == Phase.Id.CASINO or state.phase == Phase.Id.PRE_MINIGAME):
		state.hot_left = maxf(state.hot_left - delta, 0.0)
	if state.results_return_in > 0.0:
		state.results_return_in = maxf(state.results_return_in - delta, 0.0)
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
		var offers: Array = (snap.get("shop", {}) as Dictionary).get("offers", [])
		if offers != state.shop_offers:
			state.shop_offers = offers.duplicate(true)
			state.shop_changed.emit()
		var st: Dictionary = snap.get("stations", {})
		for sid: Variant in st:
			state.stations[sid] = st[sid]
			state.station_changed.emit(StringName(sid))
		# Positions of bots simulated in-process (online, positions come from the world stream).
		if Net.is_client():
			return
		var players: Dictionary = snap.get("players", {})
		for id: Variant in players:
			if state.players.has(int(id)):
				state.players[int(id)]["pos"] = players[id].get("pos", state.players[int(id)].get("pos", [0, 0, 0]))


func _on_event(ev: Dictionary) -> void:
	var ok: bool = state.apply_event(ev)
	if ev["type"] == &"match_reset":
		# Money, inventories and stations were rebuilt without events: start from a fresh snapshot.
		if Net.is_client():
			Net.request_fresh_snapshot()
		else:
			resync()
		return
	if not ok:
		Log.warn(&"client", "event gap at seq %d, resyncing" % int(ev.get("seq", -1)))
		if Net.is_client():
			Net.request_fresh_snapshot()
		else:
			resync()
