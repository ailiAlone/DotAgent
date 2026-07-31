extends Control

## Victory panel shown when player defeats the boss.

@onready var play_again_button: Button = %PlayAgainButton
@onready var kills_label: Label = %KillsLabel
@onready var center_panel: Panel = %CenterPanel


func _ready() -> void:
	if play_again_button != null:
		play_again_button.pressed.connect(_on_play_again_pressed)
	
	# Initialize scale to 0 for animation
	if center_panel != null:
		center_panel.scale = Vector2.ZERO


func show_victory_screen(final_kills: int) -> void:
	visible = true
	
	# Update kills label
	if kills_label != null:
		kills_label.text = "KILLS: " + str(final_kills)
	
	# Play scale-up animation
	if center_panel != null:
		var tween: Tween = create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(center_panel, "scale", Vector2.ONE, 0.5)
	
	# Pause game
	get_tree().paused = true


func _on_play_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
