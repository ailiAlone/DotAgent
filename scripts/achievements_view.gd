## Achievements View - Displays all achievements with their unlock status.

extends Control

@onready var progress_label: Label = $TitleContainer/ProgressLabel
@onready var achievements_list: VBoxContainer = $ScrollContainer/AchievementsList
@onready var back_button: Button = $BackButton

var _achievement_items: Array[Control] = []

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_refresh_achievements()

func _refresh_achievements() -> void:
	var am: Node = _am()
	if am == null:
		progress_label.text = "Achievement system not available"
		return
	
	# Clear existing items
	for item: Control in _achievement_items:
		item.queue_free()
	_achievement_items.clear()
	
	var unlocked: int = am.get_unlocked_count()
	var total: int = am.get_total_count()
	progress_label.text = str(unlocked) + "/" + str(total) + " Unlocked"
	
	# Add achievement items for each category
	_add_category("Combat", 1, am)  # COMBAT = 1
	_add_category("Boss", 2, am)   # BOSS = 2
	_add_category("Wave", 3, am)   # WAVE = 3
	_add_category("Score", 4, am)  # SCORE = 4

func _add_category(category_name: String, category_id: int, am: Node) -> void:
	# Category header
	var header: Label = Label.new()
	header.text = category_name
	header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	achievements_list.add_child(header)
	_achievement_items.append(header)
	
	# Get achievements in this category
	var achievements: Array = am.get_achievements_by_category(category_id)
	for achievement_obj in achievements:
		var item: HBoxContainer = _create_achievement_item(achievement_obj)
		achievements_list.add_child(item)
		_achievement_items.append(item)

func _create_achievement_item(achievement) -> HBoxContainer:
	var container: HBoxContainer = HBoxContainer.new()
	
	# Icon/Status
	var status_label: Label = Label.new()
	status_label.text = "☆" if achievement.unlocked else "◇"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2) if achievement.unlocked else Color(0.5, 0.5, 0.5))
	status_label.custom_minimum_size.x = 30.0
	container.add_child(status_label)
	
	# Name and description
	var text_container: VBoxContainer = VBoxContainer.new()
	
	var name_label: Label = Label.new()
	name_label.text = achievement.name
	if achievement.unlocked:
		name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	else:
		name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	text_container.add_child(name_label)
	
	var desc_label: Label = Label.new()
	desc_label.text = achievement.description
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	text_container.add_child(desc_label)
	
	container.add_child(text_container)
	
	# Progress indicator
	var progress_text: Label = Label.new()
	if achievement.unlocked:
		progress_text.text = "✓"
		progress_text.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	else:
		progress_text.text = str(achievement.current) + "/" + str(achievement.target)
		progress_text.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	container.add_child(progress_text)
	
	return container

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

static func _am() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("AchievementManager")
