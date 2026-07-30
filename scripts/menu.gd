## Main menu with title and start game button.

extends Control


func _ready() -> void:
	pass


func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
