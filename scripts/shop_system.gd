## ShopSystem autoload singleton. Manages shop items, purchase validation, and applying effects to player / game state.

extends Node

signal item_purchased(item_id)
signal purchase_failed(item_id, reason)
signal shop_opened
signal shop_closed

const ITEM_HEAL = "heal"
const ITEM_SHIELD = "shield"
const ITEM_RAPID_FIRE = "rapid_fire"
const ITEM_BOMB = "bomb"
const ITEM_SCORE_X2 = "score_x2"
const ITEM_WEAPON_UPGRADE = "weapon_upgrade"
const ITEM_MAX_HP = "max_hp"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	

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
	

func get_all_items():
	return [
		{
			"id": ITEM_HEAL,
			"name": "Repair Kit",
			"name_zh": "修理包",
			"description": "Restore 2 HP",
			"description_zh": "恢复 2 点生命值",
			"cost": 500,
			"icon": "heart",
			"color": Color(1.0, 0.3, 0.3),
			"max_stock": -1,
		},
		{
			"id": ITEM_MAX_HP,
			"name": "Hull Reinforcement",
			"name_zh": "船体加固",
			"description": "Increase max HP by 1",
			"description_zh": "最大生命值 +1",
			"cost": 1500,
			"icon": "heart_plus",
			"color": Color(1.0, 0.5, 0.5),
			"max_stock": 2,
		},
		{
			"id": ITEM_SHIELD,
			"name": "Energy Shield",
			"name_zh": "能量护盾",
			"description": "Gain 6s shield",
			"description_zh": "获得 6 秒护盾",
			"cost": 800,
			"icon": "shield",
			"color": Color(0.3, 0.9, 1.0),
			"max_stock": -1,
		},
		{
			"id": ITEM_RAPID_FIRE,
			"name": "Overdrive",
			"name_zh": "火力超载",
			"description": "Rapid fire for 10s",
			"description_zh": "10 秒急速射击",
			"cost": 900,
			"icon": "bolt",
			"color": Color(1.0, 0.85, 0.2),
			"max_stock": -1,
		},
		{
			"id": ITEM_BOMB,
			"name": "Nova Bomb",
			"name_zh": "新星炸弹",
			"description": "Destroy all enemies on screen",
			"description_zh": "清除屏幕所有敌人",
			"cost": 1200,
			"icon": "bomb",
			"color": Color(1.0, 0.4, 0.1),
			"max_stock": -1,
		},
		{
			"id": ITEM_SCORE_X2,
			"name": "Score Booster",
			"name_zh": "分数倍增",
			"description": "Double score multiplier for 15s",
			"description_zh": "15 秒分数双倍",
			"cost": 1000,
			"icon": "x2",
			"color": Color(0.4, 1.0, 0.5),
			"max_stock": -1,
		},
		{
			"id": ITEM_WEAPON_UPGRADE,
			"name": "Weapon Upgrade",
			"name_zh": "武器升级",
			"description": "Upgrade current weapon",
			"description_zh": "升级当前武器",
			"cost": 2000,
			"icon": "up",
			"color": Color(1.0, 0.6, 0.9),
			"max_stock": -1,
		},
	]
	

func get_item(item_id: String):
	for item in get_all_items():
		if item["id"] == item_id:
			return item.duplicate()
	return {}
	

func can_afford(cost: int):
	var gm = _gm()
	if gm == null:
		return false
	return gm.score >= cost
	

func get_current_score():
	var gm = _gm()
	if gm == null:
		return 0
	return gm.score
	

func deduct_score(amount: int):
	var gm = _gm()
	if gm == null:
		return false
	if gm.score < amount:
		return false
	gm.score -= amount
	return true
	

func purchase(item_id: String):
	var item = get_item(item_id)
	if item.is_empty():
		purchase_failed.emit(item_id, "Item not found")
		return {"success": false, "reason": "Item not found"}
	
	if not can_afford(item["cost"]):
		purchase_failed.emit(item_id, "Not enough score")
		return {"success": false, "reason": "Not enough score"}
	
	var player = _player()
	if player == null:
		purchase_failed.emit(item_id, "Player not found")
		return {"success": false, "reason": "Player not found"}
	
	if not _can_apply(item, player):
		purchase_failed.emit(item_id, "Already at max / full")
		return {"success": false, "reason": "Already at max / full"}
	
	if not deduct_score(item["cost"]):
		purchase_failed.emit(item_id, "Payment failed")
		return {"success": false, "reason": "Payment failed"}
	
	_apply_item(item, player)
	item_purchased.emit(item_id)
	return {"success": true, "reason": ""}
	

func _can_apply(item: Dictionary, player: Node):
	var id = item["id"]
	match id:
		ITEM_HEAL:
			if not player.has_method("heal"):
				return false
			return player.hp < player.max_hp
		ITEM_MAX_HP:
			return player.max_hp < 8
		ITEM_SHIELD:
			return true
		ITEM_RAPID_FIRE:
			return true
		ITEM_BOMB:
			return player.has_method("_explode_all_enemies")
		ITEM_SCORE_X2:
			return _gm() != null
		ITEM_WEAPON_UPGRADE:
			if not player.has_method("upgrade_weapon"):
				return false
			return not (player.weapon_level >= 3 and player.weapon_type >= 2)
	return false
	

func _apply_item(item: Dictionary, player: Node):
	var id = item["id"]
	match id:
		ITEM_HEAL:
			player.heal(2)
		ITEM_MAX_HP:
			player.max_hp += 1
			player.hp += 1
		ITEM_SHIELD:
			player.shield = true
			player.shield_timer = 6.0
		ITEM_RAPID_FIRE:
			player.rapid_fire_timer = max(player.rapid_fire_timer, 10.0)
		ITEM_BOMB:
			player._explode_all_enemies()
		ITEM_SCORE_X2:
			var gm = _gm()
			gm.score_multiplier = max(gm.score_multiplier, 2.0)
			gm.score_multiplier_timer = max(gm.score_multiplier_timer, 15.0)
		ITEM_WEAPON_UPGRADE:
			player.upgrade_weapon()
	
