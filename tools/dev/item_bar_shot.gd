extends Control
## Dev: look-dev for the item bar (`ItemBar`) on a plain casino-dark backdrop.
## Run with scripts/screenshot.sh res://tools/dev/item_bar_shot.tscn <name> 60 [args]
##   --items a,b,c   the inventory (default lucky_clover,black_cat,baseball_bat)
##   --hold N        slot in hand (default -1)
##   --info          open the info card on the held item
##   --quiet         no "NEW ITEM" card (inventory set before the bar is shown)


func _ready() -> void:
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.11, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var bar := ItemBar.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -380
	bar.offset_right = 380
	bar.offset_top = -600
	bar.offset_bottom = -20
	add_child(bar)
	var items: PackedStringArray = args.get_string("items", "lucky_clover,black_cat,baseball_bat").split(",", false)
	var inv: Array = []
	for s: String in items:
		inv.append(StringName(s))
	bar.set_inventory(inv)
	if args.has("quiet"):
		bar.pickup_queue.clear()
		bar.dismiss_pickup()
	var hold: int = args.get_int("hold", -1)
	if hold >= 0:
		bar.set_held(hold)
	if args.has("info"):
		bar.toggle_info()
