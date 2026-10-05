class_name OutOfOrderEffect
extends ItemEffect
## Out of Order sign (Patrick's "game disabler"): hang it on the nearest table or machine (within
## `range` m) and nobody can sit down or bet there for `def.duration` s. Rounds already running
## finish normally.


func can_activate(ctx: ItemContext) -> StringName:
	if not ctx.system.find_station.is_valid():
		return &"not_supported"
	return &"" if ctx.system.find_station.call(ctx.user, float(ctx.param("range", 4.0))) != &"" else &"no_station"


func activate(ctx: ItemContext) -> Dictionary:
	var sid: StringName = ctx.system.find_station.call(ctx.user, float(ctx.param("range", 4.0)))
	ctx.system.close_station.call(sid, ctx.def.duration)
	return {"station": sid, "seconds": ctx.def.duration}
