class_name BananaPeelEffect
extends ItemEffect
## Banana Peel (§2.8): dropped at your feet for `def.duration` seconds; the `ItemSystem` watches
## who steps on it (first other player slips, spills chips and is stunned).


func can_activate(ctx: ItemContext) -> StringName:
	return &"seated" if ctx.system.rules.status(ctx.user).seated else &""


func activate(ctx: ItemContext) -> Dictionary:
	var pos: Vector3 = ctx.system.world.get_position(ctx.user)
	var id: int = ctx.system.place_peel(ctx.user, pos, ctx.now, ctx.def.duration)
	return {"peel": id, "pos": Serializer.vec3(pos)}
