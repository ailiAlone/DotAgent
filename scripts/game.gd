extends Node2D

## Main game scene: manages the player, HUD, bullets, enemies, spawns, waves, and polish effects.

const Singleton: String = "GameManager"
const SPAWN_INTERVAL: float = 2.0
const WAVE_INTERVAL: float = 30.0
const WAVE_SPEED_MULT: float = 0.15
const SHAKE_DURATION: float = 0.12
const SHAKE_STRENGTH: float = 6.0

@onready var hud_scene: PackedScene = preload("res://scenes/hud.tscn")
@onready var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
@onready var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@onready var explosion_scene: PackedScene = preload("res://scenes/explosion.tscn")

var _spawn_timer: float = 0.0
var _wave_timer: float = 0.0


func _ready() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.reset()
		gm.game_paused.connect(_on_game_paused)
	var hud_instance: CanvasLayer = hud_scene.instantiate() as CanvasLayer
	if hud_instance != null:
		hud_instance.name = "HUD"
		add_child(hud_instance)
	else:
		push_error("Failed to instantiate HUD.")


func _process(delta: float) -> void:
	_handle_shooting()
	_handle_spawning(delta)
	_handle_waves(delta)
	_handle_collisions()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var gm: Node = _gm()
		if gm != null:
			gm.toggle_pause()


func _on_game_paused(is_paused: bool) -> void:
	print("Game paused: ", is_paused)


func _handle_shooting() -> void:
	if Input.is_action_just_pressed("shoot"):
		var bullet: Node2D = bullet_scene.instantiate() as Node2D
		if bullet != null:
			var player: Node2D = $Player as Node2D
			bullet.position = player.position
			bullet.position.y -= 20.0
			add_child(bullet)


func _handle_spawning(delta: float) -> void:
	var gm: Node = _gm()
	if gm != null and gm.paused:
		return

	var interval: float = SPAWN_INTERVAL
	if gm != null and gm.wave > 1:
		interval = maxf(0.4, SPAWN_INTERVAL - (gm.wave - 1) * 0.15)

	_spawn_timer += delta
	if _spawn_timer >= interval:
		_spawn_timer = 0.0
		var enemy: Node2D = enemy_scene.instantiate() as Node2D
		if enemy != null:
			var speed_mult: float = 1.0
			if gm != null:
				speed_mult = 1.0 + (gm.wave - 1) * WAVE_SPEED_MULT
			if enemy.has_method("set_speed_multiplier"):
				enemy.set_speed_multiplier(speed_mult)
			add_child(enemy)


func _handle_waves(delta: float) -> void:
	var gm: Node = _gm()
	if gm != null and gm.paused:
		return

	_wave_timer += delta
	if _wave_timer >= WAVE_INTERVAL:
		_wave_timer = 0.0
		gm.next_wave()


func _handle_collisions() -> void:
	var enemies: Array = _get_enemies()
	var bullets: Array = _get_bullets()
	var player: Node2D = $Player as Node2D

	for enemy: Node2D in enemies:
		var enemy_size: float = enemy.get("SIZE") as float
		var enemy_pos: Vector2 = enemy.position

		for bullet: Node2D in bullets:
			var bullet_size: float = bullet.get("BULLET_SIZE") as float
			if enemy_pos.distance_to(bullet.position) < enemy_size + bullet_size:
				_on_enemy_destroyed(enemy, enemy_pos)
				bullet.queue_free()
				break

		if is_instance_valid(player) and enemy_pos.distance_to(player.position) < enemy_size + 20.0:
			_spawn_explosion(enemy_pos)
			enemy.queue_free()
			var gm: Node = _gm()
			if gm != null:
				gm.take_life()


func _on_enemy_destroyed(enemy: Node2D, position: Vector2) -> void:
	var gm: Node = _gm()
	var score_value: int = enemy.get("SCORE_VALUE") as int
	if gm != null:
		gm.add_score(score_value)
	_spawn_explosion(position)
	_trigger_screen_shake()
	_show_kill_feedback(position)
	enemy.queue_free()


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
