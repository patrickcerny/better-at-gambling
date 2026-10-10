class_name RobinHoodEffect
extends ItemEffect
## Robin Hood (§2.8): takes `pct` of the current leader's money (at most `max`) and splits it
## equally among every other present player, the user included. The ItemSystem picks the leader
## (richest other player) and refuses when the user leads. Money only moves between players; the
## few dollars that don't split evenly stay with the leader.


func can_activate(ctx: ItemContext) -> StringName:
	return &"target_broke" if ctx.system.economy.balance(ctx.target) <= 0 else &""


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	var eco: Economy = sys.economy
	var rich: int = ctx.target
	var amount: int = mini(mini(int(floor(eco.balance(rich) * float(ctx.param("pct", 0.08)))), int(ctx.param("max", 800))), eco.balance(rich))
	var others: Array[int] = recipients(sys, rich)
	if others.is_empty() or amount <= 0:
		return {"leader": rich, "amount": 0, "share": 0}
	var share: int = amount / others.size()
	if share <= 0:
		return {"leader": rich, "amount": 0, "share": 0}
	eco.apply(rich, -share * others.size(), &"item_robin_hood", ctx.def.id)
	for pid: int in others:
		eco.apply(pid, share, &"item_robin_hood", ctx.def.id)
	return {"leader": rich, "amount": share * others.size(), "share": share, "to": others}


## Everyone present except the robbed player, by id.
static func recipients(sys: ItemSystem, rich: int) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = sys.players.keys()
	ids.sort()
	for id: int in ids:
		if id != rich and sys.players[id].connected:
			out.append(id)
	return out
