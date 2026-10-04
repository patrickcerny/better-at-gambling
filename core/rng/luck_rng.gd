class_name LuckRng
extends RefCounted
## Luck as rerolls (§2.7). With luck L > 0, with probability `reroll_per_point * L` a second
## candidate is drawn and the higher-quality one kept; L < 0 keeps the lower one. L = 0 never
## rerolls. Luck is clamped to ±`clamp_abs`.

## Result of a `draw`.
class Draw:
	extends RefCounted
	## The outcome that counts.
	var value: Variant
	## True if a second candidate was drawn.
	var rerolled: bool = false
	## True if the reroll changed the outcome (UI shows a clover / black cat flourish).
	var luck_changed: bool = false
	## The candidate that was thrown away (null if no reroll); e.g. a card to return to the shoe.
	var rejected: Variant = null

var rng: SeededRng
var reroll_per_point: float
var clamp_abs: int


func _init(p_rng: SeededRng, p_reroll_per_point: float = 0.12, p_clamp_abs: int = 3) -> void:
	rng = p_rng
	reroll_per_point = p_reroll_per_point
	clamp_abs = p_clamp_abs


## Clamps a raw luck sum into the allowed range.
func clamp_luck(luck: int) -> int:
	return clampi(luck, -clamp_abs, clamp_abs)


## Probability that a draw at this luck rerolls.
func reroll_chance(luck: int) -> float:
	return reroll_per_point * absi(clamp_luck(luck))


## Draws `generator.call()`; may reroll per luck, comparing `quality.call(value) -> float`.
## Ties keep the first draw, so a reroll never gives a lucky player a worse result.
func draw(luck: int, generator: Callable, quality: Callable) -> Draw:
	var d := Draw.new()
	d.value = generator.call()
	var l: int = clamp_luck(luck)
	if l == 0 or not rng.chance(reroll_chance(l)):
		return d
	var second: Variant = generator.call()
	d.rerolled = true
	var q1: float = quality.call(d.value)
	var q2: float = quality.call(second)
	var take_second: bool = q2 > q1 if l > 0 else q2 < q1
	if take_second:
		d.rejected = d.value
		d.value = second
		d.luck_changed = true
	else:
		d.rejected = second
	return d
