class_name SlotReelsFx
extends Node3D
## Three reels on a slot cabinet's screen, for everyone in the room: they blur while the machine
## spins and stop one after another on the server's line, left to right.

const STAGGER: float = 0.35
const SYMBOL_COLORS: Dictionary = {
	&"cherry": Color("#E55353"), &"lemon": Color("#F0D25A"), &"bell": Color("#E3B95C"), &"bar": Color("#F2E6C9"),
	&"seven": Color("#C83D3D"), &"clover": Color("#68C26F"), &"diamond": Color("#F2E6C9"),
}
## Short text glyphs that read in the condensed font (the 2D overlay uses emoji).
const SYMBOL_TEXT: Dictionary = {
	&"cherry": "CH", &"lemon": "LEM", &"bell": "BELL", &"bar": "BAR", &"seven": "7", &"clover": "♣", &"diamond": "◆",
}
const REEL_SPACING: float = 0.22

var reels: Array[Label3D] = []
## Per reel: seconds until it stops (< 0 = stopped).
var _stop_in: Array[float] = [-1.0, -1.0, -1.0]
var _final: Array[int] = [0, 0, 0]
var _spinning: Array[bool] = [false, false, false]
var _roll: Array[float] = [0.0, 0.0, 0.0]


func _ready() -> void:
	name = "ReelsFx"
	for i: int in 3:
		var l := Label3D.new()
		l.name = "Reel%d" % i
		l.font = Vfx.font()
		l.font_size = 64
		l.pixel_size = 0.0018
		l.outline_size = 10
		l.outline_modulate = Palette.CASINO_BLACK
		l.position = Vector3((i - 1) * REEL_SPACING, 0.0, 0.0)
		add_child(l)
		reels.append(l)
		_show(i, (i * 2 + 1) % SlotsLogic.SYMBOL_NAMES.size())


## All reels start blurring.
func spin() -> void:
	for i: int in 3:
		_spinning[i] = true
		_stop_in[i] = -1.0


## Stops the reels on `line` one after another; returns the seconds until the last one stops.
func stop_on(line: Array) -> float:
	if line.size() < 3:
		return 0.0
	for i: int in 3:
		_final[i] = int(line[i])
		if not _spinning[i]:
			_spinning[i] = true  # a spin we never saw start still lands with a short roll
		_stop_in[i] = 0.12 + STAGGER * i
	return 0.12 + STAGGER * 2.0 + 0.15


func is_spinning() -> bool:
	return _spinning[0] or _spinning[1] or _spinning[2]


func _process(delta: float) -> void:
	for i: int in 3:
		if not _spinning[i]:
			continue
		_roll[i] += delta * 22.0
		_show(i, int(_roll[i] + i * 3) % SlotsLogic.SYMBOL_NAMES.size())
		reels[i].position.y = -fposmod(_roll[i], 1.0) * 0.06 + 0.03
		if _stop_in[i] >= 0.0:
			_stop_in[i] -= delta
			if _stop_in[i] < 0.0:
				_spinning[i] = false
				_show(i, _final[i])
				reels[i].position.y = -0.05
				var t: Tween = reels[i].create_tween()
				t.tween_property(reels[i], "position:y", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				Audio.play_at(&"reel_stop", self, -12.0, 1.0 + i * 0.08)


func _show(i: int, sym: int) -> void:
	var key: StringName = SlotsLogic.SYMBOL_NAMES[clampi(sym, 0, SlotsLogic.SYMBOL_NAMES.size() - 1)]
	reels[i].text = SYMBOL_TEXT.get(key, "?")
	reels[i].modulate = SYMBOL_COLORS.get(key, Palette.CREAM)
