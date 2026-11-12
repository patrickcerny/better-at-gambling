extends SceneTree
## Dev probe: starts Practice on the full floor (`-- --practice --floor full`), waits, prints the
## draw calls, objects, primitives and frame time of one frame, then quits.
##   godot --path . -s tools/dev/draw_probe.gd -- --practice --floor full --guards 0

var _frame: int = 0
var _sum_ms: float = 0.0
var _n: int = 0


func _initialize() -> void:
	change_scene_to_file.call_deferred("res://ui/menus/main_menu.tscn")


func _process(delta: float) -> bool:
	_frame += 1
	if _frame > 240:
		_sum_ms += delta * 1000.0
		_n += 1
	if _frame == 300:
		var dc: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var obj: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		var prim: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var mem: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		print("DRAWPROBE method=%s draw_calls=%d objects=%d primitives=%d frame_ms=%.1f video_mb=%.0f nodes=%d" % [RenderingServer.get_current_rendering_method(), dc, obj, prim, _sum_ms / maxi(_n, 1), mem, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		quit()
	return false
