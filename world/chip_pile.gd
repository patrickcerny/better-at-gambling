class_name ChipPile
extends Node3D
## Money on the floor (shaken out of a knocked-out player, §2.4.1): a little stack of chips
## with its value floating above. The match scene reports pickups to the server.

var pile_id: int = -1
var amount: int = 0
var _bob: float = 0.0
var _label: Label3D


func _ready() -> void:
	var count: int = clampi(amount / 25, 1, 6)
	for i: int in count:
		var chip: Node3D = PropModels.make(&"poker_chip", 0.0, 0.32)
		chip.position = Vector3(randf_range(-0.03, 0.03), i * 0.05, randf_range(-0.03, 0.03))
		chip.scale.y = 1.5  # chunky enough to spot on the carpet
		chip.rotation.y = randf() * TAU
		add_child(chip)
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
	_label.position.y = 0.6 + sin(_bob * 3.0) * 0.05
	_label.rotation.y += delta
