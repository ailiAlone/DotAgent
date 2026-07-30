extends Control

## Crafting UI controller.
##
## Handles displaying recipes, material inventory, and crafting while open.

signal crafting_opened
signal crafting_closed

@onready var title_label: Label = $Margin/VBox/Header/Title
@onready var inventory_label: Label = $Margin/VBox/Header/Inventory
@onready var items_container: VBoxContainer = $Margin/VBox/Items
@onready var details_label: Label = $Margin/VBox/Details
@onready var close_hint: Label = $Margin/VBox/CloseHint

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_set_binds()

static func _cs() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("CraftingSystem")

static func _am() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

func _set_binds():
	var cs = _cs()
	if cs == null:
		return
	if cs.has_signal("recipe_crafted") and not cs.recipe_crafted.is_connected(_on_recipe_crafted):
		cs.recipe_crafted.connect(_on_recipe_crafted)
	if cs.has_signal("crafting_failed") and not cs.crafting_failed.is_connected(_on_crafting_failed):
		cs.crafting_failed.connect(_on_crafting_failed)
	if cs.has_signal("inventory_changed") and not cs.inventory_changed.is_connected(_on_inventory_changed):
		cs.inventory_changed.connect(_on_inventory_changed)

func _process(_delta):
	if visible:
		_update_inventory()

func open():
	if visible:
		return
	_set_binds()
	visible = true
	_build_recipes()
	_update_inventory()
	_update_details(-1)
	if items_container.get_child_count() > 0:
		var first = items_container.get_child(0)
		if first is Button:
			first.grab_focus()
	crafting_opened.emit()

func close():
	if not visible:
		return
	visible = false
	for c in items_container.get_children():
		c.queue_free()
	crafting_closed.emit()

func is_open() -> bool:
	return visible

func _unhandled_input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_C:
			close()
			get_viewport().set_input_as_handled()

func _build_recipes():
	for c in items_container.get_children():
		c.queue_free()
	var cs = _cs()
	if cs == null:
		return
	var recipes = cs.get_all_recipes()
	for recipe in recipes:
		var btn = Button.new()
		btn.set_meta("recipe_id", recipe["id"])
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = _format_recipe_line(recipe)
		btn.modulate = recipe["color"]
		btn.pressed.connect(_on_recipe_pressed.bind(recipe["id"]))
		btn.focus_entered.connect(_on_recipe_focused.bind(recipe["id"]))
		items_container.add_child(btn)

func _format_recipe_line(recipe: Dictionary) -> String:
	return "%s %s" % [recipe["icon"].to_upper(), recipe["name"]]

func _format_ingredients(ingredients: Dictionary) -> String:
	var cs = _cs()
	if cs == null:
		return ""
	var parts: Array[String] = []
	for material in ingredients.keys():
		var have = cs.get_material_count(material)
		var need = ingredients[material]
		var color = "#88ff88" if have >= need else "#ff6666"
		parts.append("%s: %s%d/%d[/color]" % [material.capitalize(), "[color=" + color + "]", have, need])
	return " ".join(parts)

func _update_inventory():
	var cs = _cs()
	if cs == null:
		inventory_label.text = "MAT: --"
		return
	var inv = cs.get_inventory()
	inventory_label.text = "SCR:%d ENE:%d CRY:%d ORG:%d" % [inv.get("scrap", 0), inv.get("energy", 0), inv.get("crystal", 0), inv.get("organics", 0)]

func _update_details(recipe_index: int):
	var cs = _cs()
	if cs == null:
		details_label.text = ""
		return
	if recipe_index < 0 or recipe_index >= items_container.get_child_count():
		details_label.text = "Select a recipe to view details"
		return
	var btn = items_container.get_child(recipe_index)
	if btn == null:
		return
	var recipe_id: String = btn.get_meta("recipe_id", "")
	var recipe: Dictionary = cs.get_recipe(recipe_id)
	if recipe.is_empty():
		details_label.text = ""
		return
	details_label.text = "[b]%s[/b]\n%s\nIngredients: %s" % [recipe["name"], recipe["description"], _format_ingredients(recipe["ingredients"])]

func _on_recipe_pressed(recipe_id: String):
	var cs = _cs()
	if cs == null:
		return
	var result = cs.craft(recipe_id)
	if result["success"]:
		_am().play_sfx("powerup")
	else:
		_am().play_sfx("click")
	_update_inventory()
	_rebuild_labels()

func _on_recipe_focused(recipe_id: String):
	for i in range(items_container.get_child_count()):
		var btn = items_container.get_child(i)
		if btn.get_meta("recipe_id", "") == recipe_id:
			_update_details(i)
			return

func _on_recipe_crafted(_recipe_id: String):
	_update_inventory()
	_rebuild_labels()

func _on_crafting_failed(_recipe_id: String, _reason: String):
	_am().play_sfx("click")
	_update_inventory()
	_rebuild_labels()

func _on_inventory_changed():
	_update_inventory()
	_rebuild_labels()

func _rebuild_labels():
	var cs = _cs()
	if cs == null:
		return
	for btn in items_container.get_children():
		if not btn is Button:
			continue
		var recipe_id: String = btn.get_meta("recipe_id", "")
		var recipe: Dictionary = cs.get_recipe(recipe_id)
		if recipe.is_empty():
			continue
		btn.text = _format_recipe_line(recipe)
		btn.disabled = not cs.can_craft(recipe_id)
