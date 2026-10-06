class_name ChipPile
extends Node3D
## Money on the floor (shaken out of a knocked-out player, §2.4.1): a little stack of chips
## with its value floating above. The match scene reports pickups to the server.
##
## Feel: piles arc out of whoever dropped them and land (`SETTLE_SECONDS`, not collectable in the
## air), sparkle a little while they wait, fly into whoever collects them (`fly_to`) and shrink
## away when they expire (`fade_out`). The money itself is the server's business: this node
## only shows it.

## Time from the drop until the pile can be picked up (the arc out of the victim).
const SETTLE_SECONDS: float = 0.45
## Flight time into the collector.
const FLY_SECONDS: float = 0.28

var pile_id: int = -1
var amount: int = 0
## Scene clock when the pile landed (set by the match scene; pickups wait for it).
var settles_at: float = 0.0
## Our own pickup is predicted: the chips are flying to us while the server confirms.
var predicted_until: float = -INF
var _bob: float = 0.0
var _label: Label3D
var _chips: Node3D
var _gone: bool = false
var _tween: Tween


func _ready() -> void:
	_chips = Node3D.new()
	_chips.name = "Chips"
	add_child(_chips)
	var count: int = clampi(amount / 25, 1, 6)
	for i: int in count:
		var chip: Node3D = PropModels.make(&"poker_chip", 0.0, 0.32)
		chip.position = Vector3(randf_range(-0.03, 0.03), i * 0.05, randf_range(-0.03, 0.03))
		chip.scale.y = 1.5  # chunky enough to spot on the carpet
		chip.rotation.y = randf() * TAU
		_chips.add_child(chip)
	_label = Label3D.new()
	_label.text = "$%d" % amount
	_label.font_size = 44
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Palette.MONEY_GREEN
	_label.outline_modulate = Palette.CASINO_BLACK
	_label.outline_size = 8
	_label.position.y = 0.6
	add_child(_label)
	add_to_group(&"chip_piles")


func _process(delta: float) -> void:
	_bob += delta
	if _label != null:
		_label.position.y = 0.6 + sin(_bob * 3.0) * 0.05
	if _chips != null and not _gone:
		_chips.rotation.y += delta * 0.8


## True once the pile has landed and nobody has taken it yet.
func is_collectable(now: float) -> bool:
	return not _gone and now >= settles_at and visible


## True while the chips fly into someone (predicted or confirmed).
func is_leaving() -> bool:
	return _gone


## Arcs the pile out of `from` (world) to where it lies, over `SETTLE_SECONDS`.
func arc_from(from: Vector3) -> void:
	if not Vfx.enabled() or _chips == null:
		return
	var land: Vector3 = global_position
	var start: Vector3 = from - land
	_chips.position = start
	_label.visible = false
	var t: Tween = create_tween()
	_tween = t
	t.tween_method(func(k: float) -> void:
		var p: Vector3 = start.lerp(Vector3.ZERO, k)
		p.y += sin(k * PI) * 0.9
		_chips.position = p, 0.0, 1.0, SETTLE_SECONDS * 0.9)
	t.tween_callback(func() -> void:
		_label.visible = true
		_chips.scale = Vector3(1.3, 0.6, 1.3))
	t.tween_property(_chips, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The chips fly into `who` and the pile frees itself; with `keep` (a predicted pickup) it only
## hides, so `restore` can bring it back if the server says no. Safe to call again (rerouted to
## someone else when the server gave the pile to another player).
func fly_to(who: Node3D, keep: bool = false) -> void:
	_gone = true
	_label.visible = false
	_kill_tween()
	if not Vfx.enabled() or who == null or not is_instance_valid(who) or not who.is_inside_tree():
		if keep:
			visible = false
		else:
			queue_free()
		return
	visible = true
	var start: Vector3 = _chips.global_position
	var t: Tween = create_tween()
	_tween = t
	t.tween_method(func(k: float) -> void:
		if not is_instance_valid(who) or not who.is_inside_tree():
			return
		var end: Vector3 = who.global_position + Vector3(0.0, 1.0, 0.0)
		var p: Vector3 = start.lerp(end, k * k)
		p.y += sin(k * PI) * 0.5
		_chips.global_position = p
		_chips.scale = Vector3.ONE * lerpf(1.0, 0.35, k), 0.0, 1.0, FLY_SECONDS)
	if keep:
		t.tween_callback(func() -> void: visible = false)
	else:
		t.tween_callback(queue_free)


## Predicted pickup was refused (nobody confirmed it): the chips drop back where they were.
func restore() -> void:
	_kill_tween()
	_gone = false
	predicted_until = -INF
	visible = true
	_label.visible = true
	if _chips != null:
		_chips.position = Vector3.ZERO
		_chips.scale = Vector3.ONE


## Expired: shrinks into the carpet instead of popping out of existence.
func fade_out() -> void:
	_gone = true
	if not Vfx.enabled():
		queue_free()
		return
	_label.visible = false
	_kill_tween()
	var t: Tween = create_tween()
	_tween = t
	t.tween_property(self, "scale", Vector3(1.4, 0.05, 1.4), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
