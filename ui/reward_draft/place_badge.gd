class_name PlaceBadge
extends Control
## A placement medallion for the round results (`RewardPanel`): a round coin with a milled rim and
## the place written in it ("1" big, "ST" small). Gold, silver and bronze for the podium places,
## dark walnut with a brass rim for everyone else. Drawn in code, so it stays sharp at any size.

const GOLD: Array[Color] = [Color("#F0C75E"), Color("#9C6F1E"), Color("#FFF0B8")]
const SILVER: Array[Color] = [Color("#C9CDD2"), Color("#6E747C"), Color("#F4F6F8")]
const BRONZE: Array[Color] = [Color("#C7814A"), Color("#6D3F1F"), Color("#F1C29A")]

var place: int = 1


static func make(p_place: int, px: float = 64.0) -> PlaceBadge:
	var b := PlaceBadge.new()
	b.place = p_place
	b.custom_minimum_size = Vector2(px, px)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## [face, rim, shine] for place `p`, or empty for a plain (walnut) badge.
static func metal(p: int) -> Array[Color]:
	match p:
		1:
			return GOLD
		2:
			return SILVER
		3:
			return BRONZE
	return []


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 2.0
	var m: Array[Color] = metal(place)
	var face: Color = m[0] if not m.is_empty() else TableSkin.WALNUT_LIGHT
	var rim: Color = m[1] if not m.is_empty() else TableSkin.BRASS_DARK
	var shine: Color = m[2] if not m.is_empty() else TableSkin.BRASS
	draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.45))  # drop shadow
	draw_circle(c, r, rim)
	# Milled edge: little notches round the rim.
	for k: int in 28:
		var a: float = TAU * k / 28.0
		draw_line(c + Vector2(cos(a), sin(a)) * (r - 1.0), c + Vector2(cos(a), sin(a)) * (r - 4.5), Color(shine, 0.35), 1.5, true)
	draw_circle(c, r * 0.8, face)
	draw_arc(c, r * 0.8, 0, TAU, 48, Color(rim, 0.9), 1.5, true)
	# Light from above: a soft crescent on the upper half of the face.
	draw_arc(c, r * 0.66, PI * 1.15, PI * 1.85, 24, Color(shine, 0.55), maxf(r * 0.08, 1.5), true)
	var ink: Color = Color("#3A2410") if not m.is_empty() else Palette.CREAM
	var num: String = str(place)
	var suffix: String = Hud._ordinal(place).substr(num.length()).to_upper()
	var big: Font = TableSkin.black_font()
	var small: Font = TableSkin.heavy_font()
	var big_size: int = int(r * 0.95)
	var small_size: int = int(r * 0.42)
	var w_big: float = big.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size).x
	var w_small: float = small.get_string_size(suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
	var x0: float = c.x - (w_big + w_small + 1.0) * 0.5
	var base: float = c.y + big.get_ascent(big_size) * 0.36
	draw_string(big, Vector2(x0, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, ink)
	draw_string(small, Vector2(x0 + w_big + 1.0, base - big.get_ascent(big_size) * 0.42), suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, ink)
