extends Control


# 预设物品数据
var items: Array[Dictionary] = [
	{"name": "Iron Sword", "icon": "🗡️", "count": 1},
	{"name": "Health Potion", "icon": "🧪", "count": 3},
	{"name": "Mana Potion", "icon": "💧", "count": 2},
	{"name": "Wooden Shield", "icon": "🛡️", "count": 1},
	{"name": "Gold Coin", "icon": "🪙", "count": 99},
	{"name": "Magic Scroll", "icon": "📜", "count": 1},
	{"name": "Iron Ore", "icon": "🪨", "count": 5},
	{"name": "Bread", "icon": "🍞", "count": 4},
	{"name": "Empty Slot", "icon": "—", "count": 0},
]

@onready var back_button: Button = %BackButton
@onready var item_grid: GridContainer = %ItemGrid


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_populate_grid()


func _populate_grid() -> void:
	# 清空已有的子节点
	for child in item_grid.get_children():
		child.queue_free()

	for item in items:
		var slot := _create_item_slot(item)
		item_grid.add_child(slot)


func _create_item_slot(item: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(120, 100)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_label := Label.new()
	icon_label.text = item["icon"]
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 36)

	var name_label := Label.new()
	name_label.text = item["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)

	var count_label := Label.new()
	count_label.text = "x%d" % item["count"]
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 14)

	vbox.add_child(icon_label)
	vbox.add_child(name_label)
	vbox.add_child(count_label)
	panel.add_child(vbox)

	return panel


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")
