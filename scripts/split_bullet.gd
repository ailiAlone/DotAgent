extends Node2D

## Split Bullet
## Player bullet that splits into 2 smaller bullets when hitting an enemy.

const SPEED: float = 500.0
const BULLET_SIZE: float = 6.0

var _current_angle: float = -PI / 2.0  # Start pointing up
var _is_split_bullet: bool = false  # True if this is a child bullet from a split


func _process(delta: float) -> void:
	position += Vector2.from_angle(_current_angle) * SPEED * delta
	if _is_off_screen():
		queue_free()


func _draw() -> void:
	# Draw cyan split bullet, smaller if split
	var color: Color = Color(0.0, 1.0, 1.0)  # Cyan
	draw_circle(Vector2.ZERO, BULLET_SIZE, color)


func _on_area_entered(area: Area2D) -> void:
	# Only split on enemy hit, not if already a split bullet
	if area.is_in_group("enemies") and not _is_split_bullet:
		_split()
		queue_free()


func _split() -> void:
	## Create 2 child bullets flying at ±30 degrees from current direction
	const SPLIT_ANGLE: float = deg_to_rad(30.0)
	const SPLIT_SPEED: float = 450.0
	
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	
	# Create two split bullets at ±30 degrees
	for offset: float in [-SPLIT_ANGLE, SPLIT_ANGLE]:
		var split_bullet: Node2D = Node2D.new()
		split_bullet.set_script(load("res://scripts/split_bullet.gd"))
		split_bullet._current_angle = _current_angle + offset
		split_bullet._is_split_bullet = true
		split_bullet.position = position
		tree.root.add_child(split_bullet)


func _is_off_screen() -> bool:
	var screen_size: Vector2 = get_viewport_rect().size
	var margin: float = BULLET_SIZE * 2.0
	return position.y < -margin or position.y > screen_size.y + margin or \
		   position.x < -margin or position.x > screen_size.x + margin
