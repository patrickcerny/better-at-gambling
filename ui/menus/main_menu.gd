extends Control
## Main menu. M0: boots and shows the entries; most actions are wired in later milestones.

@onready var _play_online: Button = %PlayOnline
@onready var _practice: Button = $Center/VBox/Practice
@onready var _quit: Button = %Quit


func _ready() -> void:
	_quit.pressed.connect(_on_quit_pressed)
	_practice.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.MATCH))
	_play_online.disabled = true  # M3
	_play_online.tooltip_text = "Online play arrives with the dedicated server milestone"
	_practice.grab_focus()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Log.info(&"menu", "main menu ready")


func _on_quit_pressed() -> void:
	get_tree().quit()
