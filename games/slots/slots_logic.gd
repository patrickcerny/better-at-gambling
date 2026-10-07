class_name SlotsLogic
extends StationLogicBase
## One slot machine: 3 reels × 1 payline, one player (§2.5).
## Spin flow: `place_bet({amount})` takes the stake and decides the line (luck-rerolled by payout),
## the reels "spin" for `slots_spin_time` (or until `stop` after `slots_skip_after`), then it pays.

enum Sym { CHERRY, LEMON, BELL, BAR, SEVEN, CLOVER, DIAMOND }
const SYMBOL_NAMES: Array[StringName] = [&"cherry", &"lemon", &"bell", &"bar", &"seven", &"clover", &"diamond"]

var player: int = -1
var spinning: bool = false
var line: Array[int] = []
var stake: int = 0
## Part of `stake` Fake Cash paid for.
var stake_covered: int = 0
var spin_elapsed: float = 0.0
var spins_played: int = 0


func _on_setup() -> void:
	game_id = &"slots"


func can_join(p: int) -> bool:
	return player < 0 or player == p


func join(p: int) -> Dictionary:
	if not can_join(p):
		return fail(&"seat_taken")
	player = p
	return OK_RESULT


func leave(p: int) -> void:
	if p != player:
		return
	if spinning:
		_finish_spin()
	player = -1


## Allowed bet sizes after the limits multiplier.
func bet_sizes() -> Array[int]:
	var out: Array[int] = []
	for s: int in balance.slots_bet_sizes:
		out.append(scaled(s))
	return out


func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if p != player:
		return fail(&"not_seated")
	if spinning:
		return fail(&"busy")
	var amount: int = int(bet.get("amount", 0))
	if not amount in bet_sizes():
		return fail(&"invalid_amount")
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	stake = amount
	stake_covered = last_covered
	if jackpot != null:
		jackpot.feed(amount)
	var lk: int = modifiers.get_luck(p, game_id)
	var d: LuckRng.Draw = luck.draw(lk, _random_line, func(l: Array[int]) -> float: return float(payout_multiplier(l, balance)))
	line = d.value
	spinning = true
	spin_elapsed = 0.0
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id}))
	events.append(GameEvents.make(&"round_started", {"station": station_id, "player": p}))
	if d.luck_changed:
		events.append(GameEvents.luck_flourish(p, station_id, &"lucky" if lk > 0 else &"jinxed"))
	return OK_RESULT


func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if p != player:
		return fail(&"not_seated")
	if action == &"stop":
		if not spinning or spin_elapsed < balance.slots_skip_after:
			return fail(&"too_early")
		_finish_spin()
		return OK_RESULT
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	if spinning:
		spin_elapsed += delta
		if spin_elapsed >= balance.slots_spin_time:
			_finish_spin()


func round_seconds() -> float:
	return balance.slots_spin_time


func has_stake(p: int) -> bool:
	return spinning and player == p


func auto_resolve() -> void:
	if spinning:
		_finish_spin()


## The spinning stake comes back (the jackpot keeps its feed: that was house money).
func refund_all() -> void:
	if not spinning:
		return
	var totals: Dictionary = {}
	_refund(player, stake, stake_covered, totals)
	spinning = false
	line.clear()
	stake = 0
	stake_covered = 0
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	return {"game": game_id, "player": player, "spinning": spinning, "line": line.duplicate() if not spinning else [], "stake": stake}


func _finish_spin() -> void:
	spinning = false
	spins_played += 1
	var mult: int = payout_multiplier(line, balance)
	var details: Dictionary = {"line": line.duplicate(), "multiplier_base": mult}
	_settle(player, stake, stake * mult, details)
	modifiers.consume_round(player, game_id)
	if jackpot != null and is_jackpot(line):
		var won: int = jackpot.award(economy, player, station_id, limits_multiplier)
		events.append(GameEvents.make(&"jackpot_won", {"player": player, "station": station_id, "amount": won}))


func _random_line() -> Array[int]:
	var l: Array[int] = []
	for i: int in 3:
		l.append(rng.weighted_index(balance.slots_reel_weights))
	return l


## True for three real Diamonds (wilds don't count for the jackpot).
static func is_jackpot(l: Array[int]) -> bool:
	return l[0] == Sym.DIAMOND and l[1] == Sym.DIAMOND and l[2] == Sym.DIAMOND


## Payout as a multiple of the bet for a line (§2.5): three of a kind with Clover wild (three
## Clovers pay as Diamonds), else any two Cherries, else a leftmost Cherry (push), else 0.
## Cherry counts use real cherries only.
static func payout_multiplier(l: Array[int], cfg: BalanceConfig) -> int:
	var non_wild: Array[int] = []
	var cherries: int = 0
	for s: int in l:
		if s != Sym.CLOVER:
			non_wild.append(s)
		if s == Sym.CHERRY:
			cherries += 1
	if non_wild.is_empty():
		return cfg.slots_three_pay[Sym.CLOVER]
	var first: int = non_wild[0]
	var same: bool = true
	for s: int in non_wild:
		if s != first:
			same = false
	if same:
		return cfg.slots_three_pay[first]
	if cherries >= 2:
		return cfg.slots_two_cherry_pay
	if l[0] == Sym.CHERRY:
		return cfg.slots_one_cherry_pay
	return 0


## Exact RTP and hit rate at neutral luck by enumerating every weighted line.
static func exact_rtp(cfg: BalanceConfig) -> Dictionary:
	var w: PackedInt32Array = cfg.slots_reel_weights
	var total_w: float = 0.0
	for x: int in w:
		total_w += x
	var rtp: float = 0.0
	var hit: float = 0.0
	for a: int in w.size():
		for b: int in w.size():
			for c: int in w.size():
				var p: float = (w[a] / total_w) * (w[b] / total_w) * (w[c] / total_w)
				var m: int = payout_multiplier([a, b, c] as Array[int], cfg)
				rtp += p * m
				if m > 0:
					hit += p
	return {"rtp": rtp, "hit_rate": hit}
