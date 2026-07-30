extends Control

## Shop UI controller.
##
## Handles displaying items, purchasing, and input while the shop is open.

signal shop_opened
signal shop_closed

@onready var title_label: Label = $Margin/VBox/Header/Title
@onready var score_label: Label = $Margin/VBox/Header/Score
@onready var items_container: VBoxContainer = $Margin/VBox/Items
@onready var details_label: Label = $Margin/VBox/Details
@onready var close_hint: Label = $Margin/VBox/CloseHint

var _last_focus_index: int = -1

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_set_binds()

static func _ss() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("ShopSystem")

static func _am() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

static func _game() -> Node:
	var current = Engine.get_main_loop().current_scene
	if current and current.name == "Game":
		return current
	return Engine.get_main_loop().root.get_node_or_null("Game")

func _set_binds():
	var ss = _ss()
	if ss == null:
		return
	if ss.has_signal("item_purchased") and not ss.item_purchased.is_connected(_on_item_purchased):
		ss.item_purchased.connect(_on_item_purchased)
	if ss.has_signal("purchase_failed") and not ss.purchase_failed.is_connected(_on_purchase_failed):
		ss.purchase_failed.connect(_on_purchase_failed)

func _process(_delta):
	if visible:
		_update_score()

func open():
	if visible:
		return
	_set_binds()
	visible = true
	_build_items()
	_update_score()
	_update_details(-1)
	if items_container.get_child_count() > 0:
		var first = items_container.get_child(0)
		if first is Button:
			first.grab_focus()
	shop_opened.emit()

func close():
	if not visible:
		return
	visible = false
	for c in items_container.get_children():
		c.queue_free()
	shop_closed.emit()

func is_open() -> bool:
	return visible

func _unhandled_input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_B:
			close()
			get_viewport().set_input_as_handled()

func _build_items():
	for c in items_container.get_children():
		c.queue_free()
	var ss = _ss()
	if ss == null:
		return
	var items = ss.get_all_items()
	for item in items:
		var btn = Button.new()
		btn.set_meta("item_id", item["id"])
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = _format_item_line(item)
		btn.modulate = item["color"]
		btn.pressed.connect(_on_item_pressed.bind(item["id"]))
		btn.focus_entered.connect(_on_item_focused.bind(item["id"]))
		items_container.add_child(btn)

func _format_item_line(item: Dictionary) -> String:
	return "%s %s    %d PTS" % [item["icon"].to_upper(), item["name"], item["cost"]]

func _update_score():
	var ss = _ss()
	if ss == null:
		score_label.text = "SCORE 000000"
		return
	score_label.text = "SCORE %06d" % ss.get_current_score()

func _update_details(item_index: int):
	var ss = _ss()
	if ss == null:
		details_label.text = ""
		return
	if item_index < 0 or item_index >= items_container.get_child_count():
		details_label.text = "Select an item to view details"
		return
	var btn = items_container.get_child(item_index)
	if btn == null:
		return
	var item_id: String = btn.get_meta("item_id", "")
	var item: Dictionary = ss.get_item(item_id)
	if item.is_empty():
		details_label.text = ""
		return
	var affordable: bool = ss.can_afford(item["cost"])
	var cost_color = "[color=#88ff88]" if affordable else "[color=#ff6666]"
	details_label.text = "[b]%s[/b]\n%s\nCost: %s%d[/color]" % [item["name"], item["description"], cost_color, item["cost"]]

func _on_item_pressed(item_id: String):
	var ss = _ss()
	if ss == null:
		return
	var result = ss.purchase(item_id)
	if result["success"]:
		_am().play_sfx("powerup")
	else:
		_am().play_sfx("click")
	_update_score()
	_rebuild_labels()

func _on_item_focused(item_id: String):
	for i in range(items_container.get_child_count()):
		var btn = items_container.get_child(i)
		if btn.get_meta("item_id", "") == item_id:
			_last_focus_index = i
			_update_details(i)
			return

func _on_item_purchased(_item_id: String):
	_update_score()
	_rebuild_labels()

func _on_purchase_failed(_item_id: String, _reason: String):
	_am().play_sfx("click")
	_update_score()
	_rebuild_labels()

func _rebuild_labels():
	for btn in items_container.get_children():
		if not btn is Button:
			continue
		var item_id: String = btn.get_meta("item_id", "")
		var ss = _ss()
		if ss == null:
			continue
		var item: Dictionary = ss.get_item(item_id)
		if item.is_empty():
			continue
		btn.text = _format_item_line(item)
		btn.disabled = not ss.can_afford(item["cost"])
