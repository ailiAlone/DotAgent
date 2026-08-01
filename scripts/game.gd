extends Node2D

## Main game scene: manages the player, HUD, bullets, enemies, spawns, waves, powerups, weather, and polish effects.

const Singleton: String = "GameManager"
const SPAWN_INTERVAL: float = 2.0
const WAVE_INTERVAL: float = 30.0
const WAVE_SPEED_MULT: float = 0.15
const SHAKE_DURATION: float = 0.12
const SHAKE_STRENGTH: float = 6.0
const BOSS_DEATH_SHAKE_DURATION: float = 0.6
const BOSS_DEATH_SHAKE_STRENGTH: float = 20.0
const PLAYER_RADIUS: float = 20.0
const BOSS_BULLET_DAMAGE: int = 1

@onready var hud_scene: PackedScene = preload("res://scenes/hud.tscn")
@onready var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
@onready var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@onready var explosion_scene: PackedScene = preload("res://scenes/explosion.tscn")
@onready var powerup_scene: PackedScene = preload("res://scenes/powerup.tscn")
@onready var magnet_powerup_scene: PackedScene = preload("res://scenes/magnet_powerup.tscn")
@onready var boss_scene: PackedScene = preload("res://scenes/boss.tscn")
@onready var boss_bullet_scene: PackedScene = preload("res://scenes/boss_bullet.tscn")
@onready var weather_particles_scene: PackedScene = preload("res://scenes/weather_particles.tscn")

var _spawn_timer: float = 0.0
var _wave_timer: float = 0.0
var _shoot_timer: float = 0.0
var _game_over_active: bool = false
var _boss_active: bool = false
var _current_boss: Node2D = null
var _weather_manager: Node = null
var _weather_particles: Node2D = null
var _magnet_active: bool = false
var _magnet_timer: float = 0.0
const MAGNET_DURATION: float = 5.0
const MAGNET_ATTRACTION_SPEED: float = 400.0


func _ready() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.reset()
		gm.game_paused.connect(_on_game_paused)
		gm.lives_changed.connect(_on_lives_changed)
	
	# Initialize weather system
	_setup_weather()
	
	var hud_instance: CanvasLayer = hud_scene.instantiate() as CanvasLayer
	if hud_instance != null:
		hud_instance.name = "HUD"
		add_child(hud_instance)
	else:
		push_error("Failed to instantiate HUD.")
	_update_weapon_level_hud()


func _process(delta: float) -> void:
	_handle_shooting(delta)
	_handle_spawning(delta)
	_handle_waves(delta)
	_handle_collisions()
	_handle_powerup_collection()
	_handle_magnet(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var gm: Node = _gm()
		if gm != null:
			gm.toggle_pause()


func _setup_weather() -> void:
	# Create weather manager node
	_weather_manager = Node.new()
	_weather_manager.set_script(load("res://scripts/weather.gd"))
	_weather_manager.name = "WeatherManager"
	add_child(_weather_manager)
	
	# Create and add weather particles
	if weather_particles_scene != null:
		_weather_particles = weather_particles_scene.instantiate() as Node2D
		if _weather_particles != null:
			_weather_particles.name = "WeatherParticles"
			add_child(_weather_particles)
			# Connect weather particles to weather manager
			_update_weather_particles()
	
	# Connect to weather manager signals
	if _weather_manager.has_signal("weather_changed"):
		_weather_manager.weather_changed.connect(_on_weather_changed)
	
	# Start with clear weather
	if _weather_manager.has_method("set_weather"):
		_weather_manager.set_weather(0)


func _on_weather_changed(weather_type: int) -> void:
	print("Weather changed in game: ", weather_type)
	_update_weather_particles()
	_apply_weather_to_player()


func _update_weather_particles() -> void:
	if _weather_particles == null:
		return
	
	# Hide all particle systems first
	for child: Node in _weather_particles.get_children():
		if child is CPUParticles2D or child is ColorRect:
			child.visible = false
	
	# Show appropriate particle system based on weather
	if _weather_manager == null or not _weather_manager.has_method("get_current_weather"):
		return
	
	var current_weather: int = _weather_manager.get_current_weather() as int
	
	match current_weather:
		1:  # RAIN
			if _weather_particles.has_node("Rain"):
				(_weather_particles.get_node("Rain") as Node).visible = true
		2:  # SNOW
			if _weather_particles.has_node("Snow"):
				(_weather_particles.get_node("Snow") as Node).visible = true
		3:  # FOG
			if _weather_particles.has_node("Fog"):
				(_weather_particles.get_node("Fog") as Node).visible = true


func _apply_weather_to_player() -> void:
	if _weather_manager == null or not _weather_manager.has_method("get_weather_effects"):
		return
	
	var effects: Dictionary = _weather_manager.get_weather_effects() as Dictionary
	var player: CharacterBody2D = $Player as CharacterBody2D
	
	if player != null and player.has_method("set_weather_speed_multiplier"):
		var speed_mult: float = effects.get("speed_mult", 1.0) as float
		player.set_weather_speed_multiplier(speed_mult)


func _get_weather_spawn_rate() -> float:
	if _weather_manager != null and _weather_manager.has_method("get_spawn_rate_multiplier"):
		return _weather_manager.get_spawn_rate_multiplier() as float
	return 1.0


func _get_weather_speed_multiplier() -> float:
	if _weather_manager != null and _weather_manager.has_method("get_player_speed_multiplier"):
		return _weather_manager.get_player_speed_multiplier() as float
	return 1.0


func _get_weather_visibility() -> float:
	if _weather_manager != null and _weather_manager.has_method("get_visibility_multiplier"):
		return _weather_manager.get_visibility_multiplier() as float
	return 1.0


func _on_game_paused(is_paused: bool) -> void:
	print("Game paused: ", is_paused)


func _on_lives_changed(value: int) -> void:
	if value <= 0 and not _game_over_active:
		# Record remaining lives for achievements before game over
		var gm: Node = _gm()
		if gm != null and gm.has_method("record_lives_remaining"):
			gm.record_lives_remaining(value)
		_show_game_over()


func _show_game_over() -> void:
	_game_over_active = true
	var am: Node = _am()
	if am != null and am.has_method("play_gameover"):
		am.play_gameover()
	var gm: Node = _gm()
	if gm != null:
		gm.set_pause(true)
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")


func _handle_shooting(delta: float) -> void:
	var player: CharacterBody2D = $Player as CharacterBody2D
	if player == null:
		return

	_shoot_timer -= delta
	if _shoot_timer > 0.0:
		return
	if not Input.is_action_pressed("shoot"):
		return

	var cooldown: float = 0.5
	if player.has_method("get_shoot_cooldown"):
		cooldown = player.get_shoot_cooldown() as float
	_shoot_timer = cooldown

	var level: int = 1
	if player.has_method("get_weapon_level"):
		level = player.get_weapon_level() as int

	var base_pos: Vector2 = player.position
	base_pos.y -= 20.0

	match level:
		1:
			_spawn_bullet(base_pos)
		2:
			_spawn_bullet(base_pos + Vector2(-8.0, 0.0))
			_spawn_bullet(base_pos + Vector2(8.0, 0.0))
		3:
			_spawn_bullet(base_pos + Vector2(-15.0, 0.0))
			_spawn_bullet(base_pos)
			_spawn_bullet(base_pos + Vector2(15.0, 0.0))
		_:
			_spawn_bullet(base_pos)


func _spawn_bullet(position: Vector2) -> void:
	var am: Node = _am()
	if am != null and am.has_method("play_shoot"):
		am.play_shoot()
	var bullet: Node2D = bullet_scene.instantiate() as Node2D
	if bullet == null:
		push_error("Failed to instantiate bullet.")
		return
	bullet.position = position
	add_child(bullet)


func _handle_spawning(delta: float) -> void:
	var gm: Node = _gm()
	if gm != null and gm.paused:
		return

	_spawn_timer += delta
	
	# Apply weather effect to spawn rate
	var spawn_rate_mult: float = _get_weather_spawn_rate()
	var effective_interval: float = SPAWN_INTERVAL / spawn_rate_mult
	
	if _spawn_timer >= effective_interval:
		_spawn_timer = 0.0
		_spawn_enemy()


func _spawn_enemy() -> void:
	# Don't spawn regular enemies when boss is active
	if _boss_active:
		return
	
	var enemy: Node2D = enemy_scene.instantiate() as Node2D
	if enemy == null:
		push_error("Failed to instantiate enemy.")
		return

	var speed_mult: float = 1.0 + (WAVE_SPEED_MULT * (get_wave() - 1))
	if enemy.has_method("set_speed_multiplier"):
		enemy.set_speed_multiplier(speed_mult)

	add_child(enemy)


func _spawn_boss() -> void:
	if _boss_active:
		return
	
	var boss: Node2D = boss_scene.instantiate() as Node2D
	if boss == null:
		push_error("Failed to instantiate boss.")
		return
	
	_boss_active = true
	_current_boss = boss
	
	# Show boss warning in HUD
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		if hud.has_method("show_boss_warning"):
			hud.show_boss_warning()
		if hud.has_method("show_boss_health_bar"):
			hud.show_boss_health_bar()
	
	# Connect to boss health signal for HUD display
	if boss.has_signal("health_changed"):
		boss.health_changed.connect(_on_boss_health_changed)
	
	add_child(boss)


func _on_boss_health_changed(health: int, max_health: int) -> void:
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	
	if hud.has_method("show_boss_health_bar"):
		hud.show_boss_health_bar()
	if hud.has_method("update_boss_health"):
		hud.update_boss_health(float(health), float(max_health))


func on_boss_died(boss_node: Node, position: Vector2) -> void:
	_boss_active = false
	_current_boss = null
	
	# Hide boss health bar
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	if hud != null and hud.has_method("hide_boss_health_bar"):
		hud.hide_boss_health_bar()
	
	# Extra screen shake for boss death
	_trigger_screen_shake()
	
	# Spawn explosions at boss position
	for i: int in range(5):
		var offset_pos: Vector2 = position + Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
		_spawn_explosion(offset_pos)


func get_wave() -> int:
	var gm: Node = _gm()
	if gm != null:
		return gm.wave as int
	return 1


func _handle_waves(delta: float) -> void:
	var gm: Node = _gm()
	if gm != null and gm.paused:
		return

	_wave_timer += delta
	if _wave_timer >= WAVE_INTERVAL:
		_wave_timer = 0.0
		gm.next_wave()
		
		# Check if this wave should spawn a boss (every 5th wave)
		if get_wave() % 5 == 0:
			_spawn_boss()
		
		# Randomize weather when wave changes
		_change_weather_on_wave_change()


func _change_weather_on_wave_change() -> void:
	if _weather_manager != null and _weather_manager.has_method("randomize_weather"):
		_weather_manager.randomize_weather()


func _handle_collisions() -> void:
	var enemies: Array = _get_enemies()
	var bullets: Array = _get_bullets()
	var player: CharacterBody2D = $Player as CharacterBody2D

	for enemy: Node2D in enemies:
		var enemy_size: float = enemy.get("SIZE") as float
		var enemy_pos: Vector2 = enemy.position

		for bullet: Node2D in bullets:
			var bullet_size: float = bullet.get("BULLET_SIZE") as float
			if enemy_pos.distance_to(bullet.position) < enemy_size + bullet_size:
				_on_enemy_destroyed(enemy, enemy_pos)
				bullet.queue_free()
				break

		if is_instance_valid(player) and enemy_pos.distance_to(player.position) < enemy_size + PLAYER_RADIUS:
			var am: Node = _am()
			if am != null and am.has_method("play_hit"):
				am.play_hit()
			_spawn_explosion(enemy_pos)
			enemy.queue_free()
			var player_has_shield: bool = false
			if player.has_method("is_shield_active"):
				player_has_shield = player.is_shield_active() as bool
			if not player_has_shield:
				var gm: Node = _gm()
				if gm != null:
					gm.take_life()


func _on_enemy_destroyed(enemy: Node2D, position: Vector2) -> void:
	var am: Node = _am()
	if am != null and am.has_method("play_explode"):
		am.play_explode()
	var gm: Node = _gm()
	var score_value: int = enemy.get("SCORE_VALUE") as int
	if gm != null:
		gm.add_score(score_value)
	_spawn_explosion(position)
	_trigger_screen_shake()
	_show_kill_feedback(position)
	_add_player_experience()
	_try_spawn_powerup(position)
	enemy.queue_free()


func _add_player_experience() -> void:
	var player: CharacterBody2D = $Player as CharacterBody2D
	if player == null or not player.has_method("add_experience"):
		return
	var old_level: int = 1
	if player.has_method("get_weapon_level"):
		old_level = player.get_weapon_level() as int
	var leveled_up: bool = player.add_experience(1) as bool
	if leveled_up:
		_update_weapon_level_hud()
		# Record weapon level for achievements
		var new_level: int = player.get_weapon_level() as int
		var gm: Node = _gm()
		if gm != null and gm.has_method("record_weapon_level"):
			gm.record_weapon_level(new_level)


func _try_spawn_powerup(position: Vector2) -> void:
	if randf() >= 0.3:
		return
	
	# Decide whether to spawn regular powerup or magnet powerup (10% chance for magnet)
	if randf() < 0.1:
		# Spawn magnet powerup
		var magnet_powerup: Node2D = magnet_powerup_scene.instantiate() as Node2D
		if magnet_powerup != null:
			magnet_powerup.position = position
			add_child(magnet_powerup)
	else:
		# Spawn regular powerup
		var powerup: Node2D = powerup_scene.instantiate() as Node2D
		if powerup == null:
			return
		powerup.position = position
		var type_index: int = randi() % 5  # 0-4 for HEAL, RAPID_FIRE, SHIELD, BOMB, MAGNET
		powerup.set("powerup_type", type_index)
		add_child(powerup)


func _handle_powerup_collection() -> void:
	var player: CharacterBody2D = $Player as CharacterBody2D
	if player == null:
		return

	for child: Node in get_children():
		if not child.is_in_group("powerup"):
			continue
		var powerup: Node2D = child as Node2D
		if powerup == null:
			continue
		var powerup_size: float = powerup.get("SIZE") as float
		if powerup.position.distance_to(player.position) < powerup_size + PLAYER_RADIUS:
			_collect_powerup(powerup, player)


func _collect_powerup(powerup: Node2D, player: CharacterBody2D) -> void:
	var am: Node = _am()
	if am != null and am.has_method("play_powerup"):
		am.play_powerup()
	var type_index: int = powerup.get("powerup_type") as int
	var type_string: String = _powerup_type_to_string(type_index)
	match type_string:
		"bomb":
			_activate_bomb()
		"magnet":
			_activate_magnet()
		_:
			if player.has_method("apply_powerup"):
				player.apply_powerup(type_string)
	# Record powerup collection for achievements
	var gm: Node = _gm()
	if gm != null and gm.has_method("record_powerup_collected"):
		gm.record_powerup_collected()
	powerup.queue_free()


func _powerup_type_to_string(type_index: int) -> String:
	match type_index:
		0:
			return "heal"
		1:
			return "rapid_fire"
		2:
			return "shield"
		3:
			return "bomb"
		4:
			return "magnet"
		_:
			return "heal"


func _activate_bomb() -> void:
	var am: Node = _am()
	if am != null and am.has_method("play_explode"):
		am.play_explode()
	var enemies: Array = _get_enemies()
	for enemy: Node2D in enemies:
		if is_instance_valid(enemy):
			_on_enemy_destroyed(enemy, enemy.position)


func _handle_magnet(delta: float) -> void:
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	
	if not _magnet_active:
		return
	
	_magnet_timer -= delta
	
	# Update HUD timer display
	if hud != null and hud.has_method("update_magnet_timer"):
		hud.update_magnet_timer(_magnet_timer)
	
	if _magnet_timer <= 0.0:
		_magnet_active = false
		_magnet_timer = 0.0
		# Hide magnet indicator in HUD
		if hud != null and hud.has_method("hide_magnet"):
			hud.hide_magnet()
		return
	
	var player: CharacterBody2D = $Player as CharacterBody2D
	if player == null:
		return
	
	# Attract all powerups toward player
	for child: Node in get_children():
		if not child.is_in_group("powerup"):
			continue
		var powerup: Node2D = child as Node2D
		if powerup == null or not is_instance_valid(powerup):
			continue
		
		var direction: Vector2 = player.position - powerup.position
		var distance: float = direction.length()
		if distance > 0.0:
			direction = direction.normalized()
			# Move powerup toward player
			powerup.position += direction * MAGNET_ATTRACTION_SPEED * delta
			# Clamp to not go past player
			if powerup.position.distance_to(player.position) < 5.0:
				powerup.position = player.position


func _activate_magnet() -> void:
	_magnet_active = true
	_magnet_timer = MAGNET_DURATION
	var am: Node = _am()
	if am != null and am.has_method("play_powerup"):
		am.play_powerup()
	
	# Show magnet indicator in HUD
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	if hud != null and hud.has_method("show_magnet"):
		hud.show_magnet()


func _update_weapon_level_hud() -> void:
	var player: CharacterBody2D = $Player as CharacterBody2D
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	if hud == null or player == null or not player.has_method("get_weapon_level"):
		return
	var level: int = player.get_weapon_level() as int
	if hud.has_method("set_weapon_level"):
		hud.set_weapon_level(level)


func _get_enemies() -> Array:
	var result: Array = []
	for child: Node in get_children():
		if child.is_in_group("enemy"):
			result.append(child)
	return result


func _get_bullets() -> Array:
	var result: Array = []
	for child: Node in get_children():
		if child.is_in_group("bullet"):
			result.append(child)
	return result


func _spawn_explosion(position: Vector2) -> void:
	var explosion: Node2D = explosion_scene.instantiate() as Node2D
	if explosion != null:
		explosion.position = position
		add_child(explosion)


func _trigger_screen_shake() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var tween: Tween = create_tween()
	if tween == null:
		return
	tween.tween_property(camera, "offset", Vector2(SHAKE_STRENGTH, -SHAKE_STRENGTH), SHAKE_DURATION * 0.25)
	tween.tween_property(camera, "offset", Vector2(-SHAKE_STRENGTH, SHAKE_STRENGTH), SHAKE_DURATION * 0.25)
	tween.tween_property(camera, "offset", Vector2(SHAKE_STRENGTH * 0.5, SHAKE_STRENGTH * 0.5), SHAKE_DURATION * 0.25)
	tween.tween_property(camera, "offset", Vector2.ZERO, SHAKE_DURATION * 0.25)


func _show_kill_feedback(position: Vector2) -> void:
	var gm: Node = _gm()
	if gm == null:
		return
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	if hud.has_method("show_kill_feedback"):
		hud.show_kill_feedback(position, gm.score)


static func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")


static func _am() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")
