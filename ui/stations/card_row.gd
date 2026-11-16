class_name CardRow
extends HBoxContainer
## A fanned row of drawn playing cards (`CardFace`) for the card tables' overlays. Redraws only
## when the cards change; a new card deals in. -1 shows a card face down (the dealer's hole card).

## A peeked face-down card (Sunglasses) is kept in `_shown` as PEEKED + card.
const PEEKED: int = 100
## How see-through a peeked card is drawn.
const PEEK_ALPHA: float = 0.5

var card_height: float = 76.0
var _shown: Array = []
## Gold underline under the row (the hand you are playing).
var active: bool = false:
	set(v):
		active = v
		queue_redraw()


func _init(p_height: float = 76.0) -> void:
	card_height = p_height
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", -int(p_height * 0.16))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, p_height)


## Shows `cards` (card ints; -1 = face down); `dim` greys them (bust, folded). `peek` (Sunglasses)
## fills the face-down cards in order: their faces show half see-through.
func show_cards(cards: Array, dim: bool = false, peek: Array = []) -> void:
	var ints: Array = []
	var down: int = 0
	for c: Variant in cards:
		if int(c) < 0 and down < peek.size():
			ints.append(PEEKED + int(peek[down]))
		else:
			ints.append(int(c))
		if int(c) < 0:
			down += 1
	if ints != _shown:
		var old: Array = _shown
		var keep: int = 0
		while keep < old.size() and keep < ints.size() and int(old[keep]) == int(ints[keep]):
			keep += 1
		var kids: Array[Node] = get_children()
		for i: int in range(kids.size() - 1, keep - 1, -1):
			remove_child(kids[i])
			kids[i].queue_free()
		for i: int in range(keep, ints.size()):
			var c: int = int(ints[i])
			var f: CardFace = CardFace.make(c - PEEKED if c >= PEEKED else c, card_height)
			if c >= PEEKED:
				f.name = "Peek%d" % i
				f.modulate.a = PEEK_ALPHA
			add_child(f)
			f.deal_in(0.08 * (i - keep))
		_shown = ints
	for ch: Node in get_children():
		(ch as CardFace).dimmed = dim


func _draw() -> void:
	if active and get_child_count() > 0:
		var first: Control = get_child(0) as Control
		var last: Control = get_child(get_child_count() - 1) as Control
		var y: float = size.y + 5.0
		draw_line(Vector2(first.position.x, y), Vector2(last.position.x + last.size.x, y), Palette.VIP_GOLD, 3.0, true)
		TableSkin.diamond(self, Vector2((first.position.x + last.position.x + last.size.x) * 0.5, y), 5.0, Palette.VIP_GOLD)
