extends Control

@onready var vbox: VBoxContainer = $VBoxContainer

func _ready() -> void:
	pass

func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_achievements_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/achievements.tscn")

func _on_leaderboard_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/leaderboard.tscn")
