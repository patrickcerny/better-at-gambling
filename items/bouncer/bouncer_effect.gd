class_name BouncerEffect
extends ModifierItemEffect
## Bouncer (§2.8): a bouncer hauls a seated player off their seat and they can't sit anywhere for
## `def.duration` seconds (the `bounced` flag; the server's sit check reads it). Their open bets
## are handled exactly as if they had stood up themselves (a running round settles normally).
## Simplest reading of the spec: the throw happens at once (no NPC walk-up); the client shows it
## as a short knockdown.


func can_activate(ctx: ItemContext) -> StringName:
	return &"" if ctx.system.rules.status(ctx.target).seated else &"not_seated"


func activate(ctx: ItemContext) -> Dictionary:
	var sys: ItemSystem = ctx.system
	sys.pull_off_seat(ctx.target)
	sys.knock_down(ctx.target, float(ctx.param("stun", 1.0)), ctx.user, &"bouncer", ctx.now)
	var out: Dictionary = super.activate(ctx)
	out["bounced"] = ctx.target
	return out
