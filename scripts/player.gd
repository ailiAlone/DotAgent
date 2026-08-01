extends CharacterBody2D

const SPEED: float = 300.0
const BASE_SHOOT_COOLDOWN: float = 0.5
const RAPID_FIRE_SHOOT_COOLDOWN: float = 0.15
const MAX_WEAPON_LEVEL: int = 3
const EXP_TO_LEVEL: Array = [5, 10]
const MAGNET_RANGE: float = 150.0
const MAGNET_SPEED: float = 400.0

signal shield_depleted()

@export var start_position: Vector2 = Vector2(500, 500)

var weapon_level: int = 1
var _experience: int = 0
var _shield_active: bool = false
var _rapid_fire_active: bool = false
var _weather_speed_mult: float = 1.0

func _ready() -> void:
	position = start_position

func _physics_process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("left", "right", "up", "down")
	var effective_speed: float = SPEED * _weather_speed_mult
	velocity = direction * effective_speed
	move_and_slide()

func _process(_delta: float) -> void:
	pass

func add_experience(amount: int) -> bool:
	_experience += amount
	var leveled_up: bool = false
	while weapon_level < MAX_WEAPON_LEVEL and _experience >= EXP_TO_LEVEL[weapon_level - 1]:
		leveled_up = true
		weapon_level += 1
	return leveled_up

func get_weapon_level() -> int:
	return weapon_level

func apply_powerup(type: String) -> void:
	match type:
		"heal":
			var gm: Node = _gm()
			if gm != null:
				gm.add_life(1)
		"rapid_fire":
			_rapid_fire_active = true
			await get_tree().create_timer(5.0).timeout
			_rapid_fire_active = false
		"shield":
			_shield_active = true

func is_shield_active() -> bool:
	return _shield_active

func is_rapid_fire_active() -> bool:
	return _rapid_fire_active

func get_shoot_cooldown() -> float:
	if _rapid_fire_active:
		return RAPID_FIRE_SHOOT_COOLDOWN
	return BASE_SHOOT_COOLDOWN

func set_weather_speed_multiplier(mult: float) -> void:
	_weather_speed_mult = clampf(mult, 0.1, 1.0)

static func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
