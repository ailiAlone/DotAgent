## Player ship that moves with WASD and shoots bullets at space press.

extends CharacterBody2D

@export var speed: float = 300.0
@export var shoot_cooldown: float = 0.25

var _shoot_timer: float = 0.0

func _ready() -> void:
	add_to_group("players")

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input = input.normalized()
	velocity = input * speed
	move_and_slide()

	_shoot_timer -= delta
	if Input.is_action_pressed("shoot") and _shoot_timer <= 0.0:
		_shoot()
		_shoot_timer = shoot_cooldown

func _draw() -> void:
	const size := 20.0
	var points := PackedVector2Array([
		Vector2(0, -size),
		Vector2(-size * 0.7, size),
		Vector2(size * 0.7, size),
	])
	draw_colored_polygon(points, Color.WHITE)

func _shoot() -> void:
	var bullet := preload("res://scenes/bullet.tscn").instantiate() as Area2D
	bullet.global_position = global_position + Vector2(0, -30)
	get_tree().current_scene.add_child(bullet)

func take_damage() -> void:
	GameManager.take_life()
