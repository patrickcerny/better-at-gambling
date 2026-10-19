class_name SwordTapperLogic
extends StationLogicBase
## Sword Tapper: a sword in a stone on a marble pedestal, ringed by 17 gem lamps, each showing a
## prize (a multiple of the stake, `BalanceConfig.sword_ring`). One player per pedestal (like a
## slot machine); one tap is one pull.
##
## A pull (`place_bet({amount})`, $10–$100 × limits, all-in over the balance) takes the stake and
## decides everything at once on the server (`draw_pull`): the sword stays stuck (the stake is
## lost) or comes free and lights 3 to 17 gems (a uniform pick from the ring) and pays their sum;
## a win of `sword_mult_max_gems` gems or fewer may get a ×2 / ×3 / ×5 / ×10 multiplier. A stuck
## pull is drawn again once with `sword_favour` chance (the quiet house rule of 0.9.6), and the
## player's luck rerolls the whole pull like a slot line (Lucky Clover keeps the better of two,
## Black Cat the worse). Nothing about either is shown or sent; the flourish shows on the result.
##
## The pull goes out in one `sword_pull` event (every client plays the same reveal from it) and in
## the public state. It pays (`round_result`) when the reveal ends (`sword_reveal_time`), or at
## once when the player walks away, the casino closes or a minigame starts: the result exists
## already, so it is paid, never refunded. Money never depends on the animation.

const RING_SIZE: int = 17
## The fewest gems a freed sword lights (`sword_count_weights[0]` is for this many).
const MIN_GEMS: int = 3
## Seconds a pull needs at least: one placed later than this before the casino closes is refused
## ("Table closing!").
const ROUND_SECONDS: float = 3.0
## How many past pulls the public state keeps for the panel.
const HISTORY: int = 8

var player: int = -1
## The open pull ({free, gems, mult}); empty when none is being revealed.
var pull: Dictionary = {}
var stake: int = 0
## Part of `stake` Fake Cash paid for.
var stake_covered: int = 0
## Seconds left on the reveal of the open pull (it pays at 0).
var reveal_left: float = 0.0
var pulls_played: int = 0
## Pulls made here so far: tells the clients a new pull from the one before.
var serial: int = 0
## The last pull that paid, for late joiners: {pull, stake, returned, serial}.
var last: Dictionary = {}
## The last `HISTORY` pulls, newest first: {free, gems (how many), mult, stake, returned}.
var history: Array[Dictionary] = []
## Luck changed this pull: the clover / black cat shows when it pays (not at the tap: that would
## spoil the reveal).
var _flourish: StringName = &""


func _on_setup() -> void:
	game_id = &"sword_tapper"


func can_join(p: int) -> bool:
	return player < 0 or player == p


func join(p: int) -> Dictionary:
	if not can_join(p):
		return fail(&"seat_taken")
	player = p
	return OK_RESULT


## Walking away (or being knocked off) pays the open pull at once: it was decided at the tap.
func leave(p: int) -> void:
	if p != player:
		return
	auto_resolve()
	player = -1


## Min and max stake after the limits multiplier.
func limits() -> Vector2i:
	return Vector2i(scaled(balance.sword_min_bet), scaled(balance.sword_max_bet))


## All-in: a stake over the balance (or the max) pulls with what fits.
func bet_limits(_p: int, _bet: Dictionary) -> Vector2i:
	return limits()


## Bet shape: `{amount}`. One pull at a time: the next one waits until the last has paid.
func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if p != player:
		return fail(&"not_seated")
	if not pull.is_empty():
		return fail(&"pulling")
	var amount: int = int(bet.get("amount", 0))
	var lim: Vector2i = limits()
	if amount < lim.x:
		return fail(&"below_min")
	if amount > lim.y:
		return fail(&"above_max")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	stake = amount
	stake_covered = last_covered
	serial += 1
	var lk: int = modifiers.get_luck(p, game_id)
	var d: LuckRng.Draw = luck.draw(lk, func() -> Dictionary: return draw_pull(rng, balance),
		func(x: Dictionary) -> float: return pull_multiplier(x, balance))
	pull = d.value
	_flourish = (&"lucky" if lk > 0 else &"jinxed") if d.luck_changed else &""
	reveal_left = balance.sword_reveal_time
	events.append(GameEvents.bet_placed(p, station_id, amount, with_all_in(bet, {"game": game_id})))
	events.append(GameEvents.make(&"sword_pull", {"station": station_id, "player": p, "stake": amount, "serial": serial,
		"free": pull["free"], "gems": (pull["gems"] as Array).duplicate(), "mult": pull["mult"], "win": prize(amount, pull, balance),
		"seconds": reveal_left}))
	return OK_RESULT


func player_action(p: int, _action: StringName, _params: Dictionary = {}) -> Dictionary:
	if p != player:
		return fail(&"not_seated")
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	if pull.is_empty():
		return
	if player >= 0 and _fast_for([player]):
		delta *= 2.0  # Energy Drink
	reveal_left -= delta
	if reveal_left <= 0.0:
		_pay()


func round_seconds() -> float:
	return ROUND_SECONDS


func has_stake(p: int) -> bool:
	return not pull.is_empty() and player == p


func auto_resolve() -> void:
	if not pull.is_empty():
		_pay()


## A minigame starts: the open pull was decided at the tap, so it pays now (never a refund).
func refund_all() -> void:
	auto_resolve()


## The pedestal never turns into the Hot Table (a default; it can join the draw later).
func hot_table_candidate() -> bool:
	return false


func get_public_state() -> Dictionary:
	return {"game": game_id, "player": player, "pulling": not pull.is_empty(), "pull": pull.duplicate(true), "stake": stake,
		"serial": serial, "reveal_left": snappedf(maxf(reveal_left, 0.0), 0.01), "last": last.duplicate(true), "history": history.duplicate(true)}


## The reveal is over (or cut short): the pull pays its printed prize (times the usual item / Last
## Call multipliers on the winnings).
func _pay() -> void:
	var paid: Dictionary = pull.duplicate(true)
	var mult: float = pull_multiplier(paid, balance)
	var details: Dictionary = {"pull": paid, "multiple": mult}
	if mult >= balance.sword_big_win:
		details["big"] = true
	if _flourish != &"":
		events.append(GameEvents.luck_flourish(player, station_id, _flourish))
	var returned: int = _settle(player, stake, prize(stake, paid, balance), details)
	modifiers.consume_round(player, game_id)
	pulls_played += 1
	last = {"pull": paid, "stake": stake, "returned": returned, "serial": serial}
	history.push_front({"free": paid["free"], "gems": (paid["gems"] as Array).size(), "mult": paid["mult"], "stake": stake, "returned": returned})
	if history.size() > HISTORY:
		history.resize(HISTORY)
	pull = {}
	stake = 0
	stake_covered = 0
	reveal_left = 0.0
	_flourish = &""


# --- The draw (pure) ----------------------------------------------------------------------------


## One pull: the sword comes free with `sword_pull_chance` (a stuck pull is drawn again once with
## `sword_favour` chance: the house rule), then how many gems (`sword_count_weights`), which ones
## (a uniform pick from the ring) and, for a small win, the multiplier.
static func draw_pull(r: SeededRng, cfg: BalanceConfig) -> Dictionary:
	var free: bool = r.chance(cfg.sword_pull_chance)
	if not free and r.chance(cfg.sword_favour):
		free = r.chance(cfg.sword_pull_chance)
	if not free:
		return stuck()
	var n: int = MIN_GEMS + maxi(r.weighted_index(cfg.sword_count_weights), 0)
	var ring: Array[int] = []
	for i: int in cfg.sword_ring.size():
		ring.append(i)
	r.shuffle(ring)
	var gems: Array[int] = ring.slice(0, mini(n, ring.size()))
	gems.sort()
	var mult: int = 1
	if gems.size() <= cfg.sword_mult_max_gems:
		mult = cfg.sword_mult_values[maxi(r.weighted_index(cfg.sword_mult_weights), 0)]
	return {"free": true, "gems": gems, "mult": mult}


## A pull where the sword stays in the stone.
static func stuck() -> Dictionary:
	return {"free": false, "gems": [] as Array[int], "mult": 1}


## A gem's prize per $1 of stake, in hundredths (whole numbers, so sums are exact).
static func gem_cents(cfg: BalanceConfig, gem: int) -> int:
	return roundi(cfg.sword_ring[gem] * 100.0) if gem >= 0 and gem < cfg.sword_ring.size() else 0


## What a pull pays per $1 of stake, in hundredths: the lit gems' sum times the multiplier, never
## more than `sword_max_pay`.
static func pull_cents(p: Dictionary, cfg: BalanceConfig) -> int:
	if not bool(p.get("free", false)):
		return 0
	var sum: int = 0
	for g: Variant in p.get("gems", []):
		sum += gem_cents(cfg, int(g))
	return mini(sum * maxi(int(p.get("mult", 1)), 1), roundi(cfg.sword_max_pay * 100.0))


## What a pull pays as a multiple of the stake (0 when the sword stayed). This is the prize rule
## printed on the panel and the only thing the server pays by.
static func pull_multiplier(p: Dictionary, cfg: BalanceConfig) -> float:
	return pull_cents(p, cfg) / 100.0


## What a pull pays on `amount`, rounded down to whole dollars.
static func prize(amount: int, p: Dictionary, cfg: BalanceConfig) -> int:
	return amount * pull_cents(p, cfg) / 100


## What one gem shows on a stake of `amount`, in cents (the ring prints it in dollars).
static func gem_prize_cents(amount: int, cfg: BalanceConfig, gem: int) -> int:
	return amount * gem_cents(cfg, gem)


## Chance a pull frees the sword, the house rule counted in.
static func free_chance(cfg: BalanceConfig) -> float:
	var p: float = cfg.sword_pull_chance
	return p + (1.0 - p) * cfg.sword_favour * p


## Every payout a pull can make at neutral luck, the house rule counted in: cents per $1 of stake
## → probability (0 = the sword stayed). Counts every subset of the ring (2^17), each size weighted
## by `sword_count_weights` and spread evenly over the subsets of that size.
static func payout_probs(cfg: BalanceConfig) -> Dictionary:
	var size: int = cfg.sword_ring.size()
	var count_w: float = 0.0
	for w: float in cfg.sword_count_weights:
		count_w += maxf(w, 0.0)
	var mult_w: float = 0.0
	for w: float in cfg.sword_mult_weights:
		mult_w += maxf(w, 0.0)
	var subsets: PackedFloat64Array = PackedFloat64Array()  # how many subsets of each size
	subsets.resize(size + 1)
	subsets[0] = 1.0
	for n: int in range(1, size + 1):
		subsets[n] = subsets[n - 1] * (size - n + 1) / n
	var free: float = free_chance(cfg)
	var cap: int = roundi(cfg.sword_max_pay * 100.0)
	var out: Dictionary = {0: 1.0 - free}
	var sums: PackedInt32Array = PackedInt32Array()
	sums.resize(1 << size)
	for mask: int in range(1, 1 << size):
		var low: int = mask & -mask
		var bit: int = 0
		while (1 << bit) != low:
			bit += 1
		sums[mask] = sums[mask & (mask - 1)] + gem_cents(cfg, bit)
		var n: int = _bits(mask)
		var wi: int = n - MIN_GEMS
		if wi < 0 or wi >= cfg.sword_count_weights.size():
			continue
		var p: float = free * maxf(cfg.sword_count_weights[wi], 0.0) / count_w / subsets[n]
		if p <= 0.0:
			continue
		if n > cfg.sword_mult_max_gems:
			var c: int = mini(sums[mask], cap)
			out[c] = float(out.get(c, 0.0)) + p
			continue
		for k: int in cfg.sword_mult_values.size():
			var c: int = mini(sums[mask] * cfg.sword_mult_values[k], cap)
			out[c] = float(out.get(c, 0.0)) + p * maxf(cfg.sword_mult_weights[k], 0.0) / mult_w
	return out


static func _bits(x: int) -> int:
	var n: int = 0
	while x != 0:
		x &= x - 1
		n += 1
	return n


## Exact RTP at neutral luck (the house rule counted in, before the dollar rounding), the chance the
## sword comes free and the largest multiple a pull can pay: {rtp, free, max}.
static func exact_rtp(cfg: BalanceConfig) -> Dictionary:
	var probs: Dictionary = payout_probs(cfg)
	var rtp: float = 0.0
	var top: int = 0
	for c: Variant in probs:
		rtp += int(c) / 100.0 * float(probs[c])
		top = maxi(top, int(c))
	return {"rtp": rtp, "free": free_chance(cfg), "max": top / 100.0}
