class_name NameTag
extends Label3D
## A player's name over their head that stays readable at any distance: it keeps its world size in
## the middle distances but its on-screen height is clamped between `MIN_PX` and `MAX_PX` (at the
## 1080p reference height), so it never fills the screen up close nor shrinks to a speck far away.
## Very close it fades out (you can see who it is), far away it fades out too.

## On-screen text height limits in pixels at a 1080-pixel-high viewport.
const MIN_PX: float = 17.0
const MAX_PX: float = 30.0
## Under the pixel look the world renders at 1/2..1/4 resolution: the tag then needs at least this
## many *rendered* pixels to stay readable, so the on-screen limits grow with the shrink factor.
const MIN_RENDERED_PX: float = 12.0
const MAX_RENDERED_PX: float = 18.0
## Distances (metres) for the near and far fades.
const NEAR_FADE: float = 1.6
const FAR_FADE: float = 34.0

var _base_pixel_size: float = 0.004


func _ready() -> void:
	_base_pixel_size = pixel_size
	# Distance fades handled here instead of the visibility range (which would pop at the far end).
	visibility_range_begin = 0.0
	visibility_range_end = 0.0
	set_process(DisplayServer.get_name() != "headless")


func _process(_delta: float) -> void:
	if not visible:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var d: float = cam.global_position.distance_to(global_position)
	var scale_k: float = size_factor(d, cam.fov, _base_pixel_size * font_size, float(PixelView.shrink_of(self)))
	pixel_size = _base_pixel_size * scale_k
	var a: float = clampf((d - NEAR_FADE) / 0.8, 0.0, 1.0) * clampf((FAR_FADE - d) / 6.0, 0.0, 1.0)
	modulate.a = a
	outline_modulate.a = a


## Factor to multiply the world size by so a text of `world_h` metres seen from `distance` with a
## vertical `fov_deg` lands between MIN_PX and MAX_PX on a 1080-pixel-high screen (both limits
## raised so the text keeps MIN/MAX_RENDERED_PX when the world is drawn `shrink` times smaller).
static func size_factor(distance: float, fov_deg: float, world_h: float, shrink: float = 1.0) -> float:
	var px: float = world_h / (2.0 * maxf(distance, 0.05) * tan(deg_to_rad(fov_deg) * 0.5)) * 1080.0
	if px <= 0.0:
		return 1.0
	var lo: float = maxf(MIN_PX, MIN_RENDERED_PX * shrink)
	var hi: float = maxf(MAX_PX, MAX_RENDERED_PX * shrink)
	return clampf(px, lo, hi) / px
