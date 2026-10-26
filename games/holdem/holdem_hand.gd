class_name HoldemHand
extends RefCounted
## Poker hand evaluation for Casino Hold'em (pure, no state): the best five-card hand out of up to
## seven cards (`Card` ints) as one comparable score. Aces play high, and low in the wheel straight
## A-2-3-4-5.
##
## Score = category × 15^5 + the five tie-break ranks (2..14, most significant first) in base 15,
## so a higher score is always the better hand and equal scores tie. Categories, low to high: high
## card, pair, two pair, three of a kind, straight, flush, full house, four of a kind, straight
## flush, royal flush (the ace-high straight flush has a category of its own so the paytables can
## name it; it still compares as the best straight flush).

enum Rank { HIGH_CARD, PAIR, TWO_PAIR, THREE_OF_A_KIND, STRAIGHT, FLUSH, FULL_HOUSE, FOUR_OF_A_KIND, STRAIGHT_FLUSH, ROYAL_FLUSH }

const NAMES: Array[String] = ["High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush", "Full House", "Four of a Kind", "Straight Flush", "Royal Flush"]
## Rank names by poker value (2..14), one and many.
const ONE: Array[String] = ["", "", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace"]
const MANY: Array[String] = ["", "", "Twos", "Threes", "Fours", "Fives", "Sixes", "Sevens", "Eights", "Nines", "Tens", "Jacks", "Queens", "Kings", "Aces"]
const BASE: int = 15
const CATEGORY_UNIT: int = 759375  # 15^5
const ACE: int = 14


## Poker value of a card: 2..13 as printed, ace 14.
static func value(card: int) -> int:
	var r: int = Card.rank(card)
	return ACE if r == 1 else r


## The best five-card score out of `cards` (up to seven; fewer score what they hold: two queens
## alone are a pair of queens).
static func evaluate(cards: Array[int]) -> int:
	var counts := PackedInt32Array()
	counts.resize(ACE + 1)
	var suit_masks := PackedInt32Array([0, 0, 0, 0])
	var suit_counts := PackedInt32Array([0, 0, 0, 0])
	var mask: int = 0
	for c: int in cards:
		var v: int = value(c)
		var s: int = Card.suit(c)
		counts[v] += 1
		mask |= 1 << v
		suit_masks[s] |= 1 << v
		suit_counts[s] += 1
	var grouped: int = _groups_score(counts)
	# Out of seven cards a flush and a full house (or quads) can't both be made, so the order of
	# these checks is the ranking.
	for s: int in 4:
		if suit_counts[s] >= 5:
			var top: int = straight_top(suit_masks[s])
			if top == ACE:
				return Rank.ROYAL_FLUSH * CATEGORY_UNIT + _pack([ACE, 13, 12, 11, 10] as Array[int])
			if top > 0:
				return Rank.STRAIGHT_FLUSH * CATEGORY_UNIT + _pack([top] as Array[int])
			if grouped >= Rank.FULL_HOUSE * CATEGORY_UNIT:
				return grouped
			return Rank.FLUSH * CATEGORY_UNIT + _pack(_top_of_mask(suit_masks[s], 5))
	if grouped >= Rank.FULL_HOUSE * CATEGORY_UNIT:
		return grouped
	var st: int = straight_top(mask)
	if st > 0:
		return Rank.STRAIGHT * CATEGORY_UNIT + _pack([st] as Array[int])
	return grouped


## The hand's category (`Rank`) from a score.
static func category(score: int) -> int:
	return score / CATEGORY_UNIT


## The tie-break rank at `slot` (0 = most significant) of a score.
static func kicker(score: int, slot: int) -> int:
	var rest: int = score % CATEGORY_UNIT
	for i: int in 4 - slot:
		rest /= BASE
	return rest % BASE


## Top card of the best straight in a rank bitmask (bit v set for value v): 5 for the wheel, 0 for
## none.
static func straight_top(mask: int) -> int:
	var m: int = mask
	if m & (1 << ACE):
		m |= 1 << 1  # the ace plays low too
	for top: int in range(ACE, 4, -1):
		var run: int = 0b11111 << (top - 4)
		if m & run == run:
			return top
	return 0


## Quads, full houses, trips, pairs and high cards, from the rank counts.
static func _groups_score(counts: PackedInt32Array) -> int:
	var quads: int = 0
	var trips: Array[int] = []
	var pairs: Array[int] = []
	var singles: Array[int] = []
	for v: int in range(ACE, 1, -1):
		match counts[v]:
			4:
				quads = maxi(quads, v)
			3:
				trips.append(v)
			2:
				pairs.append(v)
			1:
				singles.append(v)
	if quads > 0:
		var rest: int = 0
		for v: int in range(ACE, 1, -1):
			if v != quads and counts[v] > 0:
				rest = v
				break
		return Rank.FOUR_OF_A_KIND * CATEGORY_UNIT + _pack([quads, rest] as Array[int])
	if trips.size() >= 2 or (trips.size() == 1 and not pairs.is_empty()):
		var under: int = trips[1] if trips.size() >= 2 else 0
		if not pairs.is_empty():
			under = maxi(under, pairs[0])
		return Rank.FULL_HOUSE * CATEGORY_UNIT + _pack([trips[0], under] as Array[int])
	if trips.size() == 1:
		var t: Array[int] = [trips[0]]
		t.append_array(singles.slice(0, 2))
		return Rank.THREE_OF_A_KIND * CATEGORY_UNIT + _pack(t)
	if pairs.size() >= 2:
		# A third pair's rank can be the fifth card.
		var fifth: Array[int] = singles.duplicate()
		fifth.append_array(pairs.slice(2))
		fifth.sort()
		fifth.reverse()
		var tp: Array[int] = [pairs[0], pairs[1]]
		tp.append_array(fifth.slice(0, 1))
		return Rank.TWO_PAIR * CATEGORY_UNIT + _pack(tp)
	if pairs.size() == 1:
		var p: Array[int] = [pairs[0]]
		p.append_array(singles.slice(0, 3))
		return Rank.PAIR * CATEGORY_UNIT + _pack(p)
	return Rank.HIGH_CARD * CATEGORY_UNIT + _pack(singles.slice(0, 5))


## The `n` highest ranks set in a bitmask, highest first.
static func _top_of_mask(mask: int, n: int) -> Array[int]:
	var out: Array[int] = []
	for v: int in range(ACE, 1, -1):
		if mask & (1 << v) and out.size() < n:
			out.append(v)
	return out


## Five tie-break ranks in base 15, most significant first (missing ones count as 0).
static func _pack(ranks: Array[int]) -> int:
	var out: int = 0
	for i: int in 5:
		out = out * BASE + (ranks[i] if i < ranks.size() else 0)
	return out


## "Pair of Kings", "Two Pair, Kings and Fives", "Full House, Eights over Threes", "Royal Flush".
static func describe(score: int) -> String:
	var k0: int = kicker(score, 0)
	var k1: int = kicker(score, 1)
	match category(score):
		Rank.HIGH_CARD:
			return ("%s High" % ONE[k0]) if k0 >= 2 else "High Card"
		Rank.PAIR:
			return "Pair of %s" % MANY[k0]
		Rank.TWO_PAIR:
			return "Two Pair, %s and %s" % [MANY[k0], MANY[k1]]
		Rank.THREE_OF_A_KIND:
			return "Three %s" % MANY[k0]
		Rank.STRAIGHT:
			return "Straight, %s High" % ONE[k0]
		Rank.FLUSH:
			return "Flush, %s High" % ONE[k0]
		Rank.FULL_HOUSE:
			return "Full House, %s over %s" % [MANY[k0], MANY[k1]]
		Rank.FOUR_OF_A_KIND:
			return "Four %s" % MANY[k0]
		Rank.STRAIGHT_FLUSH:
			return "Straight Flush, %s High" % ONE[k0]
	return "Royal Flush"


## A category's name ("Flush"), for the paytables and the feed.
static func category_name(cat: int) -> String:
	return NAMES[clampi(cat, 0, NAMES.size() - 1)]


## The five cards of `cards` that make its best hand, in the order given (all of them when there
## are five or fewer). Tries the 21 ways to pick five of seven: for the felt and the overlay only.
static func best_five(cards: Array[int]) -> Array[int]:
	if cards.size() <= 5:
		return cards.duplicate()
	var want: int = evaluate(cards)
	var n: int = cards.size()
	for a: int in n:
		for b: int in range(a + 1, n):
			for c: int in range(b + 1, n):
				for d: int in range(c + 1, n):
					for e: int in range(d + 1, n):
						var five: Array[int] = [cards[a], cards[b], cards[c], cards[d], cards[e]]
						if evaluate(five) == want:
							return five
	return []


## Casino Hold'em: the dealer plays only with a pair of fours or better.
static func dealer_qualifies(score: int) -> bool:
	var cat: int = category(score)
	return cat >= Rank.TWO_PAIR or (cat == Rank.PAIR and kicker(score, 0) >= 4)


## Four cards of one suit among `cards` (a flush draw).
static func has_flush_draw(cards: Array[int]) -> bool:
	var suits := PackedInt32Array([0, 0, 0, 0])
	for c: int in cards:
		suits[Card.suit(c)] += 1
	for s: int in 4:
		if suits[s] >= 4:
			return true
	return false


## Four different ranks inside one five-rank window: an open-ended or inside straight draw (the
## ace counts high and low).
static func has_straight_draw(cards: Array[int]) -> bool:
	var m: int = 0
	for c: int in cards:
		m |= 1 << value(c)
	if m & (1 << ACE):
		m |= 1 << 1
	for low: int in range(1, 11):
		var window: int = (m >> low) & 0b11111
		var bits: int = 0
		for i: int in 5:
			bits += (window >> i) & 1
		if bits >= 4:
			return true
	return false
