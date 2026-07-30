extends Node2D

const SPEED: float = 300.0

var _shoot_cooldown: float = 0.0

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

	position += direction * SPEED * delta

	var viewport_size: Vector2 = get_viewport_rect().size
	position.x = clampf(position.x, 20.0, viewport_size.x - 20.0)
	position.y = clampf(position.y, 20.0, viewport_size.y - 20.0)


func _draw() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	points.push_back(Vector2(0.0, -20.0))
	points.push_back(Vector2(15.0, 20.0))
	points.push_back(Vector2(-15.0, 20.0))
	draw_colored_polygon(points, Color.WHITE)
