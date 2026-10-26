class_name ProfileBadge
extends PanelContainer
## The profile line on the main menu (docs/GDD.md "Progression"): LEVEL n, the XP bar to the next
## level with "x / y XP", and the Coins balance with its coin. Follows `ProfileManager.changed`.

var level_label: Label
var xp_bar: ProgressBar
var xp_label: Label
var coins_label: Label


func _ready() -> void:
	name = "ProfileBadge"
	theme_type_variation = &"HudPlate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	level_label = Label.new()
	level_label.name = "Level"
	level_label.theme_type_variation = &"HeadingLabel"
	level_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	level_label.custom_minimum_size.x = 150
	h.add_child(level_label)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	xp_bar = ProgressBar.new()
	xp_bar.name = "XpBar"
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(200, 12)
	xp_bar.max_value = 1.0
	xp_bar.step = 0.0
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(xp_bar)
	xp_label = Label.new()
	xp_label.name = "Xp"
	xp_label.theme_type_variation = &"SmallLabel"
	v.add_child(xp_label)
	var coins := HBoxContainer.new()
	coins.add_theme_constant_override(&"separation", 6)
	coins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(coins)
	var icon := CoinIcon.make(30.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins.add_child(icon)
	coins_label = Label.new()
	coins_label.name = "Coins"
	coins_label.add_theme_color_override(&"font_color", Palette.COIN_GOLD)
	coins_label.tooltip_text = "Coins: earned by playing, spent on cosmetics. Never on the tables."
	coins.add_child(coins_label)
	ProfileManager.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var p: PlayerProfile = ProfileManager.profile
	if p == null or level_label == null:
		return
	level_label.text = "LEVEL %d" % p.level
	xp_bar.value = p.level_progress()
	var need: int = p.xp_needed()
	xp_label.text = "%d / %d XP" % [p.xp_into_level(), need] if need > 0 else "MAX LEVEL"
	coins_label.text = "%d" % p.coins
