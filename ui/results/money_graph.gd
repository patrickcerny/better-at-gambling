class_name MoneyGraph
extends Control
## Money over the match (results screen): one line per player from the start money to the final
## balance, drawn left to right over `DRAW_TIME` seconds, with the start money as a dashed guide,
## a $ scale on the left and minutes along the bottom. Data: the `series` of each standings row
## (a sample every `MoneyHistory.interval_for(duration)` casino seconds plus the final balance).

const DRAW_TIME: float = 2.4
const PAD_LEFT: float = 84.0
const PAD_RIGHT: float = 18.0
const PAD_TOP: float = 14.0
const PAD_BOTTOM: float = 34.0

## [{player, color, series: Array[int], local: bool}]
var lines: Array[Dictionary] = []
var interval: float = 10.0
var duration_s: float = 600.0
var start_money: int = 0
var font: Font
var _progress: float = 0.0
var _lo: float = 0.0
var _hi: float = 1.0


func _ready() -> void:
	font = get_theme_default_font()
	clip_contents = true


## `rows`: standings rows with `series`; `colors`: player → Color.
func setup(rows: Array, colors: Dictionary, local_id: int, p_duration_s: float, p_start: int) -> void:
	duration_s = maxf(p_duration_s, 1.0)
	interval = MoneyHistory.interval_for(duration_s)
	start_money = p_start
	lines.clear()
	_lo = float(p_start)
	_hi = float(p_start)
	for row: Variant in rows:
		var series: Array = (row as Dictionary).get("series", [])
		if series.size() < 2:
			continue
		var pid: int = int(row["player"])
		lines.append({"player": pid, "color": colors.get(pid, Palette.CREAM), "series": series, "local": pid == local_id})
		for v: Variant in series:
			_lo = minf(_lo, float(v))
			_hi = maxf(_hi, float(v))
	# Local player last so their line is on top.
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return not a["local"] and b["local"])
	var span: float = maxf(_hi - _lo, 100.0)
	_lo = maxf(_lo - span * 0.08, 0.0) if _lo >= 0.0 else _lo - span * 0.08
	_hi += span * 0.08
	_progress = 0.0
	queue_redraw()


func has_data() -> bool:
	return not lines.is_empty()


func _process(delta: float) -> void:
	if _progress < 1.0:
		_progress = minf(_progress + delta / DRAW_TIME, 1.0)
		queue_redraw()


## Seconds of casino time of sample `i` in a series of `n` (the last one is the end of the match).
func _time_of(i: int, n: int) -> float:
	return duration_s if i == n - 1 else minf(i * interval, duration_s)


func _to_px(t: float, money: float) -> Vector2:
	var w: float = size.x - PAD_LEFT - PAD_RIGHT
	var h: float = size.y - PAD_TOP - PAD_BOTTOM
	return Vector2(PAD_LEFT + t / duration_s * w, PAD_TOP + (1.0 - (money - _lo) / maxf(_hi - _lo, 1.0)) * h)


func _draw() -> void:
	if lines.is_empty() or font == null:
		return
	var axis: Color = Palette.CREAM.darkened(0.45)
	var fs: int = 20
	# Money scale: 4 gridlines.
	for k: int in 5:
		var m: float = lerpf(_lo, _hi, k / 4.0)
		var y: float = _to_px(0.0, m).y
		draw_line(Vector2(PAD_LEFT, y), Vector2(size.x - PAD_RIGHT, y), Color(axis, 0.25), 1.0)
		draw_string(font, Vector2(4.0, y + 7.0), "$" + Hud._thousands(int(roundf(m / 10.0) * 10.0)), HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 12.0, fs, axis)
	# Start money guide (dashed).
	var sy: float = _to_px(0.0, start_money).y
	draw_dashed_line(Vector2(PAD_LEFT, sy), Vector2(size.x - PAD_RIGHT, sy), Color(Palette.VIP_GOLD, 0.6), 2.0, 10.0)
	# Minutes along the bottom.
	var minutes: int = int(duration_s / 60.0)
	var step: int = 1 if minutes <= 6 else 2 if minutes <= 12 else 5
	for mi: int in range(0, minutes + 1, step):
		var x: float = _to_px(mi * 60.0, _lo).x
		draw_string(font, Vector2(x - 20.0, size.y - 8.0), "%dm" % mi, HORIZONTAL_ALIGNMENT_CENTER, 40.0, fs, axis)
	# Lines, revealed left to right.
	var t_end: float = _progress * duration_s
	var li: int = -1
	for line: Dictionary in lines:
		li += 1
		# Equal lines (ties) are nudged apart a little so every colour stays visible.
		var nudge: Vector2 = Vector2(0.0, (li - (lines.size() - 1) * 0.5) * 2.5)
		var series: Array = line["series"]
		var n: int = series.size()
		var pts := PackedVector2Array()
		for i: int in n:
			var t: float = _time_of(i, n)
			if t <= t_end:
				pts.append(_to_px(t, float(series[i])) + nudge)
			else:
				var t0: float = _time_of(i - 1, n)
				var f: float = (t_end - t0) / maxf(t - t0, 0.001)
				pts.append(_to_px(t_end, lerpf(float(series[i - 1]), float(series[i]), f)) + nudge)
				break
		if pts.size() < 2:
			continue
		var c: Color = line["color"]
		var w: float = 5.0 if line["local"] else 3.0
		draw_polyline(pts, Color(Palette.CASINO_BLACK, 0.6), w + 3.0, true)
		draw_polyline(pts, c, w, true)
		draw_circle(pts[-1], w + 2.5, c)
