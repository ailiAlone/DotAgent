extends Node2D

## Homing Bullet
## Player bullet that slowly rotates toward the nearest enemy while flying.

const SPEED: float = 400.0
const BULLET_SIZE: float = 6.0
const TURN_SPEED: float = 2.0  # radians per second

var _current_angle: float = -PI / 2.0  # Start pointing up


func _process(delta: float) -> void:
	# Find nearest enemy
	var nearest_enemy: Node2D = _find_nearest_enemy()
	
	if nearest_enemy != null:
		# Calculate desired direction to enemy
		var to_enemy: Vector2 = nearest_enemy.global_position - global_position
		var target_angle: float = to_enemy.angle()
		
		# Smoothly rotate toward target
		var angle_diff: float = _angle_difference(_current_angle, target_angle)
		
		# Limit rotation by turn speed
		var max_rotation: float = TURN_SPEED * delta
		_current_angle += clamp(angle_diff, -max_rotation, max_rotation)
	
	# Move bullet
	position += Vector2.from_angle(_current_angle) * SPEED * delta
	
	# Remove if off screen
	if _is_off_screen():
		queue_free()


func _find_nearest_enemy() -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return null
	
	var nearest: Node2D = null
	var nearest_dist: float = INF
	
	for enemy: Node in enemies:
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	
	return nearest


func _angle_difference(from: float, to: float) -> float:
	# Returns shortest angle from 'from' to 'to'
	var diff: float = fmod(to - from + PI, 2.0 * PI) - PI
	if diff < -PI:
		diff += 2.0 * PI
	return diff


func _is_off_screen() -> bool:
	var screen_size: Vector2 = get_viewport_rect().size
	var margin: float = BULLET_SIZE * 2.0
	return position.y < -margin or position.y > screen_size.y + margin or \
		   position.x < -margin or position.x > screen_size.x + margin


func _draw() -> void:
	# Draw golden homing bullet
	draw_circle(Vector2.ZERO, BULLET_SIZE, Color(1.0, 0.84, 0.0))
