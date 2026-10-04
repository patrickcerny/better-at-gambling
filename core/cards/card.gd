class_name Card
extends RefCounted
## Cards are plain ints 0..51 for speed and easy serialization:
## rank = card % 13 + 1 (1 = Ace … 13 = King), suit = card / 13 (0 ♠, 1 ♥, 2 ♦, 3 ♣).

const RANK_NAMES: Array[String] = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUIT_NAMES: Array[String] = ["S", "H", "D", "C"]


## Card int from rank (1..13) and suit (0..3).
static func make(rank: int, suit: int = 0) -> int:
	return suit * 13 + (rank - 1)


## Rank 1 (Ace) .. 13 (King).
static func rank(card: int) -> int:
	return card % 13 + 1


## Suit 0..3.
static func suit(card: int) -> int:
	return card / 13


## Blackjack value with Ace = 1 (soft handling is in HandEval).
static func bj_value(card: int) -> int:
	return mini(rank(card), 10)


## Short label like "AS", "10H".
static func label(card: int) -> String:
	return RANK_NAMES[rank(card)] + SUIT_NAMES[suit(card)]
