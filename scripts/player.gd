extends Node2D

const SPEED: float = 300.0
const SLOW_EFFECT: float = 0.5  # Snow weather speed multiplier (50% speed)
const MAX_WEAPON_LEVEL: int = 3
const EXP_TO_LEVEL: Array[int] = [5, 10, 15]
const BASE_SHOOT_COOLDOWN: float = 0.5
const RAPID_FIRE_SHOOT_COOLDOWN: float = 0.15
const RAPID_FIRE_DURATION: float = 5.0
const SHIELD_DURATION: float = 3.0

var weapon_level: int = 1
var _experience: int = 0
var _shoot_cooldown: float = 0.0
var _rapid_fire_active: bool = false
var _rapid_fire_timer: float = 0.0
var _shield_active: bool = false
var _shield_timer: float = 0.0
var _weather_speed_mult: float = 1.0  # Weather speed multiplier (set by game.gd)


static func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")


func _get_weather_multiplier() -> float:
	# Try to get weather system - check for WeatherSystem autoload or child node
	var weather_system: Node = Engine.get_main_loop().root.get_node_or_null("WeatherSystem")
	if weather_system == null:
		weather_system = get_node_or_null("/root/WeatherSystem")
	if weather_system == null:
		weather_system = get_tree().root.find_child("WeatherSystem", false, false)
	
	if weather_system != null and weather_system.has_method("get_weather"):
		var weather_type: String = weather_system.get_weather()
		if weather_type == "snow":
			return SLOW_EFFECT
	return 1.0  # Default: no speed penalty


func _process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("move_up"):
		direction.y -= 1.0
	if Input.is_action_pressed("move_down"):
		direction.y += 1.0
	if Input.is_action_pressed("move_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("move_right"):
		direction.x += 1.0

	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	
	# Apply weather effect to movement speed (from game.gd weather system)
	var effective_speed: float = SPEED * _weather_speed_mult
	position += direction * effective_speed * delta

	var viewport_size: Vector2 = get_viewport_rect().size
	position.x = clampf(position.x, 20.0, viewport_size.x - 20.0)
	position.y = clampf(position.y, 20.0, viewport_size.y - 20.0)

	if _rapid_fire_active:
		_rapid_fire_timer -= delta
		if _rapid_fire_timer <= 0.0:
			_rapid_fire_active = false
			_rapid_fire_timer = 0.0

	if _shield_active:
		_shield_timer -= delta
		if _shield_timer <= 0.0:
			_shield_active = false
			_shield_timer = 0.0


func _draw() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	points.push_back(Vector2(0.0, -20.0))
	points.push_back(Vector2(15.0, 20.0))
	points.push_back(Vector2(-15.0, 20.0))
	draw_colored_polygon(points, Color.WHITE)


func add_experience(amount: int) -> bool:
	_experience += amount
	var leveled_up: bool = false
	while weapon_level < MAX_WEAPON_LEVEL and _experience >= EXP_TO_LEVEL[weapon_level - 1]:
		weapon_level += 1
		leveled_up = true
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
			_rapid_fire_timer = RAPID_FIRE_DURATION
		"shield":
			_shield_active = true
			_shield_timer = SHIELD_DURATION
		"bomb":
			pass


func is_shield_active() -> bool:
	return _shield_active


func is_rapid_fire_active() -> bool:
	return _rapid_fire_active


func get_shoot_cooldown() -> float:
	if _rapid_fire_active:
		return RAPID_FIRE_SHOOT_COOLDOWN
	return BASE_SHOOT_COOLDOWN


## Set weather speed multiplier from weather system
## Called by game.gd when weather changes
func set_weather_speed_multiplier(mult: float) -> void:
	_weather_speed_mult = clampf(mult, 0.1, 1.0)
