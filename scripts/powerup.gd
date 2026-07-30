extends Node2D

## Powerup: falls downward, grants an effect when collected by the player.
## Game.gd handles collection via distance checks.

enum Type { HEAL, RAPID_FIRE, SHIELD, BOMB }

const DROP_SPEED: float = 80.0
const SIZE: float = 12.0

@export var powerup_type: Type = Type.HEAL


func _process(delta: float) -> void:
	position.y += DROP_SPEED * delta
	var viewport_size: Vector2 = get_viewport_rect().size
	if position.y > viewport_size.y + SIZE:
		queue_free()


func _draw() -> void:
	var color: Color = Color.WHITE
	match powerup_type:
		Type.HEAL:
			color = Color.GREEN
		Type.RAPID_FIRE:
			color = Color.ORANGE
		Type.SHIELD:
			color = Color.BLUE
		Type.BOMB:
			color = Color.PURPLE
	draw_circle(Vector2.ZERO, SIZE, color)
