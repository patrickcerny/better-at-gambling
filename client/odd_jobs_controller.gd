class_name OddJobsController
extends Node
## Client side of the Odd Jobs cabinet (no window): walk up, look at the big red button and click
## (left mouse or E); each click is one `odd_jobs_press`. The bar is shared by everyone in the
## casino and the click that fills it wins the $50 (server/odd_jobs.gd); the cabinet shows the bar,
## "N clicks to $50" at your own share and who won. While you are broke (below the House Comp line,
## the smallest table minimum) the cabinet's lamps pulse and the button is outlined, with a
## one-time hint. Never decides anything: the server counts, fills and pays.

const ENOUGH_TEXT: String = "You've got enough. Go gamble!"
## Client-side cap on sends (the server drops anything over ~12/s anyway).
const MIN_SEND_GAP: float = 1.0 / 14.0
const HINT_TEXT: String = "Broke? Smash the big red button at the Odd Jobs cabinet by the Gift Shop: $50 a bar."

var scene: MatchScene
## True while the local player looks at the button from the stand spot.
var aimed: bool = false
var broke: bool = false
## The shared bar as last heard from the server (plus local clicks counted ahead online).
var fill: float = 0.0
var _last_send: float = -INF


func _init(p_scene: MatchScene) -> void:
	scene = p_scene
	name = "OddJobsController"


func _ready() -> void:
	if not Net.event_received.is_connected(_on_event):
		Net.event_received.connect(_on_event)


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)


func cabinet() -> OddJobsCabinet:
	return scene.map.odd_jobs if scene != null and scene.map != null else null


func money() -> int:
	return scene.view.state.balance(scene.local_id) if scene != null and scene.view != null else 0


## Below this the player counts as broke: the House Comp line (= the smallest table minimum),
## scaled with the table limits like the server's comp check.
static func broke_line(cfg: BalanceConfig, segment: int) -> int:
	return int(floor(cfg.comp_threshold * cfg.limits_multiplier(segment)))


func _casino_open() -> bool:
	var ph: Phase.Id = scene.view.state.phase
	return (ph == Phase.Id.CASINO or ph == Phase.Id.PRE_MINIGAME) and not scene._minigames_only()


## True when the local player stands at the cabinet and the camera looks at the button.
func is_aiming() -> bool:
	var cab: OddJobsCabinet = cabinet()
	if cab == null or scene.local == null or not scene.local.is_standing() or scene.local.cam == null:
		return false
	if not scene._near_odd_jobs():
		return false
	var cam: Camera3D = scene.local.cam.camera
	return cab.aimed_by(cam.global_position, -cam.global_transform.basis.z)


func _process(_delta: float) -> void:
	var cab: OddJobsCabinet = cabinet()
	if cab == null or scene.local == null:
		return
	aimed = is_aiming()
	cab.set_aimed(aimed)
	var now_broke: bool = _casino_open() and money() < broke_line(scene.cfg, scene.view.state.segment_index)
	if now_broke != broke:
		broke = now_broke
		cab.set_glow(broke)
		if broke:
			scene._hint(&"odd_jobs", HINT_TEXT, 1.0)
	cab.set_counts(fill, OddJobs.presses_needed(money()))


## A click (left mouse or E): presses the button when the player looks at it. False = not aimed,
## so the click goes on to its usual use (grab, sit, ...).
func try_press() -> bool:
	if not is_aiming():
		return false
	var cab: OddJobsCabinet = cabinet()
	if money() >= OddJobs.CAP:
		cab.show_note(ENOUGH_TEXT)
		scene.hud.toast(ENOUGH_TEXT, 1.5)
		return true
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_send < MIN_SEND_GAP:
		return true
	_last_send = now
	var res: Dictionary = Net.send_intent(Intents.make(&"odd_jobs_press"))
	cab.dip()
	Audio.play_at(&"ui_click", cab.button, -2.0, randf_range(0.85, 1.1))
	if not res["ok"]:
		cab.show_note(reason(res["error"]))
		return true
	if bool(res.get("pending", false)):
		fill = minf(fill + 1.0 / maxi(OddJobs.presses_needed(money()), 1), 0.999)  # the server's bar follows
		cab.set_fill(fill)
	return true


func _on_event(ev: Dictionary) -> void:
	var type: StringName = StringName(ev.get("type", &""))
	if type != &"odd_jobs_bar" and type != &"odd_jobs_payout" and type != &"intent_rejected":
		return  # other events carry "player" as a dictionary (player_joined), never int() those
	var cab: OddJobsCabinet = cabinet()
	if cab == null or scene == null:
		return
	var who: int = int(ev.get("player", -1))
	match type:
		&"odd_jobs_bar":
			var f: float = float(ev["fill"])
			if who >= 0 and who != scene.local_id and f > fill:
				cab.dip()  # someone else is smashing it
			fill = f
			cab.set_fill(fill)
		&"odd_jobs_payout":
			fill = 0.0
			cab.set_fill(0.0)
			if who == scene.local_id:
				cab.show_note("+$%d! YOUR CLICK WON" % int(ev["amount"]))
			else:
				cab.show_note("+$%d TO %s" % [int(ev["amount"]), scene.view.state.player_name(who).to_upper()])
		&"intent_rejected":
			if who == scene.local_id and StringName(ev.get("intent", &"")) == &"odd_jobs_press":
				cab.show_note(reason(StringName(ev.get("error", &""))))


static func reason(error: StringName) -> String:
	match error:
		&"enough_money":
			return ENOUGH_TEXT
		&"money_off":
			return "No money in this mode."
		&"too_far":
			return "Too far away"
		&"wrong_phase":
			return "The casino is closed."
		&"not_standing":
			return "Stand up first"
	return String(error).capitalize()
