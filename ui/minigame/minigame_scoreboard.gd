class_name MinigameScoreboard
extends PanelContainer
## The scoreboard every UI minigame shares (0.9.71): a walnut and brass panel (TableSkin) with one
## card per player. A card shows the player's bean portrait in a ring of their colour, the name,
## an optional detail line, the score (or hearts) and a badge on the portrait for the round state:
## a green check once they locked in, a quiet dot while they think, a red cross when they are out.
## The leader gets a brass card and a crown, you get a gold name and a gold edge. Scores count up,
## cards glide to their new place when the order changes and a fresh check pops in.
##
## Callers hand over the rows already sorted, best first, with `set_rows`; each row is a
## Dictionary:
##   player   int        required
##   score    int        the big number (counts up); leave out with `hearts` or `score_text`
##   score_text String   shown instead of the number ("—", "3 / 5")
##   hearts   int        draws `max_hearts` hearts, this many full (Roulette Royale)
##   max_hearts int
##   detail   String     small line under the name ("12 total", "0 steals")
##   tag      String     small pill left of the score ("+120", "ON STAGE")
##   tag_color Color
##   status   StringName &"done" (check), &"waiting" (dot), &"out" (cross, card dimmed) or none
##   rank     int        place to print; equal scores share a place (default: position + 1;
##                       0 hides it, for lists without an order such as who is still in)
##   leader   bool       crown + brass card (default: rank 1 with a score above 0)
## It never takes focus or mouse input, so controller focus in the minigame is untouched.

enum Status { NONE, WAITING, DONE, OUT }

const ROW_H: float = 58.0
const ROW_H_COMPACT: float = 46.0
const GAP: float = 6.0
const GLIDE: float = 0.35

var state: ClientMatchState
var local_id: int = -1

var _title: Label
var _sub: Label
var _list: Control
var _body: VBoxContainer
var _cards: Dictionary = {}  # pid -> ScoreCard
var _order: Array[int] = []
var _compact: bool = false


func _init(title: String = "SCORE", subtitle: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	var sb: StyleBoxFlat = TableSkin.panel_box()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	add_theme_stylebox_override(&"panel", sb)
	draw.connect(TableSkin.draw_frame.bind(self))
	var v := VBoxContainer.new()
	_body = v
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override(&"separation", 8)
	add_child(v)
	var head := VBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", -2)
	v.add_child(head)
	_title = TableSkin.label(title, 24, Palette.VIP_GOLD, true)
	_title.add_theme_font_override(&"font", TableSkin.black_font())
	head.add_child(_title)
	_sub = TableSkin.label(subtitle, 15, TableSkin.TEXT_MUTED)
	_sub.add_theme_constant_override(&"outline_size", 0)
	_sub.visible = subtitle != ""
	head.add_child(_sub)
	_list = Control.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.resized.connect(_on_list_resized)
	v.add_child(_list)
	add_child(BeanPortraits.new())


func bind(p_state: ClientMatchState, p_local_id: int) -> MinigameScoreboard:
	state = p_state
	local_id = p_local_id
	return self


## A quiet line under the cards (hints such as the voice chat note); returns it for updates.
func add_footer(text: String) -> Label:
	var l: Label = TableSkin.label(text, 15, TableSkin.TEXT_MUTED)
	l.add_theme_constant_override(&"outline_size", 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	_body.add_child(l)
	return l


func set_title(title: String, subtitle: String = "") -> void:
	_title.text = title
	_sub.text = subtitle
	_sub.visible = subtitle != ""


## Shows `rows` (sorted best first, see the class doc). Cards are reused per player.
func set_rows(rows: Array) -> void:
	var compact: bool = rows.size() > 6
	if compact != _compact:
		_compact = compact
		for pid: int in _cards:
			(_cards[pid] as ScoreCard).set_compact(compact)
	var seen: Dictionary = {}
	var order: Array[int] = []
	for i: int in rows.size():
		var r: Dictionary = rows[i]
		var pid: int = int(r.get("player", -1))
		if seen.has(pid):
			continue
		seen[pid] = true
		order.append(pid)
		var card: ScoreCard = _cards.get(pid)
		var fresh: bool = card == null
		if fresh:
			card = ScoreCard.new(_compact)
			_cards[pid] = card
			_list.add_child(card)
		var info: Dictionary = _info(pid)
		var rank: int = int(r.get("rank", i + 1))
		var has_score: bool = r.has("score")
		var leader: bool = bool(r.get("leader", rank == 1 and has_score and int(r["score"]) > 0))
		card.apply(r, info, rank, leader, pid == local_id)
	for pid: int in _cards.keys():
		if not seen.has(pid):
			(_cards[pid] as ScoreCard).queue_free()
			_cards.erase(pid)
	_order = order
	_layout(true)


## Row height the list uses now (tests, layout of callers).
func row_height() -> float:
	return ROW_H_COMPACT if _compact else ROW_H


func card_for(pid: int) -> ScoreCard:
	return _cards.get(pid)


## Players on the board, in the order shown.
func order() -> Array[int]:
	return _order.duplicate()


func _layout(animate: bool) -> void:
	var h: float = row_height()
	_list.custom_minimum_size = Vector2(0, maxf(_order.size() * (h + GAP) - GAP, 0.0))
	for i: int in _order.size():
		var card: ScoreCard = _cards[_order[i]]
		var y: float = i * (h + GAP)
		card.size = Vector2(_list.size.x, h)
		if card.placed and animate and is_inside_tree():
			if absf(card.target_y - y) > 0.5:
				if card.glide != null:
					card.glide.kill()
				card.glide = card.create_tween()
				card.glide.tween_property(card, ^"position:y", y, GLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			card.position = Vector2(0, y)
		card.target_y = y
		card.placed = true


func _on_list_resized() -> void:
	for pid: int in _cards:
		(_cards[pid] as ScoreCard).size.x = _list.size.x


func _info(pid: int) -> Dictionary:
	var p: Dictionary = state.players.get(pid, {}) if state != null else {}
	var color_idx: int = int(p.get("color", pid - 1))
	return {
		"name": state.player_name(pid) if state != null else "Player %d" % pid,
		"color": Palette.player_color(color_idx),
		"bean": int(p.get("bean_color", color_idx)),
		"outfit": p.get("outfit", []),
	}


## Status from a string or StringName ("done", "waiting", "out").
static func status_of(v: Variant) -> Status:
	match StringName(str(v)):
		&"done", &"picked", &"locked", &"ready":
			return Status.DONE
		&"waiting", &"thinking":
			return Status.WAITING
		&"out":
			return Status.OUT
	return Status.NONE


## Places for rows sorted best first by `key` (equal values share a place): fills r["rank"].
static func rank_rows(rows: Array, key: String = "score", tiebreak: String = "") -> void:
	var place: int = 0
	for i: int in rows.size():
		var r: Dictionary = rows[i]
		if i == 0:
			place = 1
		else:
			var prev: Dictionary = rows[i - 1]
			var same: bool = prev.get(key) == r.get(key) and (tiebreak == "" or prev.get(tiebreak) == r.get(tiebreak))
			if not same:
				place = i + 1
		r["rank"] = place


# --- One player's card -------------------------------------------------------------------------

class ScoreCard extends Panel:
	var placed: bool = false
	var glide: Tween
	var target_y: float = 0.0
	var compact: bool = false
	var _box: StyleBoxFlat
	var _rank: PlaceMark
	var _medal: Panel
	var _medal_box: StyleBoxFlat
	var _ring_box: StyleBoxFlat
	var _portrait: TextureRect
	var _badge: StatusBadge
	var _name: Label
	var _detail: Label
	var _tag: Label
	var _tag_box: StyleBoxFlat
	var _score: Label
	var _hearts: HeartRow
	var _row: HBoxContainer
	var _medal_holder: Control
	var _shown: float = -1.0
	var _target: int = 0
	var _count: Tween
	var _status: Status = Status.NONE
	var _leader: bool = false
	var _mine: bool = false
	var _look: String = ""

	func _init(p_compact: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box = StyleBoxFlat.new()
		_box.set_corner_radius_all(12)
		_box.set_border_width_all(1)
		_box.anti_aliasing = true
		add_theme_stylebox_override(&"panel", _box)
		_row = HBoxContainer.new()
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_row.offset_left = 8
		_row.offset_right = -12
		_row.add_theme_constant_override(&"separation", 10)
		add_child(_row)
		_rank = PlaceMark.new()
		_rank.custom_minimum_size = Vector2(24, 0)
		_row.add_child(_rank)
		_medal_holder = Control.new()
		_medal_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_medal_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(_medal_holder)
		_medal = Panel.new()
		_medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_medal.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		_medal_box = StyleBoxFlat.new()
		_medal_box.anti_aliasing = true
		_medal.add_theme_stylebox_override(&"panel", _medal_box)
		_medal_holder.add_child(_medal)
		_portrait = TextureRect.new()
		_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_medal.add_child(_portrait)
		var ring := Panel.new()  # over the clipped picture so the ring stays crisp
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ring_box = StyleBoxFlat.new()
		_ring_box.draw_center = false
		_ring_box.set_border_width_all(3)
		_ring_box.anti_aliasing = true
		ring.add_theme_stylebox_override(&"panel", _ring_box)
		_medal.add_child(ring)
		_badge = StatusBadge.new()
		_medal_holder.add_child(_badge)
		var texts := VBoxContainer.new()
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.alignment = BoxContainer.ALIGNMENT_CENTER
		texts.add_theme_constant_override(&"separation", -5)
		_row.add_child(texts)
		_name = TableSkin.label("", 24, Palette.CREAM, true)
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_name.clip_text = true
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		texts.add_child(_name)
		_detail = TableSkin.label("", 15, TableSkin.TEXT_MUTED)
		_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_detail.add_theme_constant_override(&"outline_size", 0)
		_detail.clip_text = true
		texts.add_child(_detail)
		_tag = TableSkin.label("", 14, Palette.CREAM, true)
		_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_tag.add_theme_constant_override(&"outline_size", 0)
		_tag_box = TableSkin.band_box(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 10)
		_tag_box.content_margin_left = 8
		_tag_box.content_margin_right = 8
		_tag_box.content_margin_top = 1
		_tag_box.content_margin_bottom = 1
		_tag.add_theme_stylebox_override(&"normal", _tag_box)
		_row.add_child(_tag)
		_hearts = HeartRow.new()
		_hearts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(_hearts)
		_score = TableSkin.label("0", 32, Palette.CREAM, true)
		_score.add_theme_font_override(&"font", TableSkin.black_font())
		_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_score.custom_minimum_size = Vector2(44, 0)
		_row.add_child(_score)
		set_compact(p_compact)

	func tag() -> String:
		return _tag.text if _tag.visible else ""

	func status() -> Status:
		return _status

	func score_text() -> String:
		return _score.text if _score.visible else ""

	func set_compact(on: bool) -> void:
		compact = on
		var h: float = MinigameScoreboard.ROW_H_COMPACT if on else MinigameScoreboard.ROW_H
		var d: float = h - 10.0
		_medal_holder.custom_minimum_size = Vector2(d, d)
		_medal.size = Vector2(d, d)
		_medal_box.set_corner_radius_all(int(d / 2.0))
		_ring_box.set_corner_radius_all(int(d / 2.0))
		var b: float = 18.0 if on else 21.0
		_badge.size = Vector2(b, b)
		_badge.position = Vector2(d - b + 4.0, d - b + 3.0)
		_name.add_theme_font_size_override(&"font_size", 20 if on else 24)
		_score.add_theme_font_size_override(&"font_size", 26 if on else 32)
		_detail.add_theme_font_size_override(&"font_size", 13 if on else 15)
		_hearts.unit = 15.0 if on else 18.0
		_hearts.update_minimum_size()

	func apply(r: Dictionary, info: Dictionary, rank: int, leader: bool, mine: bool) -> void:
		var col: Color = info["color"]
		var status: Status = MinigameScoreboard.status_of(r.get("status", &""))
		_ring_box.border_color = col
		_medal_box.bg_color = col.darkened(0.45)
		var look: String = "%d|%s" % [int(info["bean"]), str(info["outfit"])]
		if look != _look:
			_look = look
			_portrait.texture = BeanPortraits.texture_for(int(info["bean"]), info["outfit"])
		_name.text = str(info["name"]) + ("  (you)" if mine else "")
		_name.add_theme_color_override(&"font_color", Palette.VIP_GOLD if mine else Palette.CREAM)
		var detail: String = str(r.get("detail", ""))
		_detail.text = detail
		_detail.visible = detail != ""
		var tag: String = str(r.get("tag", ""))
		_tag.text = tag
		_tag.visible = tag != ""
		if tag != "":
			var tc: Color = r.get("tag_color", Palette.CREAM)
			_tag.add_theme_color_override(&"font_color", tc)
			_tag_box.bg_color = Color(tc.darkened(0.6), 0.55)
			_tag_box.border_color = Color(tc, 0.5)
			_tag_box.set_border_width_all(1)
		_rank.rank = rank
		_rank.crown = leader
		_rank.queue_redraw()
		# Score: a number that counts up, fixed text, or hearts.
		_hearts.visible = r.has("hearts")
		if r.has("hearts"):
			_hearts.full = int(r["hearts"])
			_hearts.total = int(r.get("max_hearts", r["hearts"]))
			_hearts.update_minimum_size()
			_hearts.queue_redraw()
		if r.has("score_text"):
			_score.visible = true
			_score.text = str(r["score_text"])
			var long: bool = _score.text.length() > 5
			_score.add_theme_font_size_override(&"font_size", (18 if compact else 20) if long else (26 if compact else 32))
			_score.add_theme_font_override(&"font", TableSkin.heavy_font() if long else TableSkin.black_font())
			_shown = -1.0
		elif r.has("score"):
			_score.visible = true
			_set_score(int(r["score"]))
		else:
			_score.visible = false
		_score.add_theme_color_override(&"font_color", Palette.VIP_GOLD if leader else Palette.CREAM)
		# StatusBadge on the portrait.
		if status != _status:
			_badge.status = status
			_badge.queue_redraw()
			if status == Status.DONE and placed:
				TableSkin.pop(_badge, 0.2)
			_status = status
		modulate.a = 0.55 if status == Status.OUT else 1.0
		var new_leader: bool = leader and not _leader and placed
		_leader = leader
		_mine = mine
		_restyle()
		if new_leader:
			TableSkin.flash(self)

	func _restyle() -> void:
		if _leader:
			_box.bg_color = Color("#3A2B17")
			_box.border_color = TableSkin.BRASS
			_box.set_border_width_all(2)
		else:
			_box.bg_color = TableSkin.WALNUT_LIGHT
			_box.border_color = Color(TableSkin.BRASS, 0.7) if _mine else Color("#3E322A")
			_box.set_border_width_all(2 if _mine else 1)
		queue_redraw()

	func _draw() -> void:
		if _mine:  # a gold edge down the left so you find yourself at a glance
			draw_rect(Rect2(3, 9, 3, size.y - 18), Palette.VIP_GOLD)

	func _set_score(v: int) -> void:
		if _shown < 0.0 or not is_inside_tree() or not placed:
			_shown = v
			_target = v
			_score.text = Hud._thousands(v)
			return
		if v == _target:
			return
		var up: bool = v > _target
		_target = v
		if _count != null:
			_count.kill()
		_count = create_tween()
		_count.tween_method(_show_value, _shown, float(v), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_score.pivot_offset = _score.size * 0.5
		_score.scale = Vector2(1.3, 1.3)
		var pop: Tween = _score.create_tween()
		pop.tween_property(_score, ^"scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		TableSkin.flash(_score, Color(0.8, 1.5, 0.8) if up else Color(1.5, 0.7, 0.7))

	func _show_value(f: float) -> void:
		_shown = f
		_score.text = Hud._thousands(roundi(f))


## Place number, or a crown for the leader.
class PlaceMark extends Control:
	var rank: int = 1
	var crown: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		if crown:
			var w: float = 22.0
			var h: float = 15.0
			var o: Vector2 = c - Vector2(w * 0.5, h * 0.5)
			var pts := PackedVector2Array([
				o + Vector2(0, h), o + Vector2(0, h * 0.25), o + Vector2(w * 0.27, h * 0.6),
				o + Vector2(w * 0.5, 0), o + Vector2(w * 0.73, h * 0.6), o + Vector2(w, h * 0.25),
				o + Vector2(w, h)])
			draw_colored_polygon(pts, Palette.VIP_GOLD)
			pts.append(pts[0])
			draw_polyline(pts, TableSkin.BRASS_DARK, 1.2, true)
			for p: Vector2 in [o + Vector2(0, h * 0.25), o + Vector2(w * 0.5, 0), o + Vector2(w, h * 0.25)]:
				draw_circle(p, 2.2, Palette.CREAM)
			return
		if rank <= 0:
			return
		var f: Font = TableSkin.heavy_font()
		var s: String = str(rank)
		var fs: int = 20
		var tw: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TableSkin.TEXT_MUTED)


## The round state on the portrait's corner.
class StatusBadge extends Control:
	var status: Status = Status.NONE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if status == Status.NONE:
			return
		var c: Vector2 = size * 0.5
		var r: float = size.x * 0.5
		match status:
			Status.DONE:
				draw_circle(c, r, TableSkin.WALNUT)
				draw_circle(c, r - 2.0, Color("#3FA052"))
				var k: float = r * 0.5
				draw_polyline(PackedVector2Array([c + Vector2(-k, 0.05 * k), c + Vector2(-0.25 * k, 0.75 * k), c + Vector2(k, -0.6 * k)]), Color.WHITE, 2.6, true)
			Status.WAITING:
				draw_circle(c, r * 0.8, TableSkin.WALNUT)
				draw_circle(c, r * 0.8 - 2.0, Color("#5A4E44"))
				for i: int in 3:
					draw_circle(c + Vector2((i - 1) * r * 0.42, 0), r * 0.13, Palette.CREAM.darkened(0.2))
			Status.OUT:
				draw_circle(c, r, TableSkin.WALNUT)
				draw_circle(c, r - 2.0, Palette.LOSS_RED.darkened(0.15))
				var k: float = r * 0.38
				draw_line(c + Vector2(-k, -k), c + Vector2(k, k), Color.WHITE, 2.4, true)
				draw_line(c + Vector2(-k, k), c + Vector2(k, -k), Color.WHITE, 2.4, true)


## A row of hearts (lives), full first.
class HeartRow extends Control:
	var full: int = 0
	var total: int = 0
	var unit: float = 18.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(maxf(total * (unit + 3.0) - 3.0, 0.0), unit)

	func _draw() -> void:
		for i: int in total:
			var o := Vector2(i * (unit + 3.0) + unit * 0.5, unit * 0.55)
			var col: Color = Palette.LOSS_RED if i < full else Color("#4A3E36")
			_heart(o, unit * 0.5, col)

	func _heart(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i: int in 24:
			var t: float = TAU * i / 24.0
			var x: float = 16.0 * pow(sin(t), 3)
			var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			pts.append(c + Vector2(x, y) * (r / 17.0))
		draw_colored_polygon(pts, col)
