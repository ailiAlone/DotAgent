extends Node

var game = null
var waited_frames = 0
var phase = 0

func _ready():
	var main = preload("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	add_child(main)

func _process(delta):
	waited_frames += 1
	var main_node = null
	for child in get_children():
		if child.name == "Main":
			main_node = child
			break
	if main_node == null:
		return
	match phase:
		0:
			if waited_frames >= 60:
				phase = 1
				waited_frames = 0
				for child in main_node.get_children():
					if child.name == "Menu":
						child._on_start()
						break
		1:
			if waited_frames >= 120:
				phase = 2
				waited_frames = 0
				for child in main_node.get_children():
					if child.name == "Game":
						game = child
						break
				if game:
					game._gm().score = 12345
					game.wave = 5
					game._game_over()
		2:
			if waited_frames >= 360:
				phase = 3
				waited_frames = 0
		3:
			print("=== GameOver layout ===")
			if game and is_instance_valid(game):
				for child in game.get_children():
					if child.name == "GameOver":
						print("  GameOver type=", child.get_class(), " visible=", child.visible, " proc_mode=", child.process_mode)
						var ui = child.get_node_or_null("UI")
						if ui:
							print("  UI size=", ui.size, " position=", ui.position)
						var center = child.get_node_or_null("UI/Center")
						if center:
							print("  Center size=", center.size, " position=", center.position, " global_pos=", center.global_position)
							print("  Center anchors: L=", center.anchor_left, " T=", center.anchor_top, " R=", center.anchor_right, " B=", center.anchor_bottom)
							print("  Center offsets: L=", center.offset_left, " T=", center.offset_top, " R=", center.offset_right, " B=", center.offset_bottom)
						var title = child.get_node_or_null("UI/Center/Title")
						if title:
							print("  Title text=", title.text, " size=", title.size)
			get_tree().quit()