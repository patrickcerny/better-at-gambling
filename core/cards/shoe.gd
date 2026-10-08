class_name Shoe
extends RefCounted
## Multi-deck shoe that reshuffles once `penetration` of it has been dealt.

var decks: int
var penetration: float
var rng: SeededRng

var _cards: Array[int] = []
var _size: int = 0


func _init(p_rng: SeededRng, p_decks: int = 6, p_penetration: float = 0.75) -> void:
	rng = p_rng
	decks = p_decks
	penetration = p_penetration
	reshuffle()


## Rebuilds and shuffles the full shoe.
func reshuffle() -> void:
	_cards.clear()
	for d: int in decks:
		for c: int in 52:
			_cards.append(c)
	rng.shuffle(_cards)
	_size = _cards.size()


## Cards left.
func remaining() -> int:
	return _cards.size()


## True once the cut card has been reached (checked between rounds).
func needs_reshuffle() -> bool:
	return float(_size - _cards.size()) >= float(_size) * penetration


## Deals one card (reshuffles automatically if empty).
func draw() -> int:
	if _cards.is_empty():
		reshuffle()
	return _cards.pop_back()


## The card `draw()` will deal next, without dealing it (reshuffles first if empty, like `draw()`).
func peek() -> int:
	if _cards.is_empty():
		reshuffle()
	return _cards.back()


## Puts a card back at a random position (used for luck-rejected candidates).
func return_card(card: int) -> void:
	_cards.insert(rng.range_int(0, _cards.size()), card)


## Puts `cards` on top so they are dealt in the given order (tests and tutorial scripting).
func stack_top(cards: Array[int]) -> void:
	for i: int in range(cards.size() - 1, -1, -1):
		_cards.append(cards[i])
