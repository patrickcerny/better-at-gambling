class_name ModifierItemEffect
extends ItemEffect
## Items that are one ModifierStack entry on their target (Lucky Clover, Black Cat, Hot Hands,
## Loaded Reels, Double Trouble, Golden Chip, Bodyguard, Mirror, Spring Glove). Tuned in the
## item's `params`: `luck`, `game` (one game only), `rounds` (uses), `payout_multiplier`,
## `consume_on_win`, `refund_on_loss`, `flags` (names other systems look for) and `segment_end`
## (also runs out when the casino segment closes). `def.duration` is the time limit (0 = none).
## Using the same item again stacks (luck stays clamped to ±3).


func activate(ctx: ItemContext) -> Dictionary:
	var m := Modifier.new()
	m.id = ctx.def.id
	m.source_player = ctx.user
	m.game_id = StringName(ctx.param("game", ""))
	m.luck = int(ctx.param("luck", 0))
	m.payout_multiplier = float(ctx.param("payout_multiplier", 1.0))
	m.consume_on_win = bool(ctx.param("consume_on_win", false))
	m.refund_on_loss = bool(ctx.param("refund_on_loss", false))
	m.rounds_left = int(ctx.param("rounds", -1))
	if ctx.def.duration > 0.0:
		m.expires_at = ctx.now + ctx.def.duration
	for f: Variant in ctx.param("flags", []):
		m.flags[StringName(f)] = true
	if bool(ctx.param("segment_end", false)):
		m.flags[&"segment_end"] = true
	ctx.system.modifiers.add(ctx.target, m)
	return {"affected": ctx.target, "seconds": ctx.def.duration, "uses": m.rounds_left, "luck": m.luck}
