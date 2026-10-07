class_name EventSfx
extends RefCounted
## Sounds for server events that `MatchScene._on_event` shows without one of its own (M7 game-feel
## pass: every action has audio feedback). The full event → sound map is in docs/GDD.md
## ("Game-feel checklist"). Positional where the event happens at a player, 2D when it is about
## the local player. Silent on headless servers (the `Audio` autoload is).

## Local round losses play the sad sting at most this often (roulette loses a lot).
const LOSS_STING_GAP: float = 6.0

var scene: MatchScene
var _last_sting: float = -INF


func _init(p_scene: MatchScene) -> void:
	scene = p_scene


func on_event(ev: Dictionary) -> void:
	var me: int = scene.local_id
	match StringName(ev["type"]):
		&"phase_changed":
			var phase: int = int(ev["phase"])
			var from: int = int(ev.get("from", -1))
			if phase == Phase.Id.INTRO or (phase == Phase.Id.CASINO and from == Phase.Id.REGROUP):
				Audio.play(&"chime", &"SFX", -8.0)
		&"round_result":
			if int(ev["player"]) == me and int(ev["net"]) < 0:
				var now: float = Time.get_ticks_msec() / 1000.0
				if now - _last_sting >= LOSS_STING_GAP:
					_last_sting = now
					Audio.play(&"loss_sting", &"SFX", -14.0)
		&"shop_bought":
			_at(int(ev["player"]), &"cash_register", -6.0)
		&"monkey_passed":
			_at(int(ev["to"]), &"boing", -6.0, 1.2)
		&"fake_cash_caught":
			_at(int(ev["player"]), &"buzzer", -6.0)
		&"credit_repaid":
			if int(ev["player"]) == me:
				Audio.play(&"chip_clack", &"SFX", -6.0, 0.7)
		&"collar_cut":
			if int(ev["owner"]) == me:
				Audio.play(&"coin", &"SFX", -8.0, 1.2)
		&"rps_result":
			if not bool(ev["replay"]) and (int(ev["a"]) == me or int(ev["b"]) == me):
				var w: int = int(ev["winner"])
				if w == me:
					Audio.play(&"big_win", &"SFX", -8.0)
				elif w >= 0:
					Audio.play(&"loss_sting", &"SFX", -10.0)
		&"rps_start":
			if int(ev["a"]) == me or int(ev["b"]) == me:
				Audio.play(&"countdown_beep", &"UI", -8.0, 1.1)
		&"bets_refunded":
			if int(ev["player"]) == me and int(ev.get("amount", 0)) > 0:
				Audio.play(&"chip_clack", &"SFX", -6.0, 0.9)
		&"regroup_started":
			Audio.play(&"whoosh", &"SFX", -8.0)
		&"banana_placed":
			_at(int(ev["owner"]), &"thud", -10.0, 1.4)
		&"player_grabbed":
			_at(int(ev["target"]), &"oof", -10.0, 1.15)
		&"player_broke_free":
			_at(int(ev["target"]), &"whoosh", -10.0, 1.3)
		&"player_released":
			_at(int(ev["target"]), &"thud", -12.0)
		&"emote":
			_at(int(ev["player"]), &"jump", -14.0, 1.2)
		&"player_respawned":
			if int(ev["player"]) == me:
				Audio.play(&"whoosh", &"SFX", -10.0, 0.8)
		&"item_used":
			if StringName(ev.get("result", &"")) == &"reflected":
				_at(int(ev["target"]), &"boing", -6.0, 1.4)
		&"player_joined", &"player_rejoined":
			Audio.play(&"ui_click", &"UI", -14.0, 1.2)
		&"player_left":
			Audio.play(&"ui_hover", &"UI", -12.0, 0.7)
		&"player_skin":
			_at(int(ev["player"]), &"pickup", -10.0, 1.2)
		&"player_got_up":
			_at(int(ev["player"]), &"jump", -16.0, 0.8)
		&"player_stood":
			if int(ev["player"]) == me:
				Audio.play(&"ui_hover", &"UI", -10.0)
		&"intent_rejected":
			var err: StringName = StringName(ev["error"])
			if int(ev["player"]) == me and not err in [&"rate_limited", &"not_standing", &"vip_denied", &"no_target"]:
				Audio.play(&"buzzer", &"UI", -18.0, 1.4)
		&"rps_cancelled":
			if int(ev["a"]) == me:
				Audio.play(&"ui_hover", &"UI", -8.0, 0.8)
		&"match_reset":
			Audio.play(&"chime", &"SFX", -10.0, 0.9)
		&"megaphone_dropped":
			_at(int(ev["player"]), &"ui_click", -10.0, 0.7)
		&"effect_ended":
			if int(ev["player"]) == me:
				Audio.play(&"ui_hover", &"UI", -10.0, 0.8)


func _at(pid: int, clip: StringName, db: float, pitch: float = 1.0) -> void:
	var a: PlayerAvatar = scene.avatars.get(pid, null)
	if a != null:
		Audio.play_at(clip, a, db, pitch)

