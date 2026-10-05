extends SceneTree
## Regenerates the `[input]` section of project.godot with keyboard, mouse and
## joypad bindings for every action in the design (§2.4, §2.8, §2.14).
## Run: tools/godot/godot --headless --path . -s tools/gen_input_map.gd

# [action, deadzone, [events...]]; events: "key:W", "mouse:1", "joy:0" (button), "axis:1:-1"
const ACTIONS: Array = [
	["move_forward", 0.2, ["key:W", "key:Up", "axis:1:-1"]],
	["move_back", 0.2, ["key:S", "key:Down", "axis:1:1"]],
	["move_left", 0.2, ["key:A", "key:Left", "axis:0:-1"]],
	["move_right", 0.2, ["key:D", "key:Right", "axis:0:1"]],
	["look_up", 0.15, ["axis:3:-1"]],
	["look_down", 0.15, ["axis:3:1"]],
	["look_left", 0.15, ["axis:2:-1"]],
	["look_right", 0.15, ["axis:2:1"]],
	["sprint", 0.5, ["key:Shift", "joy:7"]],
	["jump", 0.5, ["key:Space", "joy:0"]],
	["interact", 0.5, ["key:E", "joy:2"]],
	["leave_station", 0.5, ["key:Q", "joy:1"]],
	["grab", 0.5, ["mouse:1", "axis:5:1"]],
	["shove", 0.5, ["mouse:2", "joy:10"]],
	["toggle_camera", 0.5, ["key:V", "joy:4"]],
	["emote_wheel", 0.5, ["key:G", "joy:12"]],
	["ping", 0.5, ["mouse:3", "key:Z"]],
	["item_1", 0.5, ["key:1", "joy:13"]],
	["item_2", 0.5, ["key:2", "joy:11"]],
	["item_3", 0.5, ["key:3", "joy:14"]],
	["leaderboard", 0.5, ["key:Tab", "joy:3"]],
	["pause", 0.5, ["key:Escape", "joy:6"]],
	["push_to_talk", 0.5, ["key:T", "key:CapsLock", "joy:9"]],
	["bet_confirm", 0.5, ["key:Space", "key:Enter", "joy:0"]],
	["bet_clear", 0.5, ["key:Backspace", "joy:2"]],
	["bet_repeat", 0.5, ["key:R", "joy:3"]],
	["bet_chip_prev", 0.5, ["joy:9"]],
	["bet_chip_next", 0.5, ["joy:10"]],
	["bet_chip_1", 0.5, ["key:1"]],
	["bet_chip_2", 0.5, ["key:2"]],
	["bet_chip_3", 0.5, ["key:3"]],
	["bet_chip_4", 0.5, ["key:4"]],
	["bj_hit", 0.5, ["key:H", "joy:0"]],
	["bj_stand", 0.5, ["key:S", "joy:2"]],
	["bj_double", 0.5, ["key:D", "joy:3"]],
	["bj_split", 0.5, ["key:P", "joy:10"]],
	["break_free", 0.5, ["key:Space", "joy:0"]],
	["shake", 0.5, ["key:E", "joy:2"]],
]


func _init() -> void:
	for entry: Array in ACTIONS:
		var events: Array[InputEvent] = []
		for spec: String in entry[2]:
			var ev: InputEvent = _make_event(spec)
			if ev == null:
				push_error("bad event spec %s" % spec)
				quit(1)
				return
			ev.device = -1  # all devices
			events.append(ev)
		ProjectSettings.set_setting("input/" + str(entry[0]), {"deadzone": float(entry[1]), "events": events})
	var err: Error = ProjectSettings.save()
	print("input map written: %d actions (err=%d)" % [ACTIONS.size(), err])
	quit(0 if err == OK else 1)


func _make_event(spec: String) -> InputEvent:
	var parts: PackedStringArray = spec.split(":")
	match parts[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = OS.find_keycode_from_string(parts[1])
			return k if k.physical_keycode != KEY_NONE else null
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(parts[1]) as MouseButton
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.button_index = int(parts[1]) as JoyButton
			return j
		"axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(parts[1]) as JoyAxis
			a.axis_value = float(parts[2])
			return a
	return null
