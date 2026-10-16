class_name ScratchLogic
extends StationLogicBase
## Scratch-card kiosk: one player at the counter at a time (like a slot machine).
##
## Buying a card (`place_bet({tier})`, or `{amount}` = one of the card prices) takes the price and
## decides the whole card at once on the server: an outcome is drawn from the tier's odds (blank,
## a "$" or three in a line of one symbol), a blank gets the house rule's quiet second draw
## (`scratch_favour`), the player's luck rerolls the card like a slot line, and a 3×3 card that
## shows exactly that outcome is built. The card goes out in one `scratch_card` event and in the
## public state; the client only scratches the foil off. It pays (`round_result`) when the player
## has revealed it (`action reveal`), when they walk away, or after `scratch_auto_reveal` seconds.
##
## Prize rules (printed on the card, and the only thing `card_multiplier` pays by): three of a
## symbol in a row, column or diagonal pays that symbol's prize; a "$" anywhere pays the instant
## prize. Nothing about the favour or the luck reroll is shown or sent.

enum Sym { CHERRY, LEMON, BELL, CLOVER, SEVEN, DIAMOND, CASH }
const SYMBOL_NAMES: Array[StringName] = [&"cherry", &"lemon", &"bell", &"clover", &"seven", &"diamond", &"cash"]
## Symbols that can make a line (everything but the "$").
const LINE_SYMBOLS: int = 6
const CELLS: int = 9
## Rows, columns and the two diagonals, as cell indices (row-major).
const LINES: Array[Array] = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
## Outcome indices into `BalanceConfig.scratch_odds`: blank, "$", then one per line symbol.
const OUTCOME_BLANK: int = 0
const OUTCOME_CASH: int = 1
const OUTCOME_LINE0: int = 2
## Seconds a purchase needs at least: a card bought later than this before the casino closes is
## refused ("Table closing!"); a card still open when a minigame starts is refunded, at the end of
## the match it pays.
const ROUND_SECONDS: float = 6.0

var player: int = -1
## The card on the counter (9 symbols, row-major); empty when there is none.
var card: Array[int] = []
var tier: int = -1
var stake: int = 0
## Part of `stake` Fake Cash paid for.
var stake_covered: int = 0
## Seconds since the card was bought (it scratches itself at `scratch_auto_reveal`).
var card_age: float = 0.0
var cards_played: int = 0
## Cards sold here so far: tells the panel a new card from the one before (they may look alike).
var serial: int = 0
## The last card that paid, for the panel: {card, tier, stake, returned}.
var last: Dictionary = {}
## Luck changed this card: the clover / black cat shows when it pays, not when it is bought
## (that would spoil the scratching).
var _flourish: StringName = &""


func _on_setup() -> void:
	game_id = &"scratch"


func can_join(p: int) -> bool:
	return player < 0 or player == p


func join(p: int) -> Dictionary:
	if not can_join(p):
		return fail(&"seat_taken")
	player = p
	return OK_RESULT


## Walking away scratches the card for you: it was decided when it was bought.
func leave(p: int) -> void:
	if p != player:
		return
	auto_resolve()
	player = -1
	last = {}


## Card prices for the tiers after the limits multiplier, cheapest first.
func prices() -> Array[int]:
	var out: Array[int] = []
	for s: int in balance.scratch_prices:
		out.append(scaled(s))
	return out


func place_bet(p: int, bet: Dictionary) -> Dictionary:
	if p != player:
		return fail(&"not_seated")
	if not card.is_empty():
		return fail(&"card_open")
	var list: Array[int] = prices()
	var t: int = int(bet.get("tier", list.find(int(bet.get("amount", -1)))))
	if t < 0 or t >= list.size():
		return fail(&"invalid_amount")
	var amount: int = list[t]
	if not _take_stake(p, amount):
		return fail(&"insufficient_funds")
	stake = amount
	stake_covered = last_covered
	tier = t
	card_age = 0.0
	serial += 1
	var lk: int = modifiers.get_luck(p, game_id)
	var d: LuckRng.Draw = luck.draw(lk, func() -> Array[int]: return draw_card(rng, balance, t),
		func(c: Array[int]) -> float: return card_multiplier(c, t, balance))
	card = d.value
	_flourish = (&"lucky" if lk > 0 else &"jinxed") if d.luck_changed else &""
	last = {}
	events.append(GameEvents.bet_placed(p, station_id, amount, {"game": game_id, "tier": t}))
	events.append(GameEvents.make(&"scratch_card", {"station": station_id, "player": p, "tier": t, "price": amount, "serial": serial, "card": card.duplicate()}))
	return OK_RESULT


## `reveal`: the player has scratched the whole card (or pressed REVEAL ALL): it pays now.
func player_action(p: int, action: StringName, _params: Dictionary = {}) -> Dictionary:
	if p != player:
		return fail(&"not_seated")
	if action == &"reveal":
		if card.is_empty():
			return fail(&"no_card")
		_pay()
		return OK_RESULT
	return fail(&"unknown_action")


func tick(delta: float) -> void:
	if card.is_empty():
		return
	card_age += delta
	if card_age >= balance.scratch_auto_reveal:
		_pay()


func round_seconds() -> float:
	return ROUND_SECONDS


func has_stake(p: int) -> bool:
	return not card.is_empty() and player == p


func auto_resolve() -> void:
	if not card.is_empty():
		_pay()


## The open card is called off: its price comes back and the card is gone.
func refund_all() -> void:
	if card.is_empty():
		return
	var totals: Dictionary = {}
	_refund(player, stake, stake_covered, totals)
	card.clear()
	stake = 0
	stake_covered = 0
	tier = -1
	_flourish = &""
	last = {}
	_emit_refunds(totals)


func get_public_state() -> Dictionary:
	return {"game": game_id, "player": player, "card": card.duplicate(), "tier": tier, "stake": stake, "serial": serial, "last": last.duplicate(true)}


## The card is revealed: it pays what it shows (times the usual item / Hot Table / Last Call
## multipliers on the winnings).
func _pay() -> void:
	var paid: Array[int] = card.duplicate()
	var mult: float = card_multiplier(paid, tier, balance)
	var details: Dictionary = {"card": paid, "tier": tier, "lines": winning_lines(paid), "multiplier_base": mult}
	if _flourish != &"":
		events.append(GameEvents.luck_flourish(player, station_id, _flourish))
	var returned: int = _settle(player, stake, prize(stake, mult), details)
	modifiers.consume_round(player, game_id)
	cards_played += 1
	last = {"card": paid, "tier": tier, "stake": stake, "returned": returned}
	card.clear()
	stake = 0
	stake_covered = 0
	tier = -1
	_flourish = &""


## What a card pays at `price`: the printed multiple, rounded down to whole dollars.
static func prize(price: int, multiplier: float) -> int:
	return int(floor(price * multiplier + 0.000001))


## Indices into `LINES` that hold three of one line symbol.
static func winning_lines(c: Array[int]) -> Array[int]:
	var out: Array[int] = []
	if c.size() != CELLS:
		return out
	for i: int in LINES.size():
		var l: Array = LINES[i]
		var s: int = c[int(l[0])]
		if s >= 0 and s < LINE_SYMBOLS and c[int(l[1])] == s and c[int(l[2])] == s:
			out.append(i)
	return out


## Payout of a card as a multiple of its price: every line's prize plus the instant prize for each
## "$". This is the printed prize table, and the only thing the server pays by.
static func card_multiplier(c: Array[int], t: int, cfg: BalanceConfig) -> float:
	if c.size() != CELLS or t < 0 or t >= cfg.scratch_prices.size():
		return 0.0
	var pays: PackedFloat32Array = cfg.scratch_pays(t)
	var m: float = 0.0
	for i: int in winning_lines(c):
		m += pays[c[int(LINES[i][0])]]
	m += c.count(Sym.CASH) * cfg.scratch_cash_pays[t]
	return m


## One card for tier `t`: the outcome from the tier's odds, a blank drawn again once with
## `scratch_favour` chance (house rule), then the card that shows it.
static func draw_card(r: SeededRng, cfg: BalanceConfig, t: int) -> Array[int]:
	var odds: PackedInt32Array = cfg.scratch_odds(t)
	var outcome: int = r.weighted_index(odds)
	if outcome == OUTCOME_BLANK and r.chance(cfg.scratch_favour):
		outcome = r.weighted_index(odds)
	return build_card(r, outcome)


## A 3×3 card showing exactly `outcome`: blank (no line, no "$"), one "$" and no line, or three of
## one symbol on one random line (no "$"). The other cells are filled one by one with symbols that
## never finish a second line, so near misses happen but the card pays only what it shows.
static func build_card(r: SeededRng, outcome: int) -> Array[int]:
	var c: Array[int] = []
	c.resize(CELLS)
	c.fill(-1)
	if outcome == OUTCOME_CASH:
		c[r.range_int(0, CELLS - 1)] = Sym.CASH
	elif outcome >= OUTCOME_LINE0:
		var sym: int = outcome - OUTCOME_LINE0
		for cell: int in LINES[r.range_int(0, LINES.size() - 1)]:
			c[cell] = sym
	for cell: int in CELLS:
		if c[cell] >= 0:
			continue
		var allowed: Array[int] = []
		for s: int in LINE_SYMBOLS:
			if not _completes_line(c, cell, s):
				allowed.append(s)
		c[cell] = allowed[r.range_int(0, allowed.size() - 1)]
	return c


## True if putting `sym` in `cell` would finish a line of three `sym`.
static func _completes_line(c: Array[int], cell: int, sym: int) -> bool:
	for l: Array in LINES:
		if not cell in l:
			continue
		var same: int = 0
		for i: int in l:
			if i != cell and c[i] == sym:
				same += 1
		if same == 2:
			return true
	return false


## Probability of each outcome for tier `t` after the house rule's second draw for a blank.
static func outcome_probs(cfg: BalanceConfig, t: int) -> Array[float]:
	var odds: PackedInt32Array = cfg.scratch_odds(t)
	var total: float = 0.0
	for w: int in odds:
		total += w
	var p_blank: float = odds[OUTCOME_BLANK] / total
	var f: float = cfg.scratch_favour
	var out: Array[float] = []
	for i: int in odds.size():
		var p: float = odds[i] / total
		out.append(p_blank * (1.0 - f + f * p_blank) if i == OUTCOME_BLANK else p * (1.0 + p_blank * f))
	return out


## Multiple of the price an outcome pays.
static func outcome_multiplier(cfg: BalanceConfig, t: int, outcome: int) -> float:
	if outcome == OUTCOME_BLANK:
		return 0.0
	if outcome == OUTCOME_CASH:
		return cfg.scratch_cash_pays[t]
	return cfg.scratch_pays(t)[outcome - OUTCOME_LINE0]


## Exact RTP and hit rate of a tier at neutral luck with the house rule (before cents rounding).
static func exact_rtp(cfg: BalanceConfig, t: int) -> Dictionary:
	var probs: Array[float] = outcome_probs(cfg, t)
	var rtp: float = 0.0
	for i: int in probs.size():
		rtp += probs[i] * outcome_multiplier(cfg, t, i)
	return {"rtp": rtp, "hit_rate": 1.0 - probs[OUTCOME_BLANK]}
