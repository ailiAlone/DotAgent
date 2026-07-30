## CraftingSystem autoload singleton. Manages recipe data and fabrication logic.

extends Node

signal recipe_crafted(recipe_id)
signal crafting_failed(recipe_id, reason)
signal inventory_changed

var inventory: Dictionary = {"scrap": 0, "energy": 0, "crystal": 0, "organics": 0}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_inventory()

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _game():
	var current = Engine.get_main_loop().current_scene
	if current and current.name == "Game":
		return current
	var root = Engine.get_main_loop().root
	return root.get_node_or_null("Game")

static func _player():
	var game = _game()
	if game == null:
		return null
	return game.get_node_or_null("Player")

func get_all_recipes():
	return [
		{
			"id": "scrap_bomb",
			"name": "Scrap Bomb",
			"description": "Clear all non-boss enemies on screen",
			"ingredients": {"scrap": 3, "energy": 1},
			"result_type": "bomb",
			"result_value": 0,
			"result_amount": 1,
			"icon": "bomb",
			"color": Color(1.0, 0.4, 0.1),
		},
		{
			"id": "repair_kit",
			"name": "Field Repair",
			"description": "Restore 2 HP",
			"ingredients": {"scrap": 2, "organics": 1},
			"result_type": "heal",
			"result_value": 2,
			"result_amount": 1,
			"icon": "heart",
			"color": Color(1.0, 0.3, 0.3),
		},
		{
			"id": "shield_cell",
			"name": "Shield Cell",
			"description": "Gain 8s shield",
			"ingredients": {"energy": 3, "crystal": 1},
			"result_type": "shield",
			"result_value": 8,
			"result_amount": 1,
			"icon": "shield",
			"color": Color(0.3, 0.9, 1.0),
		},
		{
			"id": "overdrive",
			"name": "Overdrive Serum",
			"description": "Rapid fire for 12s",
			"ingredients": {"energy": 2, "organics": 2},
			"result_type": "rapid_fire",
			"result_value": 12,
			"result_amount": 1,
			"icon": "bolt",
			"color": Color(1.0, 0.85, 0.2),
		},
		{
			"id": "ammo_crate",
			"name": "Ammo Crate",
			"description": "Upgrade weapon level by 1",
			"ingredients": {"scrap": 5, "energy": 2},
			"result_type": "weapon_upgrade",
			"result_value": 1,
			"result_amount": 1,
			"icon": "up",
			"color": Color(1.0, 0.6, 0.9),
		},
		{
			"id": "data_cube",
			"name": "Score Data Cube",
			"description": "Double score multiplier for 15s",
			"ingredients": {"crystal": 2, "energy": 1},
			"result_type": "score_x2",
			"result_value": 15,
			"result_amount": 1,
			"icon": "x2",
			"color": Color(0.4, 1.0, 0.5),
		},
		{
			"id": "hull_plate",
			"name": "Hull Plate",
			"description": "Increase max HP by 1 and heal 1",
			"ingredients": {"scrap": 4, "crystal": 2, "organics": 1},
			"result_type": "max_hp",
			"result_value": 1,
			"result_amount": 1,
			"icon": "heart_plus",
			"color": Color(1.0, 0.5, 0.5),
		},
	]

func get_recipe(recipe_id: String):
	for recipe in get_all_recipes():
		if recipe["id"] == recipe_id:
			return recipe.duplicate()
	return {}

func get_inventory() -> Dictionary:
	return inventory.duplicate()

func set_inventory(new_inventory: Dictionary):
	for key in new_inventory.keys():
		var value = new_inventory[key]
		if value is int:
			inventory[key] = max(0, value)
		else:
			inventory[key] = int(value)
	inventory_changed.emit()
	_save_inventory()

func add_material(material: String, amount: int = 1):
	if amount <= 0:
		return
	if not inventory.has(material):
		inventory[material] = 0
	inventory[material] += amount
	inventory_changed.emit()
	_save_inventory()

func get_material_count(material: String) -> int:
	return inventory.get(material, 0)

func can_craft(recipe_id: String) -> bool:
	var recipe = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	return _has_ingredients(recipe["ingredients"])

func craft(recipe_id: String):
	var recipe = get_recipe(recipe_id)
	if recipe.is_empty():
		crafting_failed.emit(recipe_id, "Recipe not found")
		return {"success": false, "reason": "Recipe not found"}

	if not _has_ingredients(recipe["ingredients"]):
		crafting_failed.emit(recipe_id, "Not enough materials")
		return {"success": false, "reason": "Not enough materials"}

	var player = _player()
	if player == null:
		crafting_failed.emit(recipe_id, "Player not found")
		return {"success": false, "reason": "Player not found"}

	if not _can_apply(recipe, player):
		crafting_failed.emit(recipe_id, "Already at max / full")
		return {"success": false, "reason": "Already at max / full"}

	_deduct_ingredients(recipe["ingredients"])
	_apply_recipe(recipe, player)
	recipe_crafted.emit(recipe_id)
	return {"success": true, "reason": ""}

func reset_inventory():
	inventory = {"scrap": 0, "energy": 0, "crystal": 0, "organics": 0}
	inventory_changed.emit()
	_save_inventory()

func _has_ingredients(ingredients: Dictionary) -> bool:
	for material in ingredients.keys():
		var needed = ingredients[material]
		var have = inventory.get(material, 0)
		if have < needed:
			return false
	return true

func _deduct_ingredients(ingredients: Dictionary):
	for material in ingredients.keys():
		inventory[material] = inventory.get(material, 0) - ingredients[material]
		inventory[material] = max(0, inventory[material])
	inventory_changed.emit()
	_save_inventory()

func _can_apply(recipe: Dictionary, player: Node) -> bool:
	var result_type = recipe["result_type"]
	match result_type:
		"heal":
			if not player.has_method("heal"):
				return false
			return player.hp < player.max_hp
		"max_hp":
			return player.max_hp < 8
		"shield":
			return true
		"rapid_fire":
			return true
		"bomb":
			return player.has_method("_explode_all_enemies")
		"score_x2":
			return _gm() != null
		"weapon_upgrade":
			if not player.has_method("upgrade_weapon"):
				return false
			return not (player.weapon_level >= 3 and player.weapon_type >= 2)
	return false

func _apply_recipe(recipe: Dictionary, player: Node):
	var result_type = recipe["result_type"]
	var value = recipe.get("result_value", 0)
	match result_type:
		"heal":
			player.heal(value)
		"max_hp":
			player.max_hp += value
			player.hp += value
		"shield":
			player.shield = true
			player.shield_timer = max(player.shield_timer, float(value))
		"rapid_fire":
			player.rapid_fire_timer = max(player.rapid_fire_timer, float(value))
		"bomb":
			player._explode_all_enemies()
		"score_x2":
			var gm = _gm()
			gm.score_multiplier = max(gm.score_multiplier, 2.0)
			gm.score_multiplier_timer = max(gm.score_multiplier_timer, float(value))
		"weapon_upgrade":
			player.upgrade_weapon()

func _save_inventory():
	var sm = Engine.get_main_loop().root.get_node_or_null("SaveManager")
	if sm == null or not sm.has_method("save_crafting_inventory"):
		return
	sm.save_crafting_inventory(inventory)

func _load_inventory():
	var sm = Engine.get_main_loop().root.get_node_or_null("SaveManager")
	if sm != null and sm.has_method("load_crafting_inventory"):
		var saved = sm.load_crafting_inventory()
		if saved is Dictionary:
			inventory = saved
			return
	inventory = {"scrap": 0, "energy": 0, "crystal": 0, "organics": 0}
