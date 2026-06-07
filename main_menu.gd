extends Control

@onready var start_button := %StartButton
@onready var settings_button := %SettingsButton
@onready var quit_button := %QuitButton
@onready var title_label := %TitleLabel


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	var scene_path := "res://game.tscn"
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		push_error("Game scene not found: " + scene_path)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://settings.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
