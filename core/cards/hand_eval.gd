class_name HandEval
extends RefCounted
## Blackjack hand evaluation.


## Best total of a hand (aces count 11 when that doesn't bust).
static func total(cards: Array[int]) -> int:
	var sum: int = 0
	var has_ace: bool = false
	for c: int in cards:
		var v: int = Card.bj_value(c)
		sum += v
		if v == 1:
			has_ace = true
	if has_ace and sum + 10 <= 21:
		sum += 10
	return sum


## True if an ace is currently counted as 11.
static func is_soft(cards: Array[int]) -> bool:
	var hard: int = 0
	var has_ace: bool = false
	for c: int in cards:
		var v: int = Card.bj_value(c)
		hard += v
		if v == 1:
			has_ace = true
	return has_ace and hard + 10 <= 21


## Two-card 21.
static func is_blackjack(cards: Array[int]) -> bool:
	return cards.size() == 2 and total(cards) == 21


## Over 21.
static func is_bust(cards: Array[int]) -> bool:
	return total(cards) > 21


## Luck quality of a player hand (§2.7): non-bust total, bust = -1, natural blackjack = 22.
static func quality(cards: Array[int]) -> float:
	if is_blackjack(cards):
		return 22.0
	var t: int = total(cards)
	return -1.0 if t > 21 else float(t)
