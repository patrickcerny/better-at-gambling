class_name PlinkoSteering
extends RefCounted
## Server-steered Plinko (§2.5.4 / M2): the logic has already chosen the landing slot; this builds
## a believable peg-to-peg path that ends exactly there. Pure maths, no nodes. The visual chip
## plays the path back; the money never depends on the physics.
##
## Positions are in slot units (0 .. slots-1). Every peg row moves the chip exactly half a slot
## left or right, like a real board: a constrained random walk that always keeps the target
## reachable, so the last bounce lands on the chosen slot.

## Builds a path of `rows` + 1 positions ending at `target_slot`. The start is the middle of
## the board, nudged half a slot (toward `start_bias`'s sign) when parity requires it.
static func path_to_slot(rows: int, slots: int, target_slot: int, rng: SeededRng, start_bias: float = 0.0) -> Array[float]:
	var max_h: int = (slots - 1) * 2  # positions in half-slot units
	var target: int = clampi(target_slot, 0, slots - 1) * 2
	var h: int = slots - 1  # middle of the board, in half slots
	if (h + rows - target) % 2 != 0:
		h += 1 if start_bias >= 0.0 else -1  # fix parity so the target is reachable
	h = clampi(h, 0, max_h)
	var out: Array[float] = [h * 0.5]
	for r: int in rows:
		var left: int = rows - r
		var need: int = target - h
		var toward: int = signi(need)
		var step: int
		if absi(need) >= left:
			step = toward  # no slack left: every remaining bounce goes toward the target
		else:
			var p_toward: float = 0.5 + 0.5 * float(absi(need)) / float(left)
			if toward == 0:
				step = 1 if rng.chance(0.5) else -1
			else:
				step = toward if rng.chance(p_toward) else -toward
			if h + step < 0 or h + step > max_h:
				step = -step  # bounce off the rail
		h += step
		out.append(h * 0.5)
	return out

