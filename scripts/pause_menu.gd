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
			var game = _find_game()
			if game and game.has_method("_toggle_pause"):
				game._toggle_pause()
			get_viewport().set_input_as_handled()

func _on_resume():
	_am().play_sfx("click")
	var game = _find_game()
	if game and game.has_method("_toggle_pause"):
		game._toggle_pause()

func _on_restart():
	_am().play_sfx("click")
	get_tree().paused = false
	var holder = _get_scene_holder()
	var game_scene = load("res://scenes/game.tscn")
	if game_scene == null:
		push_error("pause_menu._on_restart: failed to load game scene")
		return
	var new_game = game_scene.instantiate()
	if new_game == null:
		push_error("pause_menu._on_restart: failed to instantiate game")
		return
	holder.add_child(new_game)
	queue_free()

func _on_menu():
	_am().play_sfx("click")
	get_tree().paused = false
	var holder = _get_scene_holder()
	var menu_scene = load("res://scenes/menu.tscn")
	if menu_scene == null:
		push_error("pause_menu._on_menu: Failed to load res://scenes/menu.tscn")
		return
	var m = menu_scene.instantiate()
	if m == null:
		push_error("pause_menu._on_menu: Failed to instantiate menu scene")
		return
	holder.add_child(m)
	queue_free()

# 找到当前 Game 实例：优先 current_scene，否则在 Main 下查找
func _find_game() -> Node:
	var current = get_tree().current_scene
	if current and (current.name == "Game" or current.has_method("_toggle_pause")):
		return current
	var main = _get_scene_holder()
	if main:
		for c in main.get_children():
			if c.name == "Game" or c.has_method("_toggle_pause"):
				return c
	return null

# 返回场景承载节点：优先 Main，否则回退 root
func _get_scene_holder() -> Node:
	var n = get_parent()
	while n != null and n.name != "Main":
		n = n.get_parent()
	return n if n != null else get_tree().root
