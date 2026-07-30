extends Node2D

## Enemy: spawns at top of screen, moves downward, damages player on contact.

const SPEED: float = 150.0
const SIZE: float = 20.0
const SCORE_VALUE: int = 10
const DAMAGE: int = 1
const OFFSCREEN_MARGIN: float = 40.0

var _speed_multiplier: float = 1.0


func _ready() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	position.y = -SIZE
	position.x = randf_range(SIZE, viewport_size.x - SIZE)


func _process(delta: float) -> void:
	position.y += SPEED * _speed_multiplier * delta
	var viewport_size: Vector2 = get_viewport_rect().size
	if position.y > viewport_size.y + OFFSCREEN_MARGIN:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, SIZE, Color.RED)


func set_speed_multiplier(value: float) -> void:
	_speed_multiplier = maxf(0.1, value)


func take_hit() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.add_score(SCORE_VALUE)
	queue_free()


static func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
