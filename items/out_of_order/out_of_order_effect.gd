class_name OutOfOrderEffect
extends ItemEffect
## Out of Order sign (Patrick's "game disabler"): hang it on the nearest open table or machine
## (within `range` m). The game there stops, every open bet is refunded, the players there stand
## up, and nobody can sit or bet there until the next minigame (Patrick 0.9.71). A `duration` > 0
## in the definition closes it for that many seconds instead.


func can_activate(ctx: ItemContext) -> StringName:
	if not ctx.system.find_station.is_valid():
		return &"not_supported"
	return &"" if ctx.system.find_station.call(ctx.user, float(ctx.param("range", 4.0))) != &"" else &"no_station"


func activate(ctx: ItemContext) -> Dictionary:
	var sid: StringName = ctx.system.find_station.call(ctx.user, float(ctx.param("range", 4.0)))
	var seconds: float = ctx.def.duration if ctx.def.duration > 0.0 else INF
	ctx.system.close_station.call(sid, seconds)
	return {"station": sid, "seconds": seconds if is_finite(seconds) else -1.0}
