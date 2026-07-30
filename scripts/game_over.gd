## Game over screen showing final score and restart button.

extends Control

const Singleton = "GameManager"

@onready var score_label: Label = $%ScoreLabel
@onready var high_score_label: Label = $%HighScoreLabel

func _ready():
	var gm: Node = _gm()
	if gm != null:
		_update_score_labels(gm.score, gm.high_score)
		gm.score_changed.connect(_on_score_changed)
		gm.high_score_changed.connect(_on_high_score_changed)
		get_tree().paused = true

func _on_score_changed(value: int):
	var gm: Node = _gm()
	if gm != null:
		_update_score_labels(gm.score, gm.high_score)

func _on_high_score_changed(value: int):
	var gm: Node = _gm()
	if gm != null:
		_update_score_labels(gm.score, gm.high_score)

func _update_score_labels(new_score: int, new_high_score: int):
	if score_label != null:
		score_label.text = "SCORE: " + str(new_score)
	if high_score_label != null:
		high_score_label.text = "HIGH SCORE: " + str(new_high_score)

func _on_restart_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_menu_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
