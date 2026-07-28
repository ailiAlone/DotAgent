extends Node

const GameManagerScript = preload("res://scripts/game_manager.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

func _ready():
	# 运行时兜底：注册 headless 模式下可能缺失的输入动作
	# （项目设置已包含 ui_accept / pause，这里只注册自定义动作）
	_ensure_input_action("alt_shoot", KEY_SHIFT)
	_ensure_input_action("dash", KEY_L)

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

func _ensure_input_action(action: StringName, keycode: int):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var found = false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.keycode == keycode:
			found = true
			break
	if not found:
		var ev = InputEventKey.new()
		ev.keycode = keycode
		InputMap.action_add_event(action, ev)
