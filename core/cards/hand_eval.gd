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


## The total as a player reads it: a soft hand under 21 shows both counts ("7 / 17", the ace as
## 1 or 11) while it is still being played; `final` (stood, settled, dealer done) shows the best only.
static func total_text(cards: Array[int], final: bool = false) -> String:
	var t: int = total(cards)
	if not final and t < 21 and is_soft(cards):
		return "%d / %d" % [t - 10, t]
	return str(t)


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
