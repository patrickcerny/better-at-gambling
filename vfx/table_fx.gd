class_name TableFx
extends Node
## Client-side presentation of the casino tables, driven by the server's events (presentation
## only, it never touches money or rules):
## - chips slide from a seat onto the felt when a bet is placed (roulette on its layout spot,
##   blackjack in front of the seat), then to the winner (with the house's chips) or to the house;
## - the roulette ball circles and drops into the server's number; the Wheel of Fortune slows onto
##   the server's segment; slot reels stop one by one; the craps dice are thrown and come to rest
##   on the server's roll;
## - win / lose / jackpot feedback over the player once the table has shown the result: floating
##   "+$120" / "-$50", coins or a sad puff, and for the local player's big wins and jackpots a gold
##   burst with screen shake and hit-stop.
## `MatchScene` creates one (never on a dedicated server) and forwards every event.

## Seconds until a blackjack result reads (cards flip first). The Plinko chip touches down as the
## server settles it (it starts falling on `plinko_dropped`), so its result only waits for the clack.
const BLACKJACK_DELAY: float = 0.35
const PLINKO_DELAY: float = 0.15
## Bets older than this are swept off the felt when a new round starts (stale leftovers).
const STALE_MS: int = 1500
const PLAYER_HEAD: float = 2.3

## StringName -> StationBase.
var stations: Dictionary = {}
## (pid: int) -> PlayerAvatar or null.
var avatar_of: Callable
## (pid: int) -> Color: the player's colour for their chips (unset = size-tier colours).
var color_of: Callable
## (sid: StringName) -> int: the table minimum at the current limits, one chip each (unset = size scale).
var min_bet_of: Callable
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
## Slot machines whose reels are already landing on the line their next result pays for.
var _landing: Array[StringName] = []


func setup(p_stations: Dictionary, p_avatar_of: Callable, p_local_id: int, p_juice: ScreenJuice, p_world: Node3D, p_color_of: Callable = Callable(), p_min_bet_of: Callable = Callable()) -> void:
	stations = p_stations
	avatar_of = p_avatar_of
	color_of = p_color_of
	min_bet_of = p_min_bet_of
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
			var hr: HorseRaceStation = stations.get(StringName(ev.get("station", &"")), null) as HorseRaceStation
			if hr != null:
				hr.reset_table()
				hr.set_names(ev.get("names", []))
		&"horse_race_started":
			# The gates open: every client replays the same seeded race.
			var hr: HorseRaceStation = stations.get(StringName(ev["station"]), null) as HorseRaceStation
			if hr != null:
				hr.start_race(int(ev["seed"]), 0.0)
		&"horse_race_finished":
			# The bets settle now on the server; here the result waits until the winner's nose
			# crosses the line on this table.
			var sid: StringName = StringName(ev["station"])
			var hr: HorseRaceStation = stations.get(sid, null) as HorseRaceStation
			if hr != null:
				_shown_at[sid] = Time.get_ticks_msec() + int(hr.finish(int(ev["winner"]), int(ev.get("seed", -1))) * 1000.0)
		&"craps_rolled":
			# The dice leave the shooter's hand; the bets settle on the server as they rest here.
			var sid: StringName = StringName(ev["station"])
			var cs: CrapsStation = stations.get(sid, null) as CrapsStation
			if cs != null:
				var by: int = int(ev.get("shooter", -1))
				var seat: int = _seat_index(cs, by) if by >= 0 and avatar_of.is_valid() and avatar_of.call(by) != null else -1
				_shown_at[sid] = Time.get_ticks_msec() + int(cs.throw(ev["dice"], int(ev["seed"]), seat) * 1000.0)
		&"craps_result":
			var cs: CrapsStation = stations.get(StringName(ev["station"]), null) as CrapsStation
			if cs != null:
				cs.show_result(int(ev["total"]), StringName(ev["outcome"]), int(ev["point"]))
		&"wheel_spin_started":
			var ws: WheelStation = stations.get(StringName(ev["station"]), null) as WheelStation
			if ws != null:
				ws.start_spin()
		&"wheel_result":
			# The wheel slows onto the server's segment; the bets pay as the pointer settles on it.
			var sid: StringName = StringName(ev["station"])
			var ws: WheelStation = stations.get(sid, null) as WheelStation
			if ws != null:
				_shown_at[sid] = Time.get_ticks_msec() + int(ws.land(int(ev["segment"]), float(ev.get("seconds", WheelLogic.LAND_TIME))) * 1000.0)
		&"roulette_spin_started":
			var rs: RouletteStation = stations.get(StringName(ev["station"]), null) as RouletteStation
			if rs != null:
				rs.start_spin(Registry.balance.roulette_spin_time)
				Audio.play_at(&"roulette_spin", rs, -4.0)
		&"roulette_result":
			var sid: StringName = StringName(ev["station"])
			var rs: RouletteStation = stations.get(sid, null) as RouletteStation
			if rs != null:
				_shown_at[sid] = Time.get_ticks_msec() + int(rs.land(int(ev["number"])) * 1000.0)
		&"slots_landing":
			# The spin ended: the reels land on the line now; the payout (`round_result`) follows
			# once the last one has stopped.
			var sid: StringName = StringName(ev["station"])
			var ss: SlotsStation = stations.get(sid, null) as SlotsStation
			if ss != null:
				_landing.append(sid)
				_shown_at[sid] = Time.get_ticks_msec() + int(ss.stop_on(ev["line"], int(ev["player"]) == local_id) * 1000.0)
		&"bj_action":
			if StringName(ev.get("action", &"")) == &"split":
				_on_bj_split(ev)
		&"scratch_card":
			# A card was bought at the kiosk: it slides out of the dispenser onto the counter.
			var sc: ScratchStation = stations.get(StringName(ev["station"]), null) as ScratchStation
			if sc != null:
				sc.dispense(int(ev.get("tier", 0)), int(ev.get("player", -1)) == local_id)
		&"round_result":
			_on_result(ev)
		&"bets_refunded":
			_return_chips(StringName(ev["station"]), int(ev["player"]))
		&"table_reset":
			_reset_table(StringName(ev["station"]))
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
	if not (st is RouletteStation or st is BlackjackStation or st is HorseRaceStation or st is WheelStation or st is CrapsStation or st is HiLoStation):
		return  # Plinko drops its own chip
	var seat: int = _seat_index(st, pid)
	var start: Vector3 = _seat_edge(st, seat)
	var type: StringName = StringName(details.get("type", &""))
	var value: int = int(details.get("value", 0))
	var target: Vector3 = _bet_spot(st, seat, type, value) + _jitter(pid)
	var key: String = _key(sid, pid)
	var list: Array = _bets.get(key, [])
	var color: Color = color_of.call(pid) if color_of.is_valid() else ChipStack.NO_COLOR
	var unit: int = int(min_bet_of.call(sid)) if min_bet_of.is_valid() else 0
	var chips: int = ChipStack.chip_count(int(ev["amount"]), unit)
	if st is CrapsStation:
		# On the seat's own spot of that bet; more chips on it stack on top of the player's own.
		target = _bet_spot(st, seat, type, value)
		for b: Dictionary in list:
			var s: ChipStack = b["stack"]
			if is_instance_valid(s) and b["type"] == type:
				target.y += mini(ChipStack.chip_count(s.amount, s.unit), ChipStack.COLUMN_CHIPS) * ChipStack.CHIP_HEIGHT
	elif st is RouletteStation or st is HorseRaceStation or st is WheelStation:
		# On its printed spot and nowhere else: a second column is centred on the spot (it used to
		# trail onto the next row), and another bet on the same spot stacks on top of the chips
		# already there (it used to be nudged sideways onto the neighbouring number).
		target = _bet_spot(st, seat, type, value)  # no jitter: stacks share a spot by going up
		target.z += (ChipStack.columns(chips) - 1) * ChipStack.CHIP_RADIUS * 2.05 * 0.5
		target.y += _height_on_spot(sid, type, value)
	else:
		for b: Dictionary in list:  # stacking on the same spot again: nudge it over
			if b["type"] == type and int(b["value"]) == value:
				target += Vector3(ChipStack.CHIP_RADIUS * 1.6, 0, 0)
	var stack: ChipStack = ChipStack.make(int(ev["amount"]), color, unit)
	st.add_child(stack)
	stack.position = start
	stack.slide_to(st.to_global(target), 0.4, 0.12)
	list.append({"stack": stack, "type": type, "value": value, "at": Time.get_ticks_msec()})
	_bets[key] = list
	Audio.play_at(&"chip_clack", stack, -10.0, randf_range(0.95, 1.1))


## A blackjack split: the bet slides in front of the first hand and an equal stack (the second
## stake) comes in from the rail in front of the second; each pays or goes to the house with its
## own hand's result (`details.hand`).
func _on_bj_split(ev: Dictionary) -> void:
	var sid: StringName = StringName(ev["station"])
	var st: BlackjackStation = stations.get(sid, null) as BlackjackStation
	var pid: int = int(ev["player"])
	var list: Array = _bets.get(_key(sid, pid), [])
	if st == null or list.is_empty() or not is_instance_valid(list[0]["stack"]):
		return
	var first: ChipStack = list[0]["stack"]
	var seat: int = _seat_index(st, pid)
	first.slide_to(st.to_global(st.hand_bet_spot(seat, 0)), 0.3, 0.05)
	var stack: ChipStack = ChipStack.make(first.amount, first.color, first.unit)
	st.add_child(stack)
	stack.position = _seat_edge(st, seat)
	stack.slide_to(st.to_global(st.hand_bet_spot(seat, 1)), 0.4, 0.12)
	list.append({"stack": stack, "type": &"split", "value": 1, "at": Time.get_ticks_msec()})
	Audio.play_at(&"chip_clack", stack, -10.0, randf_range(0.95, 1.1))


## Height of the chips already on a roulette spot, horse pad or wheel symbol (every player's), so the next stack
## goes on top.
func _height_on_spot(sid: StringName, type: StringName, value: int) -> float:
	var h: float = 0.0
	for key: String in _bets:
		if not key.begins_with(String(sid) + ":"):
			continue
		for b: Dictionary in _bets[key]:
			var s: ChipStack = b["stack"]
			if is_instance_valid(s) and b["type"] == type and int(b["value"]) == value:
				h += mini(ChipStack.chip_count(s.amount, s.unit), ChipStack.COLUMN_CHIPS) * ChipStack.CHIP_HEIGHT
	return h


func _on_result(ev: Dictionary) -> void:
	var sid: StringName = StringName(ev["station"])
	var st: StationBase = stations.get(sid, null)
	var pid: int = int(ev["player"])
	var net: int = int(ev["net"])
	var stake: int = int(ev["stake"])
	var details: Dictionary = ev.get("details", {})
	if st is SlotsStation and _landing.has(sid):
		_landing.erase(sid)  # the reels landed on this line already (`slots_landing`)
	elif st is SlotsStation and details.has("line"):  # joined after the landing started
		var t: float = (st as SlotsStation).stop_on(details["line"], pid == local_id)
		_shown_at[sid] = Time.get_ticks_msec() + int(t * 1000.0)
	elif st is PlinkoStation:
		_shown_at[sid] = Time.get_ticks_msec() + int(PLINKO_DELAY * 1000.0)
	elif st is BlackjackStation or st is HiLoStation:
		_shown_at[sid] = Time.get_ticks_msec() + int(BLACKJACK_DELAY * 1000.0)  # the card lands first
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


## A minigame refunded the bets (Patrick's note #9): the player's chips slide back to their seat.
func _return_chips(sid: StringName, pid: int) -> void:
	var st: StationBase = stations.get(sid, null)
	var key: String = _key(sid, pid)
	var list: Array = _bets.get(key, [])
	_bets.erase(key)
	_pending.erase(key)
	if st == null:
		return
	var seat: Vector3 = st.to_global(_seat_edge(st, _seat_index(st, pid)))
	for b: Dictionary in list:
		var s: ChipStack = b["stack"]
		if is_instance_valid(s):
			s.collect(seat, 0.45)


## The table was cleared for the minigame: nothing left on the felt, no result still to show.
func _reset_table(sid: StringName) -> void:
	var st: StationBase = stations.get(sid, null)
	_shown_at.erase(sid)
	_landing.erase(sid)
	for key: String in _bets.keys():
		if not key.begins_with(String(sid) + ":"):
			continue
		var pid: int = int(key.get_slice(":", 1))
		_return_chips(sid, pid)
	for key: String in _pending.keys():
		if key.begins_with(String(sid) + ":"):
			_pending.erase(key)
	if st != null and st.has_method(&"reset_table"):
		st.call(&"reset_table")


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
	if int(details.get("hand", 0)) == 1:  # a blackjack split's second hand
		for i: int in list.size():
			if StringName(list[i]["type"]) == &"split":
				idx = i
	elif details.has("type"):
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
		if st is ScratchStation:
			return st.to_global(ScratchStation.CARD_SPOT + Vector3(0, 0.45, 0.25))
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
	if st is HorseRaceStation:
		return Vector3(p.x, HorseRaceStation.TABLE_TOP + 0.02, HorseRaceStation.TABLE_D * 0.5 - 0.05)
	if st is CrapsStation:
		return Vector3(p.x, CrapsStation.RAIL_TOP + 0.07, CrapsStation.TABLE_D * 0.5 - 0.12)
	if st is WheelStation:
		return Vector3(p.x, WheelStation.FELT_Y, WheelStation.LEDGE_Z)
	if st is HiLoStation:
		return Vector3(p.x, HiLoStation.TABLE_TOP + 0.12, HiLoStation.RAIL_OUTER)  # over the rail
	if st is BlackjackStation:
		# Over the padded rail (not inside it): the stack arcs from here down onto the felt.
		var to_seat: Vector3 = Vector3(p.x, 0, p.z) - BlackjackStation.ARC_CENTRE
		to_seat.y = 0.0
		return BlackjackStation.ARC_CENTRE + to_seat.normalized() * BlackjackStation.RAIL_RADIUS + Vector3(0, BlackjackStation.TABLE_TOP + 0.12, 0)
	return Vector3(p.x * 0.6, 0.95, p.z * 0.6)


## Local spot on the felt where a bet goes.
static func _bet_spot(st: StationBase, seat: int, type: StringName, value: int) -> Vector3:
	if st is RouletteStation:
		if type == &"":
			return Vector3(_seat_edge(st, seat).x, RouletteStation.FELT_Y, 0.0)
		return RouletteStation.bet_spot(type, value)
	if st is HorseRaceStation:
		if type == &"":
			return Vector3(_seat_edge(st, seat).x, HorseRaceStation.TABLE_TOP + 0.02, HorseRaceStation.LEDGE_Z)
		return HorseRaceStation.bet_spot(value)
	if st is CrapsStation:
		if type == &"":
			return Vector3(_seat_edge(st, seat).x, CrapsStation.FELT_Y + 0.003, CrapsStation.PASS_Z)
		return CrapsStation.bet_spot(type, seat)
	if st is WheelStation:
		if type == &"":
			return Vector3(_seat_edge(st, seat).x, WheelStation.FELT_Y, WheelStation.LEDGE_Z - 0.15)
		return WheelStation.bet_spot(value)
	if st is HiLoStation:
		return HiLoStation.bet_spot(seat)  # the gold ante ring in front of the seat
	if st is BlackjackStation and not st.seats.is_empty():
		var p: Vector3 = st.seats[clampi(seat, 0, st.seats.size() - 1)].position
		var to_seat: Vector3 = Vector3(p.x, 0, p.z) - BlackjackStation.ARC_CENTRE
		to_seat.y = 0.0
		return BlackjackStation.ARC_CENTRE + to_seat.normalized() * BlackjackStation.BET_RADIUS + Vector3(0, BlackjackStation.TABLE_TOP, 0)
	return Vector3(0, 0.95, 0)


static func _house_spot(st: StationBase) -> Vector3:
	if st is RouletteStation:
		return RouletteStation.HOUSE_SPOT
	if st is HorseRaceStation:
		return HorseRaceStation.HOUSE_SPOT
	if st is CrapsStation:
		return CrapsStation.HOUSE_SPOT
	if st is WheelStation:
		return WheelStation.HOUSE_SPOT
	if st is HiLoStation:
		return HiLoStation.HOUSE_SPOT
	if st is BlackjackStation:
		return Vector3(0.75, 1.0, -0.22)  # the dealer's chip rack
	return Vector3(0, 0.95, 0)


static func _jitter(pid: int) -> Vector3:
	return Vector3((posmod(pid * 37, 7) - 3) * 0.008, 0, (posmod(pid * 53, 7) - 3) * 0.008)


static func _key(sid: StringName, pid: int) -> String:
	return "%s:%d" % [sid, pid]
