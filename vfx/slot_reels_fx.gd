class_name SlotReelsFx
extends Node3D
## Three reels on a slot cabinet's screen, for everyone in the room: they blur while the machine
## spins and stop one after another on the server's line, left to right. A winning line lights the
## payline and pulses the reels that paid. This is THE slot display; the seated overlay only shows
## the bet strip and the paytable.

## Seconds between reel stops: the gap between Patrick's riser segments, so they chain seamlessly.
const STAGGER: float = 0.71
## Delay before the first reel stops once the result is known.
const FIRST_STOP: float = 0.12
## Settle time after the last reel lands before the payout reads as final.
const SETTLE: float = 0.15
## Riser segments played on the local player's own spin as the reels land (see `stop_sounds_for`).
const RISERS: Array[StringName] = [&"slots_riser_1", &"slots_riser_2", &"slots_riser_3"]
## Played instead of the next riser when a reel breaks the match (the chain ends there).
const NO_MATCH: StringName = &"slots_no_match"
## Reel spin speed (symbols per second), and the slower roll of the last reel while it teases.
const ROLL_SPEED: float = 22.0
const TEASE_SPEED: float = 8.0
## Bold picture per symbol (the paytable uses the same ones).
const SYMBOL_TEXTURES: Dictionary = {
	&"cherry": preload("res://assets/icons/slots/cherry.png"),
	&"lemon": preload("res://assets/icons/slots/lemon.png"),
	&"bell": preload("res://assets/icons/slots/bell.png"),
	&"bar": preload("res://assets/icons/slots/bar.png"),
	&"seven": preload("res://assets/icons/slots/seven.png"),
	&"clover": preload("res://assets/icons/slots/clover.png"),
	&"diamond": preload("res://assets/icons/slots/diamond.png"),
}
const REEL_SPACING: float = 0.22
const WINDOW_SIZE: Vector2 = Vector2(0.2, 0.3)
## Win pulse peak: the paying pictures brighten towards warm gold.
const WIN_TINT: Color = Color(1.5, 1.3, 0.85)

var reels: Array[Sprite3D] = []
## Symbol index each reel shows right now (tests read this).
var shown: Array[int] = [0, 0, 0]
## Gold bar across the reels, lit on a win.
var payline: MeshInstance3D
## Reel indices that paid on the last line (empty = loss or still spinning).
var winners: Array[int] = []
## Per reel: seconds until it stops (< 0 = stopped).
var _stop_in: Array[float] = [-1.0, -1.0, -1.0]
var _final: Array[int] = [0, 0, 0]
var _spinning: Array[bool] = [false, false, false]
var _roll: Array[float] = [0.0, 0.0, 0.0]
var _pending_win: bool = false
var _win_time: float = -1.0
var _jackpot: bool = false
## Sound per reel as it lands (empty name = plain stop only); set only for the local player's spin.
var _sound_at: Array[StringName] = [&"", &"", &""]
## True when the first two reels match: the last reel slows down before it lands.
var _tease: bool = false
## Riser / no-match sounds played since the last `stop_on` (tests read this).
var played_sounds: Array[StringName] = []


## Seconds from a result arriving until every reel has landed (the overlay waits this long).
static func land_seconds() -> float:
	return FIRST_STOP + STAGGER * 2.0 + SETTLE


## The sound for each reel as it lands, left to right (Patrick: same first, second and third
## emblem = all three risers, else riser 1 and 2, or only 1; a reel that breaks the match plays
## `slots_no_match` and ends the chain). Exact symbols, wilds don't count. "" = no extra sound.
static func stop_sounds_for(line: Array[int]) -> Array[StringName]:
	if line.size() < 3:
		return [&"", &"", &""] as Array[StringName]
	if line[1] != line[0]:
		return [RISERS[0], NO_MATCH, &""] as Array[StringName]
	if line[2] != line[1]:
		return [RISERS[0], RISERS[1], NO_MATCH] as Array[StringName]
	return RISERS.duplicate()


## Reels that paid for `line`: all three for three of a kind, the cherries for a cherry pay.
static func winning_reels(line: Array[int], cfg: BalanceConfig) -> Array[int]:
	var out: Array[int] = []
	if line.size() < 3 or SlotsLogic.payout_multiplier(line, cfg) <= 0:
		return out
	var first: int = -1
	var same: bool = true
	for s: int in line:
		if s == SlotsLogic.Sym.CLOVER:
			continue
		if first < 0:
			first = s
		elif s != first:
			same = false
	if same:
		return [0, 1, 2] as Array[int]
	if line.count(SlotsLogic.Sym.CHERRY) >= 2:
		for i: int in 3:
			if line[i] == SlotsLogic.Sym.CHERRY:
				out.append(i)
		return out
	out.append(0)  # a cherry on the left reel
	return out


func _ready() -> void:
	name = "ReelsFx"
	for i: int in 3:
		var x: float = (i - 1) * REEL_SPACING
		var window := MeshInstance3D.new()  # a dark reel window behind each symbol
		window.name = "Window%d" % i
		var q := QuadMesh.new()
		q.size = WINDOW_SIZE
		window.mesh = q
		var wm := StandardMaterial3D.new()  # opaque, so it always draws before the transparent symbols
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.albedo_color = Color("#0B0A0A")
		window.material_override = wm
		window.position = Vector3(x, 0.0, -0.004)
		add_child(window)
		var l := Sprite3D.new()
		l.name = "Reel%d" % i
		l.texture = SYMBOL_TEXTURES[&"cherry"]
		l.pixel_size = WINDOW_SIZE.x * 0.85 / float(l.texture.get_width())  # fills the window's width
		l.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD  # scissor: no transparent sorting against the window
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		l.shaded = false
		l.position = Vector3(x, 0.0, 0.0)
		add_child(l)
		reels.append(l)
		_show(i, (i * 2 + 1) % SlotsLogic.SYMBOL_NAMES.size())
	for side: int in [-1, 1]:  # small gold payline markers either side of the reels
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.025, 0.025, 0.01)
		m.mesh = b
		m.material_override = Vfx.glow_material(Palette.WARM_GOLD)
		m.position = Vector3(side * (REEL_SPACING * 1.5 + 0.005), 0.0, 0.0)
		m.rotation.z = PI * 0.25
		add_child(m)
	payline = MeshInstance3D.new()
	payline.name = "Payline"
	var pm := BoxMesh.new()
	pm.size = Vector3(REEL_SPACING * 3.0, 0.012, 0.002)
	payline.mesh = pm
	payline.material_override = Vfx.glow_material(Palette.VIP_GOLD, true)
	payline.position = Vector3(0.0, 0.0, -0.002)
	payline.visible = false
	add_child(payline)


## All reels start blurring (ignored while a result is already landing, e.g. a late lever tween).
func spin() -> void:
	if _stop_in[0] >= 0.0 or _stop_in[1] >= 0.0 or _stop_in[2] >= 0.0:
		return
	_clear_win()
	for i: int in 3:
		_spinning[i] = true
		_stop_in[i] = -1.0


## Stops the reels on `line` one after another; returns the seconds until the last one stops.
## `own` = the local player's spin: the riser / no-match sounds play as the reels land.
func stop_on(line: Array, own: bool = false) -> float:
	if line.size() < 3:
		return 0.0
	_clear_win()
	var ints: Array[int] = []
	for i: int in 3:
		_final[i] = int(line[i])
		ints.append(_final[i])
		if not _spinning[i]:
			_spinning[i] = true  # a spin we never saw start still lands with a short roll
		_stop_in[i] = FIRST_STOP + STAGGER * i
	played_sounds.clear()
	_sound_at = stop_sounds_for(ints) if own else ([&"", &"", &""] as Array[StringName])
	_tease = ints[0] == ints[1]
	winners = winning_reels(ints, Registry.balance)
	_jackpot = SlotsLogic.is_jackpot(ints)
	_pending_win = not winners.is_empty()
	return land_seconds()


## Stops every reel on the symbol it shows right now (a refunded spin: no result, no payline).
func cancel() -> void:
	_clear_win()
	for i: int in 3:
		_spinning[i] = false
		_stop_in[i] = -1.0
		reels[i].position.y = 0.0


func is_spinning() -> bool:
	return _spinning[0] or _spinning[1] or _spinning[2]


## True while the payline is lit for a win.
func is_showing_win() -> bool:
	return payline != null and payline.visible


func _process(delta: float) -> void:
	for i: int in 3:
		if not _spinning[i]:
			continue
		var speed: float = ROLL_SPEED
		if i == 2 and _tease and _stop_in[i] >= 0.0 and _stop_in[i] < STAGGER:
			speed = lerpf(TEASE_SPEED, ROLL_SPEED, _stop_in[i] / STAGGER)  # the last reel slows: will it match?
		_roll[i] += delta * speed
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
				if _sound_at[i] != &"":
					played_sounds.append(_sound_at[i])
					Audio.play(_sound_at[i], &"SFX", -4.0)
					_sound_at[i] = &""
	if _pending_win and not is_spinning():
		_pending_win = false
		_win_time = 0.0
		payline.visible = true
	if _win_time >= 0.0:
		_win_time += delta
		var rate: float = 14.0 if _jackpot else 8.0
		var pulse: float = 0.5 + 0.5 * sin(_win_time * rate)
		payline.transparency = 0.55 * (1.0 - pulse)
		for i: int in winners:
			reels[i].scale = Vector3.ONE * (1.0 + 0.18 * pulse)
			reels[i].modulate = Color.WHITE.lerp(WIN_TINT, pulse)
		if _win_time > (6.0 if _jackpot else 3.0):
			_win_time = -1.0  # settle: payline stays lit, reels go back to rest size
			payline.transparency = 0.0
			for i: int in winners:
				reels[i].scale = Vector3.ONE
				reels[i].modulate = Color.WHITE


func _clear_win() -> void:
	_pending_win = false
	_win_time = -1.0
	_tease = false
	winners.clear()
	if payline != null:
		payline.visible = false
	for l: Sprite3D in reels:
		l.scale = Vector3.ONE
		l.modulate = Color.WHITE


func _show(i: int, sym: int) -> void:
	shown[i] = clampi(sym, 0, SlotsLogic.SYMBOL_NAMES.size() - 1)
	reels[i].texture = symbol_texture(shown[i])


## The picture for symbol index `sym` (reels and paytable).
static func symbol_texture(sym: int) -> Texture2D:
	return SYMBOL_TEXTURES[SlotsLogic.SYMBOL_NAMES[clampi(sym, 0, SlotsLogic.SYMBOL_NAMES.size() - 1)]]
