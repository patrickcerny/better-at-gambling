extends Control
## Dev: the menu/loading panorama on its own. `PANO_LEG=2.5` picks the point on the camera loop.
## Run with tools/screenshot.gd --scene res://tools/dev/panorama_shot.tscn.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var p := CasinoPanorama.new()
	p.start_leg = float(OS.get_environment("PANO_LEG")) if OS.has_environment("PANO_LEG") else 0.0
	add_child(p)
