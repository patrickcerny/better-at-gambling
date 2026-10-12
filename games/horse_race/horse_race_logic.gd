class_name HorseRaceLogic
extends StationLogicBase
## The horse race table (Patrick: "4 horses, 1:4, first to end wins, random names").
## Round: BETTING (four fresh names; the countdown starts with the first bet) → RACING (the gates
## open, a seeded race runs `simulate(race_seed)`) → RESULT (the first horse over the line wins;
## bets on it pay 1:4, every other bet goes to the house) → BETTING. The race is a pure function of
## its seed: the server only publishes the seed and its own race clock, every client replays the
## same race from it, and the money never depends on anything a client shows.

enum State { IDLE, BETTING, RACING, RESULT }

const HORSES: int = 4
## Track length is 1.0; a horse has won when its nose reaches it. The others run out past it.
const FINISH: float = 1.0
## How far past the line the field pulls up (the table's run-out).
const RUNOUT: float = 1.09
## Average pace: the line is about this many seconds from the gate.
const RACE_SECONDS: float = 9.0
## Simulation step and the spacing of the recorded frames clients interpolate between.
const SIM_DT: float = 0.05
const FRAME_DT: float = 0.1
## No race lasts longer than this (a hard cap, the slowest horse is well inside it).
const MAX_SECONDS: float = 16.0
## Fun casino names; four distinct ones are drawn every round.
const NAME_POOL: Array[String] = [
	"Lucky Seven", "Bean Lightning", "Sir Trots-a-Lot", "Double Down", "Snake Eyes", "Royal Flush",
	"House Edge", "Jackpot Jenny", "Chip Off The Block", "Hold My Oats", "Neigh Sayer", "All In Alice",
	"Comp'd Cocktail", "Velvet Rope", "Split The Aces", "Hay Roller", "Mane Event", "Pocket Rockets",
	"Black Cat Betty", "Clover Me Bad", "Gallop Poll", "Dealer's Choice", "Free Spin", "Last Call Larry",
	"Penny Slot", "Whale Watcher", "Bust Or Bank", "Cash Cow Pony", "Lady Luck", "Pit Boss",
	"Odds On Olive", "Payout Pete", "Roulette Rocket", "Shoe Shuffler", "Busted Flush", "Croupier Kid",
	"Marquee Mabel", "Tip Jar Tommy", "Big Blind", "Buffet Bandit", "Hoof Hearted", "Seabiscuit Lite",
	"The Rake", "Nag Of Fortune", "Beans Means Fins", "Count Cardula", "Comp Hound", "Show Me The Hay",
]

var spots: int = 6
var players: Array[int] = []
var state: State = State.IDLE
## Countdown to the gates (BETTING, only once someone has bet) or until the next round (RESULT).
var timer: float = 0.0
## True once the countdown runs (the first bet of the round is in).
var counting: bool = false
## Bets this round: {player, horse, amount, covered}.
var bets: Array[Dictionary] = []
## This round's horse names, lane 0..3.
var names: Array[String] = []
## Seed of the race being run (−1 between races) and seconds since its gates opened.
var race_seed: int = -1
var race_time: float = 0.0
## Where each horse is now (0 = gate, 1 = line), from the plan.
var progress: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Winning lane of the last race (−1 while none is decided).
var winner: int = -1
var races_played: int = 0

var _plan: Dictionary = {}
## True once this line-up has raced: the next round brings four new names.
var _names_used: bool = true


func _on_setup() -> void:
	game_id = &"horse_race"
	_new_names()  # the board shows a line-up before anyone sits down


func can_join(p: int) -> bool:
	return p in players or players.size() < spots


func join(p: int) -> Dictionary:
	if p in players:
		return OK_RESULT
	if players.size() >= spots:
		return fail(&"seat_taken")
	players.append(p)
	if state == State.IDLE:
		_start_betting()
	return OK_RESULT


func leave(p: int) -> void:
	players.erase(p)


## Minimum per bet and maximum total per race for one player, after the limits multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.horse_min_bet), scaled(balance.horse_max_total))


## Total staked by a player this race.
func player_total(p: int) -> int:
	var sum: int = 0
	for b: Dictionary in bets:
		if b["player"] == p:
			sum += int(b["amount"])
	return sum


## The lane a player backs this race (−1 = none yet).
func horse_of(p: int) -> int:
	for b: Dictionary in bets:
		if b["player"] == p:
			return int(b["horse"])
	return -1


## Bet shape: `{horse: 0..3, amount}`. One horse per player per race (backing every horse at 1:4
## would be a sure profit); more chips on the same horse are fine up to the table maximum.
func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if not p in players:
		return fail(&"not_seated")
	if state != State.BETTING:
		return fail(&"betting_closed")
	var horse: int = int(bet.get("horse", -1))
	var amount: int = int(bet.get("amount", 0))
	if horse < 0 or horse >= HORSES:
		return fail(&"invalid_horse")
	var backed: int = horse_of(p)
	if backed >= 0 and backed != horse:
		return fail(&"one_horse_only")
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if player_total(p) + amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	bets.append({"player": p, "horse": horse, "amount": amount, "covered": last_covered})
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id, "type": &"horse", "value": horse, "horse": horse, "name": names[horse] if horse < names.size() else ""}))
	if not counting:
		counting = true
		timer = balance.horse_countdown
		events.append(GameEvents.make(&"horse_race_countdown", {"station": station_id, "seconds": timer}))
	return OK_RESULT


func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if action == &"clear_bets":
		if state != State.BETTING:
			return fail(&"betting_closed")
		for b: Dictionary in bets.duplicate():
			if b["player"] == p:
				bets.erase(b)
				# Only what the player paid comes back: Fake Cash never turns into real money.
				var back: int = int(b["amount"]) - int(b.get("covered", 0))
				if back > 0:
					economy.apply(p, back, &"bet_cleared", station_id)
		if bets.is_empty():
			counting = false  # nobody is in any more: wait for the next first bet
			timer = 0.0
		return OK_RESULT
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	# Energy Drink (alone at the table) speeds up the waiting, never the race itself: every
	# client replays the race at its real pace.
	var wait: float = delta * (2.0 if _fast_for(players) else 1.0)
	match state:
		State.IDLE:
			if not players.is_empty():
				_start_betting()
		State.BETTING:
			if counting:
				timer -= wait
				if timer <= 0.0:
					_start_race()
			elif players.is_empty():
				state = State.IDLE
		State.RACING:
			_advance_race(delta)
			if race_time >= float(_plan["finish"][int(_plan["winner"])]):
				_finish()
		State.RESULT:
			_advance_race(delta)
			timer -= wait
			if timer <= 0.0:
				if players.is_empty():
					_go_idle()
				else:
					_start_betting()


func round_seconds() -> float:
	return (timer if state == State.BETTING and counting else balance.horse_countdown) + RACE_SECONDS + 2.0


func has_stake(p: int) -> bool:
	return (state == State.BETTING or state == State.RACING) and player_total(p) > 0


func auto_resolve() -> void:
	if state == State.BETTING and not bets.is_empty():
		_start_race()
	if state == State.RACING:
		_finish()
	if state == State.BETTING and bets.is_empty():
		_go_idle()


func refund_all() -> void:
	if state == State.IDLE:
		return
	var totals: Dictionary = {}
	if state == State.BETTING or state == State.RACING:
		for b: Dictionary in bets:
			_refund(int(b["player"]), int(b["amount"]), int(b.get("covered", 0)), totals)
	bets.clear()
	_go_idle()
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	var prog: Array = []
	for x: float in progress:
		prog.append(snappedf(x, 0.001))
	return {
		"game": game_id, "state": state, "timer": timer, "counting": counting, "players": players.duplicate(),
		"bets": bets.duplicate(true), "names": names.duplicate(), "race_seed": race_seed,
		"race_time": snappedf(race_time, 0.01), "progress": prog, "winner": winner if state == State.RESULT else -1,
	}


## A new round: four fresh names, the horses back in the gate.
func _start_betting() -> void:
	state = State.BETTING
	counting = false
	timer = 0.0
	bets.clear()
	winner = -1
	race_seed = -1
	race_time = 0.0
	_plan = {}
	progress = [0.0, 0.0, 0.0, 0.0]
	if _names_used:
		_new_names()
	events.append(GameEvents.make(&"round_started", {"station": station_id, "names": names.duplicate()}))


func _new_names() -> void:
	names = draw_names(rng)
	_names_used = false


func _go_idle() -> void:
	state = State.IDLE
	counting = false
	timer = 0.0
	race_seed = -1
	race_time = 0.0
	_plan = {}
	progress = [0.0, 0.0, 0.0, 0.0]


## Bets close and the gates open: the race is drawn now (its seed) and runs on the clock.
func _start_race() -> void:
	state = State.RACING
	counting = false
	timer = 0.0
	race_seed = rng.range_int(1, 2_000_000_000)
	_names_used = true
	race_time = 0.0
	winner = -1
	_plan = simulate(race_seed)
	progress = [0.0, 0.0, 0.0, 0.0]
	events.append(GameEvents.make(&"horse_race_started", {"station": station_id, "seed": race_seed, "names": names.duplicate()}))


func _advance_race(delta: float) -> void:
	if _plan.is_empty():
		return
	race_time = minf(race_time + delta, float(_plan["duration"]))
	progress = sample(_plan, race_time)


## The first horse is over the line: every bet settles (a winner pays 1:4, the rest go to the
## house) and the field runs out while the result shows.
func _finish() -> void:
	winner = int(_plan["winner"])
	race_time = maxf(race_time, float(_plan["finish"][winner]))
	progress = sample(_plan, race_time)
	races_played += 1
	events.append(GameEvents.make(&"horse_race_finished", {"station": station_id, "winner": winner, "name": names[winner] if winner < names.size() else "", "seed": race_seed}))
	var played: Dictionary[int, bool] = {}
	for b: Dictionary in bets:
		var p: int = int(b["player"])
		var stake: int = int(b["amount"])
		var horse: int = int(b["horse"])
		var base_return: int = stake * (balance.horse_payout_ratio + 1) if horse == winner else 0
		_settle(p, stake, base_return, {"type": &"horse", "value": horse, "horse": horse, "winner": winner})
		played[p] = true
	for p: int in played.keys():
		modifiers.consume_round(p, game_id)
	bets.clear()
	state = State.RESULT
	timer = balance.horse_result_time


## Four distinct names from the pool.
static func draw_names(r: SeededRng) -> Array[String]:
	var idx: Array = range(NAME_POOL.size())
	r.shuffle(idx)
	var out: Array[String] = []
	for i: int in HORSES:
		out.append(NAME_POOL[int(idx[i])])
	return out


## The whole race from its seed, identical wherever it runs: `{frames: [PackedFloat32Array per
## horse, one value every FRAME_DT], finish: [seconds each nose reached the line], winner,
## duration}`. Each horse has a small talent for the day and changes pace every half a second to
## a second and a half, so the lead changes hands; the first nose over the line wins (an exact
## tie, practically impossible, goes to the lower lane).
static func simulate(seed_value: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var base: float = FINISH / RACE_SECONDS
	var talent: Array[float] = []
	var speed: Array[float] = []
	var target: Array[float] = []
	var seg_left: Array[float] = []
	var pos: Array[float] = []
	var finish: Array[float] = []
	var frames: Array[PackedFloat32Array] = []
	for h: int in HORSES:
		talent.append(r.randf_range(0.97, 1.03))
		speed.append(base * r.randf_range(0.25, 0.45))  # out of the gate
		target.append(base * talent[h] * r.randf_range(0.85, 1.15))
		seg_left.append(r.randf_range(0.4, 1.2))
		pos.append(0.0)
		finish.append(-1.0)
		frames.append(PackedFloat32Array([0.0]))
	var t: float = 0.0
	var subs: int = roundi(FRAME_DT / SIM_DT)
	var follow: float = 1.0 - exp(-SIM_DT * 2.2)
	var last_cross: float = INF
	while t < MAX_SECONDS:
		for _s: int in subs:
			t += SIM_DT
			for h: int in HORSES:
				seg_left[h] -= SIM_DT
				if seg_left[h] <= 0.0:
					# Always draw, finished or not, so the sequence never depends on the field.
					target[h] = base * talent[h] * r.randf_range(0.8, 1.2)
					seg_left[h] = r.randf_range(0.5, 1.5)
				var goal: float = target[h]
				if finish[h] >= 0.0:
					goal = base * 0.25  # past the line: pulling up
				speed[h] = lerpf(speed[h], goal, follow)
				var before: float = pos[h]
				pos[h] = minf(pos[h] + speed[h] * SIM_DT, RUNOUT)
				if finish[h] < 0.0 and pos[h] >= FINISH:
					finish[h] = t - SIM_DT + (FINISH - before) / maxf(speed[h], 0.0001)
		for h: int in HORSES:
			frames[h].append(pos[h])
		if last_cross == INF and finish.min() >= 0.0:
			last_cross = t
		if t >= last_cross + 1.5:
			break
	for h: int in HORSES:  # the cap: anyone still out is over the line at the end
		if finish[h] < 0.0:
			finish[h] = t
	var win: int = 0
	for h: int in range(1, HORSES):
		if finish[h] < finish[win]:
			win = h
	return {"frames": frames, "finish": finish, "winner": win, "duration": (frames[0].size() - 1) * FRAME_DT}


## Every horse's position at `seconds` into a race plan (linear between frames).
static func sample(plan: Dictionary, seconds: float) -> Array[float]:
	var out: Array[float] = []
	var frames: Array = plan.get("frames", [])
	for h: int in HORSES:
		if h >= frames.size():
			out.append(0.0)
			continue
		var f: PackedFloat32Array = frames[h]
		var x: float = clampf(seconds / FRAME_DT, 0.0, float(f.size() - 1))
		var i: int = mini(int(floor(x)), f.size() - 1)
		var j: int = mini(i + 1, f.size() - 1)
		out.append(lerpf(f[i], f[j], x - i))
	return out


## Lanes in race order (leader first) for a set of positions.
static func order_of(prog: Array) -> Array[int]:
	var lanes: Array[int] = []
	for h: int in prog.size():
		lanes.append(h)
	lanes.sort_custom(func(a: int, b: int) -> bool: return float(prog[a]) > float(prog[b]) or (float(prog[a]) == float(prog[b]) and a < b))
	return lanes
