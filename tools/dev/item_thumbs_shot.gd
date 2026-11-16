extends Control
## Dev: every item's preview picture (`ItemThumbnails`) in a labelled grid, to check they face the
## camera. scripts/screenshot.sh res://tools/dev/item_thumbs_shot.tscn thumbs 120 [--turn 180]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.11, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	ItemThumbnails.extra_turn = Cmdline.parse(OS.get_cmdline_user_args()).get_float("turn", 0.0)
	add_child(ItemThumbnails.new())
	var grid := GridContainer.new()
	grid.columns = 9
	grid.position = Vector2(20, 20)
	add_child(grid)
	var ids: Array = Registry.items.keys()
	ids.sort()
	for id: StringName in ids:
		var v := VBoxContainer.new()
		grid.add_child(v)
		var t := TextureRect.new()
		t.custom_minimum_size = Vector2(190, 190)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.texture = ItemThumbnails.texture_for(id)
		v.add_child(t)
		var l := Label.new()
		l.text = String(id)
		v.add_child(l)
