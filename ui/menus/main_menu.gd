extends Control
## Main menu: Play Online (create a party, join by code or address, rejoin), Practice, Quit.
## Connection errors from the last online attempt are shown here when we return.

@onready var _play_online: Button = %PlayOnline
@onready var _practice: Button = $Center/VBox/Practice
@onready var _quit: Button = %Quit
@onready var _main_box: VBoxContainer = $Center/VBox

var _online_box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _ip_edit: LineEdit
var _rejoin: Button
var _status: Label
var _busy: bool = false


func _ready() -> void:
	_quit.pressed.connect(_on_quit_pressed)
	_practice.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.MATCH))
	_play_online.pressed.connect(_show_online)
	_build_online()
	_practice.grab_focus()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.last_error != "":
		# Back from a failed or lost online session: say why.
		_show_online()
		_set_status(Net.last_error, true)
		Net.last_error = ""
	Log.info(&"menu", "main menu ready")


func _build_online() -> void:
	_online_box = VBoxContainer.new()
	_online_box.name = "Online"
	_online_box.custom_minimum_size = Vector2(480, 0)
	_online_box.add_theme_constant_override(&"separation", 12)
	_online_box.visible = false
	$Center.add_child(_online_box)
	var title := Label.new()
	title.text = "PLAY ONLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	_online_box.add_child(title)
	_name_edit = _field("Your name", SceneRouter.profile_name(), 24)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _save_name())
	_name_edit.focus_exited.connect(_save_name)
	_online_box.add_child(_button("Create Party", _create))
	var join_row := HBoxContainer.new()
	_online_box.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ROOM CODE"
	_code_edit.max_length = 5
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_changed.connect(func(t: String) -> void:
		var caret: int = _code_edit.caret_column
		_code_edit.text = t.to_upper()
		_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_code())
	join_row.add_child(_code_edit)
	join_row.add_child(_button("Join", _join_code))
	var ip_row := HBoxContainer.new()
	_online_box.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "host:port (direct, for testing)"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join_ip())
	ip_row.add_child(_ip_edit)
	ip_row.add_child(_button("Connect", _join_ip))
	_online_box.add_child(_button("Host on This PC (LAN / port %d)" % Protocol.DEFAULT_PORT, _host_local))
	_rejoin = _button("Rejoin Last Party", _rejoin_last)
	_online_box.add_child(_rejoin)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(480, 0)
	_online_box.add_child(_status)
	_online_box.add_child(_button("Back", _show_main))


func _field(placeholder: String, value: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.max_length = max_len
	_online_box.add_child(e)
	return e


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override(&"font_size", 24)
	b.pressed.connect(cb)
	return b


func _show_online() -> void:
	_main_box.visible = false
	_online_box.visible = true
	var last: Dictionary = Net.online.last_room()
	_rejoin.visible = str(last.get("room_id", "")) != ""
	_rejoin.text = "Rejoin Last Party (%s)" % last.get("room_code", "") if _rejoin.visible else ""
	_status.text = ""
	_online_box.get_child(2).grab_focus()


func _show_main() -> void:
	if _busy:
		return
	_online_box.visible = false
	_main_box.visible = true
	_play_online.grab_focus()


func _save_name() -> void:
	var n: String = _name_edit.text.strip_edges()
	if n != "":
		Settings.set_value("profile", "name", n)
		Settings.save()


func _display_name() -> String:
	_save_name()
	return SceneRouter.profile_name()


func _set_status(text: String, error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", Palette.LOSS_RED if error else Palette.CREAM)


func _create() -> void:
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.create_party(n), "Creating party…")


func _join_code() -> void:
	var code: String = _code_edit.text.strip_edges().to_upper()
	if code.length() != 5:
		_set_status("Room codes have 5 letters.", true)
		return
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.join_party(n, code), "Joining %s…" % code)


func _rejoin_last() -> void:
	var last: Dictionary = Net.online.last_room()
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.join_party(n, "", str(last.get("room_id", ""))), "Rejoining…")


func _via_orchestrator(call: Callable, busy_text: String) -> void:
	if _busy:
		return
	_busy = true
	_set_status(busy_text)
	var name_: String = _display_name()
	var room: Dictionary = await call.call(name_)
	if room.is_empty():
		_busy = false
		_set_status(Net.online.last_error, true)
		return
	_connect(func() -> Error: return Net.online.connect_room(room, name_, SceneRouter.profile_cosmetics()))


func _join_ip() -> void:
	if _busy:
		return
	var parts: PackedStringArray = _ip_edit.text.strip_edges().rsplit(":", true, 1)
	var host: String = parts[0] if parts.size() > 0 and parts[0] != "" else "127.0.0.1"
	var port: int = int(parts[1]) if parts.size() > 1 else Protocol.DEFAULT_PORT
	_busy = true
	_set_status("Connecting to %s:%d…" % [host, port])
	var hello: Dictionary = SceneRouter.profile_cosmetics()
	hello["name"] = _display_name()
	_connect(func() -> Error: return Net.join_server(host, port, hello))


## Starts a dedicated server process on this machine (closes itself once everyone has left) and
## joins it. Friends connect with this PC's address; the UDP port must be reachable for them.
func _host_local() -> void:
	if _busy:
		return
	var args: PackedStringArray = []
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--headless", "--audio-driver", "Dummy", "--", "--server", "--port", str(Protocol.DEFAULT_PORT), "--empty-timeout", "30"])
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		_set_status("Could not start a server on this PC.", true)
		return
	Log.info(&"menu", "started local server (pid %d)" % pid)
	_busy = true
	_set_status("Starting a server on this PC…")
	await get_tree().create_timer(2.5).timeout
	var hello: Dictionary = SceneRouter.profile_cosmetics()
	hello["name"] = _display_name()
	_connect(func() -> Error: return Net.join_server("127.0.0.1", Protocol.DEFAULT_PORT, hello))


## Starts the UDP connection; the match scene loads once the server welcomes us.
func _connect(start: Callable) -> void:
	Net.connected.connect(_on_connected, CONNECT_ONE_SHOT)
	Net.disconnected.connect(_on_failed, CONNECT_ONE_SHOT)
	var err: Error = start.call()
	if err != OK:
		_on_failed(Net.last_error if Net.last_error != "" else "Could not open a connection.")


func _on_connected() -> void:
	if Net.disconnected.is_connected(_on_failed):
		Net.disconnected.disconnect(_on_failed)
	SceneRouter.goto(SceneRouter.MATCH)


func _on_failed(reason: String) -> void:
	if Net.connected.is_connected(_on_connected):
		Net.connected.disconnect(_on_connected)
	_busy = false
	Net.last_error = ""
	_set_status(reason, true)


func _on_quit_pressed() -> void:
	get_tree().quit()
