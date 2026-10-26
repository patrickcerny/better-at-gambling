class_name ColorPanelController
extends Node
## Client side of the pedestal colour panels (`ColorPlaque`, Patrick: "under the podest should be
## a color panel you can click (choose color)"). Keeps every plaque showing the right swatches:
## your own pedestal's the colours your profile owns (the one your bean wears framed, the ones
## other beans wear dimmed), the others the free colours with their owner's framed. In the lobby,
## standing at your own plaque and looking at a swatch, a click or E (`try_press`) sends
## `set_color`; the server checks it is free and broadcasts `player_color`, so your bean recolours
## for everyone, and the colour becomes your preferred one in the profile (worn on every join).
## Only your own pedestal's panel works for you.

## How close (m, flat) you must stand to your plaque to use it.
const RANGE: float = 2.6

var scene: MatchScene
## The colour under the crosshair on your own plaque (-1 = none).
var aimed: int = -1


func _init(p_scene: MatchScene) -> void:
	scene = p_scene
	name = "ColorPanelController"


## The local player's slot (their pedestal) and wire dictionary.
func _me() -> Dictionary:
	return scene.view.state.players.get(scene.local_id, {}) if scene != null and scene.view != null else {}


func _plaque(slot: int) -> ColorPlaque:
	var lounge: LuckyLounge = scene.map as LuckyLounge if scene != null else null
	if lounge == null or slot < 0 or slot >= lounge.color_plaques.size():
		return null
	return lounge.color_plaques[slot]


## True while colours can be changed (the lobby of an online room, or Practice's lobby).
func _open() -> bool:
	return scene.view.state.phase == Phase.Id.LOBBY


## Bean colours the other connected players wear.
func worn_by_others() -> Array[int]:
	var out: Array[int] = []
	for pid: Variant in scene.view.state.players:
		var p: Dictionary = scene.view.state.players[pid]
		if int(pid) != scene.local_id and bool(p.get("connected", true)):
			out.append(int(p.get("bean_color", p.get("color", 0))))
	return out


## True when the local player stands by their own plaque in the lobby.
func near_own_plaque() -> bool:
	var me: Dictionary = _me()
	var plaque: ColorPlaque = _plaque(int(me.get("color", -1)))
	if plaque == null or scene.local == null or not scene.local.is_standing() or not _open():
		return false
	var a: Vector3 = scene.local.global_position
	var b: Vector3 = plaque.global_position
	return Vector2(a.x - b.x, a.z - b.z).length() <= RANGE and absf(a.y - b.y) < 1.2


## Shows the right swatches on every plaque (cheap: plaques rebuild only on a change).
func refresh_plaques() -> void:
	var lounge: LuckyLounge = scene.map as LuckyLounge if scene != null else null
	if lounge == null or scene.view == null:
		return
	var free: Array[int] = []
	for c: int in Cosmetics.SLOT_COLORS:
		free.append(c)
	var by_slot: Dictionary = {}
	for pid: Variant in scene.view.state.players:
		var p: Dictionary = scene.view.state.players[pid]
		if bool(p.get("connected", true)):
			by_slot[int(p.get("color", -1))] = p
	var me: Dictionary = _me()
	var mine: int = int(me.get("color", -1))
	for i: int in lounge.color_plaques.size():
		var owner: Dictionary = by_slot.get(i, {})
		var bean: int = int(owner.get("bean_color", owner.get("color", -1))) if not owner.is_empty() else -1
		if i == mine and scene.local_id >= 0:
			lounge.color_plaques[i].show_colors(ProfileManager.profile.owned_colors(), bean, worn_by_others(), true)
		else:
			var shown: Array[int] = free.duplicate()
			if bean >= Cosmetics.SLOT_COLORS:
				shown.append(bean)  # a bought colour: show it framed too
			lounge.color_plaques[i].show_colors(shown, bean, [], false)


func _process(_delta: float) -> void:
	if scene == null or scene.view == null or scene.map == null:
		return
	refresh_plaques()
	var plaque: ColorPlaque = _plaque(int(_me().get("color", -1)))
	var now: int = -1
	if near_own_plaque() and scene.local.cam != null:
		var cam: Camera3D = scene.local.cam.camera
		now = plaque.swatch_at(cam.global_position, -cam.global_transform.basis.z)
	aimed = now
	if plaque != null:
		plaque.set_hovered(aimed)


## The HUD prompt while at your plaque ("" elsewhere).
func prompt() -> String:
	if not near_own_plaque():
		return ""
	if aimed < 0:
		return "YOUR COLOUR PANEL: look at a colour (buy more in the main menu's COSMETICS)"
	var name_: String = Palette.PLAYER_COLOR_NAMES[aimed]
	if aimed == int(_me().get("bean_color", -1)):
		return "Your bean wears %s" % name_
	if aimed in worn_by_others():
		return "%s: another bean wears it" % name_
	return InputGlyphs.fill("[{interact} / {grab}] Wear %s") % name_


## Click or E at your plaque: wear the aimed colour. True when the press was used here.
func try_press() -> bool:
	if aimed < 0 or not near_own_plaque():
		return false
	return choose(aimed)


## Asks the server for colour `c` and, when it takes it, makes it the preferred colour.
func choose(c: int) -> bool:
	if not ProfileManager.profile.owns_color(c):
		scene.hud.toast("Buy %s in the main menu's COSMETICS first" % Palette.PLAYER_COLOR_NAMES[c], 2.0)
		return true
	if c == int(_me().get("bean_color", -1)):
		ProfileManager.set_preferred_color(c)
		return true
	var res: Dictionary = Net.send_intent(Intents.make(&"set_color", {"color": c}))
	if not bool(res.get("ok", false)):
		scene.hud.toast("Another bean wears %s" % Palette.PLAYER_COLOR_NAMES[c] if res.get("error", &"") == &"color_taken" else "Can't change colour now", 1.8)
		return true
	ProfileManager.set_preferred_color(c)
	Audio.play(&"ui_click", &"UI", -6.0, 1.2)
	return true
