extends CanvasLayer
## `Loading` autoload: the loading screen between the menu and a match (M6). The live casino
## panorama (`CasinoPanorama`, blurred and gently tilting) with the logo, a tip and "Loading…".
## `SceneRouter.goto` calls `begin` before it swaps to the match and the match scene calls
## `finish` once its world is built. Nothing shows when headless.

## Shortest time the screen stays up, so it never just flashes.
const MIN_SECONDS: float = 1.6
const FADE_SECONDS: float = 0.6
const TIPS: Array[String] = [
	"Luck is visible: every reroll it gives you shows up on the table.",
	"Knock someone over and shake them. Their chips are yours if you grab them first.",
	"Hot Tables pay extra. Follow the big jumping arrow.",
	"Guards throw out anyone causing trouble near the tables. Mostly.",
	"The jackpot grows with every Slots and Plinko bet. Three Diamonds take it all.",
	"The Casino Quiz pays the fastest correct answers best.",
	"Out of Order signs close the nearest table for 30 seconds.",
	"Press {interact} at the Gift Shop next to the bar: one purchase per round.",
	"Spend items before the next draft. You can only carry three.",
	"At blackjack, {bj_hit} hits, {bj_stand} stands, {bj_double} doubles and {bj_split} splits a pair.",
	"Settings live under {pause}, in game and in the menu.",
	"Last Call: in the final minute every table pays ×1.5.",
]

var _root: Control
var _shown_at: float = 0.0
var _finishing: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


## True while the screen is up.
func is_showing() -> bool:
	return _root != null


## Puts the screen up (no-op headless or when already showing).
func begin() -> void:
	if _root != null or DisplayServer.get_name() == "headless":
		return
	_finishing = false
	_shown_at = Time.get_ticks_msec() / 1000.0
	_root = Control.new()
	_root.name = "LoadingScreen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = load("res://ui/theme/main_theme.tres") as Theme
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Palette.CASINO_BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var pano := CasinoPanorama.new()
	pano.blur_px = 3.0
	pano.darken = 0.5
	pano.start_leg = randf() * CasinoPanorama.PATH.size()
	_root.add_child(pano)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 18)
	_root.add_child(box)
	var title := Label.new()
	title.text = "BETTER AT GAMBLING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 84)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override(&"shadow_offset_y", 4)
	box.add_child(title)
	var loading := Label.new()
	loading.name = "Loading"
	loading.text = "Loading"
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override(&"font_size", 40)
	loading.add_theme_color_override(&"font_color", Palette.CREAM)
	box.add_child(loading)
	var tip := Label.new()
	tip.text = InputGlyphs.fill(TIPS[randi() % TIPS.size()])
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(900, 0)
	tip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tip.add_theme_font_size_override(&"font_size", 30)
	tip.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.15))
	box.add_child(tip)


func _process(_delta: float) -> void:
	if _root == null or _finishing:
		return
	var dots: int = int(Time.get_ticks_msec() / 400.0) % 4
	(_root.find_child("Loading", true, false) as Label).text = "Loading" + ".".repeat(dots)


## Fades the screen out (after `MIN_SECONDS`) and frees it.
func finish() -> void:
	if _root == null or _finishing:
		return
	_finishing = true
	var wait: float = MIN_SECONDS - (Time.get_ticks_msec() / 1000.0 - _shown_at)
	if wait > 0.0:
		await get_tree().create_timer(wait, true, false, true).timeout
	if _root == null:
		return
	var tw: Tween = create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	await tw.finished
	if _root != null:
		_root.queue_free()
		_root = null
	_finishing = false
