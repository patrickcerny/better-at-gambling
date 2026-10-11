class_name PokerHand
extends RefCounted
## A small poker hand evaluator for Grab Your Hand: 0 to 5 cards (`Card` ints) → a comparable rank
## tuple `[category, tie-breakers...]`. Bigger tuples win (`compare`). Aces play high (14), and low
## only in the wheel straight A-2-3-4-5 (which ranks as a 5-high straight).
## - Straights and flushes need all 5 cards; pairs, two pair, trips and quads work with fewer (a
##   4-card hand can hold two pair, a 3-card hand trips).
## - Tie-breakers are ranks, most important first: the groups by size, then the kickers by rank.
##   A hand with more kickers beats the same hand with fewer ("then the highest card"): pair of
##   kings with a 9 beats a bare pair of kings. Suits never break a tie.
## - No cards: `[-1]`, below every hand.

enum Category { HIGH_CARD, PAIR, TWO_PAIR, THREE_OF_A_KIND, STRAIGHT, FLUSH, FULL_HOUSE, FOUR_OF_A_KIND, STRAIGHT_FLUSH }

const NO_HAND: int = -1
const NAMES: Array[String] = ["HIGH CARD", "PAIR", "TWO PAIR", "THREE OF A KIND", "STRAIGHT", "FLUSH", "FULL HOUSE", "FOUR OF A KIND", "STRAIGHT FLUSH"]
const WORDS: Array[String] = ["", "", "2", "3", "4", "5", "6", "7", "8", "9", "10", "JACK", "QUEEN", "KING", "ACE"]
const PLURAL: Array[String] = ["", "", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "SEVENS", "EIGHTS", "NINES", "TENS", "JACKS", "QUEENS", "KINGS", "ACES"]


## Poker rank of a card: 2..14 (the ace is 14).
static func high_rank(card: int) -> int:
	var r: int = Card.rank(card)
	return 14 if r == 1 else r


## The rank tuple of `cards` (1–5 Card ints; more than 5 uses only the first 5).
static func evaluate(cards: Array) -> Array[int]:
	var hand: Array[int] = []
	for c: Variant in cards:
		if hand.size() < 5:
			hand.append(int(c))
	if hand.is_empty():
		return [NO_HAND]
	# Count ranks, then order the groups: bigger groups first, higher ranks first inside a size.
	var counts: Dictionary[int, int] = {}
	for c: int in hand:
		var r: int = high_rank(c)
		counts[r] = counts.get(r, 0) + 1
	var groups: Array = []
	for r: int in counts:
		groups.append([counts[r], r])
	groups.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] > b[1])
	var order: Array[int] = []
	for g: Array in groups:
		order.append(int(g[1]))
	var most: int = int(groups[0][0])
	if hand.size() == 5:
		var flush: bool = true
		for c: int in hand:
			flush = flush and Card.suit(c) == Card.suit(hand[0])
		var top: int = _straight_top(counts)
		if flush and top > 0:
			return [Category.STRAIGHT_FLUSH, top]
		if most == 4:
			return _tuple(Category.FOUR_OF_A_KIND, order)
		if most == 3 and int(groups[1][0]) == 2:
			return _tuple(Category.FULL_HOUSE, order)
		if flush:
			return _tuple(Category.FLUSH, order)
		if top > 0:
			return [Category.STRAIGHT, top]
	match most:
		4:
			return _tuple(Category.FOUR_OF_A_KIND, order)
		3:
			return _tuple(Category.THREE_OF_A_KIND, order)
		2:
			return _tuple(Category.TWO_PAIR if groups.size() > 1 and int(groups[1][0]) == 2 else Category.PAIR, order)
	return _tuple(Category.HIGH_CARD, order)


## -1, 0 or 1: how tuple `a` compares with tuple `b` (element by element; a longer tuple wins
## when one is a prefix of the other).
static func compare(a: Array, b: Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if int(a[i]) != int(b[i]):
			return 1 if int(a[i]) > int(b[i]) else -1
	if a.size() == b.size():
		return 0
	return 1 if a.size() > b.size() else -1


## Compares two hands of cards directly.
static func compare_cards(a: Array, b: Array) -> int:
	return compare(evaluate(a), evaluate(b))


## "TWO PAIR", "ROYAL FLUSH", "NO CARDS" for a rank tuple.
static func name_of(tuple: Array) -> String:
	if tuple.is_empty() or int(tuple[0]) == NO_HAND:
		return "NO CARDS"
	var cat: int = int(tuple[0])
	if cat == Category.STRAIGHT_FLUSH and tuple.size() > 1 and int(tuple[1]) == 14:
		return "ROYAL FLUSH"
	return NAMES[cat]


## A longer line: "PAIR OF KINGS", "ACE HIGH", "FULL HOUSE, SEVENS OVER THREES".
static func describe(tuple: Array) -> String:
	if tuple.is_empty() or int(tuple[0]) == NO_HAND:
		return "NO CARDS"
	var cat: int = int(tuple[0])
	var r: int = int(tuple[1]) if tuple.size() > 1 else 0
	match cat:
		Category.HIGH_CARD:
			return "%s HIGH" % WORDS[r]
		Category.PAIR:
			return "PAIR OF %s" % PLURAL[r]
		Category.TWO_PAIR:
			return "TWO PAIR, %s AND %s" % [PLURAL[r], PLURAL[int(tuple[2])]]
		Category.THREE_OF_A_KIND:
			return "THREE %s" % PLURAL[r]
		Category.FOUR_OF_A_KIND:
			return "FOUR %s" % PLURAL[r]
		Category.FULL_HOUSE:
			return "FULL HOUSE, %s OVER %s" % [PLURAL[r], PLURAL[int(tuple[2])]]
		Category.STRAIGHT, Category.FLUSH, Category.STRAIGHT_FLUSH:
			var n: String = name_of(tuple)
			return n if n == "ROYAL FLUSH" else "%s, %s HIGH" % [n, WORDS[r]]
	return name_of(tuple)


## Index of the card whose loss hurts the hand least (what the drop button lets go by default):
## the hand left over is the best; on a tie the lowest card goes. -1 for an empty hand.
static func worst_index(cards: Array) -> int:
	var best: int = -1
	var best_rest: Array[int] = []
	for i: int in cards.size():
		var rest: Array = cards.duplicate()
		rest.remove_at(i)
		var t: Array[int] = evaluate(rest)
		if best < 0:
			best = i
			best_rest = t
			continue
		var cmp: int = compare(t, best_rest)
		if cmp > 0 or (cmp == 0 and high_rank(int(cards[i])) < high_rank(int(cards[best]))):
			best = i
			best_rest = t
	return best


## A card in words for feeds and prompts (the UI font has no suit glyphs): "KING OF HEARTS".
static func card_name(card: int) -> String:
	const RANKS: Array[String] = ["", "ACE", "2", "3", "4", "5", "6", "7", "8", "9", "10", "JACK", "QUEEN", "KING"]
	const SUITS: Array[String] = ["SPADES", "HEARTS", "DIAMONDS", "CLUBS"]
	return "%s OF %s" % [RANKS[Card.rank(card)], SUITS[Card.suit(card)]]


## The top rank of the straight in `counts` (5 distinct ranks in a row; the wheel is 5), else 0.
static func _straight_top(counts: Dictionary[int, int]) -> int:
	if counts.size() != 5:
		return 0
	var ranks: Array[int] = []
	for r: int in counts:
		ranks.append(r)
	ranks.sort()
	if ranks[4] - ranks[0] == 4:
		return ranks[4]
	if ranks[0] == 2 and ranks[3] == 5 and ranks[4] == 14:  # the wheel: A-2-3-4-5
		return 5
	return 0


static func _tuple(cat: int, order: Array[int]) -> Array[int]:
	var out: Array[int] = [cat]
	out.append_array(order)
	return out
