extends Node2D

## Player bullet: travels upward and damages enemies on contact.

const SPEED: float = 600.0
const BULLET_SIZE: float = 6.0


func _process(delta: float) -> void:
	position.y -= SPEED * delta
	if position.y < -BULLET_SIZE:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, BULLET_SIZE, Color.YELLOW)
