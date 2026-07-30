extends Control

signal entry_submitted(name: String, score: int, rank: int)

@onready var entries_container: VBoxContainer = %EntriesContainer
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton
@onready var name_input_panel: Panel = %NameInputPanel
@onready var congrats_label: Label = %CongratsLabel
@onready var rank_label: Label = %RankLabel
@onready var name_line_edit: LineEdit = %NameLineEdit
@onready var submit_button: Button = %SubmitButton

var _pending_score: int = 0
var _pending_rank: int = -1

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	submit_button.pressed.connect(_on_submit_pressed)
	_refresh_entries()

func _refresh_entries() -> void:
	var lb: Node = _lb()
	if lb == null or not lb.has_method("get_entries"):
		return
	
	for child: Node in entries_container.get_children():
		child.queue_free()
	
	var entries: Array = lb.get_entries()
	var is_empty: bool = entries.is_empty()
	
	if is_empty:
		var empty_label: Label = Label.new()
		empty_label.text = "No scores yet!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		entries_container.add_child(empty_label)
		return
	
	for i: int in range(entries.size()):
		var entry: Dictionary = entries[i] as Dictionary
		var row: HBoxContainer = _create_entry_row(i + 1, entry.get("name", "???"), entry.get("score", 0))
		entries_container.add_child(row)

func _create_entry_row(rank: int, name: String, score: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 40
	
	var rank_lbl: Label = Label.new()
	rank_lbl.text = "#" + str(rank)
	rank_lbl.custom_minimum_size.x = 60
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	var name_lbl: Label = Label.new()
	name_lbl.text = name
	name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var score_lbl: Label = Label.new()
	score_lbl.text = str(score)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	if rank == 1:
		rank_lbl.add_theme_color_override("font_color", Color(1, 0.84, 0))
		name_lbl.add_theme_color_override("font_color", Color(1, 0.84, 0))
		score_lbl.add_theme_color_override("font_color", Color(1, 0.84, 0))
	elif rank == 2:
		rank_lbl.add_theme_color_override("font_color", Color(0.78, 0.78, 0.9))
		name_lbl.add_theme_color_override("font_color", Color(0.78, 0.78, 0.9))
		score_lbl.add_theme_color_override("font_color", Color(0.78, 0.78, 0.9))
	elif rank == 3:
		rank_lbl.add_theme_color_override("font_color", Color(0.8, 0.5, 0.2))
		name_lbl.add_theme_color_override("font_color", Color(0.8, 0.5, 0.2))
		score_lbl.add_theme_color_override("font_color", Color(0.8, 0.5, 0.2))
	
	row.add_child(rank_lbl)
	row.add_child(name_lbl)
	row.add_child(score_lbl)
	
	return row

func show_name_input(score: int, rank: int) -> void:
	_pending_score = score
	_pending_rank = rank
	name_input_panel.visible = true
	rank_label.text = "Rank: #" + str(rank)
	name_line_edit.text = ""
	name_line_edit.grab_focus()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_submit_pressed() -> void:
	var player_name: String = name_line_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = "Anonymous"
	if player_name.length() > 12:
		player_name = player_name.substr(0, 12)
	
	var gm: Node = _gm()
	if gm != null and gm.has_method("submit_to_leaderboard"):
		gm.submit_to_leaderboard(player_name)
	
	entry_submitted.emit(player_name, _pending_score, _pending_rank)
	name_input_panel.visible = false
	_refresh_entries()

static func _lb():
	return Engine.get_main_loop().root.get_node_or_null("Leaderboard")

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
