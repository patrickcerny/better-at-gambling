class_name CardFace
extends Control
## One playing card drawn in code: a rounded cream card with a dark border, the rank in two
## corners and the suit glyph big in the centre (red for hearts/diamonds, near-black for
## spades/clubs). `card` < 0 (or `face_up` false) draws the back: casino red with a gold inlay.
## Size comes from `custom_minimum_size`; everything scales with the card's height.

const SUIT_GLYPHS: Array[String] = ["♠", "♥", "♦", "♣"]
## Width / height of a real playing card.
const ASPECT: float = 0.714

## Card int (see `Card`), or -1 for an unknown card (drawn face down).
var card: int = -1:
	set(v):
		card = v
		queue_redraw()
## False draws the back even for a known card.
var face_up: bool = true:
	set(v):
		face_up = v
		queue_redraw()
## Dimmed, e.g. a busted hand.
var dimmed: bool = false:
	set(v):
		dimmed = v
		queue_redraw()

## Deal / flip animation progress, 0 → 1 (applied in `_draw`, since containers reset `scale`).
var deal_t: float = 1.0:
	set(v):
		deal_t = v
		queue_redraw()
var flip_t: float = 1.0:
	set(v):
		flip_t = v
		queue_redraw()

var _font: Font
var _tween: Tween


## A card face `height` pixels tall (width from the real card aspect).
static func make(p_card: int, height: float) -> CardFace:
	var f := CardFace.new()
	f.card = p_card
	f.custom_minimum_size = Vector2(roundf(height * ASPECT), height)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _ready() -> void:
	_font = get_theme_default_font()
	resized.connect(queue_redraw)


## True when the face (not the back) is drawn.
func is_face_up() -> bool:
	return face_up and card >= 0


## "A♠", "10♥" … or "" for a card shown face down.
func text() -> String:
	if not is_face_up():
		return ""
	return Card.RANK_NAMES[Card.rank(card)] + SUIT_GLYPHS[Card.suit(card)]


## Slides the card in from above and scales it up; `delay` staggers several cards. Purely
## visual: `card` is set right away, so state reads are never behind the animation.
func deal_in(delay: float = 0.0) -> void:
	if not is_inside_tree():
		return
	_restart_tween()
	deal_t = 0.0
	_tween.tween_property(self, "deal_t", 1.0, 0.4).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A card-flip (squash and stretch on x) when the card changes in place (the shared next card).
func flip_in() -> void:
	if not is_inside_tree():
		return
	_restart_tween()
	flip_t = 0.0
	_tween.tween_property(self, "flip_t", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _restart_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	deal_t = 1.0
	flip_t = 1.0
	_tween = create_tween()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	# Deal / flip animation: scale around the centre, slide down from above while dealing.
	var t: float = clampf(deal_t, 0.0, 1.2)
	var grow: float = lerpf(0.55, 1.0, t)
	var centre: Vector2 = size * 0.5 + Vector2(0.0, -(1.0 - minf(t, 1.0)) * size.y * 0.6)
	var base := Transform2D(0.0, Vector2(grow * maxf(flip_t, 0.04), grow), 0.0, centre) * Transform2D(0.0, -size * 0.5)
	draw_set_transform_matrix(base)
	var h: float = r.size.y
	var radius: int = int(maxf(h * 0.07, 3.0))
	var border: int = int(maxf(h * 0.02, 1.0))
	var dim: float = 0.4 if dimmed else 0.0

	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(radius)
	box.set_border_width_all(border)
	box.border_color = Palette.CASINO_BLACK
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = int(maxf(h * 0.03, 2.0))
	box.shadow_offset = Vector2(0, h * 0.015)
	if not is_face_up():
		box.bg_color = Palette.CASINO_RED.darkened(0.2 + dim)
		draw_style_box(box, r)
		var inlay := StyleBoxFlat.new()
		inlay.draw_center = false
		inlay.set_corner_radius_all(maxi(radius - 2, 2))
		inlay.set_border_width_all(maxi(border, 2))
		inlay.border_color = Palette.WARM_GOLD.darkened(0.15 + dim)
		var m: float = h * 0.08
		draw_style_box(inlay, r.grow(-m))
		if _font != null:
			var fs: int = int(h * 0.3)
			draw_string(_font, Vector2(0, h * 0.5 + fs * 0.35), "♦", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Palette.WARM_GOLD.darkened(0.15 + dim))
		return

	box.bg_color = Palette.CREAM.darkened(dim)
	draw_style_box(box, r)
	if _font == null:
		return
	var suit: int = Card.suit(card)
	var ink: Color = (Palette.CASINO_RED if suit == 1 or suit == 2 else Palette.CASINO_BLACK).lightened(dim * 0.6)
	var rank_text: String = Card.RANK_NAMES[Card.rank(card)]
	var glyph: String = SUIT_GLYPHS[suit]
	var w: float = r.size.x
	var pad: float = w * 0.08
	var corner_fs: int = maxi(int(h * 0.2), 8)
	var corner_w: float = w * 0.5
	# Top-left rank + small suit.
	draw_string(_font, Vector2(pad, pad + corner_fs * 0.85), rank_text, HORIZONTAL_ALIGNMENT_LEFT, corner_w, corner_fs, ink)
	draw_string(_font, Vector2(pad, pad + corner_fs * 1.65), glyph, HORIZONTAL_ALIGNMENT_LEFT, corner_w, int(corner_fs * 0.75), ink)
	# Bottom-right rank, upside down like a real card.
	draw_set_transform_matrix(base * Transform2D(PI, r.size))
	draw_string(_font, Vector2(pad, pad + corner_fs * 0.85), rank_text, HORIZONTAL_ALIGNMENT_LEFT, corner_w, corner_fs, ink)
	draw_string(_font, Vector2(pad, pad + corner_fs * 1.65), glyph, HORIZONTAL_ALIGNMENT_LEFT, corner_w, int(corner_fs * 0.75), ink)
	draw_set_transform_matrix(base)
	# Big centre suit.
	var big_fs: int = int(h * 0.42)
	draw_string(_font, Vector2(0, h * 0.5 + big_fs * 0.35), glyph, HORIZONTAL_ALIGNMENT_CENTER, w, big_fs, ink)
