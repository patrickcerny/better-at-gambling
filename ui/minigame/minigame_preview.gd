class_name MinigamePreview
extends Control
## A minigame's looping preview clip on its rules card: plays the video
## assets/minigames/clips/<id>.ogv (Ogg Theora, 960x540 at 30 fps, tools/minigame_clips.sh; until
## 0.9.84 a low-res sprite sheet, Patrick: "Dont use GIFs use videos gifs are bad quality"), or
## shows the still picture assets/minigames/<id>.webp when there's no clip.

const CLIP_PATH: String = "res://assets/minigames/clips/%s.ogv"
const STILL_PATH: String = "res://assets/minigames/%s.webp"

var video: VideoStreamPlayer
var still: TextureRect
## True while a clip (not the still) is on.
var has_clip: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	video = VideoStreamPlayer.new()
	video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video.expand = true
	video.loop = true
	video.volume_db = -80.0
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.visible = false
	add_child(video)
	still = TextureRect.new()
	still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	still.visible = false
	add_child(still)


## Loads the clip (or still) for a minigame; false if it has neither.
func set_game(id: StringName) -> bool:
	has_clip = false
	video.stop()
	video.visible = false
	still.visible = false
	var clip: String = CLIP_PATH % id
	if ResourceLoader.exists(clip):
		var stream := load(clip) as VideoStream
		if stream != null:
			video.stream = stream
			video.visible = true
			has_clip = true
			if is_inside_tree():
				video.play()
			return true
	var path: String = STILL_PATH % id
	if ResourceLoader.exists(path):
		still.texture = load(path) as Texture2D
		still.visible = still.texture != null
		return still.visible
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and has_clip and not video.is_playing():
		video.play.call_deferred()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and has_clip:
		video.paused = not is_visible_in_tree()
