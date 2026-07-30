## Game world root that owns the player, HUD, camera, spawns enemies, and handles pause.

extends Node2D

@onready var hud: CanvasLayer = $HUD
@onready var camera: Camera2D = $Camera2D
@onready var game_manager: Node = $"/root/GameManager"

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

@export var spawn_interval: float = 2.0

var _spawn_timer: float = 0.0
var _wave_timer: float = 30.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_manager.reset_game()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _process(delta: float) -> void:
	if get_tree().paused:
		return

	spawn_interval = max(0.5, 2.0 - (game_manager.wave - 1) * 0.2)

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_enemy()
		_spawn_timer = spawn_interval

	_wave_timer -= delta
	if _wave_timer <= 0.0:
		game_manager.next_wave()
		_wave_timer = 30.0

func _spawn_enemy() -> void:
	var viewport_size := get_viewport_rect().size
	var enemy := ENEMY_SCENE.instantiate() as Area2D
	enemy.position = Vector2(randf_range(30.0, viewport_size.x - 30.0), -50.0)
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)

func _on_enemy_died(pos: Vector2) -> void:
	game_manager.register_kill()
	_shake_camera()

	var explosion := EXPLOSION_SCENE.instantiate() as Node2D
	explosion.global_position = pos
	add_child(explosion)

func _shake_camera() -> void:
	if camera == null:
		return
	var tween := create_tween()
	tween.tween_property(camera, "offset", Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)), 0.05)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.15)

func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	hud.visible = not get_tree().paused
