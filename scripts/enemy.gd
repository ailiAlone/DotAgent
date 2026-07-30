## Basic downward-moving enemy that can damage the player and take damage from bullets.

extends Area2D

signal died(position: Vector2)

@export var speed: float = 150.0
@export var health: int = 1
@export var score_value: int = 100

func _ready() -> void:
	add_to_group("enemies")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	var wave_speed_bonus := 20.0 * (GameManager.wave - 1)
	position += Vector2.DOWN * (speed + wave_speed_bonus) * delta

	var viewport_size := get_viewport_rect().size
	if position.y > viewport_size.y + 50.0:
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 18.0, Color.RED)

func take_damage(amount: int = 1) -> void:
	health -= amount
	if health <= 0:
		die()

func die() -> void:
	died.emit(global_position)
	GameManager.add_score(score_value)
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		body.take_damage()
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("bullets"):
		area.queue_free()
		take_damage()
