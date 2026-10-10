extends GutTest
## Patrick: "sometimes a lot of money is payed out at the same time (weird bug with like a lot of
## plus and minus, money count is fine but something happens)" and "when someone sits down, feed
## messages and money popups appear twice". Online, every `player_sat` resyncs the client mirror:
## it re-applies the cached snapshot and replays every event received since. Those events had
## already popped their money and feed lines; the replay must rebuild the state quietly.

var hud: Hud
var view: ClientMatchView
var snap: Dictionary
var backlog: Array[Dictionary] = []


func before_each() -> void:
	backlog.clear()
	snap = {
		"seq": 10, "phase": Phase.Id.CASINO,
		"players": {1: {"id": 1, "name": "Ann", "station": ""}, 2: {"id": 2, "name": "Bob", "station": ""}},
		"balances": {1: 1000, 2: 1000},
	}
	Net.stop()
	Net.mode = Net.Mode.CLIENT  # no transport: the cached snapshot and backlog are all there is
	Net._snapshot = snap
	view = ClientMatchView.new()
	add_child_autofree(view)
	hud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	add_child_autofree(hud)
	hud.bind(view.state, 1)
	Net.event_received.connect(_like_the_match_scene)
	await wait_process_frames(1)


func after_each() -> void:
	if Net.event_received.is_connected(_like_the_match_scene):
		Net.event_received.disconnect(_like_the_match_scene)
	Net._backlog.clear()
	Net.stop()


## `MatchScene._seat` resyncs the mirror whenever someone sits down.
func _like_the_match_scene(ev: Dictionary) -> void:
	if ev["type"] == &"player_sat":
		view.resync()


## Delivers an event the way `Net` does online: into the backlog, then to the listeners.
func _receive(type: StringName, fields: Dictionary) -> void:
	var ev: Dictionary = GameEvents.make(type, fields)
	ev["seq"] = int(snap["seq"]) + Net._backlog.size() + 1
	Net._backlog.append(ev)
	Net.event_received.emit(ev)


func _play_a_few_rounds() -> void:
	for i: int in 4:
		_receive(&"money_changed", {"player": 1, "amount": -25, "balance": 1000 - 25 * (i + 1) + 40 * i, "reason": &"bet_slots"})
		_receive(&"money_changed", {"player": 1, "amount": 40, "balance": 1000 - 25 * (i + 1) + 40 * (i + 1), "reason": &"win_slots"})
		_receive(&"round_result", {"station": &"slot_1", "player": 1, "stake": 25, "returned": 40, "net": 15, "details": {}})


func test_someone_sitting_down_does_not_replay_the_money_popups() -> void:
	_play_a_few_rounds()
	assert_eq(hud.pops.get_child_count(), 8, "one popup per money change")
	assert_eq(hud.feed.get_child_count(), 4, "one feed line per result")
	_receive(&"player_sat", {"player": 2, "station": &"roulette_1", "seat": 0})  # resyncs the mirror
	assert_eq(view.state.seat_of.get(2, &""), &"roulette_1", "the seat is known")
	assert_eq(view.state.balance(1), 1060, "the balance is right")
	assert_eq(hud.pops.get_child_count(), 8, "no burst of old plus and minus popups")
	assert_eq(hud.feed.get_child_count(), 4, "and no feed line twice")


func test_a_gap_resync_replays_quietly_and_new_events_still_show() -> void:
	_play_a_few_rounds()
	view.resync()
	view.resync()
	assert_eq(hud.pops.get_child_count(), 8)
	assert_eq(hud.feed.get_child_count(), 4)
	_receive(&"money_changed", {"player": 1, "amount": 100, "balance": 1160, "reason": &"win_roulette"})
	_receive(&"round_result", {"station": &"roulette_1", "player": 1, "stake": 100, "returned": 200, "net": 100, "details": {}})
	assert_eq(hud.pops.get_child_count(), 9, "a new win still pops")
	assert_eq(hud.feed.get_child_count(), 5, "and reaches the feed")
	assert_eq(view.state.balance(1), 1160)


func test_the_sit_down_feed_and_popup_show_once() -> void:
	_receive(&"player_sat", {"player": 1, "station": &"slot_1", "seat": 0})
	_receive(&"money_changed", {"player": 1, "amount": -50, "balance": 950, "reason": &"bet_slots"})
	_receive(&"player_sat", {"player": 2, "station": &"slot_2", "seat": 0})
	_receive(&"bets_refunded", {"station": &"slot_1", "player": 1, "amount": 50})
	_receive(&"money_changed", {"player": 1, "amount": 50, "balance": 1000, "reason": &"bet_refunded"})
	_receive(&"player_sat", {"player": 2, "station": &"slot_3", "seat": 0})
	assert_eq(hud.pops.get_child_count(), 2, "each money change pops once")
	assert_eq(hud.feed.get_child_count(), 1, "the refund line shows once")
