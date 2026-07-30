extends Control

const Singleton = "GameManager"

signal score_submitted

@onready var score_label: Label = $VBoxContainer/ScoreLabel
@onready var high_score_label: Label = $VBoxContainer/HighScoreLabel
@onready var rank_label: Label = $VBoxContainer/RankLabel
@onready var submit_panel: Panel = $VBoxContainer/SubmitPanel
@onready var name_line_edit: LineEdit = $VBoxContainer/SubmitPanel/NameLineEdit
@onready var submit_button: Button = $VBoxContainer/SubmitPanel/SubmitButton
@onready var skip_button: Button = $VBoxContainer/SubmitPanel/SkipButton

var _current_rank: int = -1
var _is_high_score: bool = false

func _ready() -> void:
	var gm: Node = _gm()
	if gm != null:
		_update_score_labels(gm.score, gm.high_score)
		_current_rank = gm.calculate_rank()
		_is_high_score = gm.is_high_score_for_leaderboard()
		_update_rank_label()
		gm.score_changed.connect(_on_score_changed)
		gm.high_score_changed.connect(_on_high_score_changed)
		get_tree().paused = true
	
	submit_button.pressed.connect(_on_submit_pressed)
	skip_button.pressed.connect(_on_skip_pressed)

func _update_score_labels(new_score: int, new_high_score: int) -> void:
	if score_label != null:
		score_label.text = "SCORE: " + str(new_score)
	if high_score_label != null:
		high_score_label.text = "HIGH SCORE: " + str(new_high_score)

func _update_rank_label() -> void:
	if rank_label != null:
		if _current_rank > 0 and _current_rank <= 10:
			rank_label.text = "RANK: #" + str(_current_rank)
			rank_label.visible = true
		else:
			rank_label.visible = false
	
	if submit_panel != null:
		submit_panel.visible = _is_high_score and _current_rank > 0

func _on_score_changed(value: int) -> void:
	var gm: Node = _gm()
	if gm != null:
		_update_score_labels(gm.score, gm.high_score)

func _on_high_score_changed(value: int) -> void:
	var gm: Node = _gm()
	if gm != null:
		_update_score_labels(gm.score, gm.high_score)

func _on_submit_pressed() -> void:
	var player_name: String = name_line_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	if player_name.length() > 12:
		player_name = player_name.substr(0, 12)
	
	var gm: Node = _gm()
	if gm != null:
		gm.submit_to_leaderboard(player_name)
	
	submit_panel.visible = false
	score_submitted.emit()

func _on_skip_pressed() -> void:
	submit_panel.visible = false

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_leaderboard_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/leaderboard.tscn")

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
