class_name CoinPile
extends Node3D
## Money on the floor as shiny gold coins that burst out and spin. Replaces ChipPile for version 0.8.5+.
## The pile itself is just a container; individual coins drop out and are collectable.
##
## Feel: coins burst out of whoever dropped them with spin and momentum, settle on the floor,
## spin and glimmer, and fly into whoever collects them.

## Time from the drop until coins can be picked up (the burst momentum settle)
const SETTLE_SECONDS: float = 0.45
## Flight time into the collector
const FLY_SECONDS: float = 0.28

var pile_id: int = -1
var amount: int = 0
## Scene clock when the pile landed (set by the match scene; pickups wait for it)
var settles_at: float = 0.0
## Our own pickup is predicted: the coins are flying to us while the server confirms
var predicted_until: float = -INF
var _label: Label3D
var _coins: Array[Coin] = []
var _gone: bool = false
var _tween: Tween


func _ready() -> void:
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
	add_to_group(&"chip_piles")  # Keep same group name for compatibility


func _process(delta: float) -> void:
	if _label != null:
		# Bobbing animation for the label
		var time: float = get_tree().get_frame() * 0.016  # Rough approximation
		_label.position.y = 0.6 + sin(time * 3.0) * 0.05


## True once the pile has landed and nobody has taken it yet
func is_collectable(now: float) -> bool:
	return not _gone and now >= settles_at and visible


## True while the coins fly into someone (predicted or confirmed)
func is_leaving() -> bool:
	return _gone


## Creates the coins for this pile with burst momentum
func create_coins(from_pos: Vector3) -> void:
	var coin_count: int = clampi(amount / 25, 1, 6)
	var pile_pos: Vector3 = global_position  # Where the pile is in world space
	var relative_start: Vector3 = from_pos - pile_pos  # Where coins start relative to pile

	# Pre-generate burst parameters for each coin
	var burst_params: Array = []
	for i: int in coin_count:
		var angle: float = randf() * TAU
		var burst_dir: Vector3 = Vector3(cos(angle), randf_range(0.4, 0.8), sin(angle)).normalized()
		var burst_speed: float = randf_range(2.5, 4.5)
		var burst_velocity: Vector3 = burst_dir * burst_speed

		var spin_axis: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var spin_velocity: Vector3 = spin_axis * randf_range(6.0, 12.0)

		burst_params.append({"vel": burst_velocity, "spin": spin_velocity})

	for i: int in coin_count:
		var coin := Coin.new()
		coin.name = "Coin%d" % i
		coin.position = Vector3.ZERO  # Start at pile center in local space
		add_child(coin)
		_coins.append(coin)

	# Arc animation from source to landing position if VFX enabled
	if not Vfx.enabled():
		# Just burst them immediately
		for i: int in _coins.size():
			var params: Dictionary = burst_params[i]
			_coins[i].burst(params["vel"], params["spin"])
		return

	# Move all coins to start position for arc animation (local space)
	for coin: Coin in _coins:
		coin.position = relative_start

	_label.visible = false

	var t: Tween = create_tween()
	_tween = t

	# Animate coins falling from source to landing position
	t.tween_method(func(k: float) -> void:
		var p: Vector3 = relative_start.lerp(Vector3.ZERO, k)
		p.y += sin(k * PI) * 0.9
		for coin: Coin in _coins:
			coin.position = p
	, 0.0, 1.0, SETTLE_SECONDS * 0.9)

	t.tween_callback(func() -> void:
		_label.visible = true
		# Now release coins to physics
		for i: int in _coins.size():
			var params: Dictionary = burst_params[i]
			_coins[i].position = Vector3.ZERO
			_coins[i].burst(params["vel"], params["spin"]))


## Coins fly into the collector; with `keep` they only hide (for prediction)
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

	# Fly all coins to the collector
	for coin: Coin in _coins:
		if is_instance_valid(coin):
			coin.fly_to(who, keep)

	if not keep:
		get_tree().create_timer(FLY_SECONDS + 0.05).timeout.connect(queue_free)


## Predicted pickup was refused: coins drop back
func restore() -> void:
	_kill_tween()
	_gone = false
	predicted_until = -INF
	visible = true
	_label.visible = true
	for coin: Coin in _coins:
		if is_instance_valid(coin):
			coin.restore()


## Expired: coins shrink away
func fade_out() -> void:
	_gone = true
	if not Vfx.enabled():
		queue_free()
		return
	_label.visible = false
	_kill_tween()

	for coin: Coin in _coins:
		if is_instance_valid(coin):
			coin.fade_out()

	var t: Tween = create_tween()
	_tween = t
	t.tween_property(self, "scale", Vector3(1.4, 0.05, 1.4), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
