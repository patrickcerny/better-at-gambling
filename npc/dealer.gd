class_name Dealer
extends CharacterBody3D
## A dealer NPC standing at a blackjack or roulette table (v0.8.4). Wears a vest and bow tie.
## When shoved or batted, player goes to jail, the current hand is cancelled, and all bets are
## refunded. The dealer body reports its position to `DealerLogic`; all decisions come from server.
## Online clients follow the dealer's streamed position.

const LAYER: int = 16
const DEALER_COLOR: Color = Color("#1a1a1a")
const VEST_COLOR: Color = Color("#DC143C")
const BOW_COLOR: Color = Color.WHITE

var station_id: StringName = &""
var position_offset: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var visuals: AvatarVisuals = null
## Online clients: follow the server's stream instead of walking.
var puppet: bool = false
var _headless: bool = false
var _net_pos: Vector3 = Vector3.INF
var _net_yaw: float = 0.0


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1
	add_to_group(&"npcs")
	add_to_group(&"dealers")
	_headless = DisplayServer.get_name() == "headless"
	if not _headless:
		_build_visuals()
	var shape := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.42
	cs.height = 1.7
	shape.shape = cs
	shape.position.y = 0.85
	add_child(shape)


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Puppet: the server's latest position/yaw.
func apply_net(pos: Vector3, p_yaw: float) -> void:
	if _net_pos == Vector3.INF:
		global_position = pos
	_net_pos = pos
	_net_yaw = p_yaw


func _physics_process(delta: float) -> void:
	if puppet:
		if _net_pos != Vector3.INF:
			global_position = global_position.lerp(_net_pos, minf(1.0, 12.0 * delta))
			yaw = lerp_angle(yaw, _net_yaw, minf(1.0, 10.0 * delta))
			rotation.y = yaw
		return
	# Host or offline: the dealer stands still on its spot, turned towards the players.
	if position_offset.is_finite():
		global_position = position_offset
	rotation.y = yaw


func _build_visuals() -> void:
	visuals = AvatarVisuals.new()
	visuals.name = "Visuals"
	add_child(visuals)
	visuals.set_color(DEALER_COLOR)
	# Red vest
	GreyboxKit.box(visuals.body, Vector3(0.3, 0.22, 0.05), Vector3(0, -0.4, -0.4), VEST_COLOR, "Vest", false)
	# White bow tie
	GreyboxKit.box(visuals.body, Vector3(0.11, 0.08, 0.05), Vector3(-0.065, -0.2, -0.43), Color.WHITE, "BowL", false)
	GreyboxKit.box(visuals.body, Vector3(0.11, 0.08, 0.05), Vector3(0.065, -0.2, -0.43), Color.WHITE, "BowR", false)
