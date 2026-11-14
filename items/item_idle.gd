class_name ItemIdle
extends Node
## The idle animation of an item model (`ItemArt`, `ItemModels`): a list of tracks, each moving one
## part of the model on its own (a tail that sways, reels that spin, a flame that flickers). It runs
## while the model is on screen, from a random start so two copies never move in step. Every track
## starts from the part's transform at `add` time, so a part animates around where the recipe put it.
## Never animate the model's root: `ItemModels.make` scales and centres that one.

## How a track moves its part (`amount`, `speed` and `axis` mean what the comment says).
enum Kind {
	SWING,  ## turns back and forth about `axis` by up to `amount` radians, `speed` rad/s of phase
	SPIN,  ## turns about `axis` at `speed` rad/s (`amount` unused)
	BOB,  ## moves back and forth along `axis` by up to `amount`
	PULSE,  ## scales along `axis` by 1 ± `amount` (Vector3.ONE scales evenly)
	RISE,  ## moves `amount` along `axis` once every 1/`speed` s, growing in and shrinking out
	FLICKER,  ## a flame: scales up and down irregularly by about `amount`, mostly along `axis`
	BLINK,  ## eyes: squashed flat along `axis` for a moment every `speed` seconds
	SLIDE,  ## a glint: sweeps from -`amount` to +`amount` along `axis` every 1/`speed` s
}

var _tracks: Array[Dictionary] = []
var _t: float = 0.0


func _init() -> void:
	name = "Idle"
	_t = randf() * 40.0


## Animates `node` (a part inside the model). `phase` offsets it against the item's other tracks.
func add(node: Node3D, kind: Kind, amount: float, speed: float, axis: Vector3 = Vector3.UP, phase: float = 0.0) -> void:
	_tracks.append({"node": node, "kind": kind, "amount": amount, "speed": speed,
		"axis": axis.normalized() if kind != Kind.PULSE else axis, "phase": phase, "base": node.transform})


func track_count() -> int:
	return _tracks.size()


func _process(delta: float) -> void:
	var host: Node3D = get_parent() as Node3D
	if host == null or not host.is_visible_in_tree():
		return
	_t += delta
	pose(_t)


## Puts every part where it is `t` seconds into the loop (also for screenshots and tests).
func pose(t: float) -> void:
	for tr: Dictionary in _tracks:
		var n: Node3D = tr["node"]
		if not is_instance_valid(n):
			continue
		var base: Transform3D = tr["base"]
		var a: float = tr["amount"]
		var s: float = tr["speed"]
		var ax: Vector3 = tr["axis"]
		var ph: float = tr["phase"]
		match int(tr["kind"]):
			Kind.SWING:
				n.transform = Transform3D(base.basis * Basis(ax, a * sin(t * s + ph)), base.origin)
			Kind.SPIN:
				n.transform = Transform3D(base.basis * Basis(ax, fmod(t * s + ph, TAU)), base.origin)
			Kind.BOB:
				n.transform = Transform3D(base.basis, base.origin + base.basis * ax * a * sin(t * s + ph))
			Kind.PULSE:
				var k: float = a * sin(t * s + ph)
				n.transform = Transform3D(base.basis * Basis.from_scale(Vector3.ONE + ax * k), base.origin)
			Kind.RISE:
				var f: float = fposmod(t * s + ph, 1.0)
				var g: float = maxf(0.05, sin(f * PI))
				n.transform = Transform3D(base.basis * Basis.from_scale(Vector3.ONE * g), base.origin + base.basis * ax * a * f)
			Kind.FLICKER:
				var w: float = a * (0.6 * sin(t * s + ph) + 0.4 * sin(t * s * 2.37 + ph * 1.7))
				var sc: Vector3 = Vector3.ONE * (1.0 + 0.35 * w) + ax * 0.65 * w
				n.transform = Transform3D(base.basis * Basis.from_scale(sc), base.origin)
			Kind.BLINK:
				var c: float = fposmod(t + ph, maxf(s, 0.5))
				var squash: float = 0.12 if c < 0.13 else 1.0
				n.transform = Transform3D(base.basis * Basis.from_scale(Vector3.ONE - ax * (1.0 - squash)), base.origin)
			Kind.SLIDE:
				var f2: float = fposmod(t * s + ph, 1.0)
				n.transform = Transform3D(base.basis, base.origin + base.basis * ax * lerpf(-a, a, f2))
