class_name TableFx
extends Node
## Client-side presentation of the casino tables, driven by the server's events (presentation
## only, it never touches money or rules):
## - chips slide from a seat onto the felt when a bet is placed (roulette on its layout spot,
##   blackjack in front of the seat), then to the winner (with the house's chips) or to the house;
## - the roulette ball circles and drops into the server's number; slot reels stop one by one;
## - win / lose / jackpot feedback over the player once the table has shown the result: floating
##   "+$120" / "-$50", coins or a sad puff, and for the local player's big wins and jackpots a gold
##   burst with screen shake and hit-stop.
## `MatchScene` creates one (never on a dedicated server) and forwards every event.

## Seconds until a blackjack result reads (cards flip first) and the Plinko chip's fall.
const BLACKJACK_DELAY: float = 0.35
const PLINKO_DELAY: float = 1.6
## Bets older than this are swept off the felt when a new round starts (stale leftovers).
const STALE_MS: int = 1500
const PLAYER_HEAD: float = 2.3

## StringName -> StationBase.
var stations: Dictionary = {}
## (pid: int) -> PlayerAvatar or null.
var avatar_of: Callable
var local_id: int = -1
var juice: ScreenJuice
## Parent for world-space effects.
var world: Node3D

## "sid:pid" -> Array of {stack: ChipStack, type, value, at: msec}.
var _bets: Dictionary[String, Array] = {}
## Station id -> msec when its result has finished showing (ball in pocket, reels stopped).
var _shown_at: Dictionary[StringName, int] = {}
## "sid:pid" -> {net, stake}: results waiting for their table to finish showing.
var _pending: Dictionary[String, Dictionary] = {}


func setup(p_stations: Dictionary, p_avatar_of: Callable, p_local_id: int, p_juice: ScreenJuice, p_world: Node3D) -> void:
	stations = p_stations
	avatar_of = p_avatar_of
	local_id = p_local_id
	juice = p_juice
	world = p_world


func on_event(ev: Dictionary) -> void:
	if not Vfx.enabled():
		return
	match StringName(ev.get("type", &"")):
		&"bet_placed":
			_on_bet(ev)
		&"round_started":
			_sweep_stale(StringName(ev.get("station", &"")))
		&"roulette_spin_started":
			var rs: RouletteStation = stations.get(StringName(ev["station"]), null) as RouletteStation
			if rs != null:
				rs.start_spin(Registry.balance.roulette_spin_time)
				Audio.play_at(&"ball_roll", rs, -10.0)
		&"roulette_result":
			var sid: StringName = StringName(ev["station"])
			var rs: RouletteStation = stations.get(sid, null) as RouletteStation
			if rs != null:
				_shown_at[sid] = Time.get_ticks_msec() + int(rs.land(int(ev["number"])) * 1000.0)
		&"round_result":
			_on_result(ev)
		&"jackpot_won":
			var sid: StringName = StringName(ev.get("station", &""))
			var pid: int = int(ev["player"])
			var amount: int = int(ev["amount"])
			_after(_delay_for(sid), func() -> void: _jackpot(sid, pid, amount))


func _on_bet(ev: Dictionary) -> void:
	var sid: StringName = StringName(ev["station"])
	var st: StationBase = stations.get(sid, null)
	if st == null:
		return
	var pid: int = int(ev["player"])
	var details: Dictionary = ev.get("details", {})
	if st is SlotsStation:
		(st as SlotsStation).start_spin(pid == local_id)
		return
	if not (st is RouletteStation or st is BlackjackStation):
		return  # Plinko drops its own chip
	var seat: int = _seat_index(st, pid)
	var start: Vector3 = _seat_edge(st, seat)
	var type: StringName = StringName(details.get("type", &""))
	var value: int = int(details.get("value", 0))
	var target: Vector3 = _bet_spot(st, seat, type, value) + _jitter(pid)
	var key: String = _key(sid, pid)
	var list: Array = _bets.get(key, [])
	for b: Dictionary in list:  # stacking on the same spot again: nudge it over
		if b["type"] == type and int(b["value"]) == value:
			target += Vector3(ChipStack.CHIP_RADIUS * 1.6, 0, 0)
	var stack: ChipStack = ChipStack.make(int(ev["amount"]))
	st.add_child(stack)
	stack.position = start
	stack.slide_to(st.to_global(target), 0.4, 0.12)
	list.append({"stack": stack, "type": type, "value": value, "at": Time.get_ticks_msec()})
	_bets[key] = list
	Audio.play_at(&"chip_clack", stack, -10.0, randf_range(0.95, 1.1))


func _on_result(ev: Dictionary) -> void:
	var sid: StringName = StringName(ev["station"])
	var st: StationBase = stations.get(sid, null)
	var pid: int = int(ev["player"])
	var net: int = int(ev["net"])
	var stake: int = int(ev["stake"])
	var details: Dictionary = ev.get("details", {})
	if st is SlotsStation and details.has("line"):
		var t: float = (st as SlotsStation).stop_on(details["line"], pid == local_id)
		_shown_at[sid] = Time.get_ticks_msec() + int(t * 1000.0)
	elif st is PlinkoStation:
		_shown_at[sid] = Time.get_ticks_msec() + int(PLINKO_DELAY * 1000.0)
	elif st is BlackjackStation:
		_shown_at[sid] = Time.get_ticks_msec() + int(BLACKJACK_DELAY * 1000.0)
	var delay: float = _delay_for(sid)
	var stack: ChipStack = _take_stack(sid, pid, details)
	if stack != null:
		_after(delay, func() -> void: _settle_chips(st, pid, stack, net, stake))
	# Several results for one player at once (roulette bets) show as one total.
	var key: String = _key(sid, pid)
	if _pending.has(key):
		_pending[key]["net"] = int(_pending[key]["net"]) + net
		_pending[key]["stake"] = int(_pending[key]["stake"]) + stake
		return
	_pending[key] = {"net": net, "stake": stake}
	if st is PlinkoStation and pid == local_id and details.has("slot"):  # over the slot the chip lands in
		var ps: PlinkoStation = st
		_pending[key]["pos"] = ps.to_global(Vector3(ps.slot_xs[clampi(int(details["slot"]), 0, ps.slot_xs.size() - 1)], 1.3, 0.3))
	_after(delay, func() -> void: _show_result(sid, pid))


func _settle_chips(st: StationBase, pid: int, stack: ChipStack, net: int, stake: int) -> void:
	if not is_instance_valid(stack) or not is_instance_valid(st):
		return
	var seat: Vector3 = st.to_global(_seat_edge(st, _seat_index(st, pid)))
	if net > 0:
		stack.pay_out(net, st.to_global(_house_spot(st)), seat)
	elif net == 0 and stake > 0:
		stack.collect(seat, 0.45, 0.1)  # push: the stake comes back
	else:
		stack.collect(st.to_global(_house_spot(st)), 0.5, 0.1)
	Audio.play_at(&"chip_clack", stack, -12.0)


func _show_result(sid: StringName, pid: int) -> void:
	var key: String = _key(sid, pid)
	var r: Dictionary = _pending.get(key, {})
	_pending.erase(key)
	var net: int = int(r.get("net", 0))
	var stake: int = int(r.get("stake", 0))
	if net == 0 or world == null or not world.is_inside_tree():
		return
	var pos: Vector3 = r.get("pos", _fx_point(stations.get(sid, null), pid))
	if not pos.is_finite():
		return
	var big: bool = WinFx.is_big_win(net, stake)
	WinFx.money_delta(world, pos + Vector3(0, 0.25, 0), net, big)
	if net < 0:
		WinFx.sad_puff(world, pos)
		return
	if big:
		WinFx.gold_burst(world, pos)
		if pid == local_id and juice != null:
			juice.shake(0.45)
			juice.hit_stop(0.1)
	else:
		WinFx.coin_burst(world, pos, clampi(6 + net / 15, 8, 26))


func _jackpot(sid: StringName, pid: int, amount: int) -> void:
	if world == null or not world.is_inside_tree():
		return
	var pos: Vector3 = _fx_point(stations.get(sid, null), pid)
	if not pos.is_finite():
		return
	WinFx.gold_burst(world, pos, 2.0)
	WinFx.gold_burst(world, pos + Vector3(0, 0.8, 0), 1.0)
	Vfx.floating_text(world, pos + Vector3(0, 0.9, 0), "JACKPOT  +$%s" % WinFx.thousands(amount), Palette.VIP_GOLD, 180, 1.2, 2.6)
	if juice == null:
		return
	if pid == local_id:
		juice.shake(0.85)
		juice.hit_stop(0.2, 0.05)
	else:
		var me: PlayerAvatar = avatar_of.call(local_id) if avatar_of.is_valid() else null
		if me != null and me.global_position.distance_to(pos) < 14.0:
			juice.shake(0.25)


## Moves chips left over from an earlier round to the house.
func _sweep_stale(sid: StringName) -> void:
	var st: StationBase = stations.get(sid, null)
	if st == null:
		return
	var now: int = Time.get_ticks_msec()
	for key: String in _bets.keys():
		if not key.begins_with(String(sid) + ":"):
			continue
		var keep: Array = []
		for b: Dictionary in _bets[key]:
			var s: ChipStack = b["stack"]
			if now - int(b["at"]) < STALE_MS:
				keep.append(b)
			elif is_instance_valid(s):
				s.collect(st.to_global(_house_spot(st)), 0.5)
		_bets[key] = keep


## The chip stack a result settles: the matching roulette bet, else the oldest one.
func _take_stack(sid: StringName, pid: int, details: Dictionary) -> ChipStack:
	var key: String = _key(sid, pid)
	var list: Array = _bets.get(key, [])
	if list.is_empty():
		return null
	var idx: int = 0
	if details.has("type"):
		for i: int in list.size():
			if StringName(list[i]["type"]) == StringName(details["type"]) and int(list[i]["value"]) == int(details.get("value", 0)):
				idx = i
				break
	var b: Dictionary = list[idx]
	list.remove_at(idx)
	_bets[key] = list
	var s: ChipStack = b["stack"]
	return s if is_instance_valid(s) else null


func _delay_for(sid: StringName) -> float:
	return maxf(0.0, (_shown_at.get(sid, 0) - Time.get_ticks_msec()) / 1000.0)


func _after(seconds: float, f: Callable) -> void:
	if seconds <= 0.0:
		f.call()
		return
	get_tree().create_timer(seconds).timeout.connect(f)


## Where a player's win / loss shows: over their head, or for the local player over the table in
## front of them (so a seated camera sees it). `Vector3.INF` when there is nowhere to show it.
func _fx_point(st: StationBase, pid: int) -> Vector3:
	var a: PlayerAvatar = avatar_of.call(pid) if avatar_of.is_valid() else null
	if st != null and pid == local_id:
		if st is SlotsStation:
			return st.to_global(Vector3(0, 1.8, 0.55))
		if st is PlinkoStation:
			return st.to_global(Vector3(0, 1.5, 0.9))
		var seat: int = _seat_index(st, pid)
		return st.to_global(_seat_edge(st, seat).lerp(_bet_spot(st, seat, &"", 0), 0.5) + Vector3(0, 0.35, 0))
	if a != null:
		return a.global_position + Vector3(0, PLAYER_HEAD, 0)
	return Vector3.INF  # nobody to show it on


func _seat_index(st: StationBase, pid: int) -> int:
	var a: PlayerAvatar = avatar_of.call(pid) if avatar_of.is_valid() else null
	if a == null or st.seats.is_empty():
		return 0
	var best: int = 0
	var best_d: float = INF
	for i: int in st.seats.size():
		var d: float = st.seats[i].global_position.distance_squared_to(a.global_position)
		if d < best_d:
			best_d = d
			best = i
	return best


## Local point on the table edge in front of a seat (chips come from and go back to here).
static func _seat_edge(st: StationBase, seat: int) -> Vector3:
	if st.seats.is_empty():
		return Vector3(0, 0.95, 0.6)
	var p: Vector3 = st.seats[clampi(seat, 0, st.seats.size() - 1)].position
	if st is RouletteStation:
		return Vector3(p.x, RouletteStation.FELT_Y, signf(p.z) * 0.8)
	if st is BlackjackStation:
		var to_seat: Vector3 = Vector3(p.x, 0, p.z) - BlackjackStation.ARC_CENTRE
		to_seat.y = 0.0
		return BlackjackStation.ARC_CENTRE + to_seat.normalized() * 1.85 + Vector3(0, BlackjackStation.TABLE_TOP, 0)
	return Vector3(p.x * 0.6, 0.95, p.z * 0.6)


## Local spot on the felt where a bet goes.
static func _bet_spot(st: StationBase, seat: int, type: StringName, value: int) -> Vector3:
	if st is RouletteStation:
		if type == &"":
			return Vector3(_seat_edge(st, seat).x, RouletteStation.FELT_Y, 0.0)
		return RouletteStation.bet_spot(type, value)
	if st is BlackjackStation and not st.seats.is_empty():
		var p: Vector3 = st.seats[clampi(seat, 0, st.seats.size() - 1)].position
		var to_seat: Vector3 = Vector3(p.x, 0, p.z) - BlackjackStation.ARC_CENTRE
		to_seat.y = 0.0
		return BlackjackStation.ARC_CENTRE + to_seat.normalized() * 1.6 + Vector3(0, BlackjackStation.TABLE_TOP, 0)
	return Vector3(0, 0.95, 0)


static func _house_spot(st: StationBase) -> Vector3:
	if st is RouletteStation:
		return RouletteStation.HOUSE_SPOT
	if st is BlackjackStation:
		return Vector3(0.75, 1.0, -0.22)  # the dealer's chip rack
	return Vector3(0, 0.95, 0)


static func _jitter(pid: int) -> Vector3:
	return Vector3((posmod(pid * 37, 7) - 3) * 0.008, 0, (posmod(pid * 53, 7) - 3) * 0.008)


static func _key(sid: StringName, pid: int) -> String:
	return "%s:%d" % [sid, pid]
