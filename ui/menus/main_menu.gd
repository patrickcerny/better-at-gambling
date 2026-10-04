extends Control
## Main menu. M0: boots and shows the entries; most actions are wired in later milestones.

@onready var _play_online: Button = %PlayOnline
@onready var _quit: Button = %Quit


func _ready() -> void:
	_quit.pressed.connect(_on_quit_pressed)
	_play_online.grab_focus()
	Log.info(&"menu", "main menu ready")


func _on_quit_pressed() -> void:
	get_tree().quit()
