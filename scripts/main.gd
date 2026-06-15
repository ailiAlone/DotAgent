extends Node

const GameManagerScript = preload("res://scripts/game_manager.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

func _ready():
	# 注册 alt_shoot 输入（headless 模式下 add_input_action 不会持久化，运行时兜底）
	if not InputMap.has_action("alt_shoot"):
		InputMap.add_action("alt_shoot")
		var ev = InputEventKey.new()
		ev.keycode = KEY_SHIFT
		InputMap.action_add_event("alt_shoot", ev)
	var tree = get_tree()
	if tree and not tree.root.has_node("GameManager"):
		var gm = GameManagerScript.new()
		gm.name = "GameManager"
		tree.root.add_child(gm)
	if tree and not tree.root.has_node("AudioManager"):
		var am = AudioManagerScript.new()
		am.name = "AudioManager"
		tree.root.add_child(am)
	var menu = preload("res://scenes/menu.tscn").instantiate()
	add_child(menu)