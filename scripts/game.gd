## Game world root that owns the player, HUD, and pause handling.

extends Node2D

@onready var hud: CanvasLayer = $HUD
@onready var game_manager: Node = $"/root/GameManager"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_manager.reset_game()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	hud.visible = not get_tree().paused
