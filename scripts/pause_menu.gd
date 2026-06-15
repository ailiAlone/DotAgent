extends Control

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var resume: Button = $Center/Resume
@onready var restart: Button = $Center/Restart
@onready var menu: Button = $Center/Menu

func _ready():
	# 必须 ALWAYS：暂停时按钮仍可点击、ESC 仍可解除
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume.text = "RESUME   继续"
	restart.text = "RESTART  重玩"
	menu.text = "MENU     主菜单"
	resume.pressed.connect(_on_resume)
	restart.pressed.connect(_on_restart)
	menu.pressed.connect(_on_menu)
	resume.grab_focus()

func _unhandled_input(event):
	# 暂停时让 ESC 也能解除暂停（game.gd 此时已 INHERIT 不跑 _process）
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# 找 game 调 _toggle_pause
			var game = get_tree().current_scene
			if game and game.has_method("_toggle_pause"):
				game._toggle_pause()
			get_viewport().set_input_as_handled()

func _on_resume():
	_am().play_sfx("click")
	var game = get_tree().current_scene
	if game and game.has_method("_toggle_pause"):
		game._toggle_pause()

func _on_restart():
	_am().play_sfx("click")
	get_tree().paused = false
	var game_scene = load("res://scenes/game.tscn")
	if game_scene == null:
		push_error("pause_menu._on_restart: failed to load game scene")
		return
	var new_game = game_scene.instantiate()
	if new_game == null:
		push_error("pause_menu._on_restart: failed to instantiate game")
		return
	get_parent().add_child(new_game)
	queue_free()

func _on_menu():
	_am().play_sfx("click")
	get_tree().paused = false
	# 用 load 替代 preload + 防御性检查（pause 上下文下 preload 行为可能异常）
	var menu_scene = load("res://scenes/menu.tscn")
	if menu_scene == null:
		push_error("pause_menu._on_menu: Failed to load res://scenes/menu.tscn")
		return
	var m = menu_scene.instantiate()
	if m == null:
		push_error("pause_menu._on_menu: Failed to instantiate menu scene")
		return
	get_parent().add_child(m)
	queue_free()
