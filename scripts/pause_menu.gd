extends Control

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var resume: Button = $Center/Resume
@onready var restart: Button = $Center/Restart
@onready var menu: Button = $Center/Menu

func _ready():
	resume.text = "RESUME   继续"
	restart.text = "RESTART  重玩"
	menu.text = "MENU     主菜单"
	resume.pressed.connect(_on_resume)
	restart.pressed.connect(_on_restart)
	menu.pressed.connect(_on_menu)
	resume.grab_focus()

func _on_resume():
	_am().play_sfx("click")
	var game = get_tree().current_scene
	if game and game.has_method("_toggle_pause"):
		game._toggle_pause()

func _on_restart():
	_am().play_sfx("click")
	get_tree().paused = false
	var new_game = preload("res://scenes/game.tscn").instantiate()
	get_parent().add_child(new_game)
	queue_free()

func _on_menu():
	_am().play_sfx("click")
	get_tree().paused = false
	var m = preload("res://scenes/menu.tscn").instantiate()
	get_parent().add_child(m)
	queue_free()
