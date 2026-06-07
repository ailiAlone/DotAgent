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
	# TODO: Replace with your actual game scene path
	get_tree().change_scene_to_file("res://game.tscn")


func _on_settings_pressed() -> void:
	# TODO: Implement settings menu
	pass


func _on_quit_pressed() -> void:
	get_tree().quit()
