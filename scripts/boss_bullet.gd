extends Node2D

## Homing bullet fired by the Boss. Travels in a fixed direction with slight acceleration, damages player on contact.

const BULLET_SIZE: float = 8.0
const LIFETIME: float = 8.0

@export var speed: float = 220.0
@export var max_speed: float = 450.0
@export var acceleration: float = 60.0
@export var damage: int = 1

var _direction: Vector2 = Vector2.DOWN
var _velocity: Vector2 = Vector2.ZERO
var _lifetime: float = 0.0


func _ready() -> void:
	add_to_group("boss_bullet")
	z_index = 5


func _process(delta: float) -> void:
	_velocity += _direction * acceleration * delta
	if _velocity.length() > max_speed:
		_velocity = _velocity.normalized() * max_speed
	position += _velocity * delta
	_lifetime += delta
	if _lifetime >= LIFETIME or _is_offscreen():
		queue_free()


func _is_offscreen() -> bool:
	var viewport_size: Vector2 = get_viewport_rect().size
	return position.y < -BULLET_SIZE or position.y > viewport_size.y + BULLET_SIZE or position.x < -BULLET_SIZE or position.x > viewport_size.x + BULLET_SIZE


func _draw() -> void:
	draw_circle(Vector2.ZERO, BULLET_SIZE, Color(0.9, 0.1, 0.9, 1.0))
	var tip: Vector2 = _direction * BULLET_SIZE
	draw_line(Vector2.ZERO, tip, Color(1.0, 0.5, 1.0, 1.0), 2.0, true)


func set_direction(direction: Vector2) -> void:
	_direction = direction.normalized()
	_velocity = _direction * speed
