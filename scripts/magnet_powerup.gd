extends Node2D

## MagnetPowerup: Falls downward, attracts all powerups on screen toward the player for 5 seconds when collected.

const DROP_SPEED: float = 80.0
const SIZE: float = 12.0

func _process(delta: float) -> void:
	position.y += DROP_SPEED * delta
	var viewport_size: Vector2 = get_viewport_rect().size
	if position.y > viewport_size.y + SIZE:
		queue_free()


func _draw() -> void:
	# Draw magnet icon - horseshoe shape using arcs
	var color: Color = Color.YELLOW
	var radius: float = SIZE
	var thickness: float = 4.0
	
	# Draw outer arc (top half of horseshoe)
	for i: int in range(180):
		var angle1: float = deg_to_rad(float(i) - 90.0)
		var angle2: float = deg_to_rad(float(i) + 1.0 - 90.0)
		var p1: Vector2 = Vector2(cos(angle1), sin(angle1)) * radius
		var p2: Vector2 = Vector2(cos(angle2), sin(angle2)) * radius
		draw_line(p1, p2, color, thickness)
	
	# Draw inner arc (top half of horseshoe inner)
	var inner_radius: float = radius * 0.6
	for i: int in range(180):
		var angle1: float = deg_to_rad(float(i) - 90.0)
		var angle2: float = deg_to_rad(float(i) + 1.0 - 90.0)
		var p1: Vector2 = Vector2(cos(angle1), sin(angle1)) * inner_radius
		var p2: Vector2 = Vector2(cos(angle2), sin(angle2)) * inner_radius
		draw_line(p1, p2, color, thickness)
	
	# Draw left pole (N pole - red tint)
	draw_line(Vector2(-radius, 0.0), Vector2(-radius, radius * 0.3), Color.RED, thickness)
	
	# Draw right pole (S pole - blue tint)
	draw_line(Vector2(radius, 0.0), Vector2(radius, radius * 0.3), Color.BLUE, thickness)
