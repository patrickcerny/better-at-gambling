class_name VoiceIcons
extends RefCounted
## Talking indicator and mute icons, drawn procedurally (no emoji fonts, nothing to import):
## a speaker with sound waves (or a cross when muted) on a dark disc so it reads on any wall.


## A `size`² speaker icon in `color`.
static func speaker(color: Color, muted: bool = false, size: int = 64) -> ImageTexture:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var disc: Color = Color(Palette.CASINO_BLACK, 0.7)
	for py: int in size:
		for px: int in size:
			var x: float = (px + 0.5) / size
			var y: float = (py + 0.5) / size
			var dy: float = absf(y - 0.5)
			if Vector2(x - 0.5, y - 0.5).length() > 0.48:
				continue
			var c: Color = disc
			var body: bool = x >= 0.16 and x <= 0.32 and dy <= 0.11
			var cone: bool = x > 0.32 and x <= 0.5 and dy <= 0.11 + (x - 0.32) / 0.18 * 0.17
			if body or cone:
				c = color
			elif muted:
				var u: float = x - 0.72
				var v: float = y - 0.5
				if absf(u) <= 0.13 and absf(v) <= 0.13 and (absf(u - v) < 0.045 or absf(u + v) < 0.045):
					c = Palette.LOSS_RED
			else:
				var r: float = Vector2(x - 0.42, y - 0.5).length()
				var facing: bool = x > 0.52 and dy < (x - 0.42) * 1.25
				if facing and (absf(r - 0.2) < 0.03 or absf(r - 0.32) < 0.03):
					c = color
			img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)
