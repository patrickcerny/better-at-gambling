class_name MinigamePreview
extends TextureRect
## A minigame's looping preview clip on its rules card: plays the sprite sheet
## assets/minigames/clips/<id>.webp (tools/minigame_clips.sh, 384x216 frames, 10 fps), or shows
## the still picture assets/minigames/<id>.webp when there's no clip.

const FRAME: Vector2i = Vector2i(384, 216)
const FPS: float = 10.0
const CLIP_PATH: String = "res://assets/minigames/clips/%s.webp"
const STILL_PATH: String = "res://assets/minigames/%s.webp"

var frames: int = 0
var frame: int = 0
var _sheet: Texture2D
var _atlas: AtlasTexture
var _cols: int = 1
var _t: float = 0.0


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Loads the clip (or still) for a minigame; false if it has neither.
func set_game(id: StringName) -> bool:
	frames = 0
	frame = 0
	_t = 0.0
	_sheet = null
	var clip: String = CLIP_PATH % id
	if ResourceLoader.exists(clip):
		_sheet = load(clip) as Texture2D
	if _sheet != null and _sheet.get_width() >= FRAME.x:
		_cols = maxi(floori(float(_sheet.get_width()) / FRAME.x), 1)
		frames = _cols * maxi(floori(float(_sheet.get_height()) / FRAME.y), 1)
		_atlas = AtlasTexture.new()
		_atlas.atlas = _sheet
		_show(0)
		texture = _atlas
		return true
	var still: String = STILL_PATH % id
	if ResourceLoader.exists(still):
		texture = load(still) as Texture2D
		return texture != null
	return false


func _process(delta: float) -> void:
	if frames <= 1:
		return
	_t += delta
	var f: int = int(_t * FPS) % frames
	if f != frame:
		_show(f)


func _show(f: int) -> void:
	frame = f
	_atlas.region = Rect2(Vector2((f % _cols) * FRAME.x, floori(float(f) / _cols) * FRAME.y), Vector2(FRAME))
