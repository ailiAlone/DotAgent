extends Node

const GameManagerScript = preload("res://scripts/game_manager.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

func _ready():
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